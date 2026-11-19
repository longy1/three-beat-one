extends Node
## 单间房间宿主（M4 服务端）：权威 GameEngine + AI 座位定时驱动 + 消息广播。
## 架构遵循 [构7] 预留约定：
## - 权威状态唯一来自本进程的 GameEngine；submit_* 是唯一状态变更入口；
## - 服务端绕过 AiPolicy 门面直调 AiBidding/AiPlay 纯模块（数据进/决策出）；
## - 每次成功提交即广播动作回放；客户端只收公开回放 + 自己的手牌（可见性裁剪）。
## 可见性纪律：他人手牌、底牌牌面、所扣之牌面永不出现在广播消息里；
## 扣底广播只发座位与新张数；底牌仅在其庄家叫主成交后私有下发（规则 2）。
## 超时托管：人类轮次倒计时，超时由 AI 纯模块按该座位手牌代打（auto=true 广播）。
## 离线快托管：掉线座位的回合改用短超时（OFFLINE_TURN_TIMEOUT），他人不必干等。
## 断线宽限：成员掉线标 offline 并开宽限计时，期间其回合由托管代打、对局继续；
## 宽限内凭会话令牌 hello（或旧连接任意消息复活）即回房（对局中发公开状态快照），
## 回合计时若在走则重挂满正常时长给足决策窗口；逾期按退出关房。
## 服务端重启不散房：每次成功变更即全量序列化落盘（store.save_live_room），
## 启动时 restore_from 重建（成员离线、令牌保留，客户端凭 token 重连回房）。
## 主动 leave 立即关房（所有成员收到 room_closed → 结算弹窗 → 主菜单）。


signal closed(room: Node)  ## 房间解散（manager 摘除并释放）

const AI_DELAY := 0.7
const AI_DISCARD_DELAY := 1.0
const TRICK_PAUSE := 1.5
## 人类回合超时托管（秒）
const TIMEOUT_BID := 20.0
const TIMEOUT_TRUMP := 30.0
const TIMEOUT_DISCARD := 60.0
const TIMEOUT_PLAY := 30.0
## 掉线宽限（秒）：逾期按退出处理（口径与客户端自动重连窗口对齐，见 [史]）
const OFFLINE_GRACE := 180.0
## 离线座位回合的托管超时（秒）：比正常回合超时短，他人不必干等
const OFFLINE_TURN_TIMEOUT := 5.0

const AI_NAMES := {1: "电脑·乙", 2: "电脑·丙", 3: "电脑·丁"}

const STATUS_LOBBY := "LOBBY"
const STATUS_GAME := "GAME"

var code := ""
var owner_name := ""
var status := STATUS_LOBBY
## 座位 0~3 定长的成员槽：null=空位；元素 { seat, name, is_ai, peer_id(0=AI), offline }
var members: Array = [null, null, null, null]
var engine: GameEngine
var _rng := RandomNumberGenerator.new()
var _manager: Node = null  ## RoomManager（广播/定向发送），动态加载无 class_name
var _store: RefCounted = null
var time_scale := 1.0  ## 测试加速钩子：所有计时等待按比例缩小

var _ai_timer: Timer
var _pending_ai: Callable = Callable()  ## 单发复用 _ai_timer 的待执行回调
var _turn_timer: Timer
var _turn_seat := -1      ## 托管目标座位（人类回合计时中）
var _turn_kind := ""      ## bid/trump/discard/play
var _after_settle := false  ## 出牌节拍：结算停留后的第一手加 TRICK_PAUSE（对齐单机节奏）


func setup(p_manager: Node, p_code: String, p_owner: String, p_store: RefCounted) -> void:
	_manager = p_manager
	code = p_code
	owner_name = p_owner
	_store = p_store


func _ready() -> void:
	_rng.randomize()
	_ai_timer = Timer.new()
	_ai_timer.one_shot = true
	add_child(_ai_timer)
	_turn_timer = Timer.new()
	_turn_timer.one_shot = true
	_turn_timer.timeout.connect(_on_turn_timeout)
	add_child(_turn_timer)
	# 权威引擎信号接线（与客户端牌桌同一信号面）
	engine = GameEngine.new()
	engine.auction_required.connect(_on_auction_required)
	engine.trump_required.connect(_on_trump_required)
	engine.discard_required.connect(_on_discard_required)
	engine.play_required.connect(_on_play_required)
	engine.trick_settled.connect(_on_trick_settled)
	engine.game_over.connect(_on_game_over)
	engine.engine_fault.connect(_on_engine_fault)


