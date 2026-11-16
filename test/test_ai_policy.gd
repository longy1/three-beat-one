extends TestBase
## AiPolicy 用例：单项策略 sanity + 30 局种子化自动对局不变量。
## 自动对局中引擎逐一校验 AI 输出，任何非法决策都会使测试失败。


## ============================= 单项策略 =============================

func test_choose_bid_levels(test) -> void:
	AiPolicy.rng.seed = 2026
	# 极强牌（四王 + 多 2 + A 对 + K 对，strength≈86 → 校准桶 [65,∞)）
	var strong: Array = [
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_2, 0), C(Card.Suit.SPADE, Card.RANK_2, 1),
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)]
	# 弱牌（无大牌无对子）→ 完全不参与
	var weak: Array = [
		C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_7, 0),
		C(Card.Suit.DIAMOND, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_9, 0),
		C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0)]
	test.eq(AiPolicy.choose_bid(weak, 130), GameEngine.BID_PASS, "弱牌放弃")
	# 中等牌（大王 + A 对 + K 对 + 2）
	var medium: Array = [
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.SPADE, Card.RANK_A, 0),
		C(Card.Suit.SPADE, Card.RANK_A, 1), C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1),
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.DIAMOND, Card.RANK_2, 0),
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0)]
	# EV 模型：极强牌锁定校准正期望档 150（s≥65 叫 150 = +0.45）
	test.eq(AiPolicy.choose_bid(strong, 130), 150, "极强牌叫 150（校准正 EV 档）")
	test.eq(AiPolicy.choose_bid(strong, 150), GameEngine.BID_PASS, "150 已叫 → 剩余档全负 EV → 放弃")
	test.eq(AiPolicy.choose_bid(strong, 165), GameEngine.BID_PASS, "165 起全负 EV → 放弃")
	test.eq(AiPolicy.choose_bid(strong, 170), GameEngine.BID_PASS, "170 起无人应叫")
	# 中等牌（strength≈65，落在校准噪声区）：插值后负 EV → 放弃（不激进）
	test.eq(AiPolicy.choose_bid(medium, 130), GameEngine.BID_PASS, "中等牌负 EV → 放弃")


func test_choose_trump_prefers_long_suit(test) -> void:
	var hand: Array = [
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_A, 1),
		C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1),
		C(Card.Suit.HEART, Card.RANK_Q, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
		C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_9, 0),
		C(Card.Suit.SPADE, Card.RANK_5, 0)]
	var choice: Dictionary = AiPolicy.choose_trump(hand)
	test.eq(choice.suit, Card.Suit.HEART, "选最长最强花色为主")
	test.eq(choice.rank, Card.RANK_A, "R 选成对点数")


func test_choose_discard_prefers_side_points(test) -> void:
	var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand: Array = [
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1),  # 主牌保留
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0),                              # 常主保留
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.HEART, Card.RANK_5, 0),  # 副牌分入底
		C(Card.Suit.DIAMOND, Card.RANK_K, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 1),
		C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0),
		C(Card.Suit.DIAMOND, Card.RANK_9, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 0),
		C(Card.Suit.CLUB, Card.RANK_Q, 0)]
	var discard := AiPolicy.choose_discard(hand, trump)
	test.eq(discard.size(), 8, "扣 8 张")
	for c in discard:
		test.check(not trump.is_trump(c), "不扣主牌：" + c.label())
	for key in [["♣", Card.Suit.CLUB, Card.RANK_10], ["♥5", Card.Suit.HEART, Card.RANK_5], ["♦K", Card.Suit.DIAMOND, Card.RANK_K]]:
		var found := false
		for c in discard:
			if c.suit == key[1] and c.rank == key[2]:
				found = true
				break
		test.check(found, "分牌 %s 入底" % key[0])


## ============================= 自动对局不变量 =============================

