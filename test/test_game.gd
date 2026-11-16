extends TestBase
## GameEngine 用例（规则 2、4、5、8.2、9、10）。


## 固定顺序牌堆切分的标准发牌（内容不重要，流程测试用）
func standard_deal() -> Dictionary:
	var deck := Card.full_deck()
	var hands: Array = []
	for s in 4:
		hands.append(deck.slice(s * 19, (s + 1) * 19))
	return {hands = hands, bottom = deck.slice(76, 84)}


func ok(test, verdict: Dictionary, note := "") -> void:
	test.check(verdict.get("ok", verdict.get("legal", false)), note + " " + str(verdict.get("error", verdict.get("text", ""))))


## ============================= 结算档位（规则 9） =============================

func test_compute_outcome_branches(test) -> void:
	# 闲家胜：205~244→1 级；245~284→2 级；≥285→3 级
	test.eq(GameEngine.compute_outcome(130, 75), {banker_won = false, level = 1, total = 205}, "205 恰好闲家胜 1 级")
	test.eq(GameEngine.compute_outcome(130, 114), {banker_won = false, level = 1, total = 244}, "244 仍 1 级")
	test.eq(GameEngine.compute_outcome(130, 115), {banker_won = false, level = 2, total = 245}, "245 → 2 级")
	test.eq(GameEngine.compute_outcome(200, 84), {banker_won = false, level = 2, total = 284}, "284 仍 2 级")
	test.eq(GameEngine.compute_outcome(200, 85), {banker_won = false, level = 3, total = 285}, "285 → 3 级")
	test.eq(GameEngine.compute_outcome(130, 155), {banker_won = false, level = 3, total = 285}, "3 级封顶")
	# 庄家胜：捉 0 分 → 3 级；5~20 → 2 级；≥25 → 1 级
	test.eq(GameEngine.compute_outcome(130, 0), {banker_won = true, level = 3, total = 130}, "捉 0 分庄胜 3 级")
	test.eq(GameEngine.compute_outcome(130, 5), {banker_won = true, level = 2, total = 135}, "捉 5 分庄胜 2 级")
	test.eq(GameEngine.compute_outcome(130, 20), {banker_won = true, level = 2, total = 150}, "捉 20 分庄胜 2 级")
	test.eq(GameEngine.compute_outcome(130, 25), {banker_won = true, level = 1, total = 155}, "捉 25 分庄胜 1 级")
	test.eq(GameEngine.compute_outcome(200, 0), {banker_won = true, level = 3, total = 200}, "叫 200 捉 0 分仍庄胜")


## ============================= 拍卖（规则 5） =============================

func test_auction_forced_130(test) -> void:
	var deal := standard_deal()
	var engine := GameEngine.new()
	engine.start_session_with_deal(0, deal.hands, deal.bottom)
	test.eq(engine.phase, Phase.AUCTION, "发牌后进入拍卖")
	# 其余三家全部放弃 → 抓牌庄家以 130 坐庄（规则 5.5）
	ok(test, engine.submit_bid(1, GameEngine.BID_PASS), "乙过")
	ok(test, engine.submit_bid(2, GameEngine.BID_PASS), "丙过")
	ok(test, engine.submit_bid(3, GameEngine.BID_PASS), "丁过")
	test.eq(engine.banker_seat, 0, "抓牌庄家坐庄")
	test.eq(engine.contract, 130, "以 130 坐庄")
	test.eq(engine.phase, Phase.TRUMP, "进入叫主")


