extends UiTestBase
## UI 层回归用例：headless 实例化场景 + 方法级驱动 + 节点状态断言。
## 纪律（AGENTS.md 第 7 章）：**每个用户报告的 UI bug，修复时必须在本套件补一个回归用例。**
##
## 已覆盖回归：
## - 扣底卡死：提交叫主后「确认扣底」按钮被 _clear_action_bar 误删
## - 牌堆悬停失效：SeatPanel.setup(seat) 被遗漏，座位号恒 -1
## - 叫主前手牌丢王/2：主牌组加入条件误写 trump != null
## - 捉分一致性：信息栏显示与引擎 captured_points 逐步一致
## - 电脑座位历史弹层永久滞留：pile_exited 连接写成求值不调用（`func(): x.start`），
##   移出面板后延迟隐藏定时器从未启动
## - 历史弹层只剩标题条：ScrollContainer 默认最小高度 0，整层塌缩致卡牌行全被裁剪


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


## 回归：牌堆弹层使用正确座位名（SeatPanel.setup 注入座位号）
func test_pile_popup_uses_seat_name(test) -> void:
	var table = await _spawn_table()
	_drive_step(table.engine)  # 让拍卖走一步，保证有真实历史数据结构
	table.get_node("SeatLeft").mouse_entered.emit()
	var popup: PanelContainer = table.get_node_or_null("PilePopup")
	test.check(popup != null and popup.visible, "悬停后牌堆弹层显示")
	if popup != null and popup.visible:
		var title: Label = popup.get_node("VBox/Header/Title")
		test.check("丁" in title.text, "弹层标题含座位名（实际：%s）" % title.text)
	await _release_table(table)


## 弹层延迟隐藏：移出入口后 0.1s 内仍可见（粘滞窗口），到期自动关闭
func test_pile_popup_delayed_hide(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	eng.submit_discard(0, AiPolicy.choose_discard(eng.hands[0], eng.trump))
	# 历史按钮已改点击开关（2026-11-17）；悬停自动隐藏路径改由座位面板驱动
	var panel: SeatPanel = table.seat_panels[3]
	panel.mouse_entered.emit()
	var popup: PanelContainer = table._piles.history_popup
	test.check(popup.visible, "悬停后弹层显示")
	panel.mouse_exited.emit()  # 移出入口 → 启动延迟隐藏
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


## 回归（2026-11-17 用户报告）：电脑座位悬停历史弹层**永久滞留**——
## pile_exited 曾连接成 `func(): _piles.hide_timer.start`（求值出 Callable 后丢弃，
## 从未调用），移出面板后延迟隐藏定时器从未启动
func test_seat_panel_popup_hides_on_exit(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	var panel: SeatPanel = table.seat_panels[3]
	panel.mouse_entered.emit()  # 悬停丁 → pile_hovered → show_history
	var popup: PanelContainer = table._piles.history_popup
	test.check(popup.visible, "悬停电脑座位后历史弹层显示")
	panel.mouse_exited.emit()  # 移出面板 → hide_timer.start（回归点：曾未调用）
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(0.5).timeout  # > HIDE_DELAY(0.1s)
	test.check(not popup.visible, "移出电脑座位后弹层自动关闭（回归：弹层永久滞留）")
	await _release_table(table)


## 回归（2026-11-17 用户报告）：历史弹层**只剩标题条、内容不显示**——
## ScrollContainer 默认最小高度为 0，放入 VBox 后整层塌缩，卡牌行全被裁剪
func test_history_popup_content_expands(test) -> void:
	var table = await _spawn_table()
	# 注入两轮真实结构的历史（丁两轮出牌，含赢轮 ✓）
	var hist: Array = [
		{plays = [
			{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_5, 0)], role = FollowRule.Role.LEAD},
			{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0)], role = FollowRule.Role.DISCARD},
		], winner = 2},
		{plays = [
			{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_9, 0)], role = FollowRule.Role.LEAD},
			{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0)], role = FollowRule.Role.FOLLOW_TYPE},
		], winner = 3},
	]
	table._piles.show_history(3, hist, table.SEAT_NAMES)
	var popup: PanelContainer = table._piles.history_popup
	var scroll: ScrollContainer = popup.get_node("VBox/Scroll")
	test.check(popup.visible, "悬停后历史弹层显示")
	var tree: SceneTree = Engine.get_main_loop()
	await tree.process_frame
	await tree.process_frame  # 布局落地两帧
	test.check(scroll.size.y > 60, "滚动区高度随内容展开（回归：高度塌缩只剩标题条），实际 %.0f" % scroll.size.y)
	test.check(popup.size.y > 100, "弹层整体高度随内容展开，实际 %.0f" % popup.size.y)
	var rows := popup.get_node("VBox/Scroll/List")
	var alive := 0
	for c in rows.get_children():
		if not c.is_queued_for_deletion():
			alive += 1
	test.eq(alive, 2, "两轮各一行，行内容已构建")
	await _release_table(table)


