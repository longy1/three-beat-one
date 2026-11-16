extends RefCounted
## 附录 A 完整一局推演（M1 验收依据：A.3~A.6 四轮出牌与结算）。
## 前提（A.2）：♠ 为主花色，R = 9；出牌庄家 = 丁（座位 甲→乙→丙→丁 循环）。
## 说明：推演是规则演示文本，存在跨轮次复用同一张牌的笔误（如 A.3 中甲的 ♣10
## 与丁领出的 ♣10♣10、A.6 中甲的四王与 A.4 中甲的大王）；每轮按牌例原样独立构造
## 手牌，不影响单轮规则校验。A.2 拍卖与 A.7 分级/抠底结算属 M2 范围，此处仅校验
## 抠底前提（末轮赢家牌为主牌类）。

var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)


func C(suit: int, rank: int, copy := 0) -> Card:
	return Card.new(suit, rank, copy)


## 校验一手出牌合法且角色符合预期，返回角色
func must_play(test, hand: Array, play: Array, lead: Combo, want_role: int, label: String) -> int:
	var v: Dictionary = FollowRule.is_legal(hand, play, lead, trump)
	test.check(v.legal, "%s 应合法（实际：%s）" % [label, v.text])
	test.eq(v.role, want_role, "%s 角色" % label)
	return v.role


## A.3 第 1 轮：丁领出含分拖拉机 ♣JJ♣1010，被丙杀 → 丙捉 35 分
func round1(test) -> Dictionary:
	var lead_cards := [C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1)]
	var lead := Combo.detect(lead_cards, trump)
	test.check(lead != null, "♣JJ♣1010 是合法副牌拖拉机")

	# 丁领出（S 牌打尽义务由甲侧验证）
	must_play(test, lead_cards, lead_cards, null, FollowRule.Role.LEAD, "丁领出")

	# 甲：♣10♣5 + ♦7♦8 —— 有 ♣ 无拖拉机 → 打尽 + 凑数，必输
	var jia := [C(Card.Suit.CLUB, Card.RANK_10, 1), C(Card.Suit.CLUB, Card.RANK_5, 0),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0)]
	var role_jia := must_play(test, jia, jia.duplicate(), lead, FollowRule.Role.EXHAUST_FILL, "甲打尽补足")

	# 乙：♥88♥99 —— 无 ♣，副牌拖拉机救不了 → 垫两对
	var yi := [C(Card.Suit.HEART, Card.RANK_8, 0), C(Card.Suit.HEART, Card.RANK_8, 1),
		C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_9, 1)]
	var role_yi := must_play(test, yi, yi.duplicate(), lead, FollowRule.Role.DISCARD, "乙垫两对")

	# 丙：♠88♠99 —— 无 ♣ → 主牌拖拉机杀（R=9 在主链中，8~9 相邻）
	var bing := [C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]
	var role_bing := must_play(test, bing, bing.duplicate(), lead, FollowRule.Role.KILL, "丙杀")

	var r := Trick.settle([
		{player = 3, cards = lead_cards, role = FollowRule.Role.LEAD},
		{player = 0, cards = jia, role = role_jia},
		{player = 1, cards = yi, role = role_yi},
		{player = 2, cards = bing, role = role_bing},
	], trump)
	test.check(r.ok, r.error)
	test.eq(r.winner, 3, "第 1 轮丙杀赢")
	test.eq(r.player, 2, "赢家玩家号 = 丙")
	test.eq(r.points, 35, "捉分 35（领出 20 + 甲垫 15）")
	return r


## A.4 第 2 轮：丙领出小王，甲以大王赢，无分
func round2(test) -> Dictionary:
	var lead_cards := [C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)]
	var lead := Combo.detect(lead_cards, trump)

	var ding := [C(Card.Suit.SPADE, Card.RANK_10, 0)]
	var role_ding := must_play(test, ding, ding.duplicate(), lead, FollowRule.Role.FOLLOW_TYPE, "丁跟 ♠10")

	var jia := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0)]
	var role_jia := must_play(test, jia, jia.duplicate(), lead, FollowRule.Role.FOLLOW_TYPE, "甲跟大王")

	# 乙：♥2 常主脱离花色，属主牌类，可跟主牌轮
	var yi := [C(Card.Suit.HEART, Card.RANK_2, 0)]
	var role_yi := must_play(test, yi, yi.duplicate(), lead, FollowRule.Role.FOLLOW_TYPE, "乙跟 ♥2")

	var r := Trick.settle([
		{player = 2, cards = lead_cards, role = FollowRule.Role.LEAD},
		{player = 3, cards = ding, role = role_ding},
		{player = 0, cards = jia, role = role_jia},
		{player = 1, cards = yi, role = role_yi},
	], trump)
	test.check(r.ok, r.error)
	test.eq(r.winner, 2, "第 2 轮甲以大王赢")
	# 文档 A.4 行文称"本轮无分"，但丁跟出的 ♠10 是分牌；按 8.1 公理
	# （本轮所有已出分牌计分）轮内分为 10，此处以规则为准
	test.eq(r.points, 10, "轮内分 10（♠10；A.4 行文「无分」系笔误）")
	return r


