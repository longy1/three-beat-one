extends TestBase
## AiPolicy 用例：单项策略 sanity + 30 局种子化自动对局不变量。
## 自动对局中引擎逐一校验 AI 输出，任何非法决策都会使测试失败。


## ============================= 单项策略 =============================

func test_choose_bid_levels(test) -> void:
	AiPolicy.rng.seed = 2026
	# 极强牌（四王 + 多 2 + A 对 + K 对，strength≈86 → 校准桶 [65,∞)，愿叫上限档 150）
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
	# 2026-11-17 平滑化 + 重校准（下分门槛细化策略下 ×2 轮）：EV 只定愿叫上限档——
	# 强牌 130~150 弱正 EV（+0.17/+0.15/+0.33，150 档最优），165+ 明确负；叫分一律 最高+5 递进
	test.eq(AiPolicy.choose_bid(strong, 130), 135, "极强牌从 130 一手只叫 +5（不跳档）")
	# 有人已叫 135 且我极强 → 150 档正 EV（+0.33）→ 确定性 +5 参与（仍不越过愿叫上限）
	AiPolicy.rng.seed = 7
	var near_cap: int = AiPolicy.choose_bid(strong, 135)
	test.check(near_cap == GameEngine.BID_PASS or near_cap == 140,
		"上限档附近：放弃或 +5 平滑（实际 %s）" % str(near_cap))
	test.eq(AiPolicy.choose_bid(strong, 165), GameEngine.BID_PASS, "越过上限档全负 EV → 放弃")
	test.eq(AiPolicy.choose_bid(strong, 180), GameEngine.BID_PASS, "180 起全负 EV → 放弃")
	# 中等牌（strength≈65）：校准负 EV 区 → 要么放弃要么 +5 试探
	var medium_bid: int = AiPolicy.choose_bid(medium, 130)
	test.check(medium_bid == GameEngine.BID_PASS or medium_bid == 135,
		"中等牌噪声区：要么放弃要么 +5（实际 %s）" % str(medium_bid))


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


## 扣底保留一门（2026-11-17 平衡细化）：顶牌最强的副花色整门尽量保留，
## 其余副牌分牌优先入底；保留门只在其余副牌凑不满时才从最弱处扣
func test_choose_discard_keeps_strongest_side_suit(test) -> void:
	var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand: Array = [
		C(Card.Suit.DIAMOND, Card.RANK_A, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 0),
		C(Card.Suit.DIAMOND, Card.RANK_Q, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_5, 0),
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_7, 0),
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_J, 0),
		C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)]
	var discard := AiPolicy.choose_discard(hand, trump)
	test.eq(discard.size(), 8, "扣 8 张")
	var buried := {}
	for c in discard:
		buried["%d_%d" % [c.suit, c.rank]] = true
	# ♦ 顶牌 A 最强 → 整门尽量保留：♦A/♦K 留在手（K 分牌随门保留），只从最弱处扣 ♦7♦8♦Q
	var expected := {}
	var spec := [
		[Card.Suit.CLUB, Card.RANK_10], [Card.Suit.CLUB, Card.RANK_5], [Card.Suit.CLUB, Card.RANK_J],
		[Card.Suit.CLUB, Card.RANK_8], [Card.Suit.CLUB, Card.RANK_7],
		[Card.Suit.DIAMOND, Card.RANK_Q], [Card.Suit.DIAMOND, Card.RANK_8], [Card.Suit.DIAMOND, Card.RANK_7]]
	for k in spec:
		expected["%d_%d" % [k[0], k[1]]] = true
	test.eq(buried, expected, "♣ 全部入底（分牌优先）+ ♦ 最弱三张，♦A♦K 留在手")
	for c in discard:
		test.check(not trump.is_trump(c), "不扣主牌：" + c.label())
	# 无 ≥2 张的副花色（不成「一种」）→ 退回旧口径：分牌优先入底
	var hand2: Array = [
		C(Card.Suit.DIAMOND, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_5, 0),
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0),
		C(Card.Suit.SPADE, Card.RANK_10, 0), C(Card.Suit.SPADE, Card.RANK_J, 0),
		C(Card.Suit.SPADE, Card.RANK_Q, 0), C(Card.Suit.SPADE, Card.RANK_K, 0),
		C(Card.Suit.HEART, Card.RANK_2, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0)]
	var discard2 := AiPolicy.choose_discard(hand2, trump)
	test.eq(discard2.size(), 8, "扣 8 张")
	test.check(discard2.has(hand2[1]), "分牌 ♣5 优先入底")
	test.check(discard2.has(hand2[0]), "无保留门时副牌 ♦A 顺手入底")


