class_name AiPlay
extends RefCounted
## AI 出牌侧策略（M2 贪心基线）：叫主 / 扣底 / 领出 / 跟杀垫。
## 数据进/决策出：不持有引擎引用，不读引擎内部状态——联机服务端
## 可绕过 AiPolicy 门面直接调用（M4 预留）。
##
## 策略概要：
## - 叫主：花色按张数/大牌/对子加权；R 选持有最多（成对额外加成）的点数
## - 扣底：副牌分牌优先入底（规则 8.2 策略注记），其次最弱副牌，不扣常主
## - 领出：手中牌力最大的完整牌型（拖拉机 > 对子 > 单张）
## - 跟牌：有同型 → 队友领先就出最小（不拆台），否则能赢用最小，赢不了出最小
## - 杀/垫：无领出花色时，桌面 ≥10 分或最后一手且能压过 → 最小杀；否则垫最差牌
##   （防守方在队友领先时垫分喂队友）
## 全部输出交由 GameEngine 校验；自动对局测试（test_ai_policy.gd）即其正确性验证。


## ============================= 叫主 =============================

## 选主花色 + 常主点数 R（花色重张数/大牌/对子；R 重持有量与成对）
static func choose_trump(hand: Array) -> Dictionary:
	var best_suit := Card.Suit.SPADE
	var best_suit_score := -1
	for s in Card.NORMAL_SUITS:
		var count := 0
		var pairs := 0
		var big := 0
		var groups := Combo.pair_groups(hand)
		for key in groups:
			var g: Array = groups[key]
			if g[0].suit != s:
				continue
			count += g.size()
			if g[0].rank >= Card.RANK_A:
				big += g.size()
			if g.size() >= 2:
				pairs += 1
		var score := count * 2 + big * 2 + pairs * 5
		if score > best_suit_score:
			best_suit_score = score
			best_suit = s
	var best_rank := Card.RANK_A
	var best_rank_score := -1
	var groups := Combo.pair_groups(hand)
	for r in Card.RANKS:
		var copies := 0
		var pairs := 0
		for key in groups:
			var g: Array = groups[key]
			if g[0].rank == r:
				copies += g.size()
				if g.size() >= 2:
					pairs += 1
		var score := copies + pairs * 3
		if score >= best_rank_score:  # 平手取较高点数（RANKS 顺序靠后者更大）
			best_rank_score = score
			best_rank = r
	return {suit = best_suit, rank = best_rank}


## ============================= 扣底 =============================

## 副牌分牌优先（8.2 策略注记），其次最弱副牌；不扣常主；返回 hand 内 8 张引用
static func choose_discard(hand: Array, trump: TrumpInfo, bottom_size: int) -> Array:
	var side: Array = []
	for c in hand:
		if not trump.is_trump(c):
			side.append(c)
	side.sort_custom(func(a: Card, b: Card) -> bool:
		if a.points() != b.points():
			return a.points() > b.points()
		return trump.card_power(a) < trump.card_power(b))
	var discard: Array = []
	for c in side:
		if discard.size() >= bottom_size:
			break
		discard.append(c)
	# 副牌不足：补最弱的主花色普通牌（仍不扣常主）
	if discard.size() < bottom_size:
		var main_normal: Array = []
		for c in hand:
			if trump.is_trump(c) and not trump.is_permanent_trump(c) and not discard.has(c):
				main_normal.append(c)
		main_normal.sort_custom(func(a: Card, b: Card) -> bool:
			return trump.card_power(a) < trump.card_power(b))
		for c in main_normal:
			if discard.size() >= bottom_size:
				break
			discard.append(c)
	# 极端情况仍不足：按牌力补最低的牌
	for c in hand:
		if discard.size() >= bottom_size:
			break
		if not discard.has(c):
			discard.append(c)
	return discard


## ============================= 出牌 =============================

## 出牌决策（数据进/决策出）。plays 为本轮已出记录 [{ seat, cards, role }]，
## plays[0] 为领出；空数组表示本手领出。
static func choose_play(hand: Array, trump: TrumpInfo, plays: Array, seat: int, banker_seat: int) -> Array:
	if plays.is_empty():
		return _choose_lead(hand, trump)

	var lead := Combo.detect(plays[0].cards, trump)
	if lead == null:
		# 主牌甩打轮（7.3）：领出为不成型多张主牌，领出者必胜——纯垫牌；
		# 领出者是闲家队友时优先垫分喂队友
		var leader_seat: int = plays[0].seat
		var feed: bool = seat != banker_seat and leader_seat != banker_seat and leader_seat != seat
		return build_discard(hand, trump, plays[0].cards.size(), feed)
	# 部分结算判定"当前最大者"：settle 与 plays 同构（键名 seat），直接传入
	var cur: Dictionary = Trick.settle(plays, trump)
	if not cur.ok:
		return [hand[0]]
	var winner_combo := Combo.detect(plays[cur.winner].cards, trump)
	var beat_power := Combo.power(winner_combo, trump)
	var i_am_defender := seat != banker_seat
	var winner_is_teammate: bool = i_am_defender and cur.seat != banker_seat and cur.seat != seat
	var trick_points := 0
	for p in plays:
		for c in p.cards:
			trick_points += c.points()
	var last_seat := plays.size() >= 3
	var s_class: int = lead.suit

	# 1) 有同牌型 → 必须跟：队友领先出最小；否则能赢用最小，赢不了出最小
	if FollowRule.has_type(hand, s_class, lead.type, trump):
		var options := list_type_options(hand, s_class, lead.type, trump)
		options.sort_custom(_option_power_asc)
		if winner_is_teammate:
			return options[0].cards
		for opt in options:
			if opt.power > beat_power:
				return opt.cards
		return options[0].cards

	# 2) 有该类牌但不成型 → 打尽（含优先对子），必输本轮
	var class_cards := FollowRule.filter_class(hand, s_class, trump)
	if not class_cards.is_empty():
		return build_exhaust_play(class_cards, hand, lead.cards.size(), s_class, trump)

	# 3) 无该类牌：杀（可选，桌面有分或最后一手才动用）或垫
	var kills := list_type_options(hand, TrumpInfo.CLASS_TRUMP, lead.type, trump)
	if not kills.is_empty() and not winner_is_teammate:
		kills.sort_custom(_option_power_asc)
		if trick_points >= 10 or last_seat:
			for opt in kills:
				if opt.power > beat_power:
					return opt.cards
	return build_discard(hand, trump, lead.cards.size(), winner_is_teammate and i_am_defender)


