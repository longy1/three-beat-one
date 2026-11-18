extends Node
## 单间房间宿主（M4 服务端）：权威 GameEngine + AI 座位定时驱动 + 消息广播。
## 架构遵循 [构7] 预留约定：
## - 权威状态唯一来自本进程的 GameEngine；submit_* 是唯一状态变更入口；
## - 服务端绕过 AiPolicy 门面直调 AiBidding/AiPlay 纯模块（数据进/决策出）；
## - 每次成功提交即广播动作回放；客户端只收公开回放 + 自己的手牌（可见性裁剪）。
## 可见性纪律：他人手牌、底牌牌面、所扣之牌面永不出现在广播消息里；
## 扣底广播只发座位与新张数；底牌仅在其庄家叫主成交后私有下发（规则 2）。
## 超时托管：人类轮次倒计时，超时由 AI 纯模块按该座位手牌代打（auto=true 广播）。
## 断线宽限：成员掉线标 offline 并开宽限计时，期间其回合由托管代打、对局继续；
## 宽限内同昵称 hello 重连即回房（对局中发公开状态快照）；逾期按退出关房。
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
## 掉线宽限（秒）：逾期按退出处理
const OFFLINE_GRACE := 120.0

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


func owner_seat() -> int:
	return 0  ## 建房者固定 0 号位（甲）


func add_member(nick: String, peer_id: int) -> int:
	for s in members.size():
		if members[s] == null:
			members[s] = {"seat": s, "name": nick, "is_ai": false, "peer_id": peer_id, "offline": false}
			return s
	return -1


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
				members[s] = {"seat": s, "name": AI_NAMES[s], "is_ai": true, "peer_id": 0, "offline": false}
	_begin_engine_game()
	return ""


## 房主开下一局（引擎内部完成庄位轮换，规则 4）。返回 "" 或错误信息。
func next_game() -> String:
	if status != STATUS_GAME:
		return "尚未开局"
	if not engine.start_next_game():
		return "本局尚未结束"
	_broadcast_game_start()
	return ""


## 测试钩子：注入固定牌型开局（对齐 GameEngine.start_session_with_deal 用法）
func _test_start_with_deal(dealer: int, test_hands: Array, test_kitty: Array) -> void:
	for s in members.size():
		if members[s] == null:
			members[s] = {"seat": s, "name": AI_NAMES[s], "is_ai": true, "peer_id": 0, "offline": false}
	engine.start_session_with_deal(dealer, test_hands, test_kitty)
	status = STATUS_GAME
	_broadcast_game_start()


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

## 成员掉线（manager 扫描判定）：标记 + 广播 + 开宽限计时
func mark_offline(seat: int) -> void:
	var m = members[seat]
	if m == null or m.is_ai or m.offline:
		return
	m.offline = true
	broadcast({"t": NetProto.MEMBER_OFFLINE, "seat": seat, "name": m.name})
	_arm_grace_timer(seat)


## 宽限内同昵称重连：解除离线、广播房间状态、对局中补发公开快照
func reconnect(peer_id: int, nick: String) -> void:
	var m = member_by_name(nick)
	if m == null:
		return
	m.peer_id = peer_id
	m.offline = false
	_cancel_grace_timer(m.seat)
	broadcast_room_state(true)
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
	broadcast(_act_msg(NetProto.KIND_BID, seat, auto, {"value": value}))


func _apply_trump(seat: int, suit: int, rank: int, auto: bool, peer_id := 0) -> void:
	_disarm_turn_timer()
	var verdict := engine.submit_trump(seat, suit, rank)
	if not verdict.ok:
		_reject(peer_id, verdict.error)
		return
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
		_arm_turn_timer(seat, TIMEOUT_BID, NetProto.KIND_BID)
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
		_arm_turn_timer(seat, TIMEOUT_TRUMP, NetProto.KIND_TRUMP)
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
		_arm_turn_timer(seat, TIMEOUT_DISCARD, NetProto.KIND_DISCARD)
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
		_arm_turn_timer(seat, TIMEOUT_PLAY, NetProto.KIND_PLAY)
	else:
		_schedule_ai(delay, func(): _ai_play(seat))


func _ai_play(seat: int) -> void:
	if not _ai_still_valid(seat, GameEngine.Phase.TRICKS):
		return
	var cards: Array = AiPlay.choose_play(engine.hands[seat], engine.trump, engine.current_plays,
		seat, engine.banker_seat, engine.trick_history, engine.trump_void_seats)
	_apply_play(seat, cards, false)


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
			var cards: Array = AiPlay.choose_play(engine.hands[seat], engine.trump, engine.current_plays,
				seat, engine.banker_seat, engine.trick_history, engine.trump_void_seats)
			_apply_play(seat, cards, true)


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


## ============================= 关房 =============================

func close(reason: String) -> void:
	if status == "CLOSED":
		return
	status = "CLOSED"
	_disarm_turn_timer()
	_ai_timer.stop()
	broadcast({"t": NetProto.ROOM_CLOSED, "reason": reason, "rows": _store.room_scores(code)})
	closed.emit(self)
	queue_free()
