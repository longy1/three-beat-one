extends UiTestBase
## 联机功能测试（M4）：真实 WebSocket 回环（同进程服务端 + 客户端）。
## 覆盖：存储持久化/昵称全局唯一、房间生命周期（不满开局拒绝→补 AI→完整对局→
## 分数落盘广播）、可见性（回放消息不含他人牌面/底牌）、超时托管、断线重连与宽限。
## 服务端计时按 time_scale=0.02 缩放（AI 节拍 ~0.014s、人类托管 ~0.4s、离线宽限 ~2.4s）。


const PORT := 9811
const STORE_PATH := "user://test_online_store.json"
const URL := "ws://127.0.0.1:9811"

var _manager: Node = null
var _store: RefCounted = null
var _clients: Array = []


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
		push_error("回环服务器启动失败：%s" % error_string(err))


func _make_client(nick: String, node_name: String) -> NetClient:
	var nc := NetClient.new()
	nc.name = node_name
	nc.standalone = true
	Engine.get_main_loop().root.add_child(nc)
	nc.connect_to(URL, nick)
	_clients.append(nc)
	return nc


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
	var got := {"msg": ""}
	nc.net_error.connect(func(m: String): got.msg = m, CONNECT_ONE_SHOT)
	await _until(func(): return str(got.msg) != "", timeout)
	return str(got.msg)


func _test_room() -> Node:
	for room in _manager._rooms.values():
		return room
	return null


func _free_clients() -> void:
	for nc in _clients:
		if is_instance_valid(nc):
			nc.queue_free()
	_clients.clear()
	await tree_pause()


func _cleanup_room() -> void:
	for room in _manager._rooms.values():
		room.close("测试清理")
	await tree_pause()


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


## ============================= 用例 =============================

## 存储层：注册唯一性、分数累计、跨实例持久化
func test_store_persistence(a) -> void:
	var path := "user://test_online_store_unit.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var store: RefCounted = load("res://server/store.gd").new(path)
	store.register_player("测试玩家甲")
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": 30}, {"name": "电脑·乙", "delta": -10}])
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": -15}, {"name": "电脑·乙", "delta": 5}])
	# 重开实例：落盘数据完整（重启不丢）
	var store2: RefCounted = load("res://server/store.gd").new(path)
	a.check(store2.has_player("测试玩家甲"), "昵称注册表持久化")
	var rows: Array = store2.room_scores("ROOM01")
	a.eq(rows.size(), 2, "两行累计分")
	var by_name := {}
	for row in rows:
		by_name[str(row.name)] = row
	a.eq(int(by_name["测试玩家甲"].score), 15, "30 + (-15) = 15")
	a.eq(int(by_name["测试玩家甲"].games), 2, "两局")
	a.eq(int(by_name["电脑·乙"].score), -5, "-10 + 5 = -5")
	DirAccess.remove_absolute(path)


## 昵称全局唯一（注册制）与非法昵称拒绝
func test_nick_uniqueness(a) -> void:
	_ensure_server()
	var first := _make_client("测甲唯一", "C_uniq_a")
	a.check(await _wait_hello(first), "首登成功")
	var dup := _make_client("测甲唯一", "C_uniq_dup")
	var err := await _wait_error(dup)
	a.check(err.contains("已被占用"), "同昵称再注册被拒：%s" % err)
	var ai := _make_client(NetProto.AI_NAME_PREFIX + "甲", "C_uniq_ai")
	err = await _wait_error(ai)
	a.check(err.contains("电脑"), "电脑前缀昵称被拒：%s" % err)
	var blank := _make_client("   ", "C_uniq_blank")
	err = await _wait_error(blank)
	a.check(err != "", "空白昵称被拒")
	await _free_clients()


