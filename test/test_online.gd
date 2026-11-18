extends UiTestBase
## 联机功能测试（M4）：真实 WebSocket 回环（同进程服务端 + 客户端）。
## 覆盖：存储持久化/昵称在线占用制（含 trim 归一与掉线释放复用）、房间守卫（重复建房/加入/满员/对局中/
## 非房主开局等错误路径）、房间生命周期（不满开局拒绝→补 AI→完整对局→分数落盘广播→
## 退出关房）、可见性（回放消息不含他人牌面/底牌）、超时托管、断线重连与宽限、
## 多局累计（庄位轮换/下一局重建/跨局累计分）、注入强牌局的确定性旋转与人类操作路径、
## 各阶段重连快照矩阵、UI 级联机牌桌（真实场景接管 + 人类经 UI 提交 + 退出弹层回主菜单）。
## 服务端计时按 time_scale=0.02 缩放（AI 节拍 ~0.014s、人类托管 ~0.4s、离线宽限 ~2.4s）。


const PORT := 9811
const STORE_PATH := "user://test_online_store.json"
const URL := "ws://127.0.0.1:9811"

var _manager: Node = null
var _store: RefCounted = null
var _clients: Array = []
var _client_errors := {}  ## NetClient → Array[String]（持久收集，避免一次性信号竞态）


## ============================= 夹具 =============================

func _ensure_server() -> void:
	if _manager != null:
		return
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
	_store = load("res://server/store.gd").new(STORE_PATH)
	_manager = load("res://server/room_manager.gd").new()
	_manager.name = "OnlineTestServer"
	Engine.get_main_loop().root.add_child(_manager)
	_manager.sweep_interval = 0.05
	# 心跳超时放大：测试里客户端心跳间隔（5s）远大于服务端判定阈值会误判离线
	# （离线检测在本套件靠 drop_connection 后的定向发送失败，仍即时生效）
	_manager.heartbeat_timeout = 60.0
	_manager.time_scale = 0.02
	var err: Error = _manager.start(PORT, _store)
	if err != OK:
		push_error("回环服务器启动失败（端口 %d）：%s" % [PORT, error_string(err)])


func _make_client(nick: String, node_name: String, standalone := true) -> NetClient:
	var nc := NetClient.new()
	nc.name = node_name
	nc.standalone = standalone
	Engine.get_main_loop().root.add_child(nc)
	nc.connect_to(URL, nick)
	var errs: Array = []
	_client_errors[nc] = errs
	nc.net_error.connect(func(m: String): errs.append(m))
	_clients.append(nc)
	return nc


func _errors(nc: NetClient) -> Array:
	return _client_errors.get(nc, [])


func _until(pred: Callable, timeout := 5.0) -> bool:
	var tree: SceneTree = Engine.get_main_loop()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout * 1000.0:
		if pred.call():
			return true
		await tree.create_timer(0.01).timeout
	return false


func _wait_hello(nc: NetClient, timeout := 5.0) -> bool:
	# 轮询持久标志而非一次性信号监听：客户端创建与监听挂载之间存在竞态窗口
	return await _until(func(): return nc.hello_done, timeout)


func _wait_error(nc: NetClient, timeout := 5.0) -> String:
	var base: int = _errors(nc).size()
	var got := await _until(func(): return _errors(nc).size() > base, timeout)
	return str(_errors(nc)[-1]) if got else ""


func _create_room(nc: NetClient) -> String:
	nc.request_create()
	var ok := await _until(func(): return not nc.room_state.is_empty(), 5.0)
	return str(nc.room_state.get("code", "")) if ok else ""


func _join_room(nc: NetClient, code: String) -> bool:
	nc.request_join(code)
	return await _until(func(): return int(nc.my_seat) >= 0, 5.0)


func _start_fill(nc: NetClient) -> bool:
	nc.request_start(true)
	return await _until(func(): return nc.view != null, 8.0)


func _test_room() -> Node:
	for room in _manager._rooms.values():
		return room
	return null


## 按房间码取房间（避免多房间并存时 values()[0] 取错导致跨用例污染）
func _room_by_code(code: String) -> Node:
	return _manager._rooms.get(code)


func _free_clients() -> void:
	for nc in _clients:
		if is_instance_valid(nc):
			nc.queue_free()
	_clients.clear()
	_client_errors.clear()
	await tree_pause()


func _cleanup_room() -> void:
	for room in _manager._rooms.values():
		room.close("测试清理")
	await tree_pause()


## 注入用发牌：0 号全黑桃强牌（19 张，无王），1~3 号弱牌，底牌 = ♦AA♦22 + 四王。
## 搭配 dealer=3（首个表态座位 = 0 号人类）与人类直接叫 200（封顶强制各家放弃），
## 0 号必为出牌庄家 → 人类叫主/扣底/出牌路径与 7.3 无主公示路径可确定性驱动。
func _strong_deal() -> Array:
	var deck := Card.full_deck()
	var hands: Array = []
	hands.append(deck.slice(0, 19))      # ♠5..♠A 各两张 + ♠2（19 张全黑桃）
	var pool := deck.slice(19)           # 剩余 65 张（1 黑桃 + 60 红/梅/方 + 4 王）
	hands.append(pool.slice(0, 19))
	hands.append(pool.slice(19, 38))
	hands.append(pool.slice(38, 57))
	var kitty := pool.slice(57, 65)      # ♦A×2 ♦2×2 小王×2 大王×2
	return [hands, kitty]


