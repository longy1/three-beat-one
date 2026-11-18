extends TestBase
## Combo 用例（规则 6 牌型、6.2 邻接链、6.3 拖拉机与常主组合）。
## 前提（A.2.2）：♠ 为主花色，R = 9 —— 继承自 TestBase.trump。


func detect(cards: Array) -> Combo:
	return Combo.detect(cards, trump)


func test_single(test) -> void:
	var combo := detect([C(Card.Suit.CLUB, Card.RANK_5)])
	test.check(combo != null, "任意 1 张为单牌")
	test.eq(combo.type, Combo.Type.SINGLE, "类型")
	test.eq(combo.suit, Card.Suit.CLUB, "♣5 副牌类")
	var joker := detect([C(Card.Suit.JOKER, Card.RANK_BIG_JOKER)])
	test.eq(joker.suit, TrumpInfo.CLASS_TRUMP, "大王主牌类")


func test_pair_valid_and_invalid(test) -> void:
	test.check(detect([C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)]) != null,
		"同花色同点数两张 = 对子")
	test.is_null(detect([C(Card.Suit.CLUB, Card.RANK_5), C(Card.Suit.HEART, Card.RANK_5)]),
		"不同花色不成对")
	test.is_null(detect([C(Card.Suit.CLUB, Card.RANK_A), C(Card.Suit.CLUB, Card.RANK_K)]),
		"同花色不同点不成对")
	test.check(detect([C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1)]) != null,
		"对大王是对子")
	test.is_null(detect([C(Card.Suit.JOKER, Card.RANK_BIG_JOKER), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER)]),
		"大王+小王不是对子")
	test.is_null(detect([C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 0)]),
		"同一张牌重复不成对")
	# 对子归属类
	var main_pair := detect([C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 1)])
	test.eq(main_pair.suit, TrumpInfo.CLASS_TRUMP, "主花色对属主牌类")
	var side_pair := detect([C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)])
	test.eq(side_pair.suit, Card.Suit.CLUB, "副花色对属副牌类")
	var trump_side_pair := detect([C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.HEART, Card.RANK_2, 1)])
	test.eq(trump_side_pair.suit, TrumpInfo.CLASS_TRUMP, "副2对（常主）属主牌类")


func test_tractor_main_suit(test) -> void:
	# 6.2 主花色：R=9 在原位不断链，8~9 相邻（A.3 丙的杀）
	test.check(detect([
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
	]) != null, "♠88♠99 主牌拖拉机（R=9 不断链）")
	test.check(detect([
		C(Card.Suit.SPADE, Card.RANK_10, 0), C(Card.Suit.SPADE, Card.RANK_10, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
	]) != null, "♠1010♠99 合法")
	# A~2 独立段（仅主花色）
	test.check(detect([
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
	]) != null, "♠AA♠22 主花色 A~2 拖拉机")
	# K~A 禁连（首尾禁连）
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_K, 0), C(Card.Suit.SPADE, Card.RANK_K, 1),
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),
	]), "♠KK♠AA 非法（K~A 禁连）")
	# 2 与 K 不相邻（A 在中间且 K~A 禁连）
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
		C(Card.Suit.SPADE, Card.RANK_K, 0), C(Card.Suit.SPADE, Card.RANK_K, 1),
	]), "♠22♠KK 非法")
	# 5 孤点
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 1),
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
	]), "♠55♠77 非法（5 孤点）")


func test_tractor_side_suit(test) -> void:
	# 6.2 副花色：链 K~7，R=9 移除断链
	test.check(detect([
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1),
	]) != null, "♣JJ♣1010 合法")
	test.is_null(detect([
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1),
		C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_8, 1),
	]), "♣1010♣88 非法（R=9 处断链）")
	test.is_null(detect([
		C(Card.Suit.CLUB, Card.RANK_9, 0), C(Card.Suit.CLUB, Card.RANK_9, 1),
		C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_8, 1),
	]), "♣99♣88 非法（副9 是常主，跨类）")
	# 副花色 A、2 不参与拖拉机（A 不可、2 跨类）——R=9（R≠A）时维持非法
	test.is_null(detect([
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_2, 0), C(Card.Suit.CLUB, Card.RANK_2, 1),
	]), "♣AA♣22 非法（R≠A）")
	test.is_null(detect([
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
	]), "♣AA♣KK 非法（K~A 禁连）")
	# 副花色拖拉机只能由 7~K 链构成（3.3 推论）
	test.check(detect([
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1),
	]) != null, "♣KK♣QQ 合法")