## ============================= 成员与房间生命周期 =============================

func human_count() -> int:
	var n := 0
	for m in members:
		if m != null and not m.is_ai:
			n += 1
	return n


## 房主座位跟人不跟座（大厅可落座/换座）：按房主昵称找当前座位，缺省 0 号位
func owner_seat() -> int:
	for m in members:
		if m != null and not m.is_ai and m.name == owner_name:
			return m.seat
	return 0


func add_member(nick: String, peer_id: int, token := "") -> int:
	for s in members.size():
		if members[s] == null:
			members[s] = {"seat": s, "name": nick, "is_ai": false, "peer_id": peer_id,
				"offline": false, "token": token}
			_persist()
			return s
	return -1


## 会话令牌 → 成员（重连身份键；AI 成员无令牌）。未命中返回 null。
func member_by_token(token: String):
	if token == "":
		return null
	for m in members:
		if m != null and str(m.get("token", "")) == token:
			return m
	return null


func member_by_name(nick: String):
	for m in members:
		if m != null and m.name == nick:
			return m
	return null


func member_by_peer(peer_id: int):
	for m in members:
		if m != null and m.peer_id == peer_id:
			return m
	return null


## 大厅落座：空位挪入、他人占座互换（成员字典整体对调，昵称/离线态随人走）。
## 返回 "" 或错误信息；座位变更经 room_state 广播（manager 落地后广播）。
func sit(nick: String, seat: int) -> String:
	if status != STATUS_LOBBY:
		return "对局进行中，无法换座"
	if seat < 0 or seat >= members.size():
		return "座位无效"
	var mine = member_by_name(nick)
	if mine == null:
		return "你不在房间中"
	var my_seat: int = mine.seat
	if seat == my_seat:
		return ""
	var target = members[seat]
	if target != null and target.is_ai:
		return "该座位不可用"
	if target != null:
		target.seat = my_seat  # 互换：对方整体挪到我原来的座位
	members[my_seat] = target
	mine.seat = seat
	members[seat] = mine
	_persist()
	return ""


func seat_names() -> Array:
	var names: Array = []
	for m in members:
		names.append(m.name if m != null else "")
	return names


func build_room_state(rejoined := false) -> Dictionary:
	var list: Array = []
	for m in members:
		if m != null:
			list.append({"seat": m.seat, "name": m.name, "is_ai": m.is_ai, "offline": m.offline})
		else:
			list.append({"seat": list.size(), "name": "", "is_ai": false, "offline": false})
	return {
		"t": NetProto.ROOM_STATE, "code": code, "members": list,
		"owner_seat": owner_seat(), "status": status, "rejoined": rejoined,
	}


func broadcast_room_state(rejoined := false) -> void:
	broadcast(build_room_state(rejoined))


## 房主开始对局（fill_ai=true 时补满电脑）。返回 "" 或错误信息。
func start_game(fill_ai: bool) -> String:
	if status != STATUS_LOBBY:
		return "对局已开始"
	if human_count() < GameEngine.PLAYER_COUNT:
		if not fill_ai:
			return "人数不满（%d/%d）" % [human_count(), GameEngine.PLAYER_COUNT]
		for s in members.size():
			if members[s] == null:
				members[s] = {"seat": s, "name": AI_NAMES[s], "is_ai": true, "peer_id": 0,
					"offline": false, "token": ""}
	_begin_engine_game()
	_persist()
	return ""


## 房主开下一局（引擎内部完成庄位轮换，规则 4）。返回 "" 或错误信息。
func next_game() -> String:
	if status != STATUS_GAME:
		return "尚未开局"
	if not engine.start_next_game():
		return "本局尚未结束"
	_broadcast_game_start()
	_persist()
	return ""


## 测试钩子：注入固定牌型开局（对齐 GameEngine.start_session_with_deal 用法）
func _test_start_with_deal(dealer: int, test_hands: Array, test_kitty: Array) -> void:
	for s in members.size():
		if members[s] == null:
			members[s] = {"seat": s, "name": AI_NAMES[s], "is_ai": true, "peer_id": 0,
				"offline": false, "token": ""}
	engine.start_session_with_deal(dealer, test_hands, test_kitty)
	status = STATUS_GAME
	_broadcast_game_start()
	_persist()


