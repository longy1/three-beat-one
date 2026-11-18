class_name AiPlay
extends RefCounted
## AI 出牌侧策略（M2 贪心基线）：叫主 / 扣底 / 领出 / 跟杀垫。
## 数据进/决策出：不持有引擎引用，不读引擎内部状态——联机服务端
## 可绕过 AiPolicy 门面直接调用（M4 预留）。
##
## 策略概要：
## - 叫主：花色按张数/大牌/对子加权；R 选持有最多（成对额外加成）的点数
## - 扣底：保留顶牌最强的副花色整门（赢张引擎），其余分牌优先入底（规则 8.2 策略注记），不扣常主
## - 领出：手中牌力最大的完整牌型（拖拉机 > 对子 > 单张）
## - 跟牌：有同型 → 队友领先就出最小（不拆台），否则能赢用最小，赢不了出最小
## - 下分：庄家当前领先且未现身牌中仍有同型能压过其当前牌（队友可能握有）→ 垫分进该轮；
##   确定无人能压（如双大王已现身、庄家出小王）→ 保留分牌
## - 杀/垫：无领出花色时，桌面 ≥10 分或最后一手且能压过 → 最小杀；否则垫最差牌
##   （防守方在队友领先时垫分喂队友）；垫牌避开队友已清的副花色（每门留一家闲家守门），
##   并按花色顶牌分级：顶 ≤10 无赢张的门尽早清理，含 K/A 的门更多保留
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

## 扣底（8.2 策略注记，平衡细化）：
## - 保留一门副花色整门在手作赢张引擎：选顶牌牌力最强（平手取更长）且 ≥2 张的门，
##   其分牌随整门保留（顶张赢面大，不必白扣入底）
## - 其余副牌：分牌优先入底（底牌分闲家极难得），再按牌力补足
## - 保留门仅在其余副牌凑不满时才从最弱处扣起（尽量保整门）；常主始终不扣
static func choose_discard(hand: Array, trump: TrumpInfo, bottom_size: int) -> Array:
	var side: Array = []
	for c in hand:
		if not trump.is_trump(c):
			side.append(c)
	# 选保留门：按花色分组，顶牌牌力最大者当选
	var by_suit := {}
	for c in side:
		var s: int = trump.effective_suit(c)
		if not by_suit.has(s):
			by_suit[s] = []
		by_suit[s].append(c)
	var kept_suit := -1
	var best_top := -1
	var best_size := 0
	for s in by_suit:
		var cards: Array = by_suit[s]
		if cards.size() < 2:
			continue
		var top := 0
		for c in cards:
			top = maxi(top, trump.card_power(c))
		if top > best_top or (top == best_top and cards.size() > best_size):
			best_top = top
			best_size = cards.size()
			kept_suit = s
	# 保留门之外的副牌：分牌优先入底、牌力弱优先
	var pool: Array = []
	for c in side:
		if trump.effective_suit(c) != kept_suit:
			pool.append(c)
	pool.sort_custom(func(a: Card, b: Card) -> bool:
		if a.points() != b.points():
			return a.points() > b.points()
		return trump.card_power(a) < trump.card_power(b))
	var discard: Array = []
	for c in pool:
		if discard.size() >= bottom_size:
			break
		discard.append(c)
	# 保留门凑数：从最弱处扣起，尽量少破整门
	if discard.size() < bottom_size and kept_suit != -1:
		var kept_cards: Array = by_suit[kept_suit]
		kept_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return trump.card_power(a) < trump.card_power(b))
		for c in kept_cards:
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
## history = 已结算轮次（可空）、trump_void = 7.3 无主公示（seat → bool，可空）：
## 供领出角色策略做情报推断，缺省时退化为纯手牌贪心。
static func choose_play(hand: Array, trump: TrumpInfo, plays: Array, seat: int, banker_seat: int,
		history: Array = [], trump_void: Array = [false, false, false, false]) -> Array:
	if plays.is_empty():
		return _choose_lead(hand, trump, seat, banker_seat, history, trump_void)

	var lead := Combo.detect(plays[0].cards, trump)
	if lead == null:
		# 主牌甩打轮（7.3）：领出为不成型多张主牌，领出者必胜——纯垫牌；
		# 领出者是闲家队友时优先垫分喂队友
		var leader_seat: int = plays[0].seat
		var feed: bool = seat != banker_seat and leader_seat != banker_seat and leader_seat != seat
		return build_discard(hand, trump, plays[0].cards.size(), feed,
			_teammate_shed_suits(history, trump, seat, banker_seat))
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

	# 提前下分：当前庄家领先、且未现身牌中仍存在能压过其当前牌的
	# 同型牌（队友手里可能还握着）→ 把分牌垫进这轮；确定压不住（如双大王已现身、
	# 庄家出小王）→ 保留分牌。判定见 _unseen_can_beat。
	var teammate_may_beat: bool = i_am_defender and cur.seat == banker_seat and plays.size() <= 2 \
		and _unseen_can_beat(winner_combo, history, plays, hand, trump)

	# 1) 有同牌型 → 必须跟：队友领先出最小；否则能赢用最小，赢不了出最小
	if FollowRule.has_type(hand, s_class, lead.type, trump):
		var options := list_type_options(hand, s_class, lead.type, trump)
		options.sort_custom(_option_power_asc)
		if winner_is_teammate:
			return options[0].cards
		for opt in options:
			if opt.power > beat_power:
				return opt.cards
		# 压不住且队友也难压：跟牌里优先无分的（不在庄家赢轮白送分）
		if not teammate_may_beat:
			for opt in options:
				var has_pts := false
				for c in opt.cards:
					if c.points() > 0:
						has_pts = true
						break
				if not has_pts:
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
	var feed: bool = (winner_is_teammate and i_am_defender) or teammate_may_beat
	return build_discard(hand, trump, lead.cards.size(), feed,
		_teammate_shed_suits(history, trump, seat, banker_seat))


