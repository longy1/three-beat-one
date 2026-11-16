extends RefCounted
## UI 层回归用例：headless 实例化场景 + 方法级驱动 + 节点状态断言。
## 纪律（AGENTS.md 第 7 章）：**每个用户报告的 UI bug，修复时必须在本套件补一个回归用例。**
##
## 已覆盖回归：
## - 扣底卡死：提交叫主后「确认扣底」按钮被 _clear_action_bar 误删
## - 牌堆悬停失效：SeatPanel.setup(seat) 被遗漏，座位号恒 -1
## - 叫主前手牌丢王/2：主牌组加入条件误写 trump != null
## - 捉分一致性：信息栏显示与引擎 captured_points 逐步一致


const Phase := GameEngine.Phase


## 实例化一个干净的牌桌场景并等两帧（布局就绪）
func _spawn_table():
	var tree: SceneTree = Engine.get_main_loop()
	var table = load("res://scene/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	# 加速 UI 定时器：测试不必等待真实的 AI 节奏与结算停留
	table._ai_timer.wait_time = 0.01
	table._trick_timer.wait_time = 0.01
	return table


func _release_table(table) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	table.queue_free()
	await tree.process_frame


## 注入标准发牌并指定抓牌庄家
func _deal(eng: GameEngine, dealer: int) -> void:
	var deck := Card.full_deck()
	var hands: Array = []
	for s in 4:
		hands.append(deck.slice(s * 19, (s + 1) * 19))
	eng.start_session_with_deal(dealer, hands, deck.slice(76, 84))


## AI 代打：走完当前阶段的全部引擎交互（不模拟鼠标）
func _drive_step(eng: GameEngine) -> void:
	match eng.phase:
		Phase.AUCTION:
			var s: int = eng.auction_turn
			eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid()))
		Phase.TRUMP:
			var ch: Dictionary = AiPolicy.choose_trump(eng.hands[eng.banker_seat])
			eng.submit_trump(eng.banker_seat, ch.suit, ch.rank)
		Phase.DISCARD:
			eng.submit_discard(eng.banker_seat, AiPolicy.choose_discard(eng.hands[eng.banker_seat], eng.trump))
		Phase.TRICKS:
			var s: int = eng.turn_seat
			eng.submit_play(s, AiPolicy.choose_play(eng, s))


## 回归：扣底卡死——人类提交叫主后「确认扣底」按钮必须存活
func test_discard_button_survives_trump_submit(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)  # 人类 130 坐庄
	test.eq(eng.phase, Phase.TRUMP, "进入叫主阶段")
	table._pending_trump_suit = Card.Suit.SPADE
	table._submit_human_trump(Card.RANK_9)  # 真实 UI 提交路径
	await tree_pause()
	var bar: HBoxContainer = table.get_node("BottomArea/ActionBar")
	var found := false
	for c in bar.get_children():
		if c is Button and c.visible and "确认扣底" in c.text:
			found = true
	test.check(found, "提交叫主后确认扣底按钮存活（回归：扣底卡死）")
	test.check(eng.phase == Phase.DISCARD, "引擎进入扣底阶段")
	await _release_table(table)


