extends RefCounted
## Trick 结算用例（规则 7.1、8.1、附录 B.2 一轮结算流程）。

var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)  # ♠ 主，R=9


func C(suit: int, rank: int, copy := 0) -> Card:
	return Card.new(suit, rank, copy)


func settle(plays: Array) -> Dictionary:
	return Trick.settle(plays, trump)


## B.2 副牌轮无杀：领出牌与跟 S 同型中最大者赢；并列先出者大（3.1）
func test_side_round_max_follow_wins(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0)]},
		{player = 1, cards = [C(Card.Suit.HEART, Card.RANK_7, 0)]},   # 垫牌
		{player = 2, cards = [C(Card.Suit.CLUB, Card.RANK_A, 0)]},    # 跟 ♣A
		{player = 3, cards = [C(Card.Suit.CLUB, Card.RANK_A, 1)]},    # 同点并列，后出
	])
	test.check(r.ok, r.error)
	test.eq(r.winner, 2, "并列 ♣A 先出者大")


## B.2 副牌轮有杀：最大杀赢，压过一切跟 S 牌与垫牌
func test_kill_beats_follow(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0)]},
		{player = 1, cards = [C(Card.Suit.CLUB, Card.RANK_A, 0)]},        # 跟 ♣A（副牌最大）
		{player = 2, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)]},      # ♠5 杀
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_7, 0)]},      # 垫
	])
	test.eq(r.winner, 2, "杀压过跟 S 牌")


## 多个杀比牌力（7.2），并列先出者大
func test_bigger_kill_wins(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)]},
		{player = 1, cards = [C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1)]},   # 杀 ♠88
		{player = 2, cards = [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]},   # 杀 ♠99（正R对）
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0)]},   # 垫
	])
	test.eq(r.winner, 2, "较大杀 ♠99 赢")


## B.2 主牌轮：领出牌与跟出的主牌类同型中最大者赢
func test_main_round_follow_wins(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.SPADE, Card.RANK_A, 0)]},           # 领 ♠A
		{player = 1, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)]},           # 跟 ♠5
		{player = 2, cards = [C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)]}, # 跟 小王
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_2, 0)]},           # 跟 ♥2（副2）
	])
	test.eq(r.winner, 2, "小王赢主牌单张轮")


## 打尽/垫牌的凑数牌不参与比较
func test_exhaust_never_wins(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1)]},
		{player = 1, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_A, 0)]},  # 打尽+补
		{player = 2, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)]},  # 跟 ♣KK
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_Q, 0)]}, # 垫
	])
	test.eq(r.winner, 2, "跟 S 对子赢，凑数牌不竞争")


## 8.1 本轮所有已出分牌计入（含垫出的分）
func test_points_include_all_discards(test) -> void:
	var r := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)]},       # 20
		{player = 1, cards = [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)]},       # 10 跟
		{player = 2, cards = [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]},     # 杀
		{player = 3, cards = [C(Card.Suit.DIAMOND, Card.RANK_10, 0), C(Card.Suit.HEART, Card.RANK_K, 0)]},  # 20 垫
	])
	test.eq(r.points, 50, "轮内总分 20+10+20")
	test.eq(r.winner, 2, "杀赢")
	test.check(r.win_main_class, "赢家牌为主牌类（抠底前提）")


## 结算自行推导角色，与 is_legal 给出的角色一致（B.2 要点）
func test_role_derivation_consistent(test) -> void:
	var hand := [C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]
	var lead_cards := [
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1)]
	var lead := Combo.detect(lead_cards, trump)
	var v: Dictionary = FollowRule.is_legal(hand, hand.duplicate(), lead, trump)
	test.eq(v.role, FollowRule.Role.KILL, "is_legal 判为杀")
	var with_role := settle([{player = 0, cards = lead_cards},
		{player = 1, cards = [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
			C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_10, 0)]},
		{player = 2, cards = hand.duplicate(), role = v.role},
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0),
			C(Card.Suit.DIAMOND, Card.RANK_5, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]}])
	var without_role := settle([{player = 0, cards = lead_cards},
		{player = 1, cards = [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
			C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_10, 0)]},
		{player = 2, cards = hand.duplicate()},
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0),
			C(Card.Suit.DIAMOND, Card.RANK_5, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]}])
	test.eq(with_role.winner, 2, "带角色：杀赢")
	test.eq(without_role.winner, 2, "推导角色：同样杀赢")


## 部分结算（1~3 份出牌）：用于 AI / UI 判定"当前最大者"
func test_partial_settle(test) -> void:
	# 仅领出：领出者暂居最大
	var r1 := settle([{player = 2, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0)]}])
	test.check(r1.ok, r1.error)
	test.eq(r1.winner, 0, "仅领出时领出者最大")
	test.eq(r1.points, 10, "部分分值已可统计")
	# 领出 + 一个杀：杀暂时领先
	var r2 := settle([
		{player = 2, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0)]},
		{player = 3, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)]},
	])
	test.eq(r2.winner, 1, "部分结算中杀领先")


## 非法输入：出牌份数越界 / 领出不构成牌型
func test_invalid_inputs(test) -> void:
	var r := settle([])
	test.check(not r.ok, "空出牌不能结算")
	var r5 := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_5, 0)]},
		{player = 1, cards = [C(Card.Suit.HEART, Card.RANK_5, 0)]},
		{player = 2, cards = [C(Card.Suit.DIAMOND, Card.RANK_5, 0)]},
		{player = 3, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)]},
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0)]},
	])
	test.check(not r5.ok, "超过四人不能结算")
	var bad_lead := settle([
		{player = 0, cards = [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 0),
			C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0)]},
		{player = 1, cards = [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
			C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_10, 0)]},
		{player = 2, cards = [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
			C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1)]},
		{player = 3, cards = [C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0),
			C(Card.Suit.DIAMOND, Card.RANK_9, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 0)]}])
	test.check(not bad_lead.ok, "领出不构成牌型须报错")