## 未现身牌中是否仍存在能压过 beat_combo 的同型牌（下分前置条件）。
## 未见 = 全副牌 − 历史已出 − 本轮已出 − 我的手牌（底牌不可知，按仍可能在队友手中计）。
## 单张：同类更高单牌；对子：同身份两张未见且更高；拖拉机：相邻两对未见且更高；
## 副牌轮另计主牌杀（未现身主牌同型即可压过一切副牌）。
## 全部不存在（如双大王已现身、庄家出小王）→ 无人再能压过 → 不应下分。
static func _unseen_can_beat(beat_combo: Combo, history: Array, current_plays: Array,
		my_hand: Array, trump: TrumpInfo) -> bool:
	var seen := {}
	for th in history:
		for p in th.plays:
			for c in p.cards:
				seen[c.key()] = true
	for p in current_plays:
		for c in p.cards:
			seen[c.key()] = true
	for c in my_hand:
		seen[c.key()] = true
	var unseen: Array = []
	for c in Card.full_deck():
		if not seen.has(c.key()):
			unseen.append(c)
	var s_class: int = beat_combo.suit
	match beat_combo.type:
		Combo.Type.SINGLE:
			var ref_power: int = trump.card_power(beat_combo.cards[0])
			for c in FollowRule.filter_class(unseen, s_class, trump):
				if trump.card_power(c) > ref_power:
					return true
			if s_class != TrumpInfo.CLASS_TRUMP \
					and not FollowRule.filter_class(unseen, TrumpInfo.CLASS_TRUMP, trump).is_empty():
				return true  # 未现身主牌单张即可杀副牌
			return false
		Combo.Type.PAIR:
			var ref_power: int = trump.card_power(beat_combo.cards[0])
			for pair in FollowRule.list_pairs(unseen, s_class, trump):
				if trump.card_power(pair[0]) > ref_power:
					return true
			if s_class != TrumpInfo.CLASS_TRUMP \
					and not FollowRule.list_pairs(unseen, TrumpInfo.CLASS_TRUMP, trump).is_empty():
				return true  # 未现身主牌对即可杀副牌对子
			return false
		Combo.Type.TRACTOR:
			var ref_power: int = Combo.power(beat_combo, trump)
			for t in FollowRule.list_tractors(unseen, s_class, trump):
				if Combo.power(Combo.detect(t, trump), trump) > ref_power:
					return true
			if s_class != TrumpInfo.CLASS_TRUMP \
					and not FollowRule.list_tractors(unseen, TrumpInfo.CLASS_TRUMP, trump).is_empty():
				return true  # 未现身主牌拖拉机即可杀副牌拖拉机
			return false
	return false