## 回归：叫主前手牌 19 张全部渲染（王与 2 曾被整组丢弃）
func test_hand_renders_all_cards_before_trump(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	table._render_hand()  # 拍卖阶段（未叫主）
	var count := 0
	for c in table.get_node("BottomArea/HandRow").get_children():
		# 跳过 queue_free 延迟删除的上一排卡牌
		if c is CardWidget and not c.is_queued_for_deletion():
			count += 1
	test.eq(count, 19, "叫主前手牌渲染 19 张（含王与 2）")
	await _release_table(table)


## 回归：牌堆弹层使用正确座位名（SeatPanel.setup 注入座位号）
func test_pile_popup_uses_seat_name(test) -> void:
	var table = await _spawn_table()
	_drive_step(table.engine)  # 让拍卖走一步，保证有真实历史数据结构
	table.get_node("SeatLeft").mouse_entered.emit()
	var popup: PanelContainer = table.get_node_or_null("PilePopup")
	test.check(popup != null and popup.visible, "悬停后牌堆弹层显示")
	if popup != null and popup.visible:
		var title: Label = popup.get_node("VBox/Title")
		test.check("丁" in title.text, "弹层标题含座位名（实际：%s）" % title.text)
	await _release_table(table)


## 回归：庄家是自己时，扣底完成后皇冠下方「牌堆」按钮可见，悬停显示底牌 8 张（2×4）
func test_bottom_pile_button_for_human_banker(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	eng.submit_discard(0, AiPolicy.choose_discard(eng.hands[0], eng.trump))
	await tree_pause()
	var btn: Button = table._bottom_pile_button
	test.check(btn.visible, "庄家是自己时牌堆按钮可见")
	# 非庄家/非出牌阶段不可见
	eng.start_session(99)  # 新局拍卖阶段
	await tree_pause()
	test.check(not btn.visible, "非出牌阶段按钮隐藏")
	await _release_table(table)


## 回归：扣底提交后直接进入可出牌状态（select_mode="play" + 出牌按钮），
## 不得被 submit 后的清理毁掉（人类坐庄喊主后无法出牌的卡死）
func test_discard_submit_leads_to_play_ui(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	table._pending_trump_suit = Card.Suit.SPADE
	table._submit_human_trump(Card.RANK_9)
	table.selected.clear()
	var hand: Array = eng.hands[0]
	for i in range(8):
		table.selected.append(hand[hand.size() - 1 - i])
	table._submit_human_discard()
	await tree_pause()
	test.eq(eng.phase, Phase.TRICKS, "进入出牌阶段")
	test.eq(table.select_mode, "play", "扣底提交后处于可出牌态（回归：卡死）")
	var bar: HBoxContainer = table.get_node("BottomArea/ActionBar")
	var found := false
	for c in bar.get_children():
		if c is Button and c.visible and not c.is_queued_for_deletion() and "出牌" in c.text:
			found = true
	test.check(found, "出牌按钮存在（回归：卡死）")
	await _release_table(table)


## 叫主后信息栏展示「正 R」牌面；未叫主时注明「未叫主」
func test_trump_display_in_sidebar(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	var state_label: Label = table.get_node("Sidebar/VBox/TrumpRow/TrumpStack/TrumpStateLabel")
	test.check("未叫主" in state_label.text, "未叫主态注明文字")
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	var slot: Control = table.get_node("Sidebar/VBox/TrumpRow/TrumpStack/TrumpSlot")
	var has_card := false
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.suit == Card.Suit.SPADE and c.card.rank == Card.RANK_9:
			has_card = true
	test.check(has_card, "叫主后信息栏展示 ♠9 牌面")
	await _release_table(table)


## 一致性不变量：自动对局中，信息栏捉分显示与引擎 captured_points 逐步一致
func test_captured_label_matches_engine(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	eng.start_session(7)
	var tree: SceneTree = Engine.get_main_loop()
	var steps := 0
	while eng.phase != Phase.SETTLED and steps < 500:
		steps += 1
		_drive_step(eng)
		await tree.create_timer(0.05).timeout  # 等 UI 信号处理器（含停留计时）完成
		var label: Label = table.get_node("Sidebar/VBox/CapturedLabel")
		test.check(str(eng.captured_points) in label.text,
			"step %d：捉分显示一致（引擎 %d，显示 %s）" % [steps, eng.captured_points, label.text])
	test.check(eng.phase == Phase.SETTLED, "整局完整结束（%d 步）" % steps)
	await _release_table(table)


## 等一个物理帧（供 UI 信号处理器中的计时器走完）
func tree_pause() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(0.05).timeout