func _begin_engine_game() -> void:
	status = STATUS_GAME
	engine.start_session()  # 引擎内部随机首局抓牌庄（规则 4）
	_broadcast_game_start()


## 开局/下一局广播：按成员逐一定向（my_hand 各不相同）
func _broadcast_game_start() -> void:
	for m in members:
		if m == null or m.is_ai:
			continue
		_manager.send_to(m.peer_id, _game_start_for(m.seat))


func _game_start_for(seat: int) -> Dictionary:
	return {
		"t": NetProto.GAME_START,
		"round": engine.round_index,
		"dealer": engine.dealer_seat,
		"my_hand": NetProto.keys_of(engine.get_hand(seat)),
		"counts": _counts(),
		"members": _members_payload(),
		"cumulative": engine.cumulative.duplicate(),
	}


func _members_payload() -> Array:
	var list: Array = []
	for m in members:
		list.append({"seat": m.seat, "name": m.name, "is_ai": m.is_ai, "offline": m.offline})
	return list


func _counts() -> Array:
	var counts: Array = []
	for s in GameEngine.PLAYER_COUNT:
		counts.append(engine.hand_count(s))
	return counts


## ============================= 重连与离线 =============================

## 成员掉线（manager 扫描判定）：标记 + 广播（附宽限秒数供倒计时显示）+ 开宽限计时；
## 其回合计时若在走则缩短为快托管超时
func mark_offline(seat: int) -> void:
	var m = members[seat]
	if m == null or m.is_ai or m.offline:
		return
	m.offline = true
	_persist()
	broadcast({"t": NetProto.MEMBER_OFFLINE, "seat": seat, "name": m.name, "grace": OFFLINE_GRACE})
	if _turn_seat == seat and _turn_timer.time_left > OFFLINE_TURN_TIMEOUT * time_scale:
		_turn_timer.wait_time = OFFLINE_TURN_TIMEOUT * time_scale
		_turn_timer.start()
	_arm_grace_timer(seat)


## 宽限内重连（同昵称 hello 或旧连接消息复活）：解除离线、广播房间状态、
## 对局中补发公开快照；其回合计时若在走则重挂满正常时长（给足决策窗口）
func reconnect(peer_id: int, nick: String) -> void:
	var m = member_by_name(nick)
	if m == null:
		return
	m.peer_id = peer_id
	m.offline = false
	_cancel_grace_timer(m.seat)
	_persist()
	broadcast_room_state(true)
	if _turn_seat == m.seat:
		_turn_timer.wait_time = _turn_timeout_for(_turn_kind) * time_scale
		_turn_timer.start()
	if status == STATUS_GAME:
		_manager.send_to(peer_id, _snapshot_for(m.seat))


func _arm_grace_timer(seat: int) -> void:
	_cancel_grace_timer(seat)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = OFFLINE_GRACE * time_scale
	t.timeout.connect(_on_grace_expired.bind(seat))
	t.set_meta("grace_seat", seat)
	add_child(t)
	t.start()


func _cancel_grace_timer(seat: int) -> void:
	for child in get_children():
		if child is Timer and child.has_meta("grace_seat") and int(child.get_meta("grace_seat")) == seat:
			child.queue_free()


func _on_grace_expired(seat: int) -> void:
	var m = members[seat] if seat >= 0 and seat < members.size() else null
	if m == null or not m.offline:
		return
	close("「%s」离线超时，房间解散" % m.name)


## ============================= 消息入口（manager 分发） =============================

## 人类操作落地。verdict 非法时把错误发回提交者，其余成员无感知。
func handle_act(peer_id: int, msg: Dictionary) -> void:
	if status != STATUS_GAME:
		_manager.send_to(peer_id, {"t": NetProto.ERR, "msg": "对局未在进行中"})
		return
	var m = member_by_peer(peer_id)
	if m == null:
		return
	var kind: String = msg.kind
	match kind:
		NetProto.KIND_BID:
			var value: int = msg.value
			_apply_bid(m.seat, value, false, peer_id)
		NetProto.KIND_TRUMP:
			var suit: int = msg.suit
			var rank: int = msg.rank
			_apply_trump(m.seat, suit, rank, false, peer_id)
		NetProto.KIND_DISCARD:
			var cards := NetProto.cards_of(msg.cards)
			_apply_discard(m.seat, cards, false, peer_id)
		NetProto.KIND_PLAY:
			var cards := NetProto.cards_of(msg.cards)
			_apply_play(m.seat, cards, false, peer_id)
		_:
			_manager.send_to(peer_id, {"t": NetProto.ERR, "msg": "未知操作"})


