class_name GameEngine
extends RefCounted
## 完整对局状态机（规则 2 总览、4 庄位、5 叫分拍卖、8.2 抠底、9 分级、10 收益）。
## 纯逻辑：不依赖场景节点；单机 UI 与未来联机服务端共用。
## 所有 submit_* 方法均校验输入并返回判定字典，非法操作不改变状态。


signal phase_changed(phase: int)
signal auction_required(seat: int)
signal trump_required(seat: int)
signal discard_required(seat: int)
signal play_required(seat: int)
signal trick_settled(info: Dictionary)
signal game_over(result: Dictionary)

enum Phase { IDLE, AUCTION, TRUMP, DISCARD, TRICKS, SETTLED }

const BID_PASS := -1
const PLAYER_COUNT := 4
const HAND_SIZE := 19
const BOTTOM_SIZE := 8
const BASE_STAKE := 1         ## 基底分 B（规则 10；房间可约定，此处固定 1）
const DEALER_BASE_BID := 130  ## 抓牌庄家底叫（规则 5.1）
const BID_CAP := 200          ## 封顶（规则 5.2）
const WIN_LINE := 205         ## 闲家胜线（规则 9）

var phase: int = Phase.IDLE
var round_index := 0            ## 第几局（1 起）
var dealer_seat := -1           ## 抓牌庄家（规则 4）
var banker_seat := -1           ## 出牌庄家（拍卖胜出者）
var contract := 0               ## 本局叫分（目标分与结算参数）
var trump: TrumpInfo = null
var hands: Array = []           ## Array[Array[Card]] × 4
var bottom: Array = []          ## 8 张底牌（扣底后为庄家所扣之牌，对其余玩家不可见）
var bottom_points := 0
var bids: Array = []            ## 每座位 { value: int, passed: bool }
var auction_turn := -1
var current_plays: Array = []   ## 本轮已出 [{ seat, cards, role }]，plays[0] 为领出
var last_trick: Array = []      ## 上一轮出牌快照（结算后停留展示，新一轮领出时清除）
var trick_history: Array = []   ## 全部已结算轮次 [{ plays, winner }]，按旧→新排列
var leader_seat := -1
var turn_seat := -1
var captured_points := 0        ## 闲家捉分（各轮之和，不含抠底）
var koudi_points := 0           ## 末轮抠底计入（8.2）
var cumulative: Array = [0, 0, 0, 0]  ## 多局累计收益（规则 10）
var last_game_result: Dictionary = {}
var rng := RandomNumberGenerator.new()


## ============================= 会话与发牌 =============================

func start_session(seed_value: int = 0, dealer := -1) -> void:
	round_index = 0
	cumulative = [0, 0, 0, 0]
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var first_dealer := dealer if dealer >= 0 else rng.randi_range(0, PLAYER_COUNT - 1)  # 首局随机（规则 4）
	_begin_game(first_dealer, [], [])


func start_next_game() -> bool:
	if phase != Phase.SETTLED or last_game_result.is_empty():
		return false
	# 庄位轮换（规则 4）：上局出牌庄家胜 → 抓牌庄家仍为该玩家；败 → 其下一位
	var next_dealer: int = last_game_result.banker_seat
	if not last_game_result.banker_won:
		next_dealer = (next_dealer + 1) % PLAYER_COUNT
	_begin_game(next_dealer, [], [])
	return true


## 测试钩子：注入固定牌型（hands 每人 19 张 + bottom 8 张，牌对象引用须互不相同）
func start_session_with_deal(dealer: int, test_hands: Array, test_bottom: Array) -> void:
	round_index = 0
	cumulative = [0, 0, 0, 0]
	rng.randomize()
	_begin_game(dealer, test_hands, test_bottom)


func _begin_game(next_dealer: int, test_hands: Array, test_bottom: Array) -> void:
	round_index += 1
	dealer_seat = next_dealer
	banker_seat = -1
	contract = 0
	trump = null
	captured_points = 0
	koudi_points = 0
	current_plays = []
	last_trick = []
	trick_history = []
	leader_seat = -1
	turn_seat = -1
	last_game_result = {}
	if test_hands.is_empty():
		var deck := Card.full_deck()
		# Fisher-Yates 洗牌（种子化，可复现）
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := deck[i]
			deck[i] = deck[j]
			deck[j] = tmp
		hands = []
		for s in PLAYER_COUNT:
			hands.append(deck.slice(s * HAND_SIZE, (s + 1) * HAND_SIZE))
		bottom = deck.slice(PLAYER_COUNT * HAND_SIZE, PLAYER_COUNT * HAND_SIZE + BOTTOM_SIZE)
	else:
		hands = test_hands
		bottom = test_bottom
	bottom_points = _points_of(bottom)
	# 拍卖初始化：抓牌庄家固定 130 底叫（规则 5.1），从其下一位开始表态
	bids = []
	for s in PLAYER_COUNT:
		bids.append({value = 0, passed = false})
	bids[dealer_seat].value = DEALER_BASE_BID
	_set_phase(Phase.AUCTION)
	auction_turn = (dealer_seat + 1) % PLAYER_COUNT
	auction_required.emit(auction_turn)