## 房间生命周期：建房/加入/不满开局拒绝/补 AI/完整对局/分数落盘/可见性/退出关房
func test_room_lifecycle_full_game(a) -> void:
	_ensure_server()
	var host := _make_client("测甲全流程", "C_life_a")
	a.check(await _wait_hello(host), "房主 hello")
	host.request_create()
	a.check(await _until(func(): return not host.room_state.is_empty()), "建房收到房间状态")
	var code: String = str(host.room_state.code)
	var guest := _make_client("测乙全流程", "C_life_b")
	guest.debug_record = true
	a.check(await _wait_hello(guest), "客人 hello")
	guest.request_join(code)
	a.check(await _until(func(): return int(guest.my_seat) >= 0), "客人入座（room_state 广播）")
	a.eq(guest.my_seat, 1, "客人坐 1 号位")

	# 人数不满：不开局并报错
	host.request_start(false)
	var err := await _wait_error(host)
	a.check(err.contains("人数不满"), "人数不满拒绝开局：%s" % err)
	# 补 AI 开局
	host.request_start(true)
	a.check(await _until(func(): return host.view != null and guest.view != null), "双方收到 game_start 建视图")
	a.eq(host.view.counts, [19, 19, 19, 19], "开局四家 19 张")
	var room := _test_room()
	a.check(room != null, "服务端房间存在")
	a.eq(room.human_count(), 2, "人类 2 人")
	a.check(room.members[2].is_ai and room.members[3].is_ai, "乙丙丁位补电脑（2/3 号位）")

	# 完整对局（人类代打驱动）
	var finished := {"done": false}
	host.game_finished.connect(func(_r: Dictionary): finished.done = true, CONNECT_ONE_SHOT)
	var ok := await _drive_until(host, func(): return bool(finished.done), 60.0)
	a.check(ok, "对局完整打完（60s 内）")
	a.check(not room.engine.faulted, "服务端引擎无故障")
	a.check(not host.view.faulted and not guest.view.faulted, "客户端视图无故障")
	# 视图与服务端引擎公开状态一致
	a.eq(host.view.captured_points, room.engine.captured_points, "捉分一致")
	a.eq(host.view.trick_history.size(), room.engine.trick_history.size(), "轮数一致")
	a.eq(guest.view.captured_points, room.engine.captured_points, "客人视角捉分一致")
	# 零收益守恒
	var result: Dictionary = host.view.last_game_result
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
	a.check(_test_room() == null, "房间已从服务端摘除")
	await _cleanup_room()
	await _free_clients()


## 超时托管：人类不操作 → AI 纯模块代打（auto 标记广播）
func test_hosting_timeout(a) -> void:
	_ensure_server()
	var host := _make_client("测甲托管", "C_host_a")
	a.check(await _wait_hello(host), "hello")
	host.request_create()
	a.check(await _until(func(): return not host.room_state.is_empty()), "建房")
	host.request_start(true)  # 单人 + 补 AI
	a.check(await _until(func(): return host.view != null), "开局")
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
	var room := _test_room()
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
	host.request_create()
	a.check(await _until(func(): return not host.room_state.is_empty()), "建房")
	var code: String = str(host.room_state.code)
	guest.request_join(code)
	a.check(await _until(func(): return int(guest.my_seat) >= 0), "入座")
	host.request_start(true)
	a.check(await _until(func(): return host.view != null and guest.view != null), "开局")
	a.check(await _drive_until(host, func(): return host.view.phase == GameEngine.Phase.TRICKS, 30.0),
		"进入出牌阶段")

	# 掉线：宽限期开始，房间不散
	host.drop_connection()
	a.check(await _until(func(): return _any_offline(guest), 5.0), "对方收到 member_offline")
	a.check(_test_room() != null, "宽限期内房间存活")
	# 同昵称重连：快照恢复
	var re := _make_client("测甲重连", "C_re_a2")
	a.check(await _wait_hello(re), "重连 hello")
	a.check(await _until(func(): return re.view != null and bool(re.room_state.get("rejoined", false)), 5.0),
		"重连回房并收到快照")
	var room := _test_room()
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