## ============================= 动作落地（AI 与人类共用，广播回放） =============================

func _apply_bid(seat: int, value: int, auto: bool, peer_id := 0) -> void:
	_disarm_turn_timer()
	var verdict := engine.submit_bid(seat, value)
	if not verdict.ok:
		_reject(peer_id, verdict.error)
		return
	_persist()
	broadcast(_act_msg(NetProto.KIND_BID, seat, auto, {"value": value}))


func _apply_trump(seat: int, suit: int, rank: int, auto: bool, peer_id := 0) -> void:
	_disarm_turn_timer()
	var verdict := engine.submit_trump(seat, suit, rank)
	if not verdict.ok:
		_reject(peer_id, verdict.error)
		return
	_persist()
	broadcast(_act_msg(NetProto.KIND_TRUMP, seat, auto, {"suit": suit, "rank": rank}))
	# 翻底：底牌仅其庄家私有下发（规则 2）；之后进入扣底阶段
	var m = members[seat]
	if m != null and not m.is_ai:
		_manager.send_to(m.peer_id, {"t": NetProto.KITTY, "cards": NetProto.keys_of(engine.kitty)})


func _apply_discard(seat: int, cards: Array, auto: bool, peer_id := 0) -> void:
	_disarm_turn_timer()
	var verdict := engine.submit_discard(seat, cards)
	if not verdict.ok:
		_reject(peer_id, verdict.error)
		return
	# 所扣之牌保密：广播不含牌面，只发座位与新张数
	_persist()
	broadcast(_act_msg(NetProto.KIND_DISCARD, seat, auto, {}))


func _apply_play(seat: int, cards: Array, auto: bool, peer_id := 0) -> void:
	_disarm_turn_timer()
	var void_before: Array = engine.trump_void_seats.duplicate()
	var verdict: Dictionary = engine.submit_play(seat, cards)
	if not verdict.legal:
		_reject(peer_id, verdict.text)
		return
	# 无主公示（7.3）先于出牌回放：客户端印章先盖再出牌
	for s in GameEngine.PLAYER_COUNT:
		if engine.trump_void_seats[s] and not void_before[s]:
			broadcast(_act_msg(NetProto.KIND_VOID, s, auto, {}))
	var payload := {"cards": NetProto.keys_of(cards), "role": int(verdict.role)}
	if verdict.get("dump", false):
		payload["dump"] = true
	_persist()
	broadcast(_act_msg(NetProto.KIND_PLAY, seat, auto, payload))


func _act_msg(kind: String, seat: int, auto: bool, payload: Dictionary) -> Dictionary:
	var msg := {"t": NetProto.ACT, "kind": kind, "seat": seat, "counts": _counts()}
	if auto:
		msg["auto"] = true
	for key in payload:
		msg[key] = payload[key]
	return msg


func _reject(peer_id: int, message: String) -> void:
	if peer_id > 0:
		_manager.send_to(peer_id, {"t": NetProto.ERR, "msg": message})


func broadcast(msg: Dictionary) -> void:
	if _manager != null:
		_manager.broadcast_room(self, msg)


## ============================= 引擎信号 → AI/托管调度 =============================

func _on_auction_required(seat: int) -> void:
	var m = members[seat]
	if m != null and not m.is_ai:
		_arm_turn_timer(seat, _human_timeout(TIMEOUT_BID, m), NetProto.KIND_BID)
	else:
		_schedule_ai(AI_DELAY, func(): _ai_bid(seat))


func _ai_bid(seat: int) -> void:
	if not _ai_still_valid(seat, GameEngine.Phase.AUCTION):
		return
	var bid_values: Array = []
	for b in engine.auction.bids:
		bid_values.append(b.value)
	var value: int = AiBidding.choose_bid(engine.hands[seat], engine.current_highest_bid(), _rng, seat, bid_values)
	_apply_bid(seat, value, false)


func _on_trump_required(seat: int) -> void:
	var m = members[seat]
	if m != null and not m.is_ai:
		_arm_turn_timer(seat, _human_timeout(TIMEOUT_TRUMP, m), NetProto.KIND_TRUMP)
	else:
		_schedule_ai(AI_DELAY, func(): _ai_trump(seat))