## 垫牌守门协调（2026-11-17）：队友（含人类 0 号位）累计垫 ≥2 张的副花色 =「在清该门」，
## 本家自由垫牌避开同门（分值打平时生效）——每门副牌至少留一家闲家，末局能压庄家剩牌
func test_defender_discard_avoids_teammate_shed_suit(test) -> void:
	var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0)]
	# 庄家（座位 2）领小王单张；我（座位 1 闲家）无主 → 自由垫 1 张
	var plays := [{seat = 2, cards = [C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)], role = FollowRule.Role.LEAD}]
	# 历史：♥ 对子轮中队友丁（座位 3）无 ♥ 垫了 ♣J♣8 → 推断其在清 ♣（♣9 是常主 R，不能作 ♣ 证据）
	var history := [{plays = [
		{seat = 2, cards = [C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1)], role = FollowRule.Role.LEAD},
		{seat = 0, cards = [C(Card.Suit.HEART, Card.RANK_Q, 0), C(Card.Suit.HEART, Card.RANK_Q, 1)], role = FollowRule.Role.FOLLOW_TYPE},
		{seat = 1, cards = [C(Card.Suit.HEART, Card.RANK_J, 0), C(Card.Suit.HEART, Card.RANK_J, 1)], role = FollowRule.Role.FOLLOW_TYPE},
		{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)], role = FollowRule.Role.DISCARD}], winner = 2}]
	var shed := AiPlay._teammate_shed_suits(history, trump, 1, 2)
	test.check(shed.has(Card.Suit.CLUB), "推断队友在清 ♣")
	test.check(not shed.has(Card.Suit.HEART), "跟牌花色不算垫牌清门")
	var play := AiPlay.choose_play(hand, trump, plays, 1, 2, history)
	test.eq(play, [hand[1]], "队友清 ♣ → 我垫 ♦8 不垫 ♣7（留 ♣ 守门）")
	# 无此情报 → 仍垫最低牌力 ♣7（旧行为）
	var play2 := AiPlay.choose_play(hand, trump, plays, 1, 2)
	test.eq(play2, [hand[0]], "无情报时仍垫最低 ♣7")
	# feed 喂分不受协调影响：队友领先时，avoid 同门的分牌照喂
	var hand3 := [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_5, 0)]
	var plays3 := [{seat = 3, cards = [C(Card.Suit.HEART, Card.RANK_A, 0)], role = FollowRule.Role.LEAD}]
	var history3 := [{plays = [
		{seat = 2, cards = [C(Card.Suit.DIAMOND, Card.RANK_A, 0)], role = FollowRule.Role.LEAD},
		{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)], role = FollowRule.Role.DISCARD},
		{seat = 0, cards = [C(Card.Suit.DIAMOND, Card.RANK_K, 0)], role = FollowRule.Role.DISCARD},
		{seat = 1, cards = [C(Card.Suit.DIAMOND, Card.RANK_Q, 0)], role = FollowRule.Role.DISCARD}], winner = 2}]
	var play3 := AiPlay.choose_play(hand3, trump, plays3, 1, 2, history3)
	test.eq(play3, [hand3[1]], "队友领先喂分：分牌优先压过 avoid（♣5 照喂）")


## 垫牌牌力分级（2026-11-17）：花色顶牌三档——≤10 尽早清理、J~Q 中性、K/A 级更多保留；
## 分级优先于守门避让与逐张牌力（弱门无守门价值），分牌保护仍最优先
func test_defender_discard_clears_weak_suits_first(test) -> void:
	var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var probe := [C(Card.Suit.DIAMOND, Card.RANK_A, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0),
		C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_7, 0),
		C(Card.Suit.HEART, Card.RANK_J, 0)]
	var classes := AiPlay._suit_classes(probe, trump)
	test.eq(classes[Card.Suit.DIAMOND], 2, "♦ 顶 A → K/A 级强门（档 2）")
	test.eq(classes[Card.Suit.HEART], 1, "♥ 顶 J → 中性门（档 1）")
	test.eq(classes[Card.Suit.CLUB], 0, "♣ 顶 ≤10 → 弱门（档 0）")
	# 弱门 ♣ 先清，中性 ♥ 次之，强门 ♦ 压轴：♦A 最后才动
	# （填充小牌用无分的 7/8/J；♣9 是常主 R 不能作 ♣ 门成员）
	var hand := [C(Card.Suit.DIAMOND, Card.RANK_A, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0),
		C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_7, 0),
		C(Card.Suit.HEART, Card.RANK_J, 0), C(Card.Suit.HEART, Card.RANK_8, 0)]
	test.eq(AiPlay.build_discard(hand, trump, 2), [hand[3], hand[2]], "弱门 ♣ 先清（♣7♣8）")
	test.eq(AiPlay.build_discard(hand, trump, 4), [hand[3], hand[2], hand[5], hand[4]], "中性 ♥ 次之（♥8 先于 ♥J）")
	test.eq(AiPlay.build_discard(hand, trump, 5), [hand[3], hand[2], hand[5], hand[4], hand[1]], "强门最后从小牌 ♦8 动起（♦A 压轴）")


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