func test_auction_validation(test) -> void:
	var deal := standard_deal()
	var engine := GameEngine.new()
	engine.start_session_with_deal(0, deal.hands, deal.bottom)
	test.check(not engine.submit_bid(1, 130).ok, "叫分须高于当前最高（130）")
	test.check(not engine.submit_bid(1, 133).ok, "叫分须为 5 的倍数")
	test.check(not engine.submit_bid(1, 205).ok, "叫分不能超过封顶 200")
	test.check(not engine.submit_bid(2, 135).ok, "未轮到不能表态")
	ok(test, engine.submit_bid(1, 135), "乙叫 135")
	ok(test, engine.submit_bid(2, 140), "丙加叫 140")
	# 放弃永久（规则 5.3）
	ok(test, engine.submit_bid(3, GameEngine.BID_PASS), "丁放弃")
	test.check(engine.has_passed(3), "丁永久退出")
	# 封顶后只能放弃（规则 5.3）
	ok(test, engine.submit_bid(0, 200), "甲（抓牌庄家）跳叫 200")
	test.check(not engine.submit_bid(1, 205).ok, "已封顶不能再加")
	ok(test, engine.submit_bid(1, GameEngine.BID_PASS), "乙只能放弃")
	ok(test, engine.submit_bid(2, GameEngine.BID_PASS), "丙放弃")
	test.eq(engine.banker_seat, 0, "甲以 200 坐庄")
	test.eq(engine.contract, 200, "叫分 200")


## ============================= 叫主 / 翻底 / 扣底（规则 2、3.2） =============================

func test_trump_and_discard_flow(test) -> void:
	var deal := standard_deal()
	var engine := GameEngine.new()
	engine.start_session_with_deal(0, deal.hands, deal.bottom)
	for s in [1, 2, 3]:
		engine.submit_bid(s, GameEngine.BID_PASS)
	# 只有出牌庄家可以叫主
	test.check(not engine.submit_trump(1, Card.Suit.HEART, Card.RANK_5).ok, "非庄家不能叫主")
	ok(test, engine.submit_trump(0, Card.Suit.HEART, Card.RANK_5), "庄家叫主 ♥5")
	test.eq(engine.phase, Phase.DISCARD, "进入扣底")
	test.eq(engine.hands[0].size(), 27, "翻底后 27 张")
	# 底牌可见性：仅庄家（规则 2）
	test.eq(engine.peek_bottom(0).size(), 8, "庄家可见底牌")
	test.eq(engine.peek_bottom(1).size(), 0, "闲家不可见底牌")
	# 扣底校验
	test.check(not engine.submit_discard(0, deal.hands[0].slice(0, 7)).ok, "须扣 8 张")
	test.check(not engine.submit_discard(1, AiPolicy.choose_discard(engine.hands[1], engine.trump)).ok, "非庄家不能扣底")
	var discard := AiPolicy.choose_discard(engine.hands[0], engine.trump)
	ok(test, engine.submit_discard(0, discard), "庄家扣底")
	test.eq(engine.hands[0].size(), 19, "扣底后 19 张")
	test.eq(engine.bottom_points, _points_of(discard), "新底牌分值")
	test.eq(engine.phase, Phase.TRICKS, "进入出牌")
	test.eq(engine.leader_seat, 0, "首轮庄家领出")