func _ai_trump(seat: int) -> void:
	if not _ai_still_valid(seat, GameEngine.Phase.TRUMP):
		return
	var choice: Dictionary = AiPlay.choose_trump(engine.hands[seat])
	_apply_trump(seat, choice.suit, choice.rank, false)


func _on_discard_required(seat: int) -> void:
	var m = members[seat]
	if m != null and not m.is_ai:
		_arm_turn_timer(seat, _human_timeout(TIMEOUT_DISCARD, m), NetProto.KIND_DISCARD)
	else:
		_schedule_ai(AI_DISCARD_DELAY, func(): _ai_discard(seat))


func _ai_discard(seat: int) -> void:
	if not _ai_still_valid(seat, GameEngine.Phase.DISCARD):
		return
	var cards: Array = AiPlay.choose_discard(engine.hands[seat], engine.trump, GameEngine.BOTTOM_SIZE)
	_apply_discard(seat, cards, false)


func _on_play_required(seat: int) -> void:
	var delay := AI_DELAY
	if _after_settle:
		delay = TRICK_PAUSE + AI_DELAY  # 对齐单机节奏：结算停留 1.5s 后才起 AI 思考
		_after_settle = false
	var m = members[seat]
	if m != null and not m.is_ai:
		_arm_turn_timer(seat, _human_timeout(TIMEOUT_PLAY, m), NetProto.KIND_PLAY)
	else:
		_schedule_ai(delay, func(): _ai_play(seat))


func _ai_play(seat: int) -> void:
	if not _ai_still_valid(seat, GameEngine.Phase.TRICKS):
		return
	var cards: Array = _ai_play_cards(seat)
	_apply_play(seat, cards, false)


## AI/托管出牌决策（共用）：纯模块按该座位手牌决策，附庄家剩牌量（守门放宽依据）
func _ai_play_cards(seat: int) -> Array:
	return AiPlay.choose_play(engine.hands[seat], engine.trump, engine.current_plays,
		seat, engine.banker_seat, engine.trick_history, engine.trump_void_seats,
		engine.hand_count(engine.banker_seat))


## AI 延迟动作的前置守卫：房间仍在、对局仍在、仍轮到该座位该阶段
func _ai_still_valid(seat: int, phase: int) -> bool:
	if engine == null or status != STATUS_GAME:
		return false
	if engine.faulted or engine.phase != phase:
		return false
	if phase == GameEngine.Phase.AUCTION:
		return engine.auction.turn == seat
	if phase == GameEngine.Phase.TRICKS:
		return engine.turn_seat == seat
	return seat == engine.banker_seat  # TRUMP/DISCARD 均为庄家回合


func _schedule_ai(delay: float, action: Callable) -> void:
	# 单发复用 Timer：一次只挂一个待执行回调，避免 timeout 连接叠加
	if not _ai_timer.timeout.is_connected(_on_ai_timer_fire):
		_ai_timer.timeout.connect(_on_ai_timer_fire)
	_pending_ai = action
	_ai_timer.wait_time = delay * time_scale
	_ai_timer.start()


func _on_ai_timer_fire() -> void:
	var action: Callable = _pending_ai
	_pending_ai = Callable()
	if action.is_valid():
		action.call()


func _arm_turn_timer(seat: int, timeout: float, kind: String) -> void:
	_turn_seat = seat
	_turn_kind = kind
	_turn_timer.wait_time = timeout * time_scale
	_turn_timer.start()


## 人类回合超时：离线座位用快托管短超时（他人不必干等），在线座位用正常时长
func _human_timeout(base: float, m) -> float:
	return OFFLINE_TURN_TIMEOUT if bool(m.get("offline", false)) else base


## 回合种类 → 正常超时（重连重挂计时用）
func _turn_timeout_for(kind: String) -> float:
	match kind:
		NetProto.KIND_BID:
			return TIMEOUT_BID
		NetProto.KIND_TRUMP:
			return TIMEOUT_TRUMP
		NetProto.KIND_DISCARD:
			return TIMEOUT_DISCARD
	return TIMEOUT_PLAY


func _disarm_turn_timer() -> void:
	_turn_timer.stop()
	_turn_seat = -1
	_turn_kind = ""


