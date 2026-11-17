extends UiTestBase
## UI 层回归用例：headless 实例化场景 + 方法级驱动 + 节点状态断言。
## 纪律（AGENTS.md 第 7 章）：**每个用户报告的 UI bug，修复时必须在本套件补一个回归用例。**
##
## 已覆盖回归：
## - 扣底卡死：提交叫主后「确认扣底」按钮被 _clear_action_bar 误删
## - 牌堆悬停失效：SeatPanel.setup(seat) 被遗漏，座位号恒 -1
## - 叫主前手牌丢王/2：主牌组加入条件误写 trump != null
## - 捉分一致性：信息栏显示与引擎 captured_points 逐步一致
## - （2026-11-17 历史面板重做）座位悬停历史弹层路径整体移除：悬停座位不再弹出任何面板
## - （2026-11-17 历史面板重做）出牌历史面板：十字摆位一轮四家出牌、翻轮次四按钮
##   边界禁用、✕/点击窗口外关闭、打开期间轮次增长就地收敛


## AI 代打：走完当前阶段的全部引擎交互（不模拟鼠标）
func _drive_step(eng: GameEngine) -> void:
	match eng.phase:
		Phase.AUCTION:
			var s: int = eng.auction.turn
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


## 回归（2026-11-17 历史面板重做）：座位悬停不再弹出历史弹层（原悬停路径已移除）
func test_seat_hover_opens_no_popup(test) -> void:
	var table = await _spawn_table()
	_drive_step(table.engine)  # 走一步拍卖，保证有真实座位数据
	table.seat_panels[3].mouse_entered.emit()
	await tree_pause()
	test.check(not table._trick_history.is_open(), "悬停电脑座位不再打开出牌历史面板")
	test.check(not table._piles.bottom_popup.visible, "悬停座位也不弹底牌弹层")
	table.seat_panels[3].mouse_exited.emit()
	await _release_table(table)