## ============================= 人类代打驱动（本地视图 → send_act） =============================

func _fingerprint(v) -> Array:
	return [
		int(v.phase), int(v.auction.turn), int(v.banker_seat),
		v.current_plays.size(), v.trick_history.size(), int(v.turn_seat),
		v.trump != null, int(v.captured_points),
	]


func _maybe_act(nc: NetClient, v) -> bool:
	if v.phase == GameEngine.Phase.AUCTION and v.auction.turn == 0:
		nc.send_act(NetProto.KIND_BID, {"value": GameEngine.BID_PASS})
		return true
	if v.phase == GameEngine.Phase.TRUMP and v.banker_seat == 0:
		var choice: Dictionary = AiPlay.choose_trump(v.get_hand(0))
		nc.send_act(NetProto.KIND_TRUMP, {"suit": choice.suit, "rank": choice.rank})
		return true
	if v.phase == GameEngine.Phase.DISCARD and v.banker_seat == 0:
		nc.send_discard(AiPlay.choose_discard(v.get_hand(0), v.trump, GameEngine.BOTTOM_SIZE))
		return true
	if v.phase == GameEngine.Phase.TRICKS and v.turn_seat == 0:
		var cards: Array = AiPlay.choose_play(v.get_hand(0), v.trump, v.current_plays,
			0, v.banker_seat, v.trick_history, v.trump_void_seats)
		nc.send_act(NetProto.KIND_PLAY, {"cards": NetProto.keys_of(cards)})
		return true
	return false


## 状态变化时人类座位自动代打，直到 pred 成立（或超时返回 false）
func _drive_until(nc: NetClient, pred: Callable, deadline_s := 30.0) -> bool:
	var tree: SceneTree = Engine.get_main_loop()
	var start := Time.get_ticks_msec()
	var prev_fp: Array = []
	while Time.get_ticks_msec() - start < deadline_s * 1000.0:
		if pred.call():
			return true
		var v = nc.view
		if v != null:
			var fp := _fingerprint(v)
			if fp != prev_fp:
				prev_fp = fp
				_maybe_act(nc, v)
		await tree.create_timer(0.01).timeout
	return false


func _wait_game_over(nc: NetClient, deadline_s := 60.0) -> Dictionary:
	var result := {"r": null}
	nc.game_finished.connect(func(r: Dictionary): result.r = r, CONNECT_ONE_SHOT)
	var ok := await _drive_until(nc, func(): return result.r != null, deadline_s)
	return result.r if ok else {}


func _find_button(node: Node) -> Button:
	if node is Button:
		return node
	for c in node.get_children():
		var found := _find_button(c)
		if found != null:
			return found
	return null


## 断言服务端引擎与客户端视图的公开状态一致（真座位 → 本地座位旋转后比对）
func _check_view_matches_server(a, nc: NetClient, room: Node) -> void:
	var eng: GameEngine = room.engine
	var v = nc.view
	var my := int(nc.my_seat)
	a.eq(v.captured_points, eng.captured_points, "捉分一致")
	a.eq(v.trick_history.size(), eng.trick_history.size(), "轮数一致")
	a.eq(int(v.banker_seat), NetProto.rot_seat(int(eng.banker_seat), my), "出牌庄家（旋转）一致")
	a.eq(int(v.contract), eng.contract, "叫分一致")
	a.eq(int(v.hand_count(0)), eng.hand_count(my), "本人张数一致")
	for s in GameEngine.PLAYER_COUNT:
		a.eq(int(v.hand_count(s)), eng.hand_count(NetProto.unrot_seat(s, my)),
			"座位 %d 张数（旋转）一致" % s)
	if eng.phase == GameEngine.Phase.AUCTION:
		for s in GameEngine.PLAYER_COUNT:
			var lt = eng.auction.bids[NetProto.unrot_seat(s, my)]
			var lv = v.auction.bids[s]
			a.eq(int(lv.value), int(lt.value), "座位 %d 叫分值（旋转）一致" % s)
			a.eq(bool(lv.passed), bool(lt.passed), "座位 %d 放弃态（旋转）一致" % s)


## ============================= 用例 =============================

## 存储层：分数累计、房间留档与跨实例持久化（昵称不落盘，见在线占用制）
func test_store_persistence(a) -> void:
	var path := "user://test_online_store_unit.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var store: RefCounted = load("res://server/store.gd").new(path)
	store.record_room("ROOM01", "测试玩家甲")
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": 30}, {"name": "电脑·乙", "delta": -10}])
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": -15}, {"name": "电脑·乙", "delta": 5}])
	# 重开实例：落盘数据完整（重启不丢）
	var store2: RefCounted = load("res://server/store.gd").new(path)
	var rows: Array = store2.room_scores("ROOM01")
	a.eq(rows.size(), 2, "两行累计分")
	var by_name := {}
	for row in rows:
		by_name[str(row.name)] = row
	a.eq(int(by_name["测试玩家甲"].score), 15, "30 + (-15) = 15")
	a.eq(int(by_name["测试玩家甲"].games), 2, "两局")
	a.eq(int(by_name["电脑·乙"].score), -5, "-10 + 5 = -5")
	DirAccess.remove_absolute(path)