## 甩打轮 AI 跟牌（7.3）：领出者必胜 → 纯垫牌，张数与甩打一致；队友领出喂分
func test_choose_play_dump_follow(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_7, 0),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0)]
	# 领出者 3 = 闲家队友；自己 1 = 闲家；庄家 = 2
	var plays := [{seat = 3, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0)], role = FollowRule.Role.LEAD}]
	var play := AiPlay.choose_play(hand, trump, plays, 1, 2)
	test.eq(play.size(), 2, "垫牌张数 = 甩打张数")
	for c in play:
		test.check(hand.has(c), "垫牌来自手牌：%s" % c.label())
	test.check(play.has(hand[0]), "队友甩打时优先垫分喂队友（♥5）")


## 甩打轮 AI 跟牌：领出者是庄家（敌对）→ 不喂分，垫最小分
func test_choose_play_dump_follow_no_feed(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_7, 0),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0)]
	var plays := [{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0)], role = FollowRule.Role.LEAD}]
	var play := AiPlay.choose_play(hand, trump, plays, 1, 2)  # 自己 1 = 闲家，领出者 2 = 庄家
	test.eq(play.size(), 2, "垫牌张数 = 甩打张数")
	test.check(not play.has(hand[0]), "庄家甩打时不喂分（♥5 保留）")


## 常主对子领出（非主花色）+ 无任何主牌 → AI 自由垫最低散张，无对子/花色强制（7.2）
## 庄家领顶张大王对（未现身牌无一能压过 → 提前下分关闭）；闲家手牌全副牌且垫出的
## 两张不成对——引擎校验放行
func test_choose_play_permanent_pair_lead_no_trump(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_7, 0),
		C(Card.Suit.DIAMOND, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 0)]
	var lead_cards := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1)]
	var lead := Combo.detect(lead_cards, trump)
	test.eq(lead.suit, TrumpInfo.CLASS_TRUMP, "大王对为常主对（主牌类）")
	var plays := [{seat = 2, cards = lead_cards, role = FollowRule.Role.LEAD}]
	var play := AiPlay.choose_play(hand, trump, plays, 1, 2, [])
	test.eq(play, [hand[1], hand[2]], "垫最低两张散张 ♥7♦8（保留分牌 ♥5；垫牌不成对亦合法）")
	var v := FollowRule.is_legal(hand, play, lead, trump)
	test.check(v.legal, "AI 垫牌通过引擎校验")
	test.eq(v.role, FollowRule.Role.DISCARD, "角色 = 自由垫牌")


## ============================= 角色化领出策略（2026-11-17） =============================

## 闲家不主动领主牌对：有副牌对 → 领副牌；庄家公示无主 / 无副牌 → 例外许可
func test_defender_avoids_trump_pair_lead(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 1, 2)
	test.eq(lead, [hand[2], hand[3]], "闲家有副牌对 → 领 ♥AA，不主动领主牌对")
	var lead2 := AiPlay.choose_play(hand, t, [], 1, 2, [], [false, false, true, false])
	test.eq(lead2, [hand[0], hand[1]], "庄家公示无主（7.3）→ 领主牌对必赢")
	var trump_only := [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.SPADE, Card.RANK_J, 0)]
	var lead3 := AiPlay.choose_play(trump_only, t, [], 1, 2)
	test.eq(lead3, [trump_only[0], trump_only[1]], "实在没有副牌 → 领主牌对")


