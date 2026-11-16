class_name FollowRule
extends RefCounted
## 跟牌 / 杀 / 垫判定（规则 7.2、附录 B.1 决策树）。
## 合法性只校验张数、来源与强制项；「有更大的不强制压」（7.2.1）不校验牌力高低。
## 强制项仅两处（7.2 垫牌总优先级：主副 > 花色 > 牌型）：
##   1) 领出主牌轮：主牌打尽，且需在主牌内挑选时常主对子必须优先垫出
##   2) 领出副牌轮：领出花色 S 的牌必须打尽，且需在 S 牌内挑选时 S 对子优先选出
## 「对子优先于散张」在自由垫牌时仅为建议级（7.2【建议】，不校验）。


enum Role {
	LEAD,          ## 领出
	FOLLOW_TYPE,   ## 跟同牌型（S 同型 / 主牌类同型）
	KILL,          ## 杀：主牌构成的完整同牌型压制副牌领出（仅副牌轮，可选）
	EXHAUST_FILL,  ## S/主牌打尽（可含补牌），必输本轮
	DISCARD,       ## 自由垫牌，必输本轮
}

enum Reason {
	OK = 0,
	WRONG_COUNT,              ## 张数与领出不符（或领出张数非法）
	NOT_IN_HAND,              ## 打出的牌不在手牌中
	DUPLICATE_CARD,           ## 重复打出同一张
	INVALID_COMBO,            ## 领出时不构成合法牌型
	MUST_FOLLOW_TYPE,         ## 有同牌型必须跟（7.2.1）
	MUST_EXHAUST_S,           ## 有 S 牌必须打尽（7.2.2）
	MUST_EXHAUST_TRUMP,       ## 领出主牌时持有主牌必须打尽
	S_PAIR_PRIORITY,          ## S 牌多于领出张数时 S 对子必须优先选出
	PERMANENT_PAIR_PRIORITY,  ## 主牌内挑选时常主对子必须优先垫出
}

const REASON_TEXT := {
	Reason.OK: "合法",
	Reason.WRONG_COUNT: "张数不符",
	Reason.NOT_IN_HAND: "牌不在手中",
	Reason.DUPLICATE_CARD: "重复出牌",
	Reason.INVALID_COMBO: "不成合法牌型",
	Reason.MUST_FOLLOW_TYPE: "有同牌型必须跟",
	Reason.MUST_EXHAUST_S: "有 S 牌必须打尽",
	Reason.MUST_EXHAUST_TRUMP: "持有主牌必须打尽",
	Reason.S_PAIR_PRIORITY: "S 对子必须优先选出",
	Reason.PERMANENT_PAIR_PRIORITY: "常主对子必须优先垫出",
}


static func _verdict(legal: bool, reason: int, role: int) -> Dictionary:
	return {legal = legal, reason = reason, role = role, text = REASON_TEXT[reason]}


## 判定出牌合法性。lead 为 null 表示领出（牌型任选，7.1.3）。
## 返回 { legal: bool, reason: int, role: int, text: String }。
static func is_legal(hand: Array, play: Array, lead: Combo, trump: TrumpInfo) -> Dictionary:
	# 1) 牌须来自手牌且不重复（真实对局中 Card 引用唯一）
	var hand_set := {}
	for c in hand:
		hand_set[c] = true
	var seen := {}
	for c in play:
		if not hand_set.has(c):
			return _verdict(false, Reason.NOT_IN_HAND, Role.DISCARD)
		if seen.has(c):
			return _verdict(false, Reason.DUPLICATE_CARD, Role.DISCARD)
		seen[c] = true

	if lead == null:
		# 领出：任意合法牌型，1/2/4 张（7.1.1、7.1.3）
		if play.size() != 1 and play.size() != 2 and play.size() != 4:
			return _verdict(false, Reason.WRONG_COUNT, Role.LEAD)
		if Combo.detect(play, trump) == null:
			return _verdict(false, Reason.INVALID_COMBO, Role.LEAD)
		return _verdict(true, Reason.OK, Role.LEAD)

	var n: int = lead.cards.size()
	if play.size() != n:
		return _verdict(false, Reason.WRONG_COUNT, Role.DISCARD)

	var play_combo := Combo.detect(play, trump)
	if lead.suit == TrumpInfo.CLASS_TRUMP:
		return _check_main_lead(hand, play, play_combo, lead, trump, n)
	return _check_side_lead(hand, play, play_combo, lead, trump, n)