func _points_of(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += c.points()
	return total


## ============================= 抠底路径（8.2）迷你剧本 =============================
## 引擎不限定手牌张数，注入 2 张迷你手牌直接构造"末轮"，确定性覆盖抠底三分支。

var KOUDI_BOTTOM_35: Array = [
	Card.new(Card.Suit.CLUB, Card.RANK_10, 0), Card.new(Card.Suit.HEART, Card.RANK_10, 0),
	Card.new(Card.Suit.DIAMOND, Card.RANK_K, 0), Card.new(Card.Suit.CLUB, Card.RANK_5, 0),
	Card.new(Card.Suit.HEART, Card.RANK_J, 0), Card.new(Card.Suit.DIAMOND, Card.RANK_Q, 0),
	Card.new(Card.Suit.CLUB, Card.RANK_8, 0), Card.new(Card.Suit.HEART, Card.RANK_7, 0)]


## 走完 拍卖(庄家=2,叫135) → 叫主 ♠R9 → 扣底(原样扣回，底牌 35 分)
func _setup_mini(test, engine: GameEngine, hands: Array) -> void:
	engine.start_session_with_deal(3, hands, KOUDI_BOTTOM_35.duplicate())
	ok(test, engine.submit_bid(0, GameEngine.BID_PASS), "甲过")
	ok(test, engine.submit_bid(1, GameEngine.BID_PASS), "乙过")
	ok(test, engine.submit_bid(2, 135), "丙叫 135")
	ok(test, engine.submit_bid(3, GameEngine.BID_PASS), "丁过")
	test.eq(engine.banker_seat, 2, "出牌庄家 = 丙")
	ok(test, engine.submit_trump(2, Card.Suit.SPADE, Card.RANK_9), "叫主 ♠9")
	ok(test, engine.submit_discard(2, KOUDI_BOTTOM_35.duplicate()), "扣回底牌")
	test.eq(engine.bottom_points, 35, "底牌 35 分")


func _payment_sum(payments: Array) -> int:
	var total := 0
	for p in payments:
		total += p
	return total


## 末轮闲家以主牌【单牌】赢 → 底牌分 ×1
func test_koudi_single_times_one(test) -> void:
	var engine := GameEngine.new()
	# 两轮迷你局：R1 庄家领 ♠2，大王赢（无分）；R2 闲家 ♥9 杀 ♣5 → 末轮主牌单牌
	_setup_mini(test, engine, [
		[C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.CLUB, Card.RANK_5, 0)],
		[C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.HEART, Card.RANK_7, 0)],
		[C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 0)],
		[C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_9, 1)],
	])
	ok(test, engine.submit_play(2, [engine.hands[2][0]]), "庄家领 ♠2")
	ok(test, engine.submit_play(3, [engine.hands[3][0]]), "丁跟 ♥9")
	ok(test, engine.submit_play(0, [engine.hands[0][0]]), "甲跟大王")
	ok(test, engine.submit_play(1, [engine.hands[1][0]]), "乙跟小王")
	test.eq(engine.leader_seat, 0, "R1 大王赢，甲领出")
	ok(test, engine.submit_play(0, [engine.hands[0][0]]), "甲领 ♣5")
	ok(test, engine.submit_play(1, [engine.hands[1][0]]), "乙垫 ♥7")
	ok(test, engine.submit_play(2, [engine.hands[2][0]]), "庄家垫 ♦10")
	ok(test, engine.submit_play(3, [engine.hands[3][0]]), "丁杀 ♥9")
	test.eq(engine.phase, Phase.SETTLED, "对局结束")
	var r: Dictionary = engine.last_game_result
	test.eq(r.koudi_points, 35, "末轮主牌单牌 → 底牌 35×1（8.2）")
	test.eq(r.captured_points, 15, "末轮分 ♣5+♦10 = 15")
	test.eq(r.captured_total, 50, "含抠底 50")
	test.eq(r.total_score, 185, "135+50 = 185 < 205")
	test.check(r.banker_won, "庄家胜")
	test.eq(r.level, 1, "捉 50 ≥ 25 → 庄家 1 级")
	test.eq(r.payments, [-1, -1, 3, -1], "每位闲家付庄家 B×1")
	test.eq(_payment_sum(r.payments), 0, "收支守恒")


## 末轮闲家以主牌【对子】杀赢 → 底牌分 ×2
func test_koudi_pair_times_two(test) -> void:
	var engine := GameEngine.new()
	# 单轮迷你局：庄家领 ♣55，乙以正9对杀 → 末轮主牌对子
	_setup_mini(test, engine, [
		[C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)],
		[C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)],
		[C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1)],
		[C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0)],
	])
	ok(test, engine.submit_play(2, engine.hands[2].duplicate()), "庄家领 ♣55")
	ok(test, engine.submit_play(3, engine.hands[3].duplicate()), "丁垫 ♥7♥8")
	ok(test, engine.submit_play(0, engine.hands[0].duplicate()), "甲 ♣ 打尽 ♣7♣8")
	ok(test, engine.submit_play(1, engine.hands[1].duplicate()), "乙杀 ♠99")
	test.eq(engine.phase, Phase.SETTLED, "对局结束")
	var r: Dictionary = engine.last_game_result
	test.eq(r.koudi_points, 70, "末轮主牌对子 → 底牌 35×2（8.2）")
	test.eq(r.captured_points, 10, "末轮分 ♣55 = 10")
	test.eq(r.captured_total, 80, "含抠底 80")
	test.eq(r.total_score, 215, "135+80 = 215 ≥ 205")
	test.check(not r.banker_won, "闲家胜")
	test.eq(r.level, 1, "205~244 → 1 级")
	test.eq(r.payments, [1, 1, -3, 1], "庄家付每位闲家 B×1")
	test.eq(_payment_sum(r.payments), 0, "收支守恒")