## 闲家副牌领出优先队友已缺失的花色（从历史推断）
func test_defender_prefers_teammate_void_suit(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_A, 1),
		C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1),
		C(Card.Suit.DIAMOND, Card.RANK_5, 0)]
	var no_history := AiPlay.choose_play(hand, t, [], 1, 2)
	test.eq(no_history, [hand[0], hand[1]], "无情报 → 领更大的 ♥AA")
	var history := [{plays = [
		{seat = 2, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_7, 1)], role = FollowRule.Role.LEAD},
		{seat = 0, cards = [C(Card.Suit.CLUB, Card.RANK_J, 0)], role = FollowRule.Role.FOLLOW_TYPE},
		{seat = 3, cards = [C(Card.Suit.DIAMOND, Card.RANK_K, 0), C(Card.Suit.DIAMOND, Card.RANK_9, 0)], role = FollowRule.Role.DISCARD},
		{seat = 1, cards = [C(Card.Suit.CLUB, Card.RANK_5, 0)], role = FollowRule.Role.FOLLOW_TYPE}], winner = 2}]
	var lead := AiPlay.choose_play(hand, t, [], 1, 2, history)
	test.eq(lead, [hand[2], hand[3]], "队友（丁）已无 ♣ → 优先领 ♣KK（可放心喂分）")


## 庄家握顶张（大王对）另有常主对 → 先出常主对勾引，藏强牌
func test_banker_baits_from_permanent_pair(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 2, 2)
	test.eq(lead, [hand[2], hand[3]], "庄家握大王对 + 正R对 → 先出 ♠RR 对勾引（藏大王对）")
	var top_only := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
		C(Card.Suit.CLUB, Card.RANK_5, 0)]
	var lead2 := AiPlay.choose_play(top_only, t, [], 2, 2)
	test.eq(lead2, [top_only[0], top_only[1], top_only[2], top_only[3]], "无常主对可出 → 领四王（最大拖）")


## 庄家弱主逼主：先出最小主牌单张消耗闲家主牌；逼空后改闯最大副牌
func test_banker_bleeds_low_trump_then_charges(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_J, 0),
		C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 2, 2)
	test.eq(lead, [hand[0]], "弱主（无王 2 张）+ 有副对 → 先出最小主牌单张逼主")
	# 2026-11-17：三家全公示无主 → 触发 7.3 甩牌（甩出全部主牌压缩闲家）
	var dump := AiPlay.choose_play(hand, t, [], 2, 2, [], [true, true, false, true])
	test.eq(dump, [hand[0], hand[1]], "三家公示无主 → 甩出全部主牌（7.3）")
	# 仅逼空 2 家（尚有一家可能有主）→ 不甩牌，改闯最大副牌
	var drained := AiPlay.choose_play(hand, t, [], 2, 2, [], [true, true, false, false])
	test.eq(drained, [hand[2], hand[3]], "≥2 闲家公示无主但未全空 → 改闯最大副牌 ♥KK")


## 庄家开局提前闯中坚副对（防主牌不够大时被闲家单张拆散）
func test_banker_charges_side_pair_early(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand: Array = [
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_9, 0),
		C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.SPADE, Card.RANK_A, 0),
		C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0),
		C(Card.Suit.CLUB, Card.RANK_9, 0), C(Card.Suit.CLUB, Card.RANK_Q, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 2, 2)
	test.eq(lead, [hand[6], hand[7]], "开局（12 张）有 Q 以上副对 → 提前闯 ♥KK")


## 闲家提前下分：庄家当前领先但队友或能压（场上还有未现身的王）→ 垫分；
## 大牌已全部现身（确定压不住）→ 保留分牌
func test_defender_feeds_points_when_teammate_may_beat(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 0)]
	# 庄家领 ♠5 低单张：未现身牌里仍有很多能压过它（含未见的大王）→ 提前垫 ♦K 下分
	var plays := [{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)], role = FollowRule.Role.LEAD}]
	var feed := AiPlay.choose_play(hand, t, plays, 1, 2, [])
	test.eq(feed, [hand[1]], "庄家领先 + 未见牌仍可能压过 → 提前垫 ♦K 下分")
	# 用户示例（2026-11-17）：双大王已现身、庄家出小王 → 未现身牌无一能压过 → 不下分
	var jokers_out := [{plays = [
		{seat = 0, cards = [
			C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1)],
			role = FollowRule.Role.DISCARD}], winner = 0}]
	var plays_sj := [{seat = 2, cards = [C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)], role = FollowRule.Role.LEAD}]
	var hold := AiPlay.choose_play(hand, t, plays_sj, 1, 2, jokers_out)
	test.eq(hold, [hand[0]], "双大王已现身、庄家出小王 → 无人能压 → 垫无分 ♥7 保留分牌")