## 状态驱动刷新（2026-11-17 设计评审）：历史弹层悬停阅读期间对局继续推进，
## 内容须就地刷新（trick_settled → _refresh → refresh_history），隐藏后刷新必须无效
func test_history_popup_refreshes_while_visible(test) -> void:
	var table = await _spawn_table()
	var hist1: Array = [
		{plays = [{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_7, 0)], role = FollowRule.Role.LEAD}], winner = 3},
	]
	table._piles.show_history(3, hist1, table.SEAT_NAMES)
	var list: VBoxContainer = table._piles.history_popup.get_node("VBox/Scroll/List")
	test.eq(_alive_rows(list), 1, "初始一行")
	# 悬停期间又结算一轮 → refresh_history 追加内容，弹层保持显示
	var hist2: Array = hist1.duplicate(true)
	hist2.append({plays = [
		{seat = 3, cards = [C(Card.Suit.CLUB, Card.RANK_8, 0), C(Card.Suit.CLUB, Card.RANK_9, 0)], role = FollowRule.Role.LEAD},
		{seat = 2, cards = [C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_8, 0)], role = FollowRule.Role.FOLLOW_TYPE},
	], winner = 3})
	table._piles.refresh_history(hist2, table.SEAT_NAMES)
	test.check(table._piles.history_popup.visible, "刷新后弹层保持显示")
	test.eq(_alive_rows(list), 2, "悬停期间历史增长 → 行数就地更新（1 → 2）")
	test.eq(table._piles.showing_seat, 3, "展示座位保持不变")
	# 隐藏后刷新：不得复活弹层、不得改动内容
	table._piles.hide_all()
	table._piles.refresh_history(hist2, table.SEAT_NAMES)
	test.check(not table._piles.history_popup.visible, "隐藏后刷新不复活弹层")
	test.eq(_alive_rows(list), 2, "隐藏后刷新不重建内容")
	test.eq(table._piles.showing_seat, -1, "隐藏后展示座位复位")
	await _release_table(table)


func _alive_rows(list: VBoxContainer) -> int:
	var n := 0
	for c in list.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


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


## 历史按钮点击开关 + 弹层 X 关闭（2026-11-17 用户需求）：
## 打开即钉住（面板移出/悬停计时器不隐藏），X 或再次点击关闭
func test_history_chip_click_toggle_with_x(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	var chip: Button = table._piles.history_chip
	var popup: PanelContainer = table._piles.history_popup
	chip.pressed.emit()  # 点击打开
	test.check(popup.visible, "点击历史按钮 → 弹层显示")
	test.check(table._piles.history_pinned, "点击打开 → 钉住模式")
	chip.pressed.emit()  # 再次点击 → 关闭
	test.check(not popup.visible, "再次点击 → 弹层关闭")
	chip.pressed.emit()  # 重新打开
	test.check(popup.visible and table._piles.history_pinned, "可重新打开（钉住）")
	# 钉住后：面板移出 / 弹层移出都不自动隐藏
	table.seat_panels[3].mouse_entered.emit()  # 悬停丁 → 内容切为丁（仍钉住）
	table.seat_panels[3].mouse_exited.emit()
	table._piles.request_hide()
	await tree_pause()
	test.check(popup.visible, "钉住的弹层不受悬停自动隐藏影响")
	var x_btn: Button = popup.get_node("VBox/Header/CloseButton")
	test.check(x_btn != null and x_btn.visible, "弹层右上角有 ✕ 关闭按钮")
	x_btn.pressed.emit()
	test.check(not popup.visible, "点击 ✕ → 弹层关闭")
	test.check(not table._piles.history_pinned, "关闭后解除钉住")
	await _release_table(table)
