class_name GameEngine
extends RefCounted
## 完整对局状态机（规则 2 总览、4 庄位、8.2 抠底）：状态编排 + 输入校验 + 信号发布。
## 领域规则委托：Auction（规则 5 叫分拍卖）、Scoring（规则 9/10 分级收益）、
## FollowRule/Trick/Combo（规则 6/7/8 出牌与结算）。
## 纯逻辑：不依赖场景节点；单机 UI 与未来联机服务端共用。
## 所有 submit_* 方法均校验输入并返回判定字典，非法操作不改变状态。
## 联机预留（M4）：submit_* 是唯一状态变更入口（按值匹配契约 = 网络消息可直接映射），
## 信号是唯一 UI 复制通道；本类无时间依赖，服务端可确定性重放。


signal phase_changed(phase: int)
signal auction_required(seat: int)
signal trump_required(seat: int)
signal discard_required(seat: int)
signal play_required(seat: int)
signal trick_settled(info: Dictionary)
signal game_over(result: Dictionary)
signal engine_fault(message: String)  ## 内部一致性破坏（正常对局不会发出；诊断用）

enum Phase { IDLE, AUCTION, TRUMP, DISCARD, TRICKS, SETTLED }

# 域内常量由领域模块持有；此处按旧引用面转发（UI/测试沿用 GameEngine.XXX）
const BID_PASS := Auction.BID_PASS
const DEALER_BASE_BID := Auction.DEALER_BASE_BID
const BID_CAP := Auction.BID_CAP
const WIN_LINE := Scoring.WIN_LINE
const PLAYER_COUNT := 4
const HAND_SIZE := 19
const BOTTOM_SIZE := 8
const BASE_STAKE := 1  ## 基底分 B（规则 10；房间可约定，此处固定 1）

var phase: int = Phase.IDLE
var round_index := 0            ## 第几局（1 起）
var dealer_seat := -1           ## 抓牌庄家（规则 4）
var banker_seat := -1           ## 出牌庄家（拍卖胜出者）
var contract := 0               ## 本局叫分（目标分与结算参数）
var trump: TrumpInfo = null
var hands: Array = []           ## Array[Array[Card]] × 4
var kitty: Array = []           ## 本局翻出的 8 张底牌（翻底后并入庄家手牌；DISCARD 阶段 peek_bottom 供其查看）
var buried: Array = []          ## 庄家扣回的底牌（8 张，对其他玩家不可见；末轮抠底分值来源）
var buried_points := 0          ## 庄家所扣底牌分值（8.2 抠底基数）
var faulted := false            ## 内部一致性破坏标记（正常对局永远为 false）
var auction := Auction.new()    ## 叫分拍卖子状态机（bids/turn 归其所有）
var current_plays: Array = []   ## 本轮已出 [{ seat, cards, role }]，plays[0] 为领出
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


## 测试钩子：注入固定牌型（hands 每人 19 张 + kitty 8 张；引擎按值匹配，副本亦可）
func start_session_with_deal(dealer: int, test_hands: Array, test_kitty: Array) -> void:
	round_index = 0
	cumulative = [0, 0, 0, 0]
	rng.randomize()
	_begin_game(dealer, test_hands, test_kitty)


func _begin_game(next_dealer: int, test_hands: Array, test_kitty: Array) -> void:
	round_index += 1
	dealer_seat = next_dealer
	banker_seat = -1
	contract = 0
	trump = null
	captured_points = 0
	koudi_points = 0
	current_plays = []
	trick_history = []
	leader_seat = -1
	turn_seat = -1
	last_game_result = {}
	faulted = false
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
		kitty = deck.slice(PLAYER_COUNT * HAND_SIZE, PLAYER_COUNT * HAND_SIZE + BOTTOM_SIZE)
	else:
		hands = test_hands
		kitty = test_kitty
	buried = []
	buried_points = 0
	# 不变式：发任何信号（phase_changed 先于 auction_required 同步到达 UI）之前，
	# 状态必须完全就绪——故先 begin 再切阶段
	var first_turn := auction.begin(dealer_seat, PLAYER_COUNT)
	_set_phase(Phase.AUCTION)
	auction_required.emit(first_turn)


## ============================= 叫分拍卖（委托 Auction，规则 5） =============================

func current_highest_bid() -> int:
	return auction.highest_bid()


func has_passed(seat: int) -> bool:
	return auction.has_passed(seat)


func bid_value(seat: int) -> int:
	return auction.bid_value(seat)


## value = BID_PASS 表示放弃（永久退出）；否则须为高于当前最高、5 的倍数、≤200
func submit_bid(seat: int, value: int) -> Dictionary:
	if phase != Phase.AUCTION:
		return _err("当前不在拍卖阶段")
	var verdict := auction.submit(seat, value)
	if not verdict.ok:
		return verdict
	_advance_auction()
	return verdict


func _advance_auction() -> void:
	if auction.is_complete():
		# 拍卖结束：唯一未放弃者为出牌庄家，以其最高叫分为本局叫分（规则 5.4/5.5）
		banker_seat = auction.winner_seat()
		contract = auction.bid_value(banker_seat)
		_set_phase(Phase.TRUMP)
		trump_required.emit(banker_seat)
		return
	auction_required.emit(auction.advance(PLAYER_COUNT))


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
	# 翻底：8 张底牌入手（27 张），仅庄家可见（规则 2）；kitty 保留供 DISCARD 阶段查看
	hands[banker_seat].append_array(kitty)
	_set_phase(Phase.DISCARD)
	discard_required.emit(banker_seat)
	return {ok = true, error = ""}