## 领出主牌类时（7.2「领出主牌时」）
static func _check_main_lead(hand: Array, play: Array, play_combo: Combo, lead: Combo, trump: TrumpInfo, n: int) -> Dictionary:
	# 有主牌类同牌型 → 必须跟（选牌自由：多组同型任选；四王为唯一拖拉机时强制打出）
	if has_type(hand, TrumpInfo.CLASS_TRUMP, lead.type, trump):
		if play_combo != null and play_combo.type == lead.type and play_combo.suit == TrumpInfo.CLASS_TRUMP:
			return _verdict(true, Reason.OK, Role.FOLLOW_TYPE)
		return _verdict(false, Reason.MUST_FOLLOW_TYPE, Role.FOLLOW_TYPE)

	# 无同型但持有主牌 → 主牌打尽
	var trumps := filter_class(hand, TrumpInfo.CLASS_TRUMP, trump)
	if not trumps.is_empty():
		if trumps.size() >= n:
			# 只能从主牌中选；常主对子必须优先垫出（【强制】）
			for c in play:
				if trump.effective_suit(c) != TrumpInfo.CLASS_TRUMP:
					return _verdict(false, Reason.MUST_EXHAUST_TRUMP, Role.EXHAUST_FILL)
			if trumps.size() > n and not _pair_priority_ok(trumps, play, true, trump):
				return _verdict(false, Reason.PERMANENT_PAIR_PRIORITY, Role.EXHAUST_FILL)
			return _verdict(true, Reason.OK, Role.EXHAUST_FILL)
		# 主牌不足领出张数：全部主牌打出 + 副牌补足
		for c in trumps:
			if not play.has(c):
				return _verdict(false, Reason.MUST_EXHAUST_TRUMP, Role.EXHAUST_FILL)
		return _verdict(true, Reason.OK, Role.EXHAUST_FILL)

	# 无任何主牌 → 垫副牌（自由）
	return _verdict(true, Reason.OK, Role.DISCARD)


## 领出副牌花色 S 时（7.2.1~7.2.3；常主脱离原花色，3.3）
static func _check_side_lead(hand: Array, play: Array, play_combo: Combo, lead: Combo, trump: TrumpInfo, n: int) -> Dictionary:
	var s: int = lead.suit
	# 有 S 同牌型 → 必须跟
	if has_type(hand, s, lead.type, trump):
		if play_combo != null and play_combo.type == lead.type and play_combo.suit == s:
			return _verdict(true, Reason.OK, Role.FOLLOW_TYPE)
		return _verdict(false, Reason.MUST_FOLLOW_TYPE, Role.FOLLOW_TYPE)

	# 有 S 牌但凑不齐牌型 → S 打尽
	var s_cards := filter_class(hand, s, trump)
	if not s_cards.is_empty():
		if s_cards.size() >= n:
			# 只能从 S 牌中选；S 对子优先选出（【强制】，领出为对子/拖拉机时皆然）
			for c in play:
				if trump.effective_suit(c) != s:
					return _verdict(false, Reason.MUST_EXHAUST_S, Role.EXHAUST_FILL)
			if s_cards.size() > n and not _pair_priority_ok(s_cards, play, false, trump):
				return _verdict(false, Reason.S_PAIR_PRIORITY, Role.EXHAUST_FILL)
			return _verdict(true, Reason.OK, Role.EXHAUST_FILL)
		# S 牌不足领出张数：全部 S 打出 + 其他花色或主牌补足
		for c in s_cards:
			if not play.has(c):
				return _verdict(false, Reason.MUST_EXHAUST_S, Role.EXHAUST_FILL)
		return _verdict(true, Reason.OK, Role.EXHAUST_FILL)

	# 无 S 牌：杀（可选，主牌完整同型）或垫牌（完全自由）
	if play_combo != null and play_combo.type == lead.type and play_combo.suit == TrumpInfo.CLASS_TRUMP:
		return _verdict(true, Reason.OK, Role.KILL)  # 杀可选，可保留待后期（7.2 四王）
	return _verdict(true, Reason.OK, Role.DISCARD)