## ============================= 叫分拍卖（规则 5） =============================

func current_highest_bid() -> int:
	var highest := 0
	for b in bids:
		highest = maxi(highest, b.value)
	return highest


func has_passed(seat: int) -> bool:
	return bids[seat].passed


## 某座位当前叫分（0 = 未叫；UI 呈现用，不触内部结构）
func bid_value(seat: int) -> int:
	return bids[seat].value


## value = BID_PASS 表示放弃（永久退出）；否则须为高于当前最高、5 的倍数、≤200
func submit_bid(seat: int, value: int) -> Dictionary:
	if phase != Phase.AUCTION:
		return _err("当前不在拍卖阶段")
	if seat != auction_turn:
		return _err("未轮到座位 %d" % seat)
	if value == BID_PASS:
		bids[seat].passed = true
	else:
		var highest := current_highest_bid()
		if bids[seat].passed:
			return _err("已放弃，不能再叫")
		if highest >= BID_CAP:
			return _err("当前叫分已封顶，只能放弃")
		if value <= highest:
			return _err("叫分须高于当前最高 %d" % highest)
		if value % 5 != 0:
			return _err("叫分须为 5 的倍数")
		if value > BID_CAP:
			return _err("叫分封顶 %d" % BID_CAP)
		bids[seat].value = value
	_advance_auction()
	return {ok = true, error = ""}


func _advance_auction() -> void:
	var active := 0
	var active_seat := -1
	for s in PLAYER_COUNT:
		if not bids[s].passed:
			active += 1
			active_seat = s
	if active <= 1:
		# 拍卖结束：唯一未放弃者为出牌庄家，以其最高叫分为本局叫分（规则 5.4/5.5）
		banker_seat = active_seat
		contract = bids[banker_seat].value
		_set_phase(Phase.TRUMP)
		trump_required.emit(banker_seat)
		return
	# 轮转到下一位未放弃者
	for i in PLAYER_COUNT:
		auction_turn = (auction_turn + 1) % PLAYER_COUNT
		if not bids[auction_turn].passed:
			break
	auction_required.emit(auction_turn)


## ============================= 叫主与扣底（规则 2、3.2） =============================

## 出牌庄家在看底牌之前叫主：指定主花色 + 常主点数 R（可任选）
func submit_trump(seat: int, suit: int, rank: int) -> Dictionary:
	if phase != Phase.TRUMP:
		return _err("当前不在叫主阶段")
	if seat != banker_seat:
		return _err("只有出牌庄家可以叫主")
	if not Card.NORMAL_SUITS.has(suit):
		return _err("非法花色")
	if not Card.RANKS.has(rank):
		return _err("非法点数")
	trump = TrumpInfo.new(suit, rank)
	# 翻底：8 张底牌入手（27 张），仅庄家可见（规则 2）
	hands[banker_seat].append_array(bottom)
	_set_phase(Phase.DISCARD)
	discard_required.emit(banker_seat)
	return {ok = true, error = ""}


## 扣底：庄家从 27 张中任选 8 张扣回（规则 2）
func submit_discard(seat: int, cards: Array) -> Dictionary:
	if phase != Phase.DISCARD:
		return _err("当前不在扣底阶段")
	if seat != banker_seat:
		return _err("只有出牌庄家可以扣底")
	if cards.size() != BOTTOM_SIZE:
		return _err("须恰好扣 %d 张，实选 %d 张" % [BOTTOM_SIZE, cards.size()])
	var hand: Array = hands[banker_seat]
	var seen := {}
	for c in cards:
		var found := false
		for h in hand:
			if h.same_card(c):
				found = true
				break
		if not found:
			return _err("所扣之牌不在庄家手中")
		var key := "%d_%d_%d" % [c.suit, c.rank, c.copy]
		if seen.has(key):
			return _err("所扣之牌重复")
		seen[key] = true
	# 执行：从手牌移除并成为新底牌
	var remaining: Array = []
	var to_remove := cards.duplicate()
	for h in hand:
		var drop := false
		for i in to_remove.size():
			if to_remove[i].same_card(h):
				drop = true
				to_remove.remove_at(i)
				break
		if not drop:
			remaining.append(h)
	hands[banker_seat] = remaining
	bottom = cards.duplicate()
	bottom_points = _points_of(bottom)
	_set_phase(Phase.TRICKS)
	leader_seat = banker_seat   # 首轮由出牌庄家领出（规则 7.1.1）
	turn_seat = banker_seat
	play_required.emit(turn_seat)
	return {ok = true, error = ""}


## 翻底阶段：仅出牌庄家可见（规则 2 底牌保密）
func peek_bottom(seat: int) -> Array:
	if phase == Phase.DISCARD and seat == banker_seat:
		return bottom.duplicate()
	return []