## 扣底：庄家从 27 张中任选 8 张扣回（规则 2）。提交按值匹配（Card.key 唯一）。
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
		var k: String = c.key()
		if seen.has(k):
			return _err("所扣之牌重复")
		seen[k] = true
	# 执行：从手牌按值移除并成为所扣底牌
	if not _remove_cards_by_value(hand, cards):
		return _err("所扣之牌不在庄家手中")  # 理论不可达：上方已按值校验归属
	buried = cards.duplicate()
	buried_points = _points_of(buried)
	_set_phase(Phase.TRICKS)
	leader_seat = banker_seat   # 首轮由出牌庄家领出（规则 7.1.1）
	turn_seat = banker_seat
	play_required.emit(turn_seat)
	return {ok = true, error = ""}


## 翻底阶段：仅出牌庄家可见（规则 2 底牌保密）
func peek_bottom(seat: int) -> Array:
	if phase == Phase.DISCARD and seat == banker_seat:
		return kitty.duplicate()
	return []


## ============================= 逐轮出牌（规则 7、8） =============================

func get_hand(seat: int) -> Array:
	return hands[seat].duplicate()


func hand_count(seat: int) -> int:
	return hands[seat].size()


func is_defender(seat: int) -> bool:
	return seat != banker_seat


## 出牌（领出或跟牌）。提交按值匹配（Card.key 唯一，UI/联机可传等值副本）。
## 返回 FollowRule.is_legal 风格判定字典。
func submit_play(seat: int, cards: Array) -> Dictionary:
	if phase != Phase.TRICKS:
		return _err_play("当前不在出牌阶段")
	if seat != turn_seat:
		return _err_play("未轮到座位 %d" % seat)
	var lead := _current_lead_combo()
	var verdict: Dictionary = FollowRule.is_legal(hands[seat], cards, lead, trump)
	if not verdict.legal:
		return verdict
	if not _remove_cards_by_value(hands[seat], cards):
		return _err_play("所出之牌不在手牌中")  # 理论不可达：is_legal 已按值校验归属
	current_plays.append({seat = seat, cards = cards.duplicate(), role = verdict.role})
	if current_plays.size() >= PLAYER_COUNT:
		_settle_trick()
	else:
		turn_seat = (turn_seat + 1) % PLAYER_COUNT
		play_required.emit(turn_seat)
	return verdict


func _current_lead_combo() -> Combo:
	if current_plays.is_empty():
		return null
	return Combo.detect(current_plays[0].cards, trump)


## 最近一轮已结算的出牌快照（供结算后 UI 停留展示）；无历史返回 []。
## 由 trick_history 末元素派生，不再单独维护镜像字段。
func get_last_trick() -> Array:
	if trick_history.is_empty():
		return []
	return trick_history.back().plays


func _settle_trick() -> void:
	var r := Trick.settle(current_plays, trump)
	if not r.ok:
		# 正常对局不可达（每手出牌都经 is_legal 校验，领出必为合法牌型）。
		# 根治旧版「静默 seat=-1 死锁」：显性报障并冻结，等待诊断。
		faulted = true
		var message := "settle 失败（内部一致性破坏）：%s" % r.error
		push_error("GameEngine: " + message)
		engine_fault.emit(message)
		return
	var snapshot: Array = current_plays.duplicate()
	var is_last := _all_hands_empty()
	var koudi := 0
	if is_last and is_defender(r.seat) and r.win_main_class:
		# 末轮抠底（8.2）：单牌 ×1，对子/拖拉机 ×2
		var multiplier: int = 1 if r.win_type == Combo.Type.SINGLE else 2
		koudi = buried_points * multiplier
		koudi_points = koudi
	if is_defender(r.seat):
		captured_points += r.points  # 闲家赢轮，本轮分牌计入捉分（8.1）
	leader_seat = r.seat
	var info := {
		result = r,
		winner = r.seat,
		points = r.points,
		is_last = is_last,
		koudi = koudi,
		captured = captured_points,
	}
	trick_history.append({plays = snapshot, winner = r.seat})
	current_plays = []
	trick_settled.emit(info)
	if is_last:
		_settle_game()
	else:
		turn_seat = leader_seat
		play_required.emit(turn_seat)


## ============================= 结算（委托 Scoring，规则 9、10） =============================

func _settle_game() -> void:
	var captured_total := captured_points + koudi_points
	var outcome := Scoring.compute_outcome(contract, captured_total)
	var payments := Scoring.compute_payments(outcome, banker_seat, BASE_STAKE, PLAYER_COUNT)
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
		buried_points = buried_points,
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


## 从手牌按值移除一组牌（Card 值身份在两副牌内唯一）。未找到返回 false。
func _remove_cards_by_value(hand: Array, cards: Array) -> bool:
	for c in cards:
		var removed := false
		for i in hand.size():
			if hand[i].same_card(c):
				hand.remove_at(i)
				removed = true
				break
		if not removed:
			return false
	return true


func _err(message: String) -> Dictionary:
	return {ok = false, error = message}


func _err_play(message: String) -> Dictionary:
	return {legal = false, reason = -1, role = -1, text = message}