## 手牌中是否存在指定类的同牌型（跟牌 / 杀能力判定）
static func has_type(hand: Array, suit_class: int, type: int, trump: TrumpInfo) -> bool:
	match type:
		Combo.Type.SINGLE:
			for c in hand:
				if trump.effective_suit(c) == suit_class:
					return true
			return false
		Combo.Type.PAIR:
			return not list_pairs(hand, suit_class, trump).is_empty()
		Combo.Type.TRACTOR:
			return not list_tractors(hand, suit_class, trump).is_empty()
	return false


## 列出指定类中所有拖拉机（两对相邻，6.2）。每个元素为 4 张牌的数组。
## 主牌类包含四王特例与主花色链；不同花色的常主对组合不会出现（pairs_adjacent 拒绝）。
static func list_tractors(cards: Array, suit_class: int, trump: TrumpInfo) -> Array:
	var tractors: Array = []
	var pairs := list_pairs(cards, suit_class, trump)
	if pairs.size() < 2:
		return tractors
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0].rank > b[0].rank)
	for i in pairs.size() - 1:
		if Combo.pairs_adjacent(pairs[i], pairs[i + 1], trump):
			tractors.append([pairs[i][0], pairs[i][1], pairs[i + 1][0], pairs[i + 1][1]])
	return tractors


## 列出指定类中的对子（同花色同点数两张；副花色不含常主，3.3）
static func list_pairs(cards: Array, suit_class: int, trump: TrumpInfo) -> Array:
	var groups := Combo.pair_groups(cards)
	var pairs: Array = []
	for key in groups:
		var g: Array = groups[key]
		if g.size() < 2:
			continue
		var c: Card = g[0]
		if trump.effective_suit(c) == suit_class:
			pairs.append([g[0], g[1]])
	return pairs


## 按归属类筛选牌（CLASS_TRUMP 或具体副花色）
static func filter_class(cards: Array, suit_class: int, trump: TrumpInfo) -> Array:
	var out: Array = []
	for c in cards:
		if trump.effective_suit(c) == suit_class:
			out.append(c)
	return out


## 打尽且池多于领出张数时的对子优先校验（7.2 两处强制项）。
## permanent_only = true：主牌轮，仅常主对子（大小王对、2 对、正R/副R 对）必须优先；
## permanent_only = false：副牌轮，S 对子必须优先选出。
## 判定标准：play 中完整对子数 ≥ min(⌊张数/2⌋, 池中对子数)。
static func _pair_priority_ok(pool: Array, play: Array, permanent_only: bool, trump: TrumpInfo) -> bool:
	var pool_pairs := 0
	if permanent_only:
		var permanents: Array = []
		for c in pool:
			if trump.is_permanent_trump(c):
				permanents.append(c)
		pool_pairs = _count_identity_pairs(permanents)
	else:
		pool_pairs = _count_identity_pairs(pool)
	var play_pairs := _count_identity_pairs(play)
	var required := mini(play.size() / 2, pool_pairs)
	return play_pairs >= required


## 同身份两张 = 一个对子；返回最大可组成的完整对子数
static func _count_identity_pairs(cards: Array) -> int:
	var groups := Combo.pair_groups(cards)
	var count := 0
	for key in groups:
		if groups[key].size() >= 2:
			count += 1
	return count