## 人类超时托管：由 AI 纯模块按该座位手牌代打，广播带 auto 标记
func _on_turn_timeout() -> void:
	if engine == null or status != STATUS_GAME or _turn_seat < 0:
		return
	var seat := _turn_seat
	var kind := _turn_kind
	_disarm_turn_timer()
	match kind:
		NetProto.KIND_BID:
			_apply_bid(seat, GameEngine.BID_PASS, true)
		NetProto.KIND_TRUMP:
			var choice: Dictionary = AiPlay.choose_trump(engine.hands[seat])
			_apply_trump(seat, choice.suit, choice.rank, true)
		NetProto.KIND_DISCARD:
			var cards: Array = AiPlay.choose_discard(engine.hands[seat], engine.trump, GameEngine.BOTTOM_SIZE)
			_apply_discard(seat, cards, true)
		NetProto.KIND_PLAY:
			_apply_play(seat, _ai_play_cards(seat), true)


## ============================= 结算 =============================

func _on_trick_settled(_info: Dictionary) -> void:
	_after_settle = true
	# 客户端用公开数据本地同源结算（Trick.settle），无需广播；节奏标记供出牌调度用


func _on_game_over(result: Dictionary) -> void:
	# 房间累计分入库并广播（分数持久化，服务端重启不丢）
	var rows: Array = []
	for s in GameEngine.PLAYER_COUNT:
		var m = members[s]
		if m != null:
			rows.append({"name": m.name, "delta": int(result.payments[s])})
	_store.add_scores(code, rows)
	_persist()
	var result_out: Dictionary = _ser_result(result)
	broadcast({"t": NetProto.GAME_OVER, "result": result_out})
	broadcast({"t": NetProto.SCORES, "rows": _store.room_scores(code)})


func _ser_result(r: Dictionary) -> Dictionary:
	var out: Dictionary = r.duplicate(true)
	out.trump = {"suit": r.trump.suit, "rank": r.trump.rank} if r.trump != null else null
	return out


func _on_engine_fault(message: String) -> void:
	push_error("HostRoom %s 引擎异常：%s" % [code, message])
	close("服务器对局异常，房间解散")


## ============================= 重连快照（公开状态全量） =============================

func _snapshot_for(seat: int) -> Dictionary:
	var snap := {
		"t": NetProto.SNAPSHOT,
		"round": engine.round_index,
		"dealer": engine.dealer_seat,
		"banker": engine.banker_seat,
		"phase": engine.phase,
		"my_hand": NetProto.keys_of(engine.get_hand(seat)),
		"counts": _counts(),
		"members": _members_payload(),
		"cumulative": engine.cumulative.duplicate(),
		"void_seats": engine.trump_void_seats.duplicate(),
		"captured": engine.captured_points,
		"owner_seat": owner_seat(),
		"code": code,
		"status": status,
		"trick_history": _ser_trick_history(),
	}
	if engine.phase == GameEngine.Phase.AUCTION:
		snap["bids"] = engine.auction.bids.duplicate(true)
		snap["auction_turn"] = engine.auction.turn
	else:
		snap["contract"] = engine.contract
		snap["trump"] = {"suit": engine.trump.suit, "rank": engine.trump.rank} if engine.trump != null else null
	if engine.phase == GameEngine.Phase.TRICKS:
		snap["current_plays"] = _ser_current_plays()
		snap["turn_seat"] = engine.turn_seat
	if engine.phase == GameEngine.Phase.DISCARD and seat == engine.banker_seat:
		snap["kitty"] = NetProto.keys_of(engine.kitty)
	if engine.phase >= GameEngine.Phase.TRICKS and seat == engine.banker_seat:
		snap["buried"] = NetProto.keys_of(engine.buried)
	if engine.phase == GameEngine.Phase.SETTLED:
		snap["last_result"] = _ser_result(engine.last_game_result)
	return snap


func _ser_current_plays() -> Array:
	var out: Array = []
	for p in engine.current_plays:
		out.append({"seat": p.seat, "cards": NetProto.keys_of(p.cards), "role": int(p.role)})
	return out


func _ser_trick_history() -> Array:
	var out: Array = []
	for th in engine.trick_history:
		var plays: Array = []
		for p in th.plays:
			plays.append({"seat": p.seat, "cards": NetProto.keys_of(p.cards), "role": int(p.role)})
		out.append({"plays": plays, "winner": th.winner})
	return out