## ============================= 逐轮出牌（规则 7、8） =============================

func get_hand(seat: int) -> Array:
	return hands[seat].duplicate()


func hand_count(seat: int) -> int:
	return hands[seat].size()


func _current_lead_combo() -> Combo:
	if current_plays.is_empty():
		return null
	return Combo.detect(current_plays[0].cards, trump)


func is_defender(seat: int) -> bool:
	return seat != banker_seat


## 出牌（领出或跟牌）。返回 FollowRule.is_legal 风格判定字典。
func submit_play(seat: int, cards: Array) -> Dictionary:
	if phase != Phase.TRICKS:
		return _err_play("当前不在出牌阶段")
	if seat != turn_seat:
		return _err_play("未轮到座位 %d" % seat)
	var lead := _current_lead_combo()
	var verdict: Dictionary = FollowRule.is_legal(hands[seat], cards, lead, trump)
	if not verdict.legal:
		return verdict
	for c in cards:
		hands[seat].erase(c)
	if current_plays.is_empty():
		last_trick = []  # 新一轮领出，清除上一轮停留快照
	current_plays.append({seat = seat, cards = cards.duplicate(), role = verdict.role})
	if current_plays.size() >= PLAYER_COUNT:
		_settle_trick()
	else:
		turn_seat = (turn_seat + 1) % PLAYER_COUNT
		play_required.emit(turn_seat)
	return verdict


func _settle_trick() -> void:
	var settle_plays: Array = []
	for p in current_plays:
		settle_plays.append({player = p.seat, cards = p.cards, role = p.role})
	var r := Trick.settle(settle_plays, trump)
	last_trick = current_plays.duplicate()  # 供 UI 在停顿期继续展示牌面
	var is_last := _all_hands_empty()
	var koudi := 0
	if is_last and r.ok and is_defender(r.player) and r.win_main_class:
		# 末轮抠底（8.2）：单牌 ×1，对子/拖拉机 ×2
		var multiplier: int = 1 if r.win_type == Combo.Type.SINGLE else 2
		koudi = bottom_points * multiplier
		koudi_points = koudi
	if r.ok and is_defender(r.player):
		captured_points += r.points  # 闲家赢轮，本轮分牌计入捉分（8.1）
	leader_seat = r.player
	var info := {
		result = r,
		winner = r.player,
		points = r.points,
		is_last = is_last,
		koudi = koudi,
		captured = captured_points,
	}
	if r.ok:
		trick_history.append({plays = last_trick.duplicate(), winner = r.player})
	current_plays = []
	trick_settled.emit(info)
	if is_last:
		_settle_game()
	else:
		turn_seat = leader_seat
		play_required.emit(turn_seat)


## ============================= 结算（规则 9、10） =============================

## 胜负与级数（规则 9）：总分 = 叫分 + 闲家捉分（含抠底）
static func compute_outcome(contract_value: int, captured_total: int) -> Dictionary:
	var total := contract_value + captured_total
	if total >= WIN_LINE:
		# 闲家胜：1 + ⌊(总分−205)/40⌋，封顶 3 级
		return {banker_won = false, level = mini(3, 1 + (total - WIN_LINE) / 40), total = total}
	if captured_total == 0:
		return {banker_won = true, level = 3, total = total}
	if captured_total <= 20:
		return {banker_won = true, level = 2, total = total}
	return {banker_won = true, level = 1, total = total}


func _settle_game() -> void:
	var captured_total := captured_points + koudi_points
	var outcome := compute_outcome(contract, captured_total)
	var payments: Array = [0, 0, 0, 0]
	var delta: int = BASE_STAKE * outcome.level
	if outcome.banker_won:
		# 每位闲家支付庄家 B×级数（规则 10）：庄家净收 3 份
		for s in PLAYER_COUNT:
			payments[s] = 3 * delta if s == banker_seat else -delta
	else:
		for s in PLAYER_COUNT:
			payments[s] = -3 * delta if s == banker_seat else delta
	for s in PLAYER_COUNT:
		cumulative[s] += payments[s]
	last_game_result = {
		round = round_index,
		dealer_seat = dealer_seat,
		banker_seat = banker_seat,
		contract = contract,
		trump = trump,
		captured_points = captured_points,
		koudi_points = koudi_points,
		bottom_points = bottom_points,
		captured_total = captured_total,
		total_score = outcome.total,
		banker_won = outcome.banker_won,
		level = outcome.level,
		payments = payments,
		cumulative = cumulative.duplicate(),
	}
	_set_phase(Phase.SETTLED)
	game_over.emit(last_game_result)


## ============================= 内部工具 =============================

func _set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)


func _all_hands_empty() -> bool:
	for s in PLAYER_COUNT:
		if not hands[s].is_empty():
			return false
	return true


func _points_of(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += c.points()
	return total


func _err(message: String) -> Dictionary:
	return {ok = false, error = message}


func _err_play(message: String) -> Dictionary:
	return {legal = false, reason = -1, role = -1, text = message}