## 下分门槛的对子/杀主维度（2026-11-17）：未现身牌能压过庄家当前对子才下分——
## 副R对领出时未现身的正R对可压（下分）；正R对已全部现身则无人能压（保留）
func test_defender_feed_gate_pair_and_kill(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 0)]
	# 庄家领 ♥99（副R对 500）：♠99（正R对 600）两张都未现身 → 队友可能压过 → 下分
	var plays_pair := [{seat = 2, cards = [C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_9, 1)], role = FollowRule.Role.LEAD}]
	var feed := AiPlay.choose_play(hand, t, plays_pair, 1, 2, [])
	test.eq(feed, [hand[1], hand[0]], "正R对未现身 → 可能压过副R对 → 下分 ♦K（feed 分牌优先）")
	# 顶张全现身（双大王对/双小王对/正R对均已出）→ 副R对已是现存最高 → 无人能压 → 保留分牌
	var all_top_out := [
		{plays = [
			{seat = 2, cards = [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1)], role = FollowRule.Role.LEAD},
			{seat = 3, cards = [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.DIAMOND, Card.RANK_A, 0)], role = FollowRule.Role.DISCARD}], winner = 2},
		{plays = [
			{seat = 2, cards = [C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1)], role = FollowRule.Role.LEAD},
			{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)], role = FollowRule.Role.DISCARD},
			{seat = 0, cards = [C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 0)], role = FollowRule.Role.DISCARD},
			{seat = 1, cards = [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)], role = FollowRule.Role.FOLLOW_TYPE}], winner = 2},
	]
	var hold := AiPlay.choose_play(hand, t, plays_pair, 1, 2, all_top_out)
	test.eq(hold, [hand[0], hand[1]], "正R对与王对均已现身 → 无人能压 → 保留分牌（♥7 先垫）")
	# 杀主维度：庄家领 ♣KK（副牌对）→ 未现身主牌对即可杀 → 下分
	var plays_club := [{seat = 2, cards = [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)], role = FollowRule.Role.LEAD}]
	var feed_kill := AiPlay.choose_play(hand, t, plays_club, 1, 2, [])
	test.check(feed_kill.has(hand[1]), "副牌领出 + 未现身主牌对可杀 → 下分 ♦K")


## 甩牌含主牌对子时拆为单张一并甩出（7.3：任意张主牌单牌）
func test_banker_dump_includes_trump_pair(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1),
		C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_K, 1)]
	var dump := AiPlay.choose_play(hand, t, [], 2, 2, [], [true, true, false, true])
	test.eq(dump, [hand[0], hand[1], hand[2]], "甩牌 = 全部主牌（主牌对拆作两张单张）")
	test.eq(dump.size(), hand.size() - 2, "副牌 ♥KK 留待甩后稳赢轮次")


## 闲家单张试探 ①：确定庄家还剩 ♣ → 领该门最大牌 ♣K（出分试探）
func test_defender_probes_banker_held_suit(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_5, 0),
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]
	var history := [{plays = [
		{seat = 0, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_7, 1)], role = FollowRule.Role.LEAD},
		{seat = 1, cards = [C(Card.Suit.HEART, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 0)], role = FollowRule.Role.DISCARD},
		{seat = 2, cards = [C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_Q, 0)], role = FollowRule.Role.FOLLOW_TYPE},
		{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_9, 0)], role = FollowRule.Role.FOLLOW_TYPE}], winner = 2}]
	var lead := AiPlay.choose_play(hand, t, [], 1, 2, history)
	test.eq(lead, [hand[0]], "庄家跟过 ♣（确定还剩）→ 领 ♣K 出分试探")


## 闲家单张试探 ②：不确定庄家剩什么 → 领 A 级大牌试探
func test_defender_probes_uncertain_high_card(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.CLUB, Card.RANK_7, 0),
		C(Card.Suit.DIAMOND, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 1, 2)
	test.eq(lead, [hand[0]], "无庄家花色情报 → 领 ♠ 之外最大的 ♥A 试探（旧版会领主牌 ♠5）")


## 闲家单张试探 ③：无 A/Q 级牌可试探 → 回退默认（最强单张）
func test_defender_no_probe_with_low_cards(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_8, 0)]
	var lead := AiPlay.choose_play(hand, t, [], 1, 2)
	test.eq(lead, [hand[1]], "无 A/Q 试探资本 → 回退默认最强单张 ♣8")


## 甩牌上限（2026-11-17 用户定夺）：一次最多甩 4 张，主牌更多时分多轮甩
func test_banker_dump_capped_at_four(test) -> void:
	var t := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_10, 0),
		C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.SPADE, Card.RANK_Q, 0),
		C(Card.Suit.HEART, Card.RANK_7, 0)]
	var dump := AiPlay.choose_play(hand, t, [], 2, 2, [], [true, true, false, true])
	test.eq(dump.size(), 4, "6 张主牌在手 → 一次只甩前 4 张")
	test.eq(dump, [hand[0], hand[1], hand[2], hand[3]], "甩出的是前 4 张主牌（余下轮次继续）")