## 昵称在线占用制（同时在线唯一；掉线释放后可复用）、trim 归一与非法昵称拒绝
func test_nick_uniqueness(a) -> void:
	_ensure_server()
	var first := _make_client("测甲唯一", "C_uniq_a")
	a.check(await _wait_hello(first), "首登成功")
	# 同时在线：第二人用同昵称被拒
	var dup := _make_client("测甲唯一", "C_uniq_dup")
	var err := await _wait_error(dup)
	a.check(err.contains("已被占用"), "在线同昵称被拒：%s" % err)
	# trim 归一：带首尾空格的昵称按去空格形态做占用判定
	var spaced := _make_client("  测乙空格  ", "C_uniq_sp")
	a.check(await _wait_hello(spaced), "带空格昵称注册成功")
	a.eq(spaced.my_name, "测乙空格", "hello_ok 回执为 trim 后昵称")
	var dup2 := _make_client("测乙空格", "C_uniq_sp2")
	err = await _wait_error(dup2)
	a.check(err.contains("已被占用"), "trim 后同昵称被拒：%s" % err)
	var ai := _make_client(NetProto.AI_NAME_PREFIX + "甲", "C_uniq_ai")
	err = await _wait_error(ai)
	a.check(err.contains("电脑"), "电脑前缀昵称被拒：%s" % err)
	var blank := _make_client("   ", "C_uniq_blank")
	err = await _wait_error(blank)
	a.check(err != "", "空白昵称被拒")
	# 掉线释放：首登者断连 → 扫描清理（≤sweep_interval）→ 同昵称可被复用
	first.drop_connection()
	var freed := await _until(func(): return not _manager._peer_nick.values().has("测甲唯一"), 2.0)
	a.check(freed, "掉线后昵称占用被释放")
	var reuser := _make_client("测甲唯一", "C_uniq_re")
	a.check(await _wait_hello(reuser), "释放后同昵称复用成功")
	await _free_clients()


