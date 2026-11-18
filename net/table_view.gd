class_name TableView
extends RefCounted
## 联机客户端视图状态（M4）：维护**可见性裁剪**的对局状态，并以与 GameEngine 同构的
## 信号面 + 查询面驱动 game_table（[构7.3]「信号 + 查询接口」预留形态）。
## 数据来源：服务器广播的公开回放（叫分/亮牌/轮次/捉分/无主公示/终局结算）+
## 我自己的手牌（私有）。他人的手牌、底牌牌面、所扣之牌面永远不可知（非庄家）。
## 同源复用：竞叫推进用真实 core/Auction（叫分全公开），一轮结算用真实 core/Trick.settle
## （亮出的牌全公开）——与服务端引擎同一份逻辑，只有隐藏信息不可推导。
## 所有 act 已由 NetClient 按本地座位旋转（本地玩家恒为 0 号位）。


signal auction_required(seat: int)
signal trump_required(seat: int)
signal discard_required(seat: int)
signal play_required(seat: int)
signal trick_settled(info: Dictionary)
signal game_over(result: Dictionary)
signal engine_fault(message: String)

var phase: int = GameEngine.Phase.IDLE
var round_index := 0
var dealer_seat := -1
var banker_seat := -1
var contract := 0
var trump: TrumpInfo = null
## 4 槽手牌：仅 0 号位（我）有真实牌；其余为空（张数走 counts）
var hands: Array = [[], [], [], []]
var counts: Array = [0, 0, 0, 0]
var kitty: Array = []          ## 仅我的庄家局、翻底后可知（私有下发）
var buried: Array = []         ## 仅我扣的底可知
var buried_points := 0
var auction := Auction.new()   ## 叫分公开：本地同源推进
var current_plays: Array = []
var trick_history: Array = []
var trump_void_seats: Array = [false, false, false, false]  ## 只消费服务器 void 事件
var leader_seat := -1
var turn_seat := -1
var captured_points := 0
var koudi_points := 0          ## 末轮前不可知；终局以服务器结果为准
var cumulative: Array = [0, 0, 0, 0]
var last_game_result: Dictionary = {}
var faulted := false

var _awaiting_kitty := false   ## 我是庄家：trump 回放已到、私有底牌未到（规则 2 顺序）


## ============================= 查询面（与 GameEngine 同构） =============================

func current_highest_bid() -> int:
	return auction.highest_bid()


func has_passed(seat: int) -> bool:
	return auction.has_passed(seat)


func bid_value(seat: int) -> int:
	return auction.bid_value(seat)


func get_hand(seat: int) -> Array:
	if seat != 0:
		return []
	return hands[0].duplicate()


func hand_count(seat: int) -> int:
	return counts[seat]


func get_last_trick() -> Array:
	if trick_history.is_empty():
		return []
	return trick_history.back().plays


func is_defender(seat: int) -> bool:
	return seat != banker_seat


## 翻底可见性：仅我的庄家局、扣底阶段（规则 2）
func peek_bottom(seat: int) -> Array:
	if phase == GameEngine.Phase.DISCARD and seat == 0:
		return kitty.duplicate()
	return []


## ============================= 开局灌入（game_start / snapshot） =============================

## 从 game_start 消息（已由 NetClient 旋转到本地座位空间）灌入并发首个信号
func load_game(data: Dictionary) -> void:
	phase = GameEngine.Phase.AUCTION
	round_index = int(data.round)
	dealer_seat = int(data.dealer)
	banker_seat = -1
	contract = 0
	trump = null
	counts = _int_array(data.counts)
	hands = [[], [], [], []]
	for k in data.my_hand:
		hands[0].append(Card.from_key(k))
	kitty = []
	buried = []
	buried_points = 0
	current_plays = []
	trick_history = []
	trump_void_seats = [false, false, false, false]
	leader_seat = -1
	turn_seat = -1
	captured_points = 0
	koudi_points = 0
	cumulative = _int_array(data.cumulative)
	last_game_result = {}
	faulted = false
	_awaiting_kitty = false
	var first_turn: int = auction.begin(dealer_seat, GameEngine.PLAYER_COUNT)
	auction_required.emit(first_turn)