## 牌堆弹层延迟隐藏：移出「牌堆」按钮后 0.1s 内仍可见（粘滞窗口），到期自动关闭
func test_pile_popup_delayed_hide(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	eng.submit_discard(0, AiPolicy.choose_discard(eng.hands[0], eng.trump))
	var btn: Button = table._piles.bottom_button
	btn.mouse_entered.emit()
	var popup: PanelContainer = table._piles.bottom_popup
	test.check(popup.visible, "悬停牌堆按钮后弹层显示")
	btn.mouse_exited.emit()  # 移出入口 → 启动延迟隐藏
	await tree_pause()  # ~0.05s < 0.1s：弹层应仍在
	test.check(popup.visible, "移出后 0.1s 内弹层保持显示（延迟隐藏）")
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(0.5).timeout
	test.check(not popup.visible, "到期后弹层自动关闭")
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
	var btn: Button = table._piles.bottom_button
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
	table.hand_area.selected.clear()
	var hand: Array = eng.hands[0]
	for i in range(8):
		table.hand_area.selected.append(hand[hand.size() - 1 - i])
	table._submit_human_discard()
	await tree_pause()
	test.eq(eng.phase, Phase.TRICKS, "进入出牌阶段")
	test.eq(table.hand_area.select_mode, "play", "扣底提交后处于可出牌态（回归：卡死）")
	var bar: HBoxContainer = table.get_node("BottomArea/ActionBar")
	var found := false
	for c in bar.get_children():
		if c is Button and c.visible and not c.is_queued_for_deletion() and "出牌" in c.text:
			found = true
	test.check(found, "出牌按钮存在（回归：卡死）")
	await _release_table(table)


## 回归：叫主点数选择以居中多排面板完整展示 12 个按钮（单行曾溢出屏幕丢 5/2）
func test_trump_rank_picker_shows_all_ranks(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	table._pick_trump_suit(Card.Suit.SPADE)  # 选花色（真实路径）→ 弹出点数面板
	var panel: PanelContainer = table.get_node_or_null("TrumpRankPicker")
	test.check(panel != null and panel.visible, "点数选择面板显示")
	if panel != null and panel.visible:
		var grid: GridContainer = panel.get_node("VBox/Grid")
		var btn_count := 0
		for c in grid.get_children():
			if c is Button and not c.is_queued_for_deletion():
				btn_count += 1
		test.eq(btn_count, 10, "10 个点数按钮完整展示（5~2，R 不可为王）")
	table._submit_human_trump(Card.RANK_9)
	await tree_pause()
	test.eq(eng.phase, Phase.DISCARD, "选择后进入扣底")
	test.check(table._trump_picker == null, "选择后面板关闭")
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
	# 主牌经揭主动画落位（0.01s 加速）后才进信息栏；0.3s 等待留足套件负载余量
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(0.3).timeout
	var slot: Control = table.get_node("Sidebar/VBox/TrumpRow/TrumpStack/TrumpSlot")
	var has_card := false
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.suit == Card.Suit.SPADE and c.card.rank == Card.RANK_9:
			has_card = true
	test.check(has_card, "叫主后信息栏展示 ♠9 牌面")
	await _release_table(table)


## 回归：一轮结算后牌面停留（✓ 赢家标记 + 出牌保留在桌上），停留到期主动清空
## （曾因控制器拆分丢失 _last_trick_winner 赋值与停留计时器启动）
func test_trick_settle_display_pauses(test) -> void:
	var table = await _spawn_table()
	table._trick_timer.wait_time = 1.5  # 本用例用真实停留时长
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	eng.submit_discard(0, AiPolicy.choose_discard(eng.hands[0], eng.trump))
	for i in 4:
		var s: int = eng.turn_seat
		eng.submit_play(s, AiPolicy.choose_play(eng, s))
	# 停留窗口内：四家出牌保留在桌上；赢家姓名版显示 ✓
	var shown_cards := 0
	for c in table.get_node("TrickArea").get_children():
		if c is HBoxContainer and not c.is_queued_for_deletion():
			shown_cards += 1
	test.eq(shown_cards, 4, "停留期内四家出牌保留在桌上")
	var winner: int = eng.leader_seat
	if winner != 0:
		var status: String = table.seat_panels[winner].get_node("VBox/StatusLabel").text
		test.check("✓" in status, "赢家姓名版显示 ✓ 标记（实际 %s）" % status)
	# 停留到期：出牌桌主动清空
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(2.0).timeout
	var remaining := 0
	for c in table.get_node("TrickArea").get_children():
		if c is HBoxContainer and not c.is_queued_for_deletion():
			remaining += 1
	test.eq(remaining, 0, "停留到期后出牌主动清空")
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


## 人类庄家翻底后：底牌 8 张入手即呈选中态（2026-11-17 需求，便于观察与直接扣回）
func test_kitty_preselected_after_flip(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)  # 人类 130 坐庄
	table._pending_trump_suit = Card.Suit.SPADE
	table._submit_human_trump(Card.RANK_9)  # 真实 UI 提交路径 → discard_required 处理器
	await tree_pause()
	test.eq(eng.phase, Phase.DISCARD, "进入扣底阶段")
	test.eq(table.hand_area.selected.size(), 8, "底牌 8 张自动选中")
	var kitty_keys := {}
	for c in eng.kitty:
		kitty_keys[c.key()] = true
	var all_kitty := true
	for c in table.hand_area.selected:
		if not kitty_keys.has(c.key()):
			all_kitty = false
	test.check(all_kitty, "选中集合恰为底牌 8 张")
	# 扣底按钮计数联动到 8/8
	var counter_text := ""
	for b in table.get_node("BottomArea/ActionBar").get_children():
		if b is Button and not b.is_queued_for_deletion():
			counter_text = b.text
	test.check("8/8" in counter_text, "扣底按钮计数 8/8（实际：%s）" % counter_text)
	await _release_table(table)


## 【无主】公示印章接线：引擎公示状态驱动三家电版与人类位印章显隐
func test_void_stamp_wiring(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	eng.trump_void_seats = [true, true, false, true]
	table._refresh()
	test.check(table.seat_panels[1].get_node("VoidStamp").visible, "乙公示无主 → 印章显示")
	test.check(not table.seat_panels[2].get_node("VoidStamp").visible, "丙未公示 → 印章隐藏")
	test.check(table.seat_panels[3].get_node("VoidStamp").visible, "丁公示无主 → 印章显示")
	test.check(table.human_void_stamp.visible, "人类位公示无主 → 印章显示")
	test.eq(table.human_void_stamp.position, Vector2(958, 488), "人类位印章固定槽位 = 手牌右上方（2026-11-17 需求）")
	eng.trump_void_seats = [false, false, false, false]
	table._refresh()
	test.check(not table.human_void_stamp.visible, "复位后隐藏")
	test.check(not table.seat_panels[1].get_node("VoidStamp").visible, "复位后隐藏（乙）")
	await _release_table(table)


## 出牌历史面板（2026-11-17 重做）：打开即定位最后一轮，十字摆位四家出牌、
## 赢家 ✓ 金标、页码文案与导航边界禁用态
func test_trick_history_panel_layout(test) -> void:
	var table = await _spawn_table()
	# 注入两轮真实结构的历史（第 2 轮 = 最后一轮：四家各 2 张，赢家丁）
	var hist: Array = [
		{plays = [
			{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)], role = FollowRule.Role.LEAD},
			{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0)], role = FollowRule.Role.DISCARD},
		], winner = 2},
		{plays = [
			{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_9, 0)], role = FollowRule.Role.LEAD},
			{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0)], role = FollowRule.Role.FOLLOW_TYPE},
			{seat = 0, cards = [C(Card.Suit.HEART, Card.RANK_8, 0), C(Card.Suit.HEART, Card.RANK_K, 0)], role = FollowRule.Role.DISCARD},
			{seat = 1, cards = [C(Card.Suit.DIAMOND, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_K, 0)], role = FollowRule.Role.DISCARD},
		], winner = 3},
	]
	var panel = table._trick_history
	panel.open(hist, table.SEAT_NAMES)
	test.check(panel.is_open(), "打开后历史面板显示")
	test.check(panel.backdrop.visible, "全屏遮罩同步显示（点击窗口外关闭用）")
	var tree: SceneTree = Engine.get_main_loop()
	await tree.process_frame
	await tree.process_frame  # 布局落地两帧
	# 十字区：最后一轮四家各一组（姓名 + 卡牌行），共 8 张小牌
	var groups := 0
	var widgets := 0
	var winner_marked := false
	for g in panel.cross_area.get_children():
		if g.is_queued_for_deletion():
			continue
		groups += 1
		var name_label: Label = g.get_child(0)
		if name_label.text.begins_with("✓"):
			winner_marked = true
			test.check(name_label.modulate.r > 0.9 and name_label.modulate.g > 0.8, "赢家名字金色高亮")
		var row: HBoxContainer = g.get_child(1)  # 组结构：姓名 Label + 卡牌行 HBox
		for c in row.get_children():
			if c is CardWidget:
				widgets += 1
	test.eq(groups, 4, "十字区四家各一组")
	test.eq(widgets, 8, "第 2 轮共 8 张小牌（各家 2 张）")
	test.check(winner_marked, "赢家姓名带 ✓ 标记")
	test.eq(panel.page_label.text, "第 2 / 2 轮", "打开定位最后一轮")
	# 边界导航态：在最后一页 → > >> 禁用；< 可用
	test.check(panel._btn_next.disabled and panel._btn_last.disabled, "最后一页：> >> 禁用")
	test.check(not panel._btn_prev.disabled, "最后一页：< 仍可用")
	await _release_table(table)