## A.5 第 3 轮：甲领出 ♣KK，丙以正9对杀 → 丙捉 30 分
func round3(test) -> Dictionary:
	var lead_cards := [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)]
	var lead := Combo.detect(lead_cards, trump)

	# 乙：有 ♣ 对子必须跟（不强制压）
	var yi := [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)]
	var role_yi := must_play(test, yi, yi.duplicate(), lead, FollowRule.Role.FOLLOW_TYPE, "乙跟 ♣55")

	# 丙：无 ♣ → 正9对杀
	var bing := [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]
	var role_bing := must_play(test, bing, bing.duplicate(), lead, FollowRule.Role.KILL, "丙杀 ♠99")

	# 丁：有杀能力但杀可选 → 垫牌保留主牌实力
	var ding := [C(Card.Suit.DIAMOND, Card.RANK_Q, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 0)]
	var role_ding := must_play(test, ding, ding.duplicate(), lead, FollowRule.Role.DISCARD, "丁垫 ♦Q♦J")

	var r := Trick.settle([
		{player = 0, cards = lead_cards, role = FollowRule.Role.LEAD},
		{player = 1, cards = yi, role = role_yi},
		{player = 2, cards = bing, role = role_bing},
		{player = 3, cards = ding, role = role_ding},
	], trump)
	test.check(r.ok, r.error)
	test.eq(r.winner, 2, "第 3 轮丙杀赢")
	test.eq(r.points, 30, "捉分 30（♣KK 20 + ♣55 10）")
	return r


## A.6 末轮：乙领出 ♦JJ♦1010，甲以四王杀赢 → 轮内 30 分，满足抠底前提
func round4(test) -> Dictionary:
	var lead_cards := [C(Card.Suit.DIAMOND, Card.RANK_J, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 1),
		C(Card.Suit.DIAMOND, Card.RANK_10, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 1)]
	var lead := Combo.detect(lead_cards, trump)

	# 丙：无 ♦ → 垫分喂队友（♣K = 10 分）
	var bing := [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_A, 0),
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_J, 1)]
	var role_bing := must_play(test, bing, bing.duplicate(), lead, FollowRule.Role.DISCARD, "丙垫分喂队友")

	# 丁：无 ♦，散主牌不成杀型 → 作垫必输
	var ding := [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_5, 0),
		C(Card.Suit.CLUB, Card.RANK_Q, 1), C(Card.Suit.HEART, Card.RANK_A, 0)]
	var role_ding := must_play(test, ding, ding.duplicate(), lead, FollowRule.Role.DISCARD, "丁散主牌作垫")

	# 甲：四王 —— 副牌轮的可选杀，刻意保留到末轮
	var jia := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1)]
	var role_jia := must_play(test, jia, jia.duplicate(), lead, FollowRule.Role.KILL, "甲四王杀")

	var r := Trick.settle([
		{player = 1, cards = lead_cards, role = FollowRule.Role.LEAD},
		{player = 2, cards = bing, role = role_bing},
		{player = 3, cards = ding, role = role_ding},
		{player = 0, cards = jia, role = role_jia},
	], trump)
	test.check(r.ok, r.error)
	test.eq(r.winner, 3, "末轮甲四王赢")
	# 文档 A.6 行文称"轮内分 20＋10 = 30"，遗漏了丁垫出的 ♠5（5 分）；
	# 按 8.1 轮内分为 35，以规则为准
	test.eq(r.points, 35, "轮内分 35（20+10+5；A.6 行文漏计 ♠5）")
	test.check(r.win_main_class, "闲家以主牌类赢末轮（抠底前提，8.2）")
	test.eq(r.win_type, Combo.Type.TRACTOR, "赢牌为拖拉机（抠底 ×2，M2 结算）")
	return r


## A.3~A.6 连续四轮：赢家依次 丙→甲→丙→甲（均为闲家）。
## 累计捉分按 8.1 严格计为 110（A.7 行文的 165 = 95 + 抠底 70 未计 A.4 的 ♠10
## 与 A.6 的 ♠5 两处分牌，属推演文本笔误；抠底倍数结算属 M2）
func test_full_round_sequence(test) -> void:
	var r1 := round1(test)
	var r2 := round2(test)
	var r3 := round3(test)
	var r4 := round4(test)
	var cumulative: int = r1.points + r2.points + r3.points + r4.points
	test.eq(cumulative, 110, "四轮累计 35+10+30+35 = 110")
	# 每轮赢家均为闲家（甲/丙），捉分全部计入
	test.eq(r1.player, 2, "R1 丙")
	test.eq(r2.player, 0, "R2 甲")
	test.eq(r3.player, 2, "R3 丙")
	test.eq(r4.player, 0, "R4 甲")


## 抠底倍数前提（8.2）：末轮主牌类单牌 ×1 / 对子与拖拉机 ×2 —— M2 实现倍数结算，
## M1 仅验证 Trick 返回的判定材料完整
func test_koudi_precondition_material(test) -> void:
	var r4 := round4(test)
	test.check(r4.ok, "末轮结算成功")
	test.check(r4.win_main_class and r4.win_type == Combo.Type.TRACTOR, "主牌类拖拉机赢末轮 → ×2 材料")
	# 对照：闲家用副牌赢末轮 → 底牌分作废（不抠底）
	var true_side_win := Trick.settle([
		{player = 1, cards = [C(Card.Suit.DIAMOND, Card.RANK_K, 0)]},
		{player = 2, cards = [C(Card.Suit.CLUB, Card.RANK_A, 0)]},
		{player = 3, cards = [C(Card.Suit.HEART, Card.RANK_7, 0)]},
		{player = 0, cards = [C(Card.Suit.DIAMOND, Card.RANK_A, 1)]},  # 跟 ♦A 更大，副牌赢
	], trump)
	test.eq(true_side_win.winner, 3, "副牌更大者赢末轮")
	test.check(not true_side_win.win_main_class, "副牌赢末轮 → 底牌分作废（不抠底）")
