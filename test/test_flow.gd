extends UiTestBase
## 主流程用例：完整一局的端到端驱动。
## 人类动作用真实 UI 提交方法（与点击按钮同一信号链），AI 走引擎 + AiPolicy。
## 覆盖两条主线：
## - 自己叫主：人类竞叫坐庄 → 人类叫主 → 人类扣底 → 混合出牌 → 结算面板
## - 其它叫主：人类放弃 → AI 竞叫坐庄 → AI 叫主/扣底 → 人类闲家出牌 → 庄位轮换


## 人类以真实 UI 方法出牌（选牌 → 提交）
func _human_play(table) -> void:
	var eng: GameEngine = table.engine
	table.selected.clear()
	for c in AiPolicy.choose_play(eng, 0):
		table.selected.append(c)
	table._submit_human_play()


## 主流程一：自己叫主——人类封顶坐庄、叫主、扣底、出牌至结算
func test_flow_human_banker(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	var tree: SceneTree = Engine.get_main_loop()
	_deal(eng, 3)  # 丁抓牌庄 → 人类 0 号先表态
	test.eq(eng.auction.turn, 0, "人类先表态")
	# 拍卖：人类封顶 200（真实 UI 方法），AI 只能放弃
	table._submit_human_bid(200)
	for s in [1, 2, 3]:
		eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid()))  # 封顶 → 全部放弃
	test.eq(eng.banker_seat, 0, "人类 200 坐庄")
	test.eq(eng.contract, 200, "叫分 200")
	# 叫主（真实 UI 两步：花色 → R）
	table._pending_trump_suit = Card.Suit.HEART
	table._submit_human_trump(Card.RANK_5)
	test.eq(eng.phase, Phase.DISCARD, "进入扣底阶段")
	var bar: HBoxContainer = table.get_node("BottomArea/ActionBar")
	var has_confirm := false
	for c in bar.get_children():
		if c is Button and c.visible and "确认扣底" in c.text:
			has_confirm = true
	test.check(has_confirm, "确认扣底按钮出现")
	# 扣底（选 8 张，真实 UI 提交）
	table.selected.clear()
	var hand: Array = eng.hands[0]
	for i in range(8):
		table.selected.append(hand[hand.size() - 1 - i])
	table._submit_human_discard()
	test.eq(eng.phase, Phase.TRICKS, "进入出牌阶段")
	test.eq(eng.hands[0].size(), 19, "扣底后手牌 19 张")
	# 出牌：人类真实 UI，AI 引擎直驱
	var guard := 0
	while eng.phase == Phase.TRICKS and guard < 500:
		guard += 1
		await tree.create_timer(0.03).timeout
		if eng.turn_seat == 0:
			_human_play(table)
		else:
			eng.submit_play(eng.turn_seat, AiPolicy.choose_play(eng, eng.turn_seat))
	test.eq(eng.phase, Phase.SETTLED, "整局结束")
	var r: Dictionary = eng.last_game_result
	test.eq(r.banker_seat, 0, "出牌庄家为人类")
	await tree.create_timer(0.1).timeout  # 末轮停留结束后结算面板才显示
	test.check(table.get_node("ResultPanel").visible, "结算面板显示")
	await _release_table(table)


## 主流程二：其它叫主——人类放弃，AI 竞叫坐庄，人类以闲家打完整局并验证庄位轮换
func test_flow_ai_banker(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	var tree: SceneTree = Engine.get_main_loop()
	_deal(eng, 1)  # 乙抓牌庄 → 丙先表态，AI 竞叫
	var guard := 0
	while eng.phase == Phase.AUCTION and guard < 60:
		guard += 1
		if eng.auction.turn == 0:
			table._submit_human_bid(GameEngine.BID_PASS)  # 人类放弃（真实 UI 方法）
		else:
			var s: int = eng.auction.turn
			eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid()))
	test.eq(eng.phase, Phase.TRUMP, "拍卖结束进入叫主")
	test.check(eng.banker_seat != 0, "AI 坐庄（座位 %d）" % eng.banker_seat)
	var ai_trump: Dictionary = AiPolicy.choose_trump(eng.hands[eng.banker_seat])
	eng.submit_trump(eng.banker_seat, ai_trump.suit, ai_trump.rank)
	eng.submit_discard(eng.banker_seat, AiPolicy.choose_discard(eng.hands[eng.banker_seat], eng.trump))
	test.eq(eng.phase, Phase.TRICKS, "进入出牌阶段")
	# 出牌：人类真实 UI，AI 引擎直驱
	guard = 0
	while eng.phase == Phase.TRICKS and guard < 500:
		guard += 1
		await tree.create_timer(0.03).timeout
		if eng.turn_seat == 0:
			_human_play(table)
		else:
			eng.submit_play(eng.turn_seat, AiPolicy.choose_play(eng, eng.turn_seat))
	test.eq(eng.phase, Phase.SETTLED, "整局结束")
	# 庄位轮换（规则 4）：庄胜 → 仍为其抓牌庄；庄负 → 其下一位
	var r: Dictionary = eng.last_game_result
	var expected: int = r.banker_seat if r.banker_won else (r.banker_seat + 1) % 4
	test.check(eng.start_next_game(), "下一局可开始")
	test.eq(eng.dealer_seat, expected, "庄位轮换正确")
	test.eq(eng.phase, Phase.AUCTION, "新局回到拍卖")
	await _release_table(table)