## ============================= 服务端重启不散房（序列化/恢复） =============================

## 全量状态落盘（每次成功变更后 _persist 调用）：成员（含会话令牌）+ 引擎。
## 只写本地存储、不进任何广播——令牌不出服务端。
func serialize() -> Dictionary:
	var member_list: Array = []
	for m in members:
		if m == null:
			continue
		member_list.append({"seat": int(m.seat), "name": str(m.name), "is_ai": bool(m.is_ai),
			"offline": bool(m.offline), "token": str(m.get("token", ""))})
	return {"owner_name": owner_name, "status": status, "members": member_list, "engine": _ser_engine()}


## 从落盘快照重建（RoomManager 启动恢复）：成员离线（原连接随进程消亡）、
## 令牌保留（客户端凭 token 重连回房）；宽限计时重挂；待办回合重新调度
func restore_from(data: Dictionary) -> void:
	owner_name = str(data.get("owner_name", ""))
	status = str(data.get("status", STATUS_LOBBY))
	members = [null, null, null, null]
	for m in data.get("members", []):
		var seat: int = int(m.seat)
		if seat < 0 or seat >= members.size():
			continue
		members[seat] = {"seat": seat, "name": str(m.name), "is_ai": bool(m.is_ai),
			"peer_id": 0, "offline": true, "token": str(m.get("token", ""))}
	_engine_restore(data.get("engine", {}))
	for m in members:
		if m != null and not m.is_ai:
			_arm_grace_timer(m.seat)
	_resume_pending_turn()


## 引擎全量序列化（牌以 Card.key() 串传输，与协议同构）
func _ser_engine() -> Dictionary:
	var d := {
		phase = engine.phase,
		round_index = engine.round_index,
		dealer_seat = engine.dealer_seat,
		banker_seat = engine.banker_seat,
		contract = engine.contract,
		hands = [],
		kitty = NetProto.keys_of(engine.kitty),
		buried = NetProto.keys_of(engine.buried),
		buried_points = engine.buried_points,
		auction_bids = engine.auction.bids.duplicate(true),
		auction_turn = engine.auction.turn,
		current_plays = _ser_current_plays(),
		trick_history = _ser_trick_history(),
		trump_void_seats = engine.trump_void_seats.duplicate(),
		leader_seat = engine.leader_seat,
		turn_seat = engine.turn_seat,
		captured_points = engine.captured_points,
		koudi_points = engine.koudi_points,
		cumulative = engine.cumulative.duplicate(),
	}
	for s in GameEngine.PLAYER_COUNT:
		# LOBBY 阶段引擎尚未发牌（hands 为空）：序列化为空手牌
		d.hands.append(NetProto.keys_of(engine.hands[s]) if s < engine.hands.size() else [])
	if engine.trump != null:
		d.trump = {"suit": engine.trump.suit, "rank": engine.trump.rank}
	if not engine.last_game_result.is_empty():
		d.last_game_result = _ser_result(engine.last_game_result)
	return d


## 引擎恢复：日志回放走 JSON 往返，整型字段逐一还原（浮点失真防护与
## NetClient._normalize_result 同口径）
func _engine_restore(d: Dictionary) -> void:
	engine.phase = int(d.get("phase", GameEngine.Phase.IDLE))
	engine.round_index = int(d.get("round_index", 0))
	engine.dealer_seat = int(d.get("dealer_seat", -1))
	engine.banker_seat = int(d.get("banker_seat", -1))
	engine.contract = int(d.get("contract", 0))
	engine.hands = []
	for hs in d.get("hands", []):
		engine.hands.append(NetProto.cards_of(hs))
	engine.kitty = NetProto.cards_of(d.get("kitty", []))
	engine.buried = NetProto.cards_of(d.get("buried", []))
	engine.buried_points = int(d.get("buried_points", 0))
	engine.auction.bids = []
	for b in d.get("auction_bids", []):
		engine.auction.bids.append({"value": int(b.value), "passed": bool(b.passed)})
	engine.auction.turn = int(d.get("auction_turn", -1))
	engine.current_plays = []
	for p in d.get("current_plays", []):
		engine.current_plays.append({"seat": int(p.seat), "cards": NetProto.cards_of(p.cards),
			"role": int(p.role)})
	engine.trick_history = []
	for th in d.get("trick_history", []):
		var plays: Array = []
		for p in th.plays:
			plays.append({"seat": int(p.seat), "cards": NetProto.cards_of(p.cards), "role": int(p.role)})
		engine.trick_history.append({"plays": plays, "winner": int(th.winner)})
	engine.trump_void_seats = []
	for v in d.get("trump_void_seats", [false, false, false, false]):
		engine.trump_void_seats.append(bool(v))
	engine.leader_seat = int(d.get("leader_seat", -1))
	engine.turn_seat = int(d.get("turn_seat", -1))
	engine.captured_points = int(d.get("captured_points", 0))
	engine.koudi_points = int(d.get("koudi_points", 0))
	engine.cumulative = []
	for c in d.get("cumulative", [0, 0, 0, 0]):
		engine.cumulative.append(int(c))
	if d.get("trump") != null:
		engine.trump = TrumpInfo.new(int(d.trump.suit), int(d.trump.rank))
	if d.get("last_game_result") != null:
		engine.last_game_result = _deser_result(d.last_game_result)