## 从历史推断各座位缺失的副花色：某副花色 S 领出的轮次里，
## 该座位未打出任何 S 牌（无论垫牌还是杀主）→ 其已无 S。返回 { seat: { suit: true } }
static func _infer_suit_voids(history: Array, trump: TrumpInfo) -> Dictionary:
	var voids := {}
	for th in history:
		var plays: Array = th.plays
		if plays.is_empty():
			continue
		var lead := Combo.detect(plays[0].cards, trump)
		if lead == null or lead.suit == TrumpInfo.CLASS_TRUMP:
			continue
		var s: int = lead.suit
		for p in plays:
			var has_s := false
			for c in p.cards:
				if trump.effective_suit(c) == s:
					has_s = true
					break
			if not has_s:
				if not voids.has(p.seat):
					voids[p.seat] = {}
				voids[p.seat][s] = true
	return voids


## 领出策略（角色化：甩牌与破坏副牌增补）：
## - 庄家：⓪三家均已公示无主 → 7.3 甩主牌（每次最多 4 张，逼三家各垫 n 张压缩闲家牌力）
##   ①握顶张（大王对/四王）先出最高常主对勾引（藏强牌诱闲家下分/耗牌）
##   ②弱主（无王 ≤5 张）且有副对 → 先出最小主牌单张逼闲家放主
##   ③逼空（≥2 闲家公示无主）→ 出最大副牌组合闯
##   ④开局（手牌 ≥12）有 Q 以上副对 → 提前闯（防主牌不够大时被单张拆散）
##   ⑤默认：最强完整组合（拖 > 对 > 单）
## - 闲家：不主动领主牌对/拖（除非无副牌、庄家已公示无主）；副牌组合优先
##   队友已缺失的花色（可放心喂分），避开庄家已缺失的花色（防小杀），
##   并加成「庄家还持有」的花色（持续磨其副牌）；无组合时单张试探破坏庄家副牌：
##   确定庄家剩某副花色 → 领该门最大牌（带分即出分试探）；不确定 → 领 A/Q 级大牌
static func _choose_lead(hand: Array, trump: TrumpInfo, seat: int, banker_seat: int,
		history: Array = [], trump_void: Array = [false, false, false, false]) -> Array:
	var trump_pairs := FollowRule.list_pairs(hand, TrumpInfo.CLASS_TRUMP, trump)
	var trump_tractors := FollowRule.list_tractors(hand, TrumpInfo.CLASS_TRUMP, trump)
	var side_combos: Array = []  # [{ cards, power, suit }]（副牌对子与拖拉机）
	var has_side := false
	var trump_count := 0
	var has_joker := false
	for c in hand:
		if trump.is_trump(c):
			trump_count += 1
			if c.is_joker():
				has_joker = true
		else:
			has_side = true
	for suit_class in Card.NORMAL_SUITS:
		for pair in FollowRule.list_pairs(hand, suit_class, trump):
			side_combos.append({cards = pair, power = trump.card_power(pair[0]), suit = suit_class})
		for t in FollowRule.list_tractors(hand, suit_class, trump):
			side_combos.append({cards = t, power = Combo.power(Combo.detect(t, trump), trump), suit = suit_class})

	# 主牌组合里的顶张标记：大王对 / 四王
	var holds_joker_pair := false
	for pair in trump_pairs:
		if pair[0].is_joker() and pair[0].rank == Card.RANK_BIG_JOKER:
			holds_joker_pair = true
	for t in trump_tractors:
		var jokers := 0
		for c in t:
			if c.is_joker():
				jokers += 1
		if jokers == 4:
			holds_joker_pair = true

	# ================= 庄家 =================
	if seat == banker_seat:
		var defenders_void := 0
		for d in 4:
			if d != banker_seat and trump_void.size() == 4 and trump_void[d]:
				defenders_void += 1
		var permanent_pairs: Array = []
		for pair in trump_pairs:
			if not pair[0].is_joker() and trump.is_permanent_trump(pair[0]):
				permanent_pairs.append(pair)
		# ⓪ 7.3 甩牌：三家均已公示无主 → 甩主牌。
		# 甩 n 张逼三家各垫 n 张（一轮挤压 3n 张），闲家手里的分牌会被强制垫出而作废；
		# 闲家皆无主后我方余下的副牌组合本就稳赢，无须再留主配合。
		# 每次最多甩 4 张（用户定夺：太多看不清）；主牌更多时下一轮继续甩。
		if defenders_void >= 3 and trump_count >= 2:
			var dump: Array = []
			for c in hand:
				if trump.is_trump(c):
					dump.append(c)
			return dump.slice(0, 4)
		# ① 藏强勾引：握顶张且另有常主对 → 先出最高常主对（顶张留到后手收割）
		if holds_joker_pair and not permanent_pairs.is_empty():
			permanent_pairs.sort_custom(_pair_power_desc(trump))
			return permanent_pairs[0]
		# ② 弱主逼主：先出最小主牌单张，逼闲家放主消耗
		if trump_count >= 1 and trump_count <= 5 and not has_joker \
				and not side_combos.is_empty() and defenders_void < 2:
			var lowest: Card = null
			for c in hand:
				if trump.is_trump(c) and (lowest == null or trump.card_power(c) < trump.card_power(lowest)):
					lowest = c
			return [lowest]
		# ③ 逼空闯副：闲家主牌已耗干 → 最大副牌组合冲分
		if defenders_void >= 2 and not side_combos.is_empty():
			side_combos.sort_custom(_combo_power_desc)
			return side_combos[0].cards
		# ④ 早局闯中坚副对：趁主牌控制力尚在提前兑现，防被单张拆散
		if hand.size() >= 12 and not side_combos.is_empty():
			var big_side: Dictionary = side_combos[0]
			for sc in side_combos:
				if sc.power > big_side.power:
					big_side = sc
			if big_side.power >= Card.RANK_Q:
				return big_side.cards
		# ⑤ 默认：最强完整组合
		return _best_combo(hand, trump, trump_pairs, trump_tractors, side_combos)

	# ================= 闲家 =================
	var banker_void: bool = trump_void.size() == 4 and trump_void[banker_seat]
	if banker_void:
		# 庄家已公示无主：主牌组合必赢，优先领主牌对（单张威胁已失）
		var best_trump := _best_combo(hand, trump, trump_pairs, trump_tractors, [])
		if best_trump.size() == 2 and not trump_pairs.is_empty():
			return best_trump
		if not trump_tractors.is_empty():
			return best_trump
	# 副牌组合评分：队友缺失花色加成（可放心喂分），庄家缺失花色减分（防小杀），
	# 庄家还持有的花色加成（持续消耗其副牌，直到底牌被磨干）
	if not side_combos.is_empty():
		var voids := _infer_suit_voids(history, trump)
		var banker_held: Dictionary = _banker_held_suits(history, trump, banker_seat, voids)
		var best_side: Dictionary = side_combos[0]
		var best_score := -1.0
		for sc in side_combos:
			var score: float = float(sc.power)
			for mate in 4:
				if mate == seat or mate == banker_seat:
					continue
				if voids.has(mate) and voids[mate].has(sc.suit):
					score += 300.0
			if voids.has(banker_seat) and voids[banker_seat].has(sc.suit):
				score -= 200.0
			if banker_held.has(sc.suit):
				score += 150.0
			if score > best_score:
				best_score = score
				best_side = sc
		return best_side.cards
	# 无副牌组合 → 单张试探破坏庄家副牌：
	#   确定庄家剩某副花色 → 领该花色最大牌（带分即为出分试探，逼庄家杀分或持续跟牌减薄）
	#   不确定庄家剩什么 → 领 A/Q 级大牌试探（庄家跟牌减薄，或被迫杀主消耗）
	var probe_voids := _infer_suit_voids(history, trump)
	var probe := _banker_probe_card(hand, trump, banker_seat,
		_banker_held_suits(history, trump, banker_seat, probe_voids), probe_voids)
	if not probe.is_empty():
		return probe
	if not has_side and (not trump_pairs.is_empty() or not trump_tractors.is_empty()):
		# 无副牌可打：领主牌组合（例外许可）
		return _best_combo(hand, trump, trump_pairs, trump_tractors, [])
	return _best_combo(hand, trump, trump_pairs, trump_tractors, [])