## 房间操作守卫：重复建房/在房加入/满员/对局中加入/非房主开局/重复开局/未开局 next/next 未结束
func test_join_create_guards(a) -> void:
	_ensure_server()
	var host := _make_client("测甲守卫", "C_gd_a")
	var g1 := _make_client("测乙守卫", "C_gd_b")
	var g2 := _make_client("测丙守卫", "C_gd_c")
	a.check(await _wait_hello(host), "房主 hello")
	a.check(await _wait_hello(g1), "g1 hello")
	a.check(await _wait_hello(g2), "g2 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	# 在房重复建房（房主本人）
	host.request_create()
	var err := await _wait_error(host)
	a.check(err.contains("已在房间中"), "在房重复建房被拒：%s" % err)
	# g1 加入后也在房：重复建房被拒
	a.check(await _join_room(g1, code), "g1 入座")
	g1.request_create()
	err = await _wait_error(g1)
	a.check(err.contains("已在房间中"), "在房客户端建房被拒：%s" % err)
	# 非房主开局
	g1.request_start(true)
	err = await _wait_error(g1)
	a.check(err.contains("只有房主"), "非房主开局被拒：%s" % err)
	# 未开局 next
	host.request_next()
	err = await _wait_error(host)
	a.check(err.contains("尚未开局"), "大厅 next 被拒：%s" % err)
	# 开局后：重复开局 / 对局中加入 / next 未结束
	a.check(await _start_fill(host), "补 AI 开局")
	host.request_start(true)
	err = await _wait_error(host)
	a.check(err.contains("对局已开始"), "对局中重复开局被拒：%s" % err)
	g2.request_join(code)
	err = await _wait_error(g2)
	a.check(err.contains("对局进行中"), "对局中加入被拒：%s" % err)
	host.request_next()
	err = await _wait_error(host)
	a.check(err.contains("尚未结束"), "对局未结束 next 被拒：%s" % err)
	await _cleanup_room()
	await _free_clients()


## 满员房间：4 名人类后第 5 人加入被拒
func test_join_full_room(a) -> void:
	_ensure_server()
	var host := _make_client("测甲满员", "C_fu_a")
	a.check(await _wait_hello(host), "房主 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	var joiners: Array = []
	for i in 3:
		var c := _make_client("测乙满员%d" % i, "C_fu_j%d" % i)
		joiners.append(c)
		a.check(await _wait_hello(c), "成员 %d hello" % i)
		a.check(await _join_room(c, code), "成员 %d 入座" % i)
	var outsider := _make_client("测丁满员", "C_fu_out")
	a.check(await _wait_hello(outsider), "第 5 人 hello")
	outsider.request_join(code)
	var err := await _wait_error(outsider)
	a.check(err.contains("房间已满"), "满员加入被拒：%s" % err)
	var room := _room_by_code(code)
	if room != null:
		a.eq(room.human_count(), 4, "房间仍为 4 人")
	else:
		a.check(false, "房间存在")
	await _cleanup_room()
	await _free_clients()


## 房间生命周期：建房/加入/不满开局拒绝/补 AI/完整对局/分数落盘/可见性/退出关房
func test_room_lifecycle_full_game(a) -> void:
	_ensure_server()
	var host := _make_client("测甲全流程", "C_life_a")
	a.check(await _wait_hello(host), "房主 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房收到房间状态")
	var guest := _make_client("测乙全流程", "C_life_b")
	guest.debug_record = true
	a.check(await _wait_hello(guest), "客人 hello")
	a.check(await _join_room(guest, code), "客人入座（room_state 广播）")
	a.eq(guest.my_seat, 1, "客人坐 1 号位")

	# 人数不满：不开局并报错
	host.request_start(false)
	var err := await _wait_error(host)
	a.check(err.contains("人数不满"), "人数不满拒绝开局：%s" % err)
	# 补 AI 开局
	a.check(await _start_fill(host), "补 AI 开局（双方收到 game_start 建视图）")
	if host.view == null or guest.view == null:
		a.check(false, "视图未建立")
		await _cleanup_room()
		await _free_clients()
		return
	a.eq(host.view.counts, [19, 19, 19, 19], "开局四家 19 张")
	var room := _room_by_code(code)
	a.check(room != null, "服务端房间存在")
	if room == null:
		await _cleanup_room()
		await _free_clients()
		return
	a.eq(room.human_count(), 2, "人类 2 人")
	a.check(room.members[2].is_ai and room.members[3].is_ai, "2/3 号位补电脑")

	# 完整对局（人类代打驱动）
	var result := await _wait_game_over(host)
	a.check(not result.is_empty(), "对局完整打完（60s 内）")
	if is_instance_valid(room) and not result.is_empty():
		a.check(not room.engine.faulted, "服务端引擎无故障")
		a.check(not host.view.faulted and not guest.view.faulted, "客户端视图无故障")
		_check_view_matches_server(a, host, room)
	# 零收益守恒
	var sum := 0
	for p in result.payments:
		sum += int(p)
	a.eq(sum, 0, "四家收益和为零")
	# 分数广播与落盘一致（含 AI 座位）
	a.eq(host.scores_rows.size(), 4, "分数行 = 4 名玩家")
	var store_rows: Array = _store.room_scores(code)
	a.eq(store_rows.size(), 4, "落盘 4 行")
	for row in store_rows:
		a.eq(int(row.games), 1, "%s 计 1 局" % str(row.name))
	# 可见性：回放消息不含隐藏牌面
	_check_privacy(a, guest.recorded)

	# 客人主动退出 → 房间关闭（房主收到累计分弹窗数据）
	var closed := {"rows": [], "reason": ""}
	host.room_closed.connect(func(rows: Array, reason: String):
		closed.rows = rows
		closed.reason = reason, CONNECT_ONE_SHOT)
	guest.send_msg({"t": NetProto.LEAVE})
	a.check(await _until(func(): return str(closed.reason) != "", 5.0), "房主收到 room_closed")
	a.check(str(closed.reason).contains("退出"), "关房原因=%s" % str(closed.reason))
	a.eq((closed.rows as Array).size(), 4, "关房附带累计分")
	a.check(_room_by_code(code) == null, "房间已从服务端摘除")
	await _cleanup_room()
	await _free_clients()


## 超时托管：人类不操作 → AI 纯模块代打（auto 标记广播，服务端状态推进）
func test_hosting_timeout(a) -> void:
	_ensure_server()
	var host := _make_client("测甲托管", "C_host_a")
	a.check(await _wait_hello(host), "hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	a.check(await _start_fill(host), "单人 + 补 AI 开局")
	var hosted := {"kind": "", "auto": false, "seat": -1}
	# 注意不可用 CONNECT_ONE_SHOT：首个 AI 动作（auto=false）也会消费一次性连接
	host.remote_action.connect(func(kind: String, seat: int, auto: bool):
		if auto and str(hosted.kind) == "":
			hosted.kind = kind
			hosted.auto = true
			hosted.seat = seat)
	a.check(await _until(func(): return bool(hosted.auto), 8.0), "超时触发托管")
	a.check(str(hosted.kind) != "", "托管动作种类=%s" % str(hosted.kind))
	# 服务端确实采纳了托管动作（按动作种类核对状态推进）
	var room := _room_by_code(code)
	if room != null and str(hosted.kind) != "":
		var true_seat := NetProto.unrot_seat(int(hosted.seat), host.my_seat)
		match str(hosted.kind):
			NetProto.KIND_BID:
				a.check(room.engine.auction.has_passed(true_seat) or room.engine.phase != GameEngine.Phase.AUCTION,
					"托管 PASS 已被服务端采纳")
			NetProto.KIND_TRUMP:
				a.check(room.engine.phase != GameEngine.Phase.TRUMP, "托管叫主后已离开叫主阶段")
			NetProto.KIND_DISCARD:
				a.check(room.engine.phase != GameEngine.Phase.DISCARD, "托管扣底后已离开扣底阶段")
			NetProto.KIND_PLAY:
				a.check(room.engine.current_plays.size() > 0 or room.engine.trick_history.size() > 0,
					"托管出牌已入局")
	await _cleanup_room()
	await _free_clients()


## 断线重连：掉线 → 离线宽限 → 同昵称重连发快照恢复 → 打完；宽限超时关房
func test_reconnect_and_grace(a) -> void:
	_ensure_server()
	var host := _make_client("测甲重连", "C_re_a")
	var guest := _make_client("测乙重连", "C_re_b")
	a.check(await _wait_hello(host), "房主 hello")
	a.check(await _wait_hello(guest), "客人 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	a.check(await _join_room(guest, code), "入座")
	a.check(await _start_fill(host), "开局")
	a.check(await _drive_until(host, func(): return host.view != null and host.view.phase == GameEngine.Phase.TRICKS, 30.0),
		"进入出牌阶段")

	# 掉线：宽限期开始，房间不散
	host.drop_connection()
	a.check(await _until(func(): return _any_offline(guest), 5.0), "对方收到 member_offline")
	a.check(_room_by_code(code) != null, "宽限期内房间存活")
	# 同昵称重连：快照恢复
	var re := _make_client("测甲重连", "C_re_a2")
	a.check(await _wait_hello(re), "重连 hello")
	a.check(await _until(func(): return re.view != null and bool(re.room_state.get("rejoined", false)), 5.0),
		"重连回房并收到快照")
	var room := _room_by_code(code)
	if re.view == null or room == null:
		a.check(false, "重连恢复失败")
		await _cleanup_room()
		await _free_clients()
		return
	a.eq(re.view.trick_history.size(), room.engine.trick_history.size(), "快照恢复轮数一致")
	a.eq(re.view.get_hand(0).size(), re.view.counts[0], "快照恢复手牌与张数一致")
	a.check(re.view.phase == GameEngine.Phase.TRICKS, "恢复到出牌阶段")
	# 继续打完
	var finished := {"done": false}
	re.game_finished.connect(func(_r: Dictionary): finished.done = true, CONNECT_ONE_SHOT)
	a.check(await _drive_until(re, func(): return bool(finished.done), 60.0), "重连后对局打完")

	# 宽限超时：按退出处理，房间关闭
	re.drop_connection()
	var closed := {"reason": ""}
	guest.room_closed.connect(func(_rows: Array, reason: String): closed.reason = reason, CONNECT_ONE_SHOT)
	a.check(await _until(func(): return str(closed.reason) != "", 8.0), "宽限超时房间关闭")
	a.check(str(closed.reason).contains("离线超时"), "原因=%s" % str(closed.reason))
	await _cleanup_room()
	await _free_clients()


## 多局累计：房主开下一局（庄位轮换、视图原地重灌）→ 第二局 → 跨局累计分一致；非房主 next 被拒
func test_multi_game_cumulative(a) -> void:
	_ensure_server()
	var host := _make_client("测甲多局", "C_mg_a")
	var guest := _make_client("测乙多局", "C_mg_b")
	a.check(await _wait_hello(host), "房主 hello")
	a.check(await _wait_hello(guest), "客人 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	a.check(await _join_room(guest, code), "入座")
	a.check(await _start_fill(host), "开局")
	var room := _room_by_code(code)

	# 第一局
	var r1 := await _wait_game_over(host)
	a.check(not r1.is_empty(), "第一局完成")
	a.check(await _until(func(): return host.scores_rows.size() == 4, 5.0), "第一局分数广播")
	# 非房主 next 被拒
	guest.request_next()
	var err := await _wait_error(guest)
	a.check(err.contains("只有房主"), "非房主开下一局被拒：%s" % err)
	# 房主 next：双方视图原地重灌
	host.request_next()
	a.check(await _until(func(): return host.view != null and guest.view != null \
			and host.view.round_index == 2 and guest.view.round_index == 2, 8.0),
		"双方进入第二局")
	a.eq(host.view.counts, [19, 19, 19, 19], "第二局重发 19 张")
	a.eq(host.view.cumulative, r1.cumulative, "第二局视图注入上一局累计")
	# 庄位轮换（规则 4）：上局庄家胜 → 庄家连庄；败 → 下一位
	var expected_dealer: int = int(r1.banker_seat) if bool(r1.banker_won) else (int(r1.banker_seat) + 1) % 4
	a.eq(int(room.engine.dealer_seat), expected_dealer, "第二局抓牌庄按规则 4 轮换")

	# 第二局
	var r2 := await _wait_game_over(host)
	a.check(not r2.is_empty(), "第二局完成")
	# 跨局累计：cumulative2 == cumulative1 + payments2（逐座位）
	for s in GameEngine.PLAYER_COUNT:
		a.eq(int(r2.cumulative[s]), int(r1.cumulative[s]) + int(r2.payments[s]),
			"座位 %d 跨局累计一致" % s)
	# 分数落盘：games==2、score==累计
	a.check(await _until(func(): return host.scores_rows[0].games == 2, 5.0), "第二局分数广播")
	var by_name := {}
	for row in _store.room_scores(code):
		by_name[str(row.name)] = row
	var members: Array = room.members
	for s in GameEngine.PLAYER_COUNT:
		var name: String = str(members[s].name)
		a.check(by_name.has(name), "落盘含 %s" % name)
		a.eq(int(by_name[name].games), 2, "%s 计 2 局" % name)
		a.eq(int(by_name[name].score), int(r2.cumulative[s]), "%s 累计分与引擎一致" % name)
	await _cleanup_room()
	await _free_clients()


## 注入强牌局：确定性旋转校验 + 人类完整操作路径（叫分值/叫主/扣底/出牌）+ 非法操作拒绝
func test_view_rotation_and_human_paths(a) -> void:
	_ensure_server()
	var host := _make_client("测甲旋转", "C_ro_a")
	var guest := _make_client("测乙旋转", "C_ro_b")
	guest.debug_record = true
	a.check(await _wait_hello(host), "房主 hello")
	a.check(await _wait_hello(guest), "客人 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	a.check(await _join_room(guest, code), "入座")
	var deal := _strong_deal()
	var room := _room_by_code(code)
	if room == null:
		a.check(false, "服务端房间存在")
		await _free_clients()
		return
	room._test_start_with_deal(3, deal[0], deal[1])  # dealer=3 → 首个表态座位 = 0（人类房主）
	a.check(await _until(func(): return host.view != null and guest.view != null, 8.0), "开局建视图")

	# 人类叫分值 200（封顶 → 三家 AI 强制放弃，0 号必为庄家）
	host.send_act(NetProto.KIND_BID, {"value": 200})
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.TRUMP, 8.0),
		"人类叫分成交进入叫主阶段")
	a.eq(int(host.view.banker_seat), 0, "房主（0 号位）为出牌庄家")
	a.eq(int(host.view.contract), 200, "叫分 200")
	# 旋转校验（真座位 0 → 客人本地座位 3）
	a.eq(int(guest.view.banker_seat), 3, "客人视角庄家 = 本地 3 号位")
	a.eq(int(guest.view.auction.bid_value(3)), 200, "客人视角叫分记录旋转一致")
	a.eq(int(guest.view.auction.bid_value(2)), 130, "客人视角庄家底叫旋转一致（真座位 3 → 本地 2）")
	_check_view_matches_server(a, guest, room)

	# 人类叫主：♠ + R5（真座位 0 的视图与客人视图主牌一致）
	host.send_act(NetProto.KIND_TRUMP, {"suit": Card.Suit.SPADE, "rank": Card.RANK_5})
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.DISCARD, 8.0),
		"进入扣底阶段")
	a.check(host.view.trump != null and host.view.trump.suit == Card.Suit.SPADE, "庄家视图主牌花色")
	a.check(guest.view.trump != null and guest.view.trump.suit == Card.Suit.SPADE, "客人视图主牌花色")
	# 翻底：庄家 27 张（私有下发），客人仍 19 张且不持有底牌
	a.eq(host.view.get_hand(0).size(), 27, "庄家翻底入手 27 张")
	a.eq(guest.view.get_hand(0).size(), 19, "客人仍 19 张（无底牌）")
	a.eq(int(guest.view.counts[3]), 27, "客人视角庄家张数 27（公开计数）")
	# 底牌保密：客人录制的消息不得出现 kitty
	var kitty_leak := false
	for msg in guest.recorded:
		if str(msg.get("t", "")) == NetProto.KITTY:
			kitty_leak = true
	a.check(not kitty_leak, "底牌私有消息未发给非庄家")

	# 人类扣底（AI 决策确定性选 8 张）
	host.send_discard(AiPlay.choose_discard(host.view.get_hand(0), host.view.trump, GameEngine.BOTTOM_SIZE))
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.TRICKS, 8.0),
		"进入出牌阶段")
	a.eq(host.view.get_hand(0).size(), 19, "扣底后庄家 19 张")
	a.eq(host.view.buried.size(), 8, "庄家视角持有所扣 8 张")
	a.eq(int(room.engine.buried_points), host.view.buried_points, "底牌分值视图与服务端一致")

	# 人类非法出牌：两张不同点数的牌（不成型）→ 服务器拒绝、状态不变、可重试合法出牌。
	# 键字符串排序下 hand[0]/hand[1] 是同点数对（合法），故取 hand[0]+hand[2]（不同点数）
	var hand: Array = host.view.get_hand(0)
	hand.sort_custom(func(x, y): return x.key() < y.key())
	var bad_cards: Array = [hand[0], hand[2]]
	host.send_act(NetProto.KIND_PLAY, {"cards": NetProto.keys_of(bad_cards)})
	var err := await _wait_error(host, 5.0)
	a.check(err != "", "非法出牌收到服务器拒绝：%s" % err)
	a.check(int(room.engine.current_plays.size()) == 0, "非法出牌未入局")
	# 合法出牌：领出单张 → 对局推进（后续 AI 跟牌很快，只断言 >= 1）
	var lead: Array = [hand[0]]
	host.send_act(NetProto.KIND_PLAY, {"cards": NetProto.keys_of(lead)})
	a.check(await _until(func(): return room.engine.current_plays.size() >= 1, 5.0), "合法出牌入局")
	a.check(int(host.view.current_plays.size()) >= 1, "视图同步领出")

	# 其余由代打驱动打完，公开状态全程一致
	var result := await _wait_game_over(host)
	a.check(not result.is_empty(), "强牌局完整打完")
	_check_view_matches_server(a, host, room)
	_check_view_matches_server(a, guest, room)
	# 无主公示路径：三家无黑桃（仅一张 ♠2 在某家），领出主牌轮 → 至少两家被公示
	var void_count := 0
	for s in GameEngine.PLAYER_COUNT:
		if bool(room.engine.trump_void_seats[s]):
			void_count += 1
	a.check(void_count >= 2, "无主公示触发（%d 家）" % void_count)
	# 收益守恒
	var sum := 0
	for p in result.payments:
		sum += int(p)
	a.eq(sum, 0, "收益和为零")
	await _cleanup_room()
	await _free_clients()