## R=A 特例：A 为常主，同花色的 A 对与 2 对相邻（A~2 连）
func test_tractor_rank_equals_a(test) -> void:
	var t_spade_a := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_A)
	# 副花色 AA22（喊 ♠A）→ 合法（用户裁定的新解释）
	var club_a22 := Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_2, 0), C(Card.Suit.CLUB, Card.RANK_2, 1),
	], t_spade_a)
	test.check(club_a22 != null, "喊 ♠A：♣AA♣22 为合法拖拉机")
	if club_a22 != null:
		test.eq(club_a22.type, Combo.Type.TRACTOR, "类型为拖拉机")
	# 主花色本尊仍合法
	var spade_a22 := Combo.detect([
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
	], t_spade_a)
	test.check(spade_a22 != null, "♠AA♠22 仍合法")
	# 不同花色的常主组合仍非法（6.3）
	var cross := Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
		C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.HEART, Card.RANK_2, 1),
	], t_spade_a)
	test.is_null(cross, "♣AA♥22 不同花色仍非法")
	# K~A 禁连不变
	var ka := Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
	], t_spade_a)
	test.is_null(ka, "♣KK♣AA 禁连不变")
	# 非 R=A（R=9）时 ♣AA♣22 维持非法
	var t_nine := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	test.is_null(Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_2, 0), C(Card.Suit.CLUB, Card.RANK_2, 1),
	], t_nine), "R≠A 时 ♣AA♣22 仍非法")
	# 牌力：R=A 常主拖 > 一切副牌拖（含同花色副牌拖——主牌类 > 副牌类）
	var heart_tr := Combo.detect([
		C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1),
		C(Card.Suit.HEART, Card.RANK_Q, 0), C(Card.Suit.HEART, Card.RANK_Q, 1),
	], t_spade_a)
	if club_a22 != null and heart_tr != null:
		test.check(Combo.compare(club_a22, heart_tr, t_spade_a) > 0, "♣AA♣22（主牌类）> ♥KK♥QQ（副牌拖）")
	var club_kq := Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1),
	], t_spade_a)
	if club_a22 != null and club_kq != null:
		test.check(Combo.compare(club_a22, club_kq, t_spade_a) > 0,
			"♣AA♣22（主牌类）> ♣KK♣QQ（同花色副牌拖）")


func test_tractor_rank_variants(test) -> void:
	# R=5：正5/副5 均为孤点，不参与任何拖拉机（6.2）
	var t5 := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_5)
	test.is_null(Combo.detect([
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 1),
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
	], t5), "R=5 时 ♠55♠77 仍非法")
	test.is_null(Combo.detect([
		C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1),
		C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_7, 1),
	], t5), "R=5 时 ♣55♣77 仍非法")
	test.check(Combo.detect([
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
	], t5) != null, "R=5 不影响 ♠99♠88")
	# R=2：主花色链不变（6.2）
	var t2 := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_2)
	test.check(Combo.detect([
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
	], t2) != null, "R=2 时 ♠AA♠22 合法")


func test_four_jokers_tractor(test) -> void:
	var four_jokers := [
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
	]
	var combo := detect(four_jokers)
	test.check(combo != null, "四王 = 拖拉机（6.3 唯一跨花色特例）")
	test.eq(combo.type, Combo.Type.TRACTOR, "四王是拖拉机")
	test.eq(combo.suit, TrumpInfo.CLASS_TRUMP, "四王属主牌类")
	# 三张同王不成拖拉机（两副牌仅两张大王，此处构造三张同身份以验证分组校验）
	test.is_null(detect([
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0),
	]), "三大王一小白非法")


func test_permanent_pairs_not_tractor(test) -> void:
	# 6.3 不同花色的常主对子组合不是拖拉机
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.CLUB, Card.RANK_9, 0), C(Card.Suit.CLUB, Card.RANK_9, 1),
	]), "正R对+副R对 不是拖拉机")
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
		C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.HEART, Card.RANK_2, 1),
	]), "正2对+副2对 不是拖拉机")
	test.is_null(detect([
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
	]), "小王对+正R对 不是拖拉机")
	# 跨主副牌类不能混构（3.3）
	test.is_null(detect([
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 1),
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
	]), "主牌对+副牌对 跨类非法")
	test.is_null(detect([C(Card.Suit.SPADE, Card.RANK_5), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER)]),
		"主牌+王 两张不成对")


func test_tractor_power_order(test) -> void:
	# 6.3 拖拉机比较：主牌类 > 一切副牌；同类比"较大一组"位置
	var four_jokers := detect([
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
	])
	var main_a2 := detect([
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
	])
	var main_10_9 := detect([
		C(Card.Suit.SPADE, Card.RANK_10, 0), C(Card.Suit.SPADE, Card.RANK_10, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
	])
	var side_kq := detect([
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1),
	])
	test.check(Combo.compare(four_jokers, main_a2, trump) > 0, "四王 > ♠AA♠22")
	# R=A 时 AA22 在其花色的同类拖拉机中排最小
	# ——主花色 AA22 < ♠1010♠99 < ♠7788（若存在）
	var main_7_8 := detect([
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
	])
	test.check(Combo.compare(main_10_9, main_a2, trump) > 0, "♠1010♠99 > ♠AA♠22（AA22 同类最小）")
	test.check(Combo.compare(main_7_8, main_a2, trump) > 0, "♠7788 > ♠AA♠22（主牌 AA22 < 主牌 7788）")
	test.check(Combo.compare(main_10_9, side_kq, trump) > 0, "主牌拖拉机 > 副牌拖拉机")
	var side_j10 := detect([
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1),
	])
	test.check(Combo.compare(side_kq, side_j10, trump) > 0, "♣KK♣QQ > ♣JJ♣1010")