## 从历史收集「庄家持有过」的副花色（跟/领/打尽过该花色即算持有证据）；
## 已被推断缺门的排除。返回 { suit: true }
static func _banker_held_suits(history: Array, trump: TrumpInfo, banker_seat: int,
		voids: Dictionary) -> Dictionary:
	var held := {}
	for th in history:
		var plays: Array = th.plays
		if plays.is_empty():
			continue
		var lead := Combo.detect(plays[0].cards, trump)
		if lead == null or lead.suit == TrumpInfo.CLASS_TRUMP:
			continue
		var s: int = lead.suit
		for p in plays:
			if p.seat != banker_seat:
				continue
			for c in p.cards:
				if trump.effective_suit(c) == s:
					held[s] = true
	if voids.has(banker_seat):
		for s in voids[banker_seat]:
			held.erase(s)
	return held


## 单张试探领出（破坏庄家副牌）：返回试探牌或空数组
static func _banker_probe_card(hand: Array, trump: TrumpInfo, banker_seat: int,
		banker_held: Dictionary, voids: Dictionary) -> Array:
	var best_by_suit := {}  # suit -> Card（我方该副花色最大牌）
	for c in hand:
		var s := trump.effective_suit(c)
		if s == TrumpInfo.CLASS_TRUMP:
			continue
		if not best_by_suit.has(s) or trump.card_power(c) > trump.card_power(best_by_suit[s]):
			best_by_suit[s] = c
	if best_by_suit.is_empty():
		return []
	# 确定庄家还剩的花色：挑我方顶牌最强的一门（顶牌带分即为出分试探）
	var probe: Card = null
	for s in banker_held:
		if voids.has(banker_seat) and voids[banker_seat].has(s):
			continue  # 已被推断缺门 → 不再试探该门
		var c: Card = best_by_suit.get(s)
		if c == null:
			continue
		if probe == null or trump.card_power(c) > trump.card_power(probe):
			probe = c
	if probe != null:
		return [probe]
	# 不确定庄家剩什么：领 A/Q 级大牌试探
	var top: Card = null
	for s in best_by_suit:
		var c: Card = best_by_suit[s]
		if top == null or trump.card_power(c) > trump.card_power(top):
			top = c
	if top != null and top.rank >= Card.RANK_Q:
		return [top]
	return []


