extends RefCounted
## Card 用例（规则 1 基本设定、8.1 分牌）。


func test_full_deck_size(test) -> void:
	test.eq(Card.full_deck().size(), 84, "两副去 3/4/6 后共 84 张")


func test_full_deck_composition(test) -> void:
	var deck := Card.full_deck()
	# 每花色每点数恰 2 张
	for s in Card.NORMAL_SUITS:
		for r in Card.RANKS:
			var count := 0
			for c in deck:
				if c.suit == s and c.rank == r:
					count += 1
			test.eq(count, 2, "%d 花色点数 %d 应有 2 张" % [s, r])
	# 大王 2 张、小王 2 张
	var big := 0
	var small := 0
	for c in deck:
		if c.is_joker():
			if c.rank == Card.RANK_BIG_JOKER:
				big += 1
			else:
				small += 1
	test.eq(big, 2, "大王 2 张")
	test.eq(small, 2, "小王 2 张")
	# 点数集合不含 3、4、6
	for c in deck:
		if not c.is_joker():
			test.check(c.rank != 3 and c.rank != 4 and c.rank != 6, "不应出现 3/4/6")


func test_points(test) -> void:
	test.eq(Card.new(Card.Suit.SPADE, Card.RANK_5).points(), 5, "5 = 5 分")
	test.eq(Card.new(Card.Suit.HEART, Card.RANK_10).points(), 10, "10 = 10 分")
	test.eq(Card.new(Card.Suit.CLUB, Card.RANK_K).points(), 10, "K = 10 分")
	test.eq(Card.new(Card.Suit.DIAMOND, Card.RANK_A).points(), 0, "A 无分")
	test.eq(Card.new(Card.Suit.SPADE, Card.RANK_2).points(), 0, "2 无分")
	test.eq(Card.new(Card.Suit.JOKER, Card.RANK_BIG_JOKER).points(), 0, "王无分")
	test.eq(Card.deck_points(), 200, "全牌总分恒为 200（8.1）")


func test_identity(test) -> void:
	var a := Card.new(Card.Suit.SPADE, Card.RANK_9, 0)
	var b := Card.new(Card.Suit.SPADE, Card.RANK_9, 1)
	var c := Card.new(Card.Suit.CLUB, Card.RANK_9, 0)
	test.check(a.same_identity(b), "两副牌同花同点 = 同张")
	test.check(not a.same_identity(c), "不同花色不算同张")
	test.check(a.same_card(Card.new(Card.Suit.SPADE, Card.RANK_9, 0)), "同副号完全相同")
	test.check(not a.same_card(b), "副号不同")


func test_label(test) -> void:
	test.eq(Card.new(Card.Suit.SPADE, Card.RANK_9).label(), "♠9")
	test.eq(Card.new(Card.Suit.HEART, Card.RANK_10).label(), "♥10")
	test.eq(Card.new(Card.Suit.CLUB, Card.RANK_A).label(), "♣A")
	test.eq(Card.new(Card.Suit.JOKER, Card.RANK_BIG_JOKER).label(), "大王")
	test.eq(Card.new(Card.Suit.JOKER, Card.RANK_SMALL_JOKER).label(), "小王")