## 重连快照矩阵：注入强牌局，在 竞叫后(叫主阶段)/扣底/出牌中/终局 四个阶段掉线重连，
## 断言快照恢复与服务器真值一致（含庄家底牌私有性）
func test_rejoin_phase_snapshots(a) -> void:
	_ensure_server()
	_manager.time_scale = 0.1  # 本用例放宽托管时限（叫主 3s/扣底 6s），给重连留窗口；结束恢复
	var host := _make_client("测甲快照", "C_snp_a")
	var guest := _make_client("测乙快照", "C_snp_b")
	a.check(await _wait_hello(host), "房主 hello")
	a.check(await _wait_hello(guest), "客人 hello")
	var code := await _create_room(host)
	a.check(code != "", "建房")
	a.check(await _join_room(guest, code), "入座")
	var deal := _strong_deal()
	var room := _room_by_code(code)
	if room == null:
		a.check(false, "服务端房间存在")
		_manager.time_scale = 0.02
		await _free_clients()
		return
	room._test_start_with_deal(3, deal[0], deal[1])
	a.check(await _until(func(): return host.view != null and guest.view != null, 8.0), "开局建视图")

	# —— CP1 叫主阶段（竞叫已结）：guest 掉线重连
	host.send_act(NetProto.KIND_BID, {"value": 200})
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.TRUMP, 8.0),
		"进入叫主阶段")
	guest.drop_connection()
	a.check(await _until(func(): return _any_offline(host), 5.0), "host 收到 member_offline")
	var re1 := await _rejoin_guest("测乙快照", "C_snp_b1")
	a.check(re1.view.phase == GameEngine.Phase.TRUMP, "CP1 快照恢复到叫主阶段")
	a.eq(int(re1.view.banker_seat), 3, "CP1 庄家旋转一致")
	a.eq(int(re1.view.contract), 200, "CP1 叫分一致")
	_check_view_matches_server(a, re1, room)

	# —— CP2 扣底阶段：host 叫主后、扣底前重连（庄家底牌只进庄家快照）
	host.send_act(NetProto.KIND_TRUMP, {"suit": Card.Suit.SPADE, "rank": Card.RANK_5})
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.DISCARD, 8.0),
		"进入扣底阶段")
	a.eq(host.view.get_hand(0).size(), 27, "庄家翻底 27 张")
	guest = re1
	guest.drop_connection()
	a.check(await _until(func(): return _any_offline(host), 5.0), "host 再次收到 member_offline")
	var re2 := await _rejoin_guest("测乙快照", "C_snp_b2")
	a.check(re2.view.phase == GameEngine.Phase.DISCARD, "CP2 快照恢复到扣底阶段")
	a.eq(re2.view.get_hand(0).size(), 19, "CP2 非庄家快照不含底牌（仍 19 张）")
	_check_view_matches_server(a, re2, room)

	# —— CP3 出牌阶段（首轮回合中）：host 扣底，打完第一轮后重连
	host.send_discard(AiPlay.choose_discard(host.view.get_hand(0), host.view.trump, GameEngine.BOTTOM_SIZE))
	a.check(await _until(func(): return host.view != null and host.view.phase == GameEngine.Phase.TRICKS, 8.0),
		"进入出牌阶段")
	a.check(await _drive_until(host, func(): return host.view != null and host.view.trick_history.size() >= 1, 30.0),
		"首轮回合结算")
	guest = re2
	guest.drop_connection()
	a.check(await _until(func(): return _any_offline(host), 5.0), "host 第三次收到 member_offline")
	var re3 := await _rejoin_guest("测乙快照", "C_snp_b3")
	a.check(re3.view.phase == GameEngine.Phase.TRICKS, "CP3 快照恢复到出牌阶段")
	a.eq(re3.view.trick_history.size(), room.engine.trick_history.size(), "CP3 历史轮数一致")
	_check_view_matches_server(a, re3, room)

	# —— CP4 终局：打完后重连（恢复结算面板数据）
	var result := await _wait_game_over(host, 90.0)
	a.check(not result.is_empty(), "对局打完")
	guest = re3
	guest.drop_connection()
	a.check(await _until(func(): return _any_offline(host), 5.0), "host 第四次收到 member_offline")
	var re4 := await _rejoin_guest("测乙快照", "C_snp_b4")
	a.check(re4.view.phase == GameEngine.Phase.SETTLED, "CP4 快照恢复到终局")
	a.check(not re4.view.last_game_result.is_empty(), "CP4 恢复终局结果（结算面板数据）")
	a.eq(int(re4.view.last_game_result.payments[3]), int(result.payments[0]),
		"CP4 收益（旋转后本庄家视角）一致")
	_check_view_matches_server(a, re4, room)

	_manager.time_scale = 0.02
	await _cleanup_room()
	await _free_clients()