## 状态驱动刷新（2026-11-17 重做）：面板打开期间新轮次结算 → refresh 就地收敛页码并
## 保持显示（trick_settled → _refresh → refresh）；关闭后刷新必须无效
func test_trick_history_panel_refresh(test) -> void:
	var table = await _spawn_table()
	var hist1: Array = [
		{plays = [{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0)], role = FollowRule.Role.LEAD}], winner = 3},
	]
	table._trick_history.open(hist1, table.SEAT_NAMES)
	test.eq(table._trick_history.page_label.text, "第 1 / 1 轮", "初始最后一轮")
	# 打开期间又结算一轮 → 保持显示，页码仍停在第 1 轮（clamp 收敛到合法范围）
	var hist2: Array = hist1.duplicate(true)
	hist2.append({plays = [
		{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_9, 0)], role = FollowRule.Role.LEAD},
		{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0)], role = FollowRule.Role.FOLLOW_TYPE},
	], winner = 3})
	table._trick_history.refresh(hist2)
	test.check(table._trick_history.is_open(), "刷新后面板保持显示")
	test.eq(table._trick_history.page_label.text, "第 1 / 2 轮", "页码停留原轮（clamp 收敛）")
	# 关闭后刷新：不得复活面板
	table._trick_history.close()
	table._trick_history.refresh(hist2)
	test.check(not table._trick_history.is_open(), "关闭后刷新不复活面板")
	await _release_table(table)