## 最强完整组合（拖拉机 > 对子 > 单张；原始贪心口径）
static func _best_combo(hand: Array, trump: TrumpInfo, trump_pairs: Array, trump_tractors: Array,
		side_combos: Array) -> Array:
	var best: Array = []
	var best_score := -1
	for c in hand:
		var s := trump.card_power(c)
		if s > best_score:
			best_score = s
			best = [c]
	for pair in trump_pairs:
		var s2 := trump.card_power(pair[0]) + 1000
		if s2 > best_score:
			best_score = s2
			best = pair
	for t in trump_tractors:
		var s3 := Combo.power(Combo.detect(t, trump), trump) + 100000
		if s3 > best_score:
			best_score = s3
			best = t
	for sc in side_combos:
		var s4: int = sc.power + 1000
		if s4 > best_score:
			best_score = s4
			best = sc.cards
	return best


static func _pair_power_desc(trump: TrumpInfo) -> Callable:
	return func(a: Array, b: Array) -> bool:
		return trump.card_power(a[0]) > trump.card_power(b[0])


static func _combo_power_desc(a, b) -> bool:
	return a.power > b.power


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
		fillers.sort_custom(_dump_key_asc(trump, false, [], _suit_classes(hand, trump)))
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


## 垫牌：优先非主牌、非分牌；花色按顶牌牌力分级（弱门先清、K/A 强门留）；
## feed_teammate 时优先垫分牌喂队友；avoid_suits 的花色最后才垫（守门协调）
static func build_discard(hand: Array, trump: TrumpInfo, n: int, feed_teammate := false,
		avoid_suits: Array = []) -> Array:
	var dump: Array = hand.duplicate()
	dump.sort_custom(_dump_key_asc(trump, feed_teammate, avoid_suits, _suit_classes(hand, trump)))
	return dump.slice(0, n)