func _rejoin_guest(nick: String, node_name: String) -> NetClient:
	var re := _make_client(nick, node_name)
	await _wait_hello(re)
	await _until(func(): return re.view != null and bool(re.room_state.get("rejoined", false)), 5.0)
	return re


## UI 级联机牌桌：真实场景接管（game_table._online）+ 人类经真实 UI 提交方法打完整局
## + 结算面板房主下一局可见 + 退出 → 累计分弹层 → 确定 → 回主菜单
func test_ui_online_table(a) -> void:
	_ensure_server()
	var owner := _make_client("测甲界面", "NetClient", false)  # 节点名固定：牌桌按名定位
	var guest := _make_client("测乙界面", "C_ui_b")
	a.check(await _wait_hello(owner), "房主 hello")
	a.check(await _wait_hello(guest), "客人 hello")
	var code := await _create_room(owner)
	a.check(code != "", "建房")
	a.check(await _join_room(guest, code), "入座")
	var deal := _strong_deal()
	var room := _test_room()
	room._test_start_with_deal(3, deal[0], deal[1])  # dealer=3 → 0 号人类房主主导全程

	# 牌桌场景接管：NetClient 收到 game_start → change_scene(game_table) → _online
	var tree: SceneTree = Engine.get_main_loop()
	var table = null
	a.check(await _until(func():
		table = tree.current_scene
		return table != null and table.get("_online") == true, 8.0), "联机牌桌场景接管")
	a.check(table.engine != null and table.engine is TableView, "牌桌引擎为联机视图")
	# 座位名（本地座位序 + 你/AI 标注）
	a.eq(str(table.seat_names[0]), "测甲界面（你）", "0 号位 = 本人昵称")
	a.eq(str(table.seat_names[1]), "测乙界面", "1 号位 = 对方昵称")
	a.eq(str(table.seat_names[2]), "电脑·丙", "2 号位 = 电脑补位")
	# 加速牌桌侧计时（服务端 AI 节拍已由 time_scale 缩放）
	table._trick_timer.wait_time = 0.01
	table._trump_reveal.fly_duration = 0.01

	# 人类叫分（真实 UI 提交方法）
	table._submit_human_bid(200)
	a.check(await _until(func(): return table.engine.phase == GameEngine.Phase.TRUMP, 10.0), "叫分成交进入叫主")
	a.eq(int(table.engine.contract), 200, "叫分 200")
	# 人类叫主（两步：花色 + 点数）
	table._pending_trump_suit = Card.Suit.SPADE
	table._submit_human_trump(Card.RANK_5)
	a.check(await _until(func(): return table.engine.phase == GameEngine.Phase.DISCARD, 10.0), "进入扣底")
	a.eq(table.engine.get_hand(0).size(), 27, "翻底 27 张（底牌入手即选中）")
	# 人类扣底（底牌 8 张已预选，直接确认）
	table._submit_human_discard()
	a.check(await _until(func(): return table.engine.phase == GameEngine.Phase.TRICKS, 10.0), "进入出牌")
	a.eq(table.engine.get_hand(0).size(), 19, "扣底后 19 张")

	# 出牌主循环：人类出牌走 hand_area.selected + _submit_human_play（真实 UI 路径）
	var settled := {"done": false}
	owner.game_finished.connect(func(_r: Dictionary): settled.done = true, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + 90000
	while not bool(settled.done) and Time.get_ticks_msec() < deadline:
		var v = table.engine
		if v.phase == GameEngine.Phase.TRICKS and int(v.turn_seat) == 0 \
				and table.action_bar.get_child_count() > 0:
			table.hand_area.selected.clear()
			for c in AiPlay.choose_play(v.get_hand(0), v.trump, v.current_plays,
					0, v.banker_seat, v.trick_history, v.trump_void_seats):
				table.hand_area.selected.append(c)
			table._submit_human_play()
		await tree.create_timer(0.02).timeout
	a.check(bool(settled.done), "UI 牌桌完整打完一局")
	a.check(await _until(func(): return table.result_panel.visible, 10.0), "结算面板弹出")
	a.check(table.result_next_button.visible, "房主结算面板可见【下一局】")
	_check_view_matches_server(a, owner, room)

	# 退出：牌桌主菜单按钮 → leave → 累计分弹层 → 确定 → 回主菜单
	table._on_menu()
	a.check(await _until(func(): return tree.root.get_node_or_null("ScoresDialog") != null, 5.0),
		"主动退出弹累计分窗")
	var dialog := tree.root.get_node("ScoresDialog")
	var ok_button := _find_button(dialog)
	a.check(ok_button != null, "弹层含确定按钮")
	if ok_button != null:
		ok_button.pressed.emit()
	a.check(await _until(func():
		var cs = tree.current_scene
		return cs != null and cs.name == "MainMenu", 5.0), "确定后回主菜单")
	await _cleanup_room()
	await _free_clients()


func _any_offline(nc: NetClient) -> bool:
	for m in nc.room_state.get("members", []):
		if bool(m.get("offline", false)):
			return true
	return false


## 可见性断言：客人视角的回放消息不含隐藏牌面
func _check_privacy(a, recorded: Array) -> void:
	a.check(recorded.size() > 0, "录制到回放消息")
	for msg in recorded:
		var t: String = str(msg.get("t", ""))
		if t == NetProto.ACT and str(msg.get("kind", "")) == NetProto.KIND_DISCARD:
			a.check(not msg.has("cards"), "扣底广播不得含牌面")
		if t == NetProto.GAME_START:
			a.check(not msg.has("kitty"), "开局不得含底牌")
			a.check(not msg.has("buried"), "开局不得含所扣之牌")
			a.eq((msg.my_hand as Array).size(), 19, "game_start 只含本人 19 张")
		if t == NetProto.SNAPSHOT:
			# 快照只在本人是庄家时允许 kitty/buried；此处对局中重连的接收方不定，
			# 只断言：不含任何他人手牌字段
			a.check(not msg.has("hands"), "快照不得含他人手牌")