## 终局结果反序列化（_ser_result 的逆：trump 字典 → TrumpInfo、整型还原）
func _deser_result(r: Dictionary) -> Dictionary:
	var out := r.duplicate(true)
	out.round = int(r.round)
	out.dealer_seat = int(r.dealer_seat)
	out.banker_seat = int(r.banker_seat)
	out.contract = int(r.contract)
	out.trump = TrumpInfo.new(int(r.trump.suit), int(r.trump.rank)) if r.trump != null else null
	out.captured_points = int(r.captured_points)
	out.koudi_points = int(r.koudi_points)
	out.buried_points = int(r.buried_points)
	out.captured_total = int(r.captured_total)
	out.total_score = int(r.total_score)
	out.level = int(r.level)
	var payments: Array = []
	for p in r.payments:
		payments.append(int(p))
	out.payments = payments
	var cumulative: Array = []
	for c in r.cumulative:
		cumulative.append(int(c))
	out.cumulative = cumulative
	return out


## 恢复后按当前阶段重新调度待办回合（引擎信号不会因恢复自动发出）：
## AI 座位重新调度代打；人类座位（恢复后均离线）重挂快托管计时
func _resume_pending_turn() -> void:
	match engine.phase:
		GameEngine.Phase.AUCTION:
			_arm_seat_turn(engine.auction.turn, NetProto.KIND_BID, TIMEOUT_BID)
		GameEngine.Phase.TRUMP:
			_arm_seat_turn(engine.banker_seat, NetProto.KIND_TRUMP, TIMEOUT_TRUMP)
		GameEngine.Phase.DISCARD:
			_arm_seat_turn(engine.banker_seat, NetProto.KIND_DISCARD, TIMEOUT_DISCARD)
		GameEngine.Phase.TRICKS:
			_arm_seat_turn(engine.turn_seat, NetProto.KIND_PLAY, TIMEOUT_PLAY)
		_:
			pass


func _arm_seat_turn(seat: int, kind: String, timeout: float) -> void:
	var m = members[seat] if seat >= 0 and seat < members.size() else null
	if m == null:
		return
	if m.is_ai:
		var delay := AI_DISCARD_DELAY if kind == NetProto.KIND_DISCARD else AI_DELAY
		match kind:
			NetProto.KIND_BID:
				_schedule_ai(delay, func(): _ai_bid(seat))
			NetProto.KIND_TRUMP:
				_schedule_ai(delay, func(): _ai_trump(seat))
			NetProto.KIND_DISCARD:
				_schedule_ai(delay, func(): _ai_discard(seat))
			NetProto.KIND_PLAY:
				_schedule_ai(delay, func(): _ai_play(seat))
	else:
		_arm_turn_timer(seat, _human_timeout(timeout, m), kind)


## 状态落盘（服务端重启不散房）：每次成功变更即保存全量快照；已关房不落
func _persist() -> void:
	if _store != null and status != "CLOSED":
		_store.save_live_room(code, serialize())


## ============================= 关房 =============================

func close(reason: String) -> void:
	if status == "CLOSED":
		return
	status = "CLOSED"
	_disarm_turn_timer()
	_ai_timer.stop()
	if _store != null:
		_store.clear_live_room(code)
	broadcast({"t": NetProto.ROOM_CLOSED, "reason": reason, "rows": _store.room_scores(code)})
	closed.emit(self)
	queue_free()