## 末轮由庄家赢 → 底牌分作废（不抠底）
func test_koudi_none_when_banker_wins_last(test) -> void:
	var engine := GameEngine.new()
	# 单轮迷你局：庄家领 ♠AA，无人能压 → 庄家赢末轮
	_setup_mini(test, engine, [
		[C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_7, 0)],
		[C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.DIAMOND, Card.RANK_5, 1)],
		[C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1)],
		[C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)],
	])
	ok(test, engine.submit_play(2, engine.hands[2].duplicate()), "庄家领 ♠AA")
	ok(test, engine.submit_play(3, engine.hands[3].duplicate()), "丁无主垫 ♣7♣8")
	ok(test, engine.submit_play(0, engine.hands[0].duplicate()), "甲主牌打尽 ♠5+♥7")
	ok(test, engine.submit_play(1, engine.hands[1].duplicate()), "乙主牌打尽 ♥2+♦5")
	test.eq(engine.phase, Phase.SETTLED, "对局结束")
	var r: Dictionary = engine.last_game_result
	test.eq(r.koudi_points, 0, "庄家赢末轮 → 底牌分作废")
	test.eq(r.captured_points, 0, "庄家赢轮分牌作废（8.1）")
	test.eq(r.total_score, 135, "135 + 0")
	test.check(r.banker_won, "庄家胜")
	test.eq(r.level, 3, "闲家捉 0 分 → 3 级")
	test.eq(r.payments, [-3, -3, 9, -3], "每位闲家付庄家 B×3")
	test.eq(_payment_sum(r.payments), 0, "收支守恒")


## ============================= 庄位轮换（规则 4） =============================

func test_dealer_rotation(test) -> void:
	var deal := standard_deal()
	var engine := GameEngine.new()
	engine.start_session_with_deal(1, deal.hands, deal.bottom)
	test.eq(engine.dealer_seat, 1, "首局抓牌庄家")
	ok(test, engine.submit_bid(2, 135), "丙叫 135")
	ok(test, engine.submit_bid(3, GameEngine.BID_PASS), "丁过")
	ok(test, engine.submit_bid(0, GameEngine.BID_PASS), "甲过")
	ok(test, engine.submit_bid(1, GameEngine.BID_PASS), "乙（抓牌庄家）过")
	test.eq(engine.banker_seat, 2, "丙坐庄")
	ok(test, engine.submit_trump(2, Card.Suit.CLUB, Card.RANK_A), "叫主 ♣A")
	ok(test, engine.submit_discard(2, AiPolicy.choose_discard(engine.hands[2], engine.trump)), "扣底")
	# 打完整局（全部用 AI 决策）
	var steps := 0
	while engine.phase == Phase.TRICKS:
		steps += 1
		if steps > 500:
			test.check(false, "步数超限")
			break
		var seat: int = engine.turn_seat
		var verdict: Dictionary = engine.submit_play(seat, AiPolicy.choose_play(engine, seat))
		test.check(verdict.legal, "AI 出牌合法：" + verdict.text)
	var r := engine.last_game_result
	# 规则 4：出牌庄家胜 → 抓牌庄家仍是该玩家；败 → 其下一位
	var expected: int = r.banker_seat if r.banker_won else (r.banker_seat + 1) % 4
	test.check(engine.start_next_game(), "开始下一局")
	test.eq(engine.dealer_seat, expected, "庄位轮换正确")
	test.eq(engine.phase, Phase.AUCTION, "新局进入拍卖")
