class_name Combo
extends RefCounted
## 牌型：单牌 / 对子 / 拖拉机（规则 6）。仅此三种，无顺子、三张、炸弹等。
## 主牌类与副牌类不得混构牌型（3.3 跨类不能成牌型）。


enum Type { SINGLE, PAIR, TRACTOR }

var type: int = Type.SINGLE
var cards: Array[Card] = []
## 归属类：TrumpInfo.CLASS_TRUMP 或具体副花色
var suit: int = Card.Suit.SPADE


static func _make(p_type: int, p_cards: Array, trump: TrumpInfo) -> Combo:
	var combo := Combo.new()
	combo.type = p_type
	for c in p_cards:
		combo.cards.append(c)
	combo.suit = trump.effective_suit(p_cards[0])
	return combo


## 识别牌型；不构成合法牌型返回 null。
## 单牌：任意 1 张。对子：同花色同点数 2 张（两副牌各一）。拖拉机：同花色两组相邻对子（6.1/6.2）。
static func detect(cards: Array, trump: TrumpInfo) -> Combo:
	match cards.size():
		1:
			return _make(Type.SINGLE, cards, trump)
		2:
			var a: Card = cards[0]
			var b: Card = cards[1]
			if a.same_identity(b) and not a.same_card(b):
				return _make(Type.PAIR, cards, trump)
			return null
		4:
			return _detect_tractor(cards, trump)
		_:
			return null


## 拖拉机识别（6.1~6.3 + 3.3 跨类约束）
static func _detect_tractor(cards: Array, trump: TrumpInfo) -> Combo:
	# 全主牌类（含四王特例）或全同副花色，否则跨类非法
	var all_trump := true
	var all_side := true
	var side_suit: int = cards[0].suit
	for c in cards:
		if not trump.is_trump(c):
			all_trump = false
		if trump.is_trump(c) or c.suit != side_suit:
			all_side = false
	if not all_trump and not all_side:
		return null

	# 分解为两组对子（每组恰 2 张同身份牌）
	var groups := pair_groups(cards)
	var pairs: Array = []
	for key in groups:
		var g: Array = groups[key]
		if g.size() == 2:
			pairs.append(g)
		else:
			return null  # 4 张无法分成两对
	if pairs.size() != 2:
		return null

	# 按链位降序排列（链序即点数序：2 > A > K > … > 7 > 5，王居首）
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0].rank > b[0].rank)
	var hi: Array = pairs[0]
	var lo: Array = pairs[1]

	if all_trump:
		# 四王 = 最大的拖拉机（6.3，唯一不受同花色约束的特例）
		var hi_joker: bool = hi[0].is_joker()
		var lo_joker: bool = lo[0].is_joker()
		if hi_joker or lo_joker:
			if hi_joker and lo_joker \
					and hi[0].rank == Card.RANK_BIG_JOKER and lo[0].rank == Card.RANK_SMALL_JOKER:
				return _make(Type.TRACTOR, cards, trump)
			return null  # 王对与花色对、或三张同王，均不构成拖拉机
		# R=A 特例（A 为常主）：同花色的 A 对与 2 对相邻——
		# 副花色的 AA22（如 ♣AA♣22 且喊 ♠A）与主花色 AA22 同判合法
		var a2_override: bool = trump.rank == Card.RANK_A \
			and hi[0].suit == lo[0].suit \
			and ((hi[0].rank == Card.RANK_2 and lo[0].rank == Card.RANK_A) \
				or (hi[0].rank == Card.RANK_A and lo[0].rank == Card.RANK_2))
		# 非 R=A 特例时，仍要求主花色两对（正R/正2 属主牌类同链）；不同花色的常主对组合不是拖拉机（6.3）
		if not a2_override and (hi[0].suit != trump.suit or lo[0].suit != trump.suit):
			return null
	else:
		# 副花色两对：不得含常主（2、副R 跨类不可用，3.3/6.2）
		if trump.is_trump(hi[0]) or trump.is_trump(lo[0]):
			return null

	if pairs_adjacent(hi, lo, trump):
		return _make(Type.TRACTOR, cards, trump)
	return null