## 从重连快照（已旋转）灌入并按阶段补发对应 required 信号
func restore(data: Dictionary) -> void:
	phase = int(data.phase)
	round_index = int(data.round)
	dealer_seat = int(data.dealer)
	counts = _int_array(data.counts)
	hands = [[], [], [], []]
	for k in data.my_hand:
		hands[0].append(Card.from_key(k))
	current_plays = []
	trick_history = []
	for th in data.trick_history:
		var plays: Array = []
		for p in th.plays:
			plays.append({"seat": int(p.seat), "cards": NetProto.cards_of(p.cards), "role": int(p.role)})
		trick_history.append({"plays": plays, "winner": int(th.winner)})
	trump_void_seats = _bool_array(data.void_seats)
	captured_points = int(data.captured)
	cumulative = _int_array(data.cumulative)
	leader_seat = -1
	turn_seat = -1
	kitty = []
	buried = []
	buried_points = 0
	faulted = false
	_awaiting_kitty = false
	if data.get("last_result") != null:
		last_game_result = data.last_result
		koudi_points = int(last_game_result.koudi_points)
	if phase == GameEngine.Phase.AUCTION:
		auction.bids = []
		for b in data.bids:
			auction.bids.append({"value": int(b.value), "passed": bool(b.passed)})
		auction.turn = int(data.auction_turn)
		auction_required.emit(auction.turn)
		return
	banker_seat = int(data.banker)
	contract = int(data.contract)
	if data.get("trump") != null:
		trump = TrumpInfo.new(int(data.trump.suit), int(data.trump.rank))
	if data.get("kitty") != null:
		kitty = NetProto.cards_of(data.kitty)
	if data.get("buried") != null:
		buried = NetProto.cards_of(data.buried)
		for c in buried:
			buried_points += c.points()
	if phase == GameEngine.Phase.TRICKS:
		for p in data.current_plays:
			current_plays.append({"seat": int(p.seat), "cards": NetProto.cards_of(p.cards), "role": int(p.role)})
		turn_seat = int(data.turn_seat)
		play_required.emit(turn_seat)
	elif phase == GameEngine.Phase.DISCARD:
		discard_required.emit(banker_seat)
	elif phase == GameEngine.Phase.TRUMP:
		trump_required.emit(banker_seat)
	elif phase == GameEngine.Phase.SETTLED:
		game_over.emit(last_game_result)


## ============================= 动作回放（本地座位空间） =============================

func apply_act(kind: String, seat: int, msg: Dictionary) -> void:
	counts = _int_array(msg.counts)
	match kind:
		NetProto.KIND_BID:
			_apply_bid(seat, int(msg.value))
		NetProto.KIND_TRUMP:
			_apply_trump(seat, int(msg.suit), int(msg.rank))
		NetProto.KIND_DISCARD:
			_apply_discard(seat)
		NetProto.KIND_PLAY:
			_apply_play(seat, NetProto.cards_of(msg.cards), int(msg.get("role", -1)))
		NetProto.KIND_VOID:
			trump_void_seats[seat] = true


func _apply_bid(seat: int, value: int) -> void:
	var verdict := auction.submit(seat, value)
	if not verdict.ok:
		# 回放与服务端竞叫推进失配：理论不可达（bug 防线）
		push_error("TableView: 竞叫回放失配 %s" % verdict.error)
		return
	if auction.is_complete():
		banker_seat = auction.winner_seat()
		contract = auction.bid_value(banker_seat)
		phase = GameEngine.Phase.TRUMP
		trump_required.emit(banker_seat)
	else:
		auction_required.emit(auction.advance(GameEngine.PLAYER_COUNT))


