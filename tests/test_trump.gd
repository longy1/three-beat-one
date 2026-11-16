extends RefCounted
## TrumpInfo 用例（规则 3 牌值与主牌体系）。

# A.2.2 推演前提：♠ 为主花色，R = 9
var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)


func C(suit: int, rank: int, copy := 0) -> Card:
	return Card.new(suit, rank, copy)


func test_power_order_full_chain(test) -> void:
	# 3.1：大王 > 小王 > 正R > 副R > 正2 > 副2 > 主A > … > 主5 > 副A > … > 副5
	var chain := [
		[C(Card.Suit.JOKER, Card.RANK_BIG_JOKER), 800, "大王"],
		[C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER), 700, "小王"],
		[C(Card.Suit.SPADE, Card.RANK_9), 600, "正9"],
		[C(Card.Suit.CLUB, Card.RANK_9), 500, "副9"],
		[C(Card.Suit.SPADE, Card.RANK_2), 400, "正2"],
		[C(Card.Suit.HEART, Card.RANK_2), 300, "副2"],
		[C(Card.Suit.SPADE, Card.RANK_A), 214, "主A"],
		[C(Card.Suit.SPADE, Card.RANK_K), 213, "主K"],
		[C(Card.Suit.SPADE, Card.RANK_5), 205, "主5"],
		[C(Card.Suit.CLUB, Card.RANK_A), 14, "副A"],
		[C(Card.Suit.CLUB, Card.RANK_K), 13, "副K"],
		[C(Card.Suit.CLUB, Card.RANK_5), 5, "副5"],
	]
	for i in chain.size():
		test.eq(trump.card_power(chain[i][0]), chain[i][1], chain[i][2] + " 牌力")
	for i in chain.size() - 1:
		test.check(trump.card_power(chain[i][0]) > trump.card_power(chain[i + 1][0]),
			"全序：%s 应大于 %s" % [chain[i][2], chain[i + 1][2]])
	# 一切主牌类 > 一切副牌类
	test.check(trump.card_power(C(Card.Suit.SPADE, Card.RANK_5)) > trump.card_power(C(Card.Suit.CLUB, Card.RANK_A)),
		"主5 > 副A")


func test_permanent_trump_membership(test) -> void:
	test.check(trump.is_trump(C(Card.Suit.HEART, Card.RANK_2)), "♥2 常主（所有 2）")
	test.check(trump.is_trump(C(Card.Suit.DIAMOND, Card.RANK_9)), "♦9 副R 常主")
	test.check(trump.is_trump(C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER)), "小王常主")
	test.check(trump.is_trump(C(Card.Suit.SPADE, Card.RANK_5)), "主花色普通牌属主牌类")
	test.check(not trump.is_trump(C(Card.Suit.CLUB, Card.RANK_K)), "副花色普通牌非主牌")


func test_effective_suit_detachment(test) -> void:
	# 3.3 常主脱离原花色：♣2、♣9（副R）不算 ♣ 牌
	test.eq(trump.effective_suit(C(Card.Suit.CLUB, Card.RANK_2)), TrumpInfo.CLASS_TRUMP, "♣2 归主牌类")
	test.eq(trump.effective_suit(C(Card.Suit.CLUB, Card.RANK_9)), TrumpInfo.CLASS_TRUMP, "♣9 副R 归主牌类")
	test.eq(trump.effective_suit(C(Card.Suit.CLUB, Card.RANK_K)), Card.Suit.CLUB, "♣K 副牌类")
	test.eq(trump.effective_suit(C(Card.Suit.SPADE, Card.RANK_5)), TrumpInfo.CLASS_TRUMP, "♠5 主牌类")
	test.eq(trump.effective_suit(C(Card.Suit.JOKER, Card.RANK_BIG_JOKER)), TrumpInfo.CLASS_TRUMP, "大王主牌类")


func test_rank_r_equals_two_order(test) -> void:
	# 3.2 R=2 时无独立 R 档：大王 > 小王 > 正2 > 副2 > 主A > …
	var t2 := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_2)
	test.eq(t2.card_power(C(Card.Suit.JOKER, Card.RANK_BIG_JOKER)), 800, "大王")
	test.eq(t2.card_power(C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER)), 700, "小王")
	test.eq(t2.card_power(C(Card.Suit.SPADE, Card.RANK_2)), 600, "正2 即正R")
	test.eq(t2.card_power(C(Card.Suit.HEART, Card.RANK_2)), 500, "副2 即副R")
	test.eq(t2.card_power(C(Card.Suit.SPADE, Card.RANK_A)), 214, "主A")
	test.check(t2.card_power(C(Card.Suit.SPADE, Card.RANK_2)) > t2.card_power(C(Card.Suit.SPADE, Card.RANK_A)),
		"正2 > 主A")


func test_rank_five_keeps_points_and_solo(test) -> void:
	# 8.1 分牌身份与分值不随常主化改变；6.2 R=5 仍是孤点
	var t5 := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_5)
	test.eq(t5.card_power(C(Card.Suit.SPADE, Card.RANK_5)), 600, "正5")
	test.eq(t5.card_power(C(Card.Suit.CLUB, Card.RANK_5)), 500, "副5")
	test.eq(C(Card.Suit.SPADE, Card.RANK_5).points(), 5, "正5 仍是 5 分牌")
	test.eq(C(Card.Suit.CLUB, Card.RANK_5).points(), 5, "副5 仍是 5 分牌")