## 回归（2026-11-17 用户需求）：出牌提交成功后按钮立即隐藏——结算停留期
## 内下一个 *_required 处理器因 await 挂起，旧「出牌」按钮曾挂满整个停留期
func test_play_bar_hidden_during_settle_pause(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	# 迷你局：庄 3（AI），人类第 4 手收尾；♠ 为主，人类全程无主垫牌
	var hands := [
		[C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0)],
		[C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.SPADE, Card.RANK_5, 0)],
		[C(Card.Suit.HEART, Card.RANK_7, 1), C(Card.Suit.DIAMOND, Card.RANK_7, 0)],
		[C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.DIAMOND, Card.RANK_9, 0)],
	]
	var bottom: Array = []
	var bottom_ranks := [Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10,
		Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A]
	for i in 8:
		bottom.append(C(Card.Suit.CLUB, bottom_ranks[i], 0))
	eng.start_session_with_deal(3, hands, bottom)
	await tree_pause()
	var guard := 0
	while eng.phase != Phase.TRICKS and guard < 40:
		guard += 1
		if eng.phase == Phase.AUCTION and eng.auction.turn == 0:
			eng.submit_bid(0, GameEngine.BID_PASS)
		await tree_pause()
	test.eq(eng.phase, Phase.TRICKS, "迷你局进入出牌")
	# r1：庄 3 领（处理器自驱）→ 轮到人类第 2 手
	guard = 0
	while eng.turn_seat != 0 and eng.phase == Phase.TRICKS and guard < 40:
		guard += 1
		await tree_pause()
	test.eq(eng.turn_seat, 0, "轮到人类（r1 第 2 手）")
	var bar: HBoxContainer = table.get_node("BottomArea/ActionBar")
	var has_btn := false
	for b in bar.get_children():
		if b is Button and b.visible and not b.is_queued_for_deletion():
			has_btn = true
	test.check(has_btn, "人类回合出牌按钮在")
	table.hand_area.select_cards([eng.hands[0][0]])
	table._submit_human_play()
	await tree_pause()
	# 推进到 r2 人类第 4 手（处理器自驱 AI）
	guard = 0
	while eng.phase == Phase.TRICKS and eng.turn_seat != 0 and guard < 40:
		guard += 1
		await tree_pause()
	test.eq(eng.turn_seat, 0, "人类第 4 手（r2 末尾）")
	test.eq(eng.hand_count(0), 1, "剩最后一张")
	table.hand_area.select_cards([eng.hands[0][0]])
	table._submit_human_play()
	# 回归断言：提交成功瞬间按钮条已清空（修复前旧「出牌」按钮挂满停留期）
	var visible_btns := 0
	for b in bar.get_children():
		if b is Button and b.visible and not b.is_queued_for_deletion():
			visible_btns += 1
	test.eq(visible_btns, 0, "出牌提交后按钮立即隐藏（结算停留期不露旧按钮）")
	await tree_pause()
	test.eq(eng.phase, Phase.SETTLED, "迷你局结算完成")
	await _release_table(table)