func _run_auto_game(test, engine: GameEngine) -> void:
	var steps := 0
	while engine.phase != Phase.SETTLED:
		steps += 1
		if steps > 3000:
			test.check(false, "步数超限（种子卡死）")
			return
		match engine.phase:
			Phase.AUCTION:
				var seat: int = engine.auction.turn
				var verdict := engine.submit_bid(seat, AiPolicy.choose_bid(engine.hands[seat], engine.current_highest_bid()))
				test.check(verdict.ok, "AI 叫分合法：" + verdict.error)
			Phase.TRUMP:
				var choice: Dictionary = AiPolicy.choose_trump(engine.hands[engine.banker_seat])
				var verdict := engine.submit_trump(engine.banker_seat, choice.suit, choice.rank)
				test.check(verdict.ok, "AI 叫主合法：" + verdict.error)
			Phase.DISCARD:
				var cards := AiPolicy.choose_discard(engine.hands[engine.banker_seat], engine.trump)
				var verdict := engine.submit_discard(engine.banker_seat, cards)
				test.check(verdict.ok, "AI 扣底合法：" + verdict.error)
			Phase.TRICKS:
				var seat: int = engine.turn_seat
				var play := AiPolicy.choose_play(engine, seat)
				var verdict: Dictionary = engine.submit_play(seat, play)
				test.check(verdict.legal, "AI（座位 %d）出牌合法：%s" % [seat, verdict.text])


func test_auto_games_invariants(test) -> void:
	var koudi_games := 0
	for seed in range(1, 31):
		var engine := GameEngine.new()
		engine.start_session(seed)
		_run_auto_game(test, engine)
		var r: Dictionary = engine.last_game_result
		test.check(not r.is_empty(), "种子 %d：对局完整结束" % seed)
		if r.is_empty():
			continue
		test.check(r.level >= 1 and r.level <= 3, "种子 %d：级数 1~3" % seed)
		test.check(r.total_score == r.contract + r.captured_total, "种子 %d：总分 = 叫分 + 捉分" % seed)
		test.check(r.captured_total <= 200 + r.buried_points, "种子 %d：捉分不超过 200+底牌分" % seed)
		test.check(r.captured_points % 5 == 0, "种子 %d：捉分为 5 的倍数" % seed)
		if r.koudi_points > 0:
			koudi_games += 1
			test.check(r.koudi_points == r.buried_points or r.koudi_points == r.buried_points * 2,
				"种子 %d：抠底为底牌分 ×1/×2" % seed)
		var payment_sum := 0
		for p in r.payments:
			payment_sum += p
		test.eq(payment_sum, 0, "种子 %d：收支守恒" % seed)
		# 胜负与级数互检（规则 9）
		var expect := Scoring.compute_outcome(r.contract, r.captured_total)
		test.eq(r.banker_won, expect.banker_won, "种子 %d：胜负判定" % seed)
		test.eq(r.level, expect.level, "种子 %d：级数判定" % seed)
	# 说明：贪心 AI 庄家扣底常留主牌，末轮多由庄家赢下，抠底路径由
	# test_game.gd 的强制剧本确定性覆盖；此处仅在出现时校验算术
	print("  · 自动对局：抠底出现 %d/30 局" % koudi_games)


func test_multi_game_session(test) -> void:
	var engine := GameEngine.new()
	engine.start_session(42)
	_run_auto_game(test, engine)
	var first := engine.last_game_result
	for game in range(2, 4):
		test.check(engine.start_next_game(), "第 %d 局可开始" % game)
		test.eq(engine.round_index, game, "局数递增")
		var expected_dealer: int = first.banker_seat if first.banker_won else (first.banker_seat + 1) % 4
		test.eq(engine.dealer_seat, expected_dealer, "第 %d 局庄位轮换" % game)
		_run_auto_game(test, engine)
		first = engine.last_game_result
	# 累计收益守恒
	var total := 0
	for v in engine.cumulative:
		total += v
	test.eq(total, 0, "三局累计收支守恒")