## 领出：手中最大的完整牌型（拖拉机 > 对子 > 单张）
static func _choose_lead(hand: Array, trump: TrumpInfo) -> Array:
	var best: Array = []
	var best_score := -1
	for c in hand:
		var s := trump.card_power(c)
		if s > best_score:
			best_score = s
			best = [c]
	var classes: Array = [TrumpInfo.CLASS_TRUMP]
	classes.append_array(Card.NORMAL_SUITS)
	for suit_class in classes:
		for pair in FollowRule.list_pairs(hand, suit_class, trump):
			var s2 := trump.card_power(pair[0]) + 1000
			if s2 > best_score:
				best_score = s2
				best = pair
		for t in FollowRule.list_tractors(hand, suit_class, trump):
			var s3 := Combo.power(Combo.detect(t, trump), trump) + 100000
			if s3 > best_score:
				best_score = s3
				best = t
	return best


## ============================= 出牌构造件（策略内部使用） =============================

## 列出指定类中某牌型的全部选择：[{ cards: Array[Card], power: int }]
static func list_type_options(cards: Array, suit_class: int, type: int, trump: TrumpInfo) -> Array:
	var options: Array = []
	match type:
		Combo.Type.SINGLE:
			for c in FollowRule.filter_class(cards, suit_class, trump):
				options.append({cards = [c], power = trump.card_power(c)})
		Combo.Type.PAIR:
			for pair in FollowRule.list_pairs(cards, suit_class, trump):
				options.append({cards = pair, power = trump.card_power(pair[0])})
		Combo.Type.TRACTOR:
			for t in FollowRule.list_tractors(cards, suit_class, trump):
				options.append({cards = t, power = Combo.power(Combo.detect(t, trump), trump)})
	return options


## 打尽出牌：类牌不足张数 → 全出 + 补最差牌；多于张数 → 强制对子优先 + 最小牌
## （对子数下限与 FollowRule._pair_priority_ok 同口径：required_pair_count）
static func build_exhaust_play(class_cards: Array, hand: Array, n: int, suit_class: int, trump: TrumpInfo) -> Array:
	var play: Array = []
	if class_cards.size() < n:
		play = class_cards.duplicate()
		var fillers: Array = []
		for c in hand:
			if not class_cards.has(c):
				fillers.append(c)
		fillers.sort_custom(_dump_key_asc(trump, false))
		for c in fillers:
			if play.size() >= n:
				break
			play.append(c)
		return play
	# 类牌不少于张数：强制对子优先（主牌轮仅常主对子，副牌轮为 S 对子）
	var mandatory: Array = []
	if suit_class == TrumpInfo.CLASS_TRUMP:
		for c in class_cards:
			if trump.is_permanent_trump(c):
				mandatory.append(c)
	else:
		mandatory = class_cards
	var mandatory_pairs := FollowRule.count_identity_pairs(mandatory)
	var required_pairs := FollowRule.required_pair_count(n, mandatory_pairs)
	var chosen: Array = []
	if required_pairs > 0:
		var pairs := FollowRule.list_pairs(mandatory, suit_class, trump)
		pairs.sort_custom(_pair_power_asc(trump))
		for pair in pairs:
			if chosen.size() / 2 >= required_pairs:
				break
			chosen.append(pair[0])
			chosen.append(pair[1])
	var singles: Array = []
	for c in class_cards:
		if not chosen.has(c):
			singles.append(c)
	singles.sort_custom(_card_power_asc(trump))
	for c in singles:
		if chosen.size() >= n:
			break
		chosen.append(c)
	return chosen


## 垫牌：优先非主牌、非分牌、最低牌力；feed_teammate 时优先垫分牌喂队友
static func build_discard(hand: Array, trump: TrumpInfo, n: int, feed_teammate := false) -> Array:
	var dump: Array = hand.duplicate()
	dump.sort_custom(_dump_key_asc(trump, feed_teammate))
	return dump.slice(0, n)


static func _option_power_asc(a, b) -> bool:
	return a.power < b.power


static func _card_power_asc(trump: TrumpInfo) -> Callable:
	return func(a: Card, b: Card) -> bool:
		return trump.card_power(a) < trump.card_power(b)


static func _pair_power_asc(trump: TrumpInfo) -> Callable:
	return func(a: Array, b: Array) -> bool:
		return trump.card_power(a[0]) < trump.card_power(b[0])


## 垫牌排序：非主牌在前 →（喂队友：分牌大者在前 / 普通：分牌小者在前）→ 牌力低者在前
static func _dump_key_asc(trump: TrumpInfo, feed: bool) -> Callable:
	return func(a: Card, b: Card) -> bool:
		var at := 1 if trump.is_trump(a) else 0
		var bt := 1 if trump.is_trump(b) else 0
		if at != bt:
			return at < bt
		if feed and a.points() != b.points():
			return a.points() > b.points()
		if not feed and a.points() != b.points():
			return a.points() < b.points()
		return trump.card_power(a) < trump.card_power(b)