## 两组对子是否满足邻接链（6.2）。hi/lo 为按链位降序的两张牌数组。
## - 主花色：两段独立链 A~2 与 K~Q~J~10~9~8~7（R 在原位不断链）；K~A 禁连；5 孤点
## - 副花色：仅 K~Q~J~10~9~8~7 一段链，R 移除断链；A、5、2 不参与
## - 王：仅"大王对 + 小王对"= 四王（调用方已保证两对皆王时只可能是此组合）
static func pairs_adjacent(hi: Array, lo: Array, trump: TrumpInfo) -> bool:
	var hi_joker: bool = hi[0].is_joker()
	var lo_joker: bool = lo[0].is_joker()
	if hi_joker != lo_joker:
		return false
	if hi_joker:
		return hi[0].rank == Card.RANK_BIG_JOKER and lo[0].rank == Card.RANK_SMALL_JOKER

	var hi_rank: int = hi[0].rank
	var lo_rank: int = lo[0].rank
	# R=A 特例：同花色的 A 对与 2 对相邻（A~2 连，含副花色）
	if trump.rank == Card.RANK_A and hi_rank == Card.RANK_2 and lo_rank == Card.RANK_A \
			and hi[0].suit == lo[0].suit:
		return true
	if hi[0].suit == trump.suit and lo[0].suit == trump.suit:
		# A~2 独立段（仅主花色；K~A 禁连）
		if hi_rank == Card.RANK_2 and lo_rank == Card.RANK_A:
			return true
		# K~7 段：R 在原位不断链；5 孤点（rank 5 不在段内）
		return hi_rank <= Card.RANK_K and lo_rank >= Card.RANK_7 and hi_rank - lo_rank == 1
	# 副花色：同花色的非常主对；R 移除断链
	if hi[0].suit == lo[0].suit and not trump.is_trump(hi[0]) and not trump.is_trump(lo[0]):
		return hi_rank <= Card.RANK_K and lo_rank >= Card.RANK_7 \
			and hi_rank != trump.rank and lo_rank != trump.rank \
			and hi_rank - lo_rank == 1
	return false


## 按身份（花色+点数）分组，用于找对子。返回 { key: Array[Card] }
static func pair_groups(cards: Array) -> Dictionary:
	var groups := {}
	for c in cards:
		var key := "%d_%d" % [c.suit, c.rank]
		if groups.has(key):
			groups[key].append(c)
		else:
			groups[key] = [c]
	return groups


## 牌型比较用牌力（3.1 全序 + 6.3 拖拉机比较）。
## - 单/对：该牌（对子两张同点同力）的 card_power
## - 拖拉机：主牌类拖拉机(100000+) > 一切副牌拖拉机(50000+)；同类比"较大一组"在 3.1 全序中的位置
## - R=A 时 AA22（A 对+2 对的拖拉机）在其花色的同类拖拉机中排最小
##   （如主牌 AA22 < 主牌 7788）；跨花色比较仍按大类（主牌类 > 副牌类）
static func power(combo: Combo, trump: TrumpInfo) -> int:
	match combo.type:
		Type.SINGLE, Type.PAIR:
			return trump.card_power(combo.cards[0])
		Type.TRACTOR:
			var groups := pair_groups(combo.cards)
			var top := 0
			for key in groups:
				top = maxi(top, trump.card_power(groups[key][0]))
			var base := 100000 if combo.suit == TrumpInfo.CLASS_TRUMP else 50000
			if _is_a2_tractor(combo):
				return base - 1  # AA22 同类最小（仍高于一切副牌类，保持杀必赢）
			return base + top
	return 0


## 是否为 AA22 拖拉机（两对分别为 A 对与 2 对）
static func _is_a2_tractor(combo: Combo) -> bool:
	var ranks := {}
	for c in combo.cards:
		ranks[c.rank] = true
	return ranks.size() == 2 and ranks.has(Card.RANK_2) and ranks.has(Card.RANK_A)


## 比较两个同类牌型：返回 1（a 大）/ -1（b 大）/ 0（并列，先出者大由 Trick 处理）
static func compare(a: Combo, b: Combo, trump: TrumpInfo) -> int:
	var pa := power(a, trump)
	var pb := power(b, trump)
	if pa > pb:
		return 1
	if pa < pb:
		return -1
	return 0