func _apply_trump(seat: int, suit: int, rank: int) -> void:
	trump = TrumpInfo.new(suit, rank)
	phase = GameEngine.Phase.DISCARD
	if seat == 0:
		# 我是庄家：等私有底牌到齐再进扣底（手牌须先呈现 27 张）
		_awaiting_kitty = true
	else:
		discard_required.emit(banker_seat)


## 私有底牌（仅庄家收到）：入手后放行扣底阶段
func apply_kitty(cards: Array) -> void:
	kitty = cards
	for c in cards:
		hands[0].append(c)
	_awaiting_kitty = false
	discard_required.emit(banker_seat)


func _apply_discard(seat: int) -> void:
	if seat == 0 and not _pending_discard.is_empty():
		# 我扣的底：从手牌移除（提交时 NetClient 已暂存所选 8 张）
		_remove_cards(_pending_discard)
		buried = _pending_discard.duplicate()
		for c in buried:
			buried_points += c.points()
		_pending_discard.clear()
	phase = GameEngine.Phase.TRICKS
	leader_seat = banker_seat
	turn_seat = banker_seat
	play_required.emit(turn_seat)


## 我提交扣底时由 NetClient 暂存所选牌（广播不含牌面，本地自行移除）
var _pending_discard: Array = []


func set_pending_discard(cards: Array) -> void:
	_pending_discard = cards.duplicate()


func _apply_play(seat: int, cards: Array, role: int) -> void:
	if seat == 0:
		_remove_cards(cards)
	current_plays.append({"seat": seat, "cards": cards, "role": role})
	if current_plays.size() >= GameEngine.PLAYER_COUNT:
		_settle_trick()
	else:
		turn_seat = (turn_seat + 1) % GameEngine.PLAYER_COUNT
		play_required.emit(turn_seat)


## 一轮结算：亮出的牌全公开，用真实 core/Trick.settle 同源结算
func _settle_trick() -> void:
	var r := Trick.settle(current_plays, trump)
	if not r.ok:
		faulted = true
		var message := "视图结算失配（内部一致性破坏）：%s" % r.error
		push_error("TableView: " + message)
		engine_fault.emit(message)
		return
	var snapshot: Array = current_plays.duplicate()
	var is_last := _all_known_hands_empty()
	if is_defender(r.seat):
		captured_points += r.points
	leader_seat = r.seat
	var info := {
		result = r,
		winner = r.seat,
		points = r.points,
		is_last = is_last,
		koudi = 0,  # 底牌分非庄家不可知；终局以服务器结果为准
		captured = captured_points,
	}
	trick_history.append({plays = snapshot, winner = r.seat})
	current_plays = []
	trick_settled.emit(info)
	if is_last:
		phase = GameEngine.Phase.SETTLED  # 等服务器 game_over 补终局结果
	else:
		turn_seat = leader_seat
		play_required.emit(turn_seat)


## 我的视角下对局是否打完：四家手牌张数全为 0（张数由服务器权威下发）
func _all_known_hands_empty() -> bool:
	for s in GameEngine.PLAYER_COUNT:
		if counts[s] > 0:
			return false
	return true


## 终局结果（NetClient 已旋转）：补齐视图不可知的底牌/抠底信息
func apply_game_over(result: Dictionary) -> void:
	last_game_result = result
	koudi_points = int(result.koudi_points)
	buried_points = int(result.buried_points)
	cumulative = _int_array(result.cumulative)
	phase = GameEngine.Phase.SETTLED
	game_over.emit(last_game_result)


func _remove_cards(cards: Array) -> void:
	for c in cards:
		for i in hands[0].size():
			if hands[0][i].same_card(c):
				hands[0].remove_at(i)
				break


func _int_array(arr) -> Array:
	var out: Array = []
	for v in arr:
		out.append(int(v))
	return out


func _bool_array(arr) -> Array:
	var out: Array = []
	for v in arr:
		out.append(bool(v))
	return out