## 历史按钮打开出牌历史面板（2026-11-17 用户需求重做）：
## 默认最后一轮；【<<】【<】【>】【>>】翻第一页/上一页/下一页/最后一轮；
## ✕ 或点击窗口外（遮罩）关闭
func test_history_chip_opens_panel_nav_and_close(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	# 迷你局（庄 3 = AI）：3 有 10 张（AI 自扣 8 留 2 张主牌，两轮自领并连赢，四家同时打空）
	# 庄家手牌不含 9/2/王——无论 AI 叫什么 R，这些牌都是确定副牌，两轮必然结算完成；
	# 拍卖/叫主/扣底/AI 出牌由牌桌处理器自驱（定时器已调快），人类叫分与出牌由本用例代点
	var hands := [
		[C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0)],
		[C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.SPADE, Card.RANK_5, 0)],
		[C(Card.Suit.HEART, Card.RANK_7, 1), C(Card.Suit.DIAMOND, Card.RANK_7, 0)],
		[C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_K, 0),
			C(Card.Suit.HEART, Card.RANK_7, 2), C(Card.Suit.HEART, Card.RANK_10, 0),
			C(Card.Suit.HEART, Card.RANK_J, 0), C(Card.Suit.HEART, Card.RANK_Q, 0),
			C(Card.Suit.DIAMOND, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 0),
			C(Card.Suit.DIAMOND, Card.RANK_Q, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 0)],
	]
	var bottom: Array = []
	var bottom_ranks := [Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10,
		Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A]
	for i in 8:
		bottom.append(C(Card.Suit.CLUB, bottom_ranks[i], 0))
	eng.start_session_with_deal(3, hands, bottom)
	var guard := 0
	while eng.phase != Phase.TRICKS and guard < 40:
		guard += 1
		if eng.phase == Phase.AUCTION and eng.auction.turn == 0:
			eng.submit_bid(0, GameEngine.BID_PASS)
		await tree_pause()
	test.eq(eng.phase, Phase.TRICKS, "迷你局进入出牌")
	# r1：庄 3 领 → 轮到人类（垫牌）；AI 出牌由处理器自驱，两轮赢家均为庄
	guard = 0
	while eng.turn_seat != 0 and eng.phase == Phase.TRICKS and guard < 40:
		guard += 1
		await tree_pause()
	var v: Dictionary = eng.submit_play(0, [eng.hands[0][0]])
	test.check(v.legal, "人类 r1 出牌合法：%s" % v.text)
	# r2：庄再领 → 再轮到人类
	guard = 0
	while eng.turn_seat != 0 and eng.phase == Phase.TRICKS and guard < 40:
		guard += 1
		await tree_pause()
	v = eng.submit_play(0, [eng.hands[0][0]])
	test.check(v.legal, "人类 r2 出牌合法：%s" % v.text)
	# 两轮后四家牌尽 → 结算
	guard = 0
	while eng.phase == Phase.TRICKS and guard < 40:
		guard += 1
		await tree_pause()
	test.eq(eng.trick_history.size(), 2, "两轮历史就绪")
	# 点击【历史】→ 面板打开，定位最后一轮（第 2 轮）
	var chip: Button = table._piles.history_chip
	var panel = table._trick_history
	chip.pressed.emit()
	test.check(panel.is_open(), "点击历史按钮 → 面板显示")
	test.eq(panel.page_label.text, "第 2 / 2 轮", "默认最后一轮")
	# 翻页：>> 幂等（已在末页）→ < 上一页 → << 第一页（边界禁用）→ > 下一页 → >> 末页
	panel._btn_last.pressed.emit()
	test.eq(panel.page_label.text, "第 2 / 2 轮", ">> 最后一轮（幂等）")
	panel._btn_prev.pressed.emit()
	test.eq(panel.page_label.text, "第 1 / 2 轮", "< 上一页")
	test.check(panel._btn_prev.disabled and panel._btn_first.disabled, "第一页：<< < 禁用")
	panel._btn_first.pressed.emit()
	test.eq(panel.page_label.text, "第 1 / 2 轮", "<< 第一页")
	panel._btn_next.pressed.emit()
	test.eq(panel.page_label.text, "第 2 / 2 轮", "> 下一页")
	test.check(panel._btn_next.disabled and panel._btn_last.disabled, "末页：> >> 禁用")
	panel._btn_last.pressed.emit()
	test.eq(panel.page_label.text, "第 2 / 2 轮", ">> 最后一轮")
	# ✕ 关闭 → 重新打开 → 点击窗口外（遮罩左键）关闭
	panel.close_button.pressed.emit()
	test.check(not panel.is_open(), "✕ 关闭面板")
	chip.pressed.emit()
	test.check(panel.is_open(), "重新打开")
	var evt := InputEventMouseButton.new()
	evt.button_index = MOUSE_BUTTON_LEFT
	evt.pressed = true
	panel.backdrop.gui_input.emit(evt)
	test.check(not panel.is_open(), "点击窗口外（遮罩）关闭")
	await _release_table(table)


## 揭主双飞（2026-11-17 用户需求）：主 R 牌与皇冠同现于中央，牌面飞至信息栏，
## 飞行中信息栏不显示主牌，落位后才显示
func test_trump_reveal_flies_to_sidebar(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	table._trump_reveal.fly_duration = 0.8  # 本用例用真实时长观察飞行过程
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	# 飞行中：信息栏主牌位仍是未叫主态，桌上存在揭主牌面
	var slot: Control = table.get_node("Sidebar/VBox/TrumpRow/TrumpStack/TrumpSlot")
	var in_slot := false
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.rank == Card.RANK_9:
			in_slot = true
	test.check(not in_slot, "飞行中信息栏尚未显示主牌（落位后才显示）")
	test.check(table._trump_reveal.active, "揭主动画进行中")
	var flying := false
	for c in table.get_children():
		if c is CardWidget and c.card != null and c.card.rank == Card.RANK_9:
			flying = true
	test.check(flying, "中央存在飞行中的主 R 牌面")
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(1.2).timeout  # > 飞行时长 0.8s
	var has_card := false
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.suit == Card.Suit.SPADE and c.card.rank == Card.RANK_9:
			has_card = true
	test.check(has_card, "落位后信息栏显示 ♠9 牌面")
	test.check(not table._trump_reveal.active, "落位后动画结束")
	await _release_table(table)