static func _option_power_asc(a, b) -> bool:
	return a.power < b.power


static func _card_power_asc(trump: TrumpInfo) -> Callable:
	return func(a: Card, b: Card) -> bool:
		return trump.card_power(a) < trump.card_power(b)


static func _pair_power_asc(trump: TrumpInfo) -> Callable:
	return func(a: Array, b: Array) -> bool:
		return trump.card_power(a[0]) < trump.card_power(b[0])


## 垫牌排序：非主牌在前 →（喂队友：分牌大者在前 / 普通：分牌小者在前）
## → 花色强弱分级（弱门先清，按顶牌牌力细化）→ avoid_suits 花色靠后（守门协调）
## → 牌力低者在前
static func _dump_key_asc(trump: TrumpInfo, feed: bool, avoid_suits: Array,
		suit_classes: Dictionary = {}) -> Callable:
	return func(a: Card, b: Card) -> bool:
		var at := 1 if trump.is_trump(a) else 0
		var bt := 1 if trump.is_trump(b) else 0
		if at != bt:
			return at < bt
		if a.points() != b.points():
			if feed:
				return a.points() > b.points()
			return a.points() < b.points()
		var ca: int = suit_classes.get(trump.effective_suit(a), 1)
		var cb: int = suit_classes.get(trump.effective_suit(b), 1)
		if ca != cb:
			return ca < cb
		var av := 1 if avoid_suits.has(trump.effective_suit(a)) else 0
		var bv := 1 if avoid_suits.has(trump.effective_suit(b)) else 0
		if av != bv:
			return av < bv
		return trump.card_power(a) < trump.card_power(b)


## 垫牌的花色强弱分级（按花色顶牌牌力三档）：
## 0 = 顶 ≤10（无赢张，尽早清理）；1 = 顶 J/Q（中性）；2 = 顶 ≥K（有 K/A 级赢张，更多保留）。
## 副花色 card_power 即点数值（3.1），弱门留之无守门价值，分级优先于守门避让。
static func _suit_classes(hand: Array, trump: TrumpInfo) -> Dictionary:
	var top := {}
	for c in hand:
		var s: int = trump.effective_suit(c)
		if s == TrumpInfo.CLASS_TRUMP:
			continue
		top[s] = maxi(top.get(s, 0), trump.card_power(c))
	var classes := {}
	for s in top:
		classes[s] = 0 if top[s] <= Card.RANK_10 else (1 if top[s] <= Card.RANK_Q else 2)
	return classes


## 队友（其余闲家，含人类 0 号位）垫牌清掉的副花色：以垫牌角色累计 ≥2 张视为在清该门。
## 我方自由垫牌避开同门——每门副牌至少留一家闲家守门，末局庄家剩余副牌有人能压。
static func _teammate_shed_suits(history: Array, trump: TrumpInfo, seat: int, banker_seat: int) -> Array:
	var counts := {}
	for th in history:
		var plays: Array = th.plays
		for p in plays:
			if p.seat == seat or p.seat == banker_seat:
				continue
			if p.role != FollowRule.Role.DISCARD:
				continue
			for c in p.cards:
				var s: int = trump.effective_suit(c)
				if s == TrumpInfo.CLASS_TRUMP:
					continue
				counts[s] = counts.get(s, 0) + 1
	var out: Array = []
	for s in counts:
		if counts[s] >= 2:
			out.append(s)
	return out
