extends UiTestBase
## UI 层回归用例：headless 实例化场景 + 方法级驱动 + 节点状态断言。
## 纪律（[码5]）：**每个用户报告的 UI bug，修复时必须在本套件补一个回归用例。**
##
## 已覆盖回归：
## - 扣底卡死：提交叫主后「确认扣底」按钮被 _clear_action_bar 误删
## - 牌堆悬停失效：SeatPanel.setup(seat) 被遗漏，座位号恒 -1
## - 叫主前手牌丢王/2：主牌组加入条件误写 trump != null
## - 捉分一致性：信息栏显示与引擎 captured_points 逐步一致
## - 座位悬停历史弹层路径整体移除：悬停座位不再弹出任何面板
## - 出牌历史面板：十字摆位一轮四家出牌、翻轮次四按钮
##   边界禁用、✕/点击窗口外关闭、打开期间轮次增长就地收敛
## - 底牌浮层不遮挡弹层：底牌 z=1 只比桌面高一层，历史/牌堆弹层 z=10


## AI 代打：走完当前阶段的全部引擎交互（不模拟鼠标）
func _drive_step(eng: GameEngine) -> void:
	match eng.phase:
		Phase.AUCTION:
			var s: int = eng.auction.turn
			eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid(), s, eng.auction.bids))
		Phase.TRUMP:
			var ch: Dictionary = AiPolicy.choose_trump(eng.hands[eng.banker_seat])
			eng.submit_trump(eng.banker_seat, ch.suit, ch.rank)
		Phase.DISCARD:
			eng.submit_discard(eng.banker_seat, AiPolicy.choose_discard(eng.hands[eng.banker_seat], eng.trump))
		Phase.TRICKS:
			var s: int = eng.turn_seat
			eng.submit_play(s, AiPolicy.choose_play(eng, s))


## 出牌桌上当前展示的出牌行数（一行 = 一家出牌，行内含 CardWidget 即计；
## 按「行」而非行内控件类型计数——出牌行摆法变动不破坏断言；一家可能出多张，
## 所以不数牌面；BottomCards 是翻底弹层按名排除，queue_free 待删行不计）
func _trick_row_count(table) -> int:
	var n := 0
	for c in table.get_node("TrickArea").get_children():
		if c.name == "BottomCards" or c.is_queued_for_deletion():
			continue
		for d in c.get_children():
			if d is CardWidget:
				n += 1
				break
	return n


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


## 回归：座位悬停不再弹出历史弹层（悬停路径已移除，历史走 TrickHistoryPanel）
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
	var tree: SceneTree = Engine.get_main_loop()
	await tree.process_frame  # 仅等 1 帧（远小于 0.1s 延迟）：用 0.05s 定时等待时，
	# 后台负载的慢帧会把本用例的恢复与 0.1s 隐藏计时器挤进同一帧造成假失败
	test.check(popup.visible, "移出后 0.1s 内弹层保持显示（延迟隐藏）")
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
	var shown_rows := _trick_row_count(table)
	test.eq(shown_rows, 4, "停留期内四家出牌保留在桌上")
	var winner: int = eng.leader_seat
	if winner != 0:
		var status: String = table.seat_panels[winner].get_node("VBox/StatusLabel").text
		test.check("✓" in status, "赢家姓名版显示 ✓ 标记（实际 %s）" % status)
	# 停留到期：出牌桌主动清空
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(2.0).timeout
	test.eq(_trick_row_count(table), 0, "停留到期后出牌主动清空")
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


## 人类庄家翻底后：底牌 8 张入手即呈选中态（便于观察与直接扣回）
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


## 回归：底牌浮层不遮挡其它弹层——底牌只比桌面高一层（z=1），
## 历史/牌堆弹层（z=10）压在底牌之上（用户报告：扣底阶段打开历史被底牌盖住）
func test_bottom_cards_z_order_below_popups(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)  # 人类 130 坐庄
	table._pending_trump_suit = Card.Suit.SPADE
	table._submit_human_trump(Card.RANK_9)  # 真实 UI 提交路径 → 扣底阶段 + 底牌展示
	await tree_pause()
	test.eq(eng.phase, Phase.DISCARD, "进入扣底阶段")
	var bottom = table.trick_area.get_node_or_null("BottomCards")
	test.check(bottom != null, "扣底阶段底牌展示存在")
	test.eq(bottom.z_index, 1, "底牌只比桌面高一层（z=1）")
	test.eq(table._trick_history.popup.z_index, 10, "历史弹层在底牌之上（z=10）")
	test.eq(table._trick_history.backdrop.z_index, 10, "历史遮罩在底牌之上（z=10）")
	test.eq(table._piles.bottom_popup.z_index, 10, "牌堆弹层在底牌之上（z=10）")
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
	test.eq(table.human_void_stamp.position, Vector2(958, 488), "人类位印章固定槽位 = 手牌右上方")
	eng.trump_void_seats = [false, false, false, false]
	table._refresh()
	test.check(not table.human_void_stamp.visible, "复位后隐藏")
	test.check(not table.seat_panels[1].get_node("VoidStamp").visible, "复位后隐藏（乙）")
	await _release_table(table)


## 出牌历史面板：打开即定位最后一轮，十字摆位四家出牌、
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


## 状态驱动刷新：面板打开期间新轮次结算 → refresh 就地收敛页码并
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


## 回归（用户需求）：出牌提交成功后按钮立即隐藏——结算停留期
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


## 历史按钮打开出牌历史面板：
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


## 揭主双飞（用户需求）：主 R 牌与皇冠同现于中央，牌面飞至信息栏，
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
	var flying_widget: CardWidget = null
	for c in table.get_children():
		if c is CardWidget and c.card != null and c.card.rank == Card.RANK_9:
			flying_widget = c
	test.check(flying_widget != null, "中央存在飞行中的主 R 牌面")
	if flying_widget != null:
		test.check(flying_widget.pivot_offset == CardWidget.SIZE_NORMAL / 2.0,
			"飞牌 pivot 居中（缩放围绕牌心，起点不偏右下）")
		test.check(flying_widget.scale.is_equal_approx(Vector2(2.2, 2.2)), "起点中央放大 ×2.2")
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(1.2).timeout  # > 飞行时长 0.8s
	var has_card := false
	var landed: CardWidget = null
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.suit == Card.Suit.SPADE and c.card.rank == Card.RANK_9:
			has_card = true
			landed = c
	test.check(has_card, "落位后信息栏显示 ♠9 牌面")
	# 落位尺寸与槽位同源（飞牌渐缩终点 = 目标槽位尺寸；旧版恒缩回 72×100 与 52×76 槽一次跳变）
	test.check(landed != null and landed.size == table.sidebar.trump_slot_size(),
		"落位牌面尺寸 = 主牌槽实测尺寸（落位零跳变）")
	test.check(not table._trump_reveal.active, "落位后动画结束")
	await _release_table(table)


## 手机版揭主落位（用户需求）：顶栏主牌槽（36×50）比桌面更小，飞牌渐缩至槽位尺寸
## 落位；落位回调经 InfoSurface 分派——旧版写死 sidebar，顶栏主牌槽整局
## 停在未叫主占位态（真牌被写进隐藏侧栏）
func test_mobile_trump_reveal_lands_bar_slot(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = await _spawn_table()
	AppSettings.mobile_ui = true  # spawn 后覆写（_spawn_table 强制桌面口径防污染）
	table._apply_layout_mode()
	await tree.process_frame
	_deal(table.engine, 0)
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	table._trump_reveal.fly_duration = 0.5  # 本用例用真实时长观察飞行起点
	for s in [1, 2, 3]:
		table.engine.submit_bid(s, GameEngine.BID_PASS)
	table.engine.submit_bid(0, GameEngine.BID_PASS)
	table.engine.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	var bar: MobileTopBar = table._info.mobile_bar()
	test.check(table._trump_reveal.active, "手机揭主动画进行中")
	test.eq(table._info.trump_slot_size(), CardWidget.SIZE_BAR, "手机落点目标尺寸 = 顶栏槽 36×50")
	var flying: CardWidget = table._trump_reveal._card_widget
	test.check(flying != null and flying.pivot_offset == CardWidget.SIZE_NORMAL / 2.0,
		"飞牌 pivot 居中（起点居中于屏幕正中）")
	test.check(flying != null and flying.scale.is_equal_approx(Vector2(2.2, 2.2)), "起点中央放大 ×2.2")
	await tree.create_timer(0.9).timeout  # > 飞行时长 0.5s
	var landed: CardWidget = null
	for c in bar._slot.get_children():
		if c is CardWidget and c.card != null and c.card.suit == Card.Suit.SPADE and c.card.rank == Card.RANK_9:
			landed = c
	test.check(landed != null, "落位后顶栏主牌槽显示 ♠9（落位回调分支分派）")
	if landed != null:
		test.eq(landed.size, CardWidget.SIZE_BAR, "顶栏槽牌面为 BAR 档尺寸（落位零跳变）")
	test.check(not table._trump_reveal.active, "落位后动画结束")
	AppSettings.mobile_ui = false
	await _release_table(table)


## 发牌动画：开局播放（_deal_active），结束后放行真实渲染（19 张牌面就位）
func test_deal_animation_lifecycle(test) -> void:
	var table = await _spawn_table()
	test.check(table._deal_active and table._deal_animator.active, "开局即处于发牌动画中")
	var tree: SceneTree = Engine.get_main_loop()
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	test.check(not table._deal_active, "动画结束（放行真实渲染）")
	var widgets := 0
	for c in table.hand_area.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			widgets += 1
	test.eq(widgets, 19, "结束后手牌 19 张真实牌面")
	await _release_table(table)


## 发牌动画为表现层：动画进行中对局照常推进（不阻塞逻辑）
func test_deal_animation_non_blocking(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	test.check(table._deal_active, "动画进行中")
	# 动画进行中提交当前回合的表态（回合由初始 AI 计时推进情况自适应）
	var turn: int = eng.auction.turn
	eng.submit_bid(turn, GameEngine.BID_PASS)
	test.check(eng.auction.has_passed(turn), "动画期间引擎照常推进")
	await _release_table(table)


## 发牌动画期间手牌虚线框隐藏（汇聚/收拢/展开阶段牌未分区排序、框位与牌不对齐），
## 排序完成（动画结束放行真实渲染）后随牌一起展现
func test_deal_animation_hides_frames(test) -> void:
	var table = await _spawn_table()
	var visible_frames := func() -> int:
		var n := 0
		for c in table.hand_area.get_children():
			if c is DashedRoundedFrame and c.visible and not c.is_queued_for_deletion():
				n += 1
		return n
	test.eq(visible_frames.call(), 0, "发牌动画期间虚线框整体隐藏")
	var tree: SceneTree = Engine.get_main_loop()
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	test.check(visible_frames.call() >= 1, "排序完成后虚线框随真实渲染展现")
	await _release_table(table)


## 发牌逐拍（无飞行牌）：各家座位面板张数随发牌一张一张增加（轮询观察到计数
## 上升），动画结束回归引擎权威 19 张
func test_deal_animation_counts_tick(test) -> void:
	var table = await _spawn_table()
	test.check(table._deal_active, "动画进行中")
	var count_of := func(seat: int) -> String:
		return str((table.seat_panels[seat].get_node("VBox/CountLabel") as Label).text)
	var tree: SceneTree = Engine.get_main_loop()
	var first := -1
	var saw_rise := false
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		var v := int(count_of.call(3).trim_suffix(" 张"))
		if first < 0:
			first = v
		elif v > first:
			saw_rise = true
		await tree.process_frame
	test.check(saw_rise, "发牌过程中张数逐拍增长（观察到计数上升）")
	test.eq(count_of.call(3), "19 张", "发牌完成回归引擎权威 19 张")
	await _release_table(table)


## 叫分对话气泡：叫分/放弃以气泡呈现（带尾巴指向座位），姓名版状态行腾空；
## 更高分出现清除低分气泡；拍卖结束全清
func test_bid_bubbles_replace_seat_status(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	# 挂起 UI AI（延迟放大到测试期内不触发）：本用例直驱全部表态，避开 UI AI 竞速
	table._ai_delay_scale = 1e9
	_deal(eng, 0)
	var dealer: int = eng.dealer_seat
	var dealer_bubble = table._bid_bubbles._bubbles[dealer]
	# 发牌/排序动画期间：庄家底叫 130 气泡挂起（随排序完成一起出现）
	test.check(not dealer_bubble.visible, "发牌动画期间底叫 130 气泡挂起")
	var tree: SceneTree = Engine.get_main_loop()
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	# 排序完成 → 拍卖呈现放行：底叫 130 气泡出现；姓名版不再显示叫分
	test.check(dealer_bubble.visible and dealer_bubble._label.text == "130",
		"排序完成后庄家底叫 130 气泡")
	test.eq(str(table.seat_panels[1].get_node("VBox/StatusLabel").text), "",
		"叫分不展示在姓名版状态行")
	# 更高叫分：低分气泡被清除，字号随分值增大
	eng.submit_bid(1, 155)
	test.check(not dealer_bubble.visible, "130 气泡被 155 取代（清除）")
	var b1 = table._bid_bubbles._bubbles[1]
	test.check(b1.visible and b1._label.text == "155", "155 气泡呈现")
	test.check(int(b1._label.get_theme_font_size("font_size")) > BidBubbles.FONT_MIN,
		"叫分越大字号越大")
	# 放弃：气泡「不要」
	eng.submit_bid(2, GameEngine.BID_PASS)
	var b2 = table._bid_bubbles._bubbles[2]
	test.check(b2.visible and b2._label.text == "不要", "放弃气泡")
	# 拍卖结束（庄家弃权后仅剩 155）：气泡全清
	eng.submit_bid(3, GameEngine.BID_PASS)
	eng.submit_bid(dealer, GameEngine.BID_PASS)
	test.eq(int(eng.phase), int(Phase.TRUMP), "拍卖结束")
	test.check(not b1.visible and not b2.visible, "拍卖结束气泡全清")
	await _release_table(table)


## 便捷操作（用户需求）：双击手牌区空白清空选择（把选中的牌全部放回）
func test_double_click_blank_clears_selection(test) -> void:
	var table = await _spawn_table()
	var eng: GameEngine = table.engine
	_deal(eng, 0)
	for s in [1, 2, 3]:
		eng.submit_bid(s, GameEngine.BID_PASS)
	eng.submit_bid(0, GameEngine.BID_PASS)
	eng.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	# 扣底模式：底牌入手即选中（8 张）→ 双击区内空白（首张牌左缘之外）清空
	test.eq(table.hand_area.selected.size(), 8, "翻底预选 8 张")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.position = Vector2(20, 60)
	table.hand_area._gui_input(ev)
	test.eq(table.hand_area.selected.size(), 0, "双击空白清空选择")
	await _release_table(table)


## 触摸两指单击出牌（用户需求）：与右键出牌等效——撤销手势期间触摸模拟的
## 鼠标点选副作用（恢复手势前选择），再按当前选择提交
func test_two_finger_tap_plays_selection(test) -> void:
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
	test.eq(int(eng.phase), int(Phase.TRICKS), "进入出牌阶段（人类领出）")
	# 选中 1 张作为领出
	var lead: Card = eng.hands[0][0]
	table.hand_area.clear_selection()
	table.hand_area.select_cards([lead])
	# 两指手势：指 0 按下（快照 [lead]）→ 触摸模拟的鼠标点选误选另一张 → 指 1 按下
	var rect: Rect2 = table.hand_area.get_global_rect()
	var t1 := InputEventScreenTouch.new()
	t1.index = 0
	t1.pressed = true
	t1.position = rect.get_center()
	table.hand_area._input(t1)
	var other: Card = eng.hands[0][1]
	var idx: int = table.hand_area._hit_cards.find(other)
	var emu := InputEventMouseButton.new()
	emu.button_index = MOUSE_BUTTON_LEFT
	emu.pressed = true
	emu.position = Vector2(table.hand_area._hit_x[idx] + 5, 60)
	table.hand_area._gui_input(emu)
	table.hand_area._drag_selecting = false
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = rect.get_center() + Vector2(30, 0)
	table.hand_area._input(t2)
	# 两指依次抬起 → 恢复快照并提交出牌
	t1.pressed = false
	table.hand_area._input(t1)
	t2.pressed = false
	table.hand_area._input(t2)
	await tree_pause()
	# 领出已入局（后续 AI 跟牌竞速：可能仍在出牌轮，也可能已整轮结算）
	var played: Card = null
	if eng.current_plays.size() >= 1:
		played = eng.current_plays[0].cards[0]
	elif eng.trick_history.size() >= 1:
		played = eng.trick_history[0].plays[0].cards[0]
	test.check(played != null and played.same_card(lead),
		"两指单击触发出牌，出的是手势前的选择（副作用已撤销）")
	await _release_table(table)


## 手牌呈现设置（用户需求）：主牌框在左/右、点数从大到小/从小到大（花色分组从左到右不变）
func test_hand_layout_settings(test) -> void:
	var table = await _spawn_table()
	var prev_side: int = AppSettings.main_side
	var prev_order: int = AppSettings.sort_order
	var hand := [
		C(Card.Suit.SPADE, Card.RANK_9, 0),  # 主（R=9）
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0),
		C(Card.Suit.HEART, Card.RANK_A, 0),
		C(Card.Suit.HEART, Card.RANK_5, 0),
		C(Card.Suit.CLUB, Card.RANK_K, 0),
	]
	var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var ha = table.hand_area
	# 默认：主牌框在左、从大到小
	AppSettings.main_side = AppSettings.MainSide.LEFT
	AppSettings.sort_order = AppSettings.SortOrder.BIG_FIRST
	ha.render(hand, trump)
	test.check(ha._hit_cards[0].is_joker(), "主牌框在左（视觉首张为主牌）")
	test.eq(int(ha._hit_cards[2].rank), int(Card.RANK_A), "副牌从大到小（♥A 先于 ♥5）")
	# 主牌框在右
	AppSettings.main_side = AppSettings.MainSide.RIGHT
	ha.render(hand, trump)
	test.check(not ha._hit_cards[0].is_joker(), "主牌框在右（视觉首张为副牌）")
	# 从小到大
	AppSettings.sort_order = AppSettings.SortOrder.SMALL_FIRST
	ha.render(hand, trump)
	test.eq(int(ha._hit_cards[0].rank), int(Card.RANK_5), "副牌从小到大（♥5 先于 ♥A）")
	AppSettings.main_side = prev_side
	AppSettings.sort_order = prev_order
	await _release_table(table)


## 设置弹层（用户需求）：循环切换按钮翻转设置、保存并回调；【完成】关闭
func test_settings_dialog_toggles(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var prev_path: String = AppSettings.cfg_path
	AppSettings.cfg_path = "user://test_settings_dialog.cfg"
	var prev_side: int = AppSettings.main_side
	var prev_order: int = AppSettings.sort_order
	var prev_mobile: bool = AppSettings.mobile_ui
	var changed := {"n": 0}
	var dialog := SettingsDialog.create(tree.root, func(): changed.n += 1)
	var buttons: Array = []
	for c in dialog.get_children()[0].get_children():
		if c is Button:
			buttons.append(c)
	test.eq(buttons.size(), 3, "三个循环切换按钮（完成按钮在中央容器内）")
	var main_btn: Button = buttons[0]
	var order_btn: Button = buttons[1]
	var mobile_btn: Button = buttons[2]
	var side_before: int = AppSettings.main_side
	main_btn.pressed.emit()
	test.check(int(AppSettings.main_side) != side_before, "切换主牌框位置")
	test.eq(int(changed.n), 1, "变更回调触发（保存生效）")
	var order_before: int = AppSettings.sort_order
	order_btn.pressed.emit()
	test.check(int(AppSettings.sort_order) != order_before, "切换排序方向")
	test.eq(int(changed.n), 2, "变更回调再次触发")
	var mobile_before: bool = AppSettings.mobile_ui
	mobile_btn.pressed.emit()
	test.check(AppSettings.mobile_ui != mobile_before, "切换手机版 UI 调试开关")
	test.eq(int(changed.n), 3, "变更回调第三次触发")
	AppSettings.main_side = prev_side
	AppSettings.sort_order = prev_order
	AppSettings.mobile_ui = prev_mobile
	AppSettings.cfg_path = prev_path
	dialog.queue_free()
	await tree.process_frame


## 手机版 UI 独立分支（PC 调试入口强制开启验证）：顶栏当局信息 bar、无右侧栏、
## 大手牌贴底（96×134/步距 40·12）、宽 ≈90% 屏宽；桌面版布局完全还原
func test_mobile_layout_mode(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	AppSettings.mobile_ui = true  # 强制开启（headless 桌面环境无移动端特性）
	var table = load("res://scene/table/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	var bottom: Control = table.get_node("BottomArea")
	var bar: MobileTopBar = table._info.mobile_bar()
	test.check(bar != null and bar.visible, "手机版顶栏当局信息 bar 生效")
	test.eq(float(bar.offset_bottom), 56.0, "顶栏高 56（当局信息 bar）")
	test.check(not table.sidebar.visible, "手机版无右侧信息栏")
	test.check(not table.get_node("TopBar").visible, "桌面版顶栏隐藏（局况入 bar）")
	test.eq(float(bottom.offset_left), 64.0, "底部区左缘 64（手牌 ≈90% 屏宽）")
	test.eq(float(bottom.offset_right), -64.0, "底部区右缘 -64")
	test.eq(table.hand_area.hand_card_size, Vector2(96, 134), "手机大手牌 96×134")
	test.eq(float(table.hand_area.spacing_max), 40.0, "手机步距上限 40（用户调整）")
	test.eq(float(table.hand_area.spacing_min), 12.0, "手机步距下限 12")
	test.eq(float(table.hand_area.hand_base_y), 30.0, "手牌贴底基线")
	test.eq(table.trick_anchors[0], Vector2(0.5, 0.60), "出牌十字居中（手机锚点组）")
	test.eq(table.result_panel.anchor_left, 0.5, "结算面板居屏幕正中（手机无右栏偏置）")
	test.check(table._bid_bubbles._anchors == MobileLayout.BUBBLE_ANCHORS, "气泡锚点切手机组（尖角贴面板）")
	test.eq(bar._slot.size, CardWidget.SIZE_BAR, "主牌槽为 BAR 档 36×50")
	test.check(bar.trump_slot_center() != Vector2.ZERO, "顶栏主牌槽可测量（揭主落点）")
	test.eq(float(bar.size.x), 1280.0, "顶栏全宽（右锚子件定位正确，「更多」按钮可见）")
	test.eq(float((bar._more as Button).offset_right), -96.0,
		"「更多」按钮避让壳层 ⛶ 全屏按钮（右缘 -96，间隙 40px）")
	# 移动端专用数据收拢（MobileLayout 单一事实源）：容器偏移/印章位/入口按钮/皇冠落点/气泡尺度
	test.eq(float(table.action_bar.offset_bottom), 52.0, "操作按钮条底缘 52")
	test.eq(float(table.hint_label.offset_top), 56.0, "提示行上缘 56")
	test.eq(float(table.hint_label.offset_bottom), 84.0, "提示行下缘 84")
	test.eq(float(table.hand_area.offset_top), 92.0, "手牌区上缘 92")
	test.eq(float(table.hand_area.offset_bottom), -8.0, "手牌区下缘 -8")
	test.eq(float(table.human_void_stamp.offset_left), 1120.0, "无主印章手机位（右缘侧）")
	test.eq(float(table.human_void_stamp.offset_top), -250.0, "无主印章手机位（距底 250）")
	test.eq(float(table._piles.history_chip.offset_top), -210.0, "「历史」按钮上移（手牌框顶上方留隙）")
	test.eq(float(table._piles.bottom_button.offset_left), 66.0, "「牌堆」按钮同行右侧")
	test.eq(table._crown_anim.human_target, MobileLayout.CROWN_HUMAN_TARGET, "甲家皇冠落点切手机值")
	test.eq(table._bid_bubbles.font_max, 36, "气泡字号上限切手机 36")
	test.eq(table._bid_bubbles.max_size, Vector2(360, 130), "气泡尺寸上限切手机 360×130")
	# 手机模式发牌/渲染链路照常：动画完成 → 19 张真实牌面、无渲染挂起
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var widgets := 0
	for c in table.hand_area.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			widgets += 1
	test.eq(widgets, 19, "手机模式发牌完成手牌 19 张")
	test.check(not table.hand_area._render_pending, "手机模式渲染无挂起（布局就绪）")
	table.queue_free()
	await tree.process_frame
	AppSettings.mobile_ui = false  # 还原（桌面版布局口径）
	var table2 = load("res://scene/table/game_table.tscn").instantiate()
	tree.root.add_child(table2)
	await tree.process_frame
	await tree.process_frame
	test.eq(float(table2.get_node("BottomArea").offset_right), -220.0, "桌面版还原让位信息栏")
	test.eq(table2.hand_area.hand_card_size, Vector2(72, 100), "桌面版手牌卡 72×100")
	test.eq(float(table2.hand_area.spacing_max), 24.0, "桌面版步距上限还原 24")
	test.eq(float(table2.hand_area.hand_base_y), 16.0, "桌面版手牌基线还原 16")
	test.eq(table2.trick_anchors[0], Vector2(0.419, 0.55), "桌面版出牌十字还原")
	test.check(is_equal_approx(float(table2.result_panel.anchor_left), 0.419), "桌面版结算面板锚回十字中心")
	test.check(table2._bid_bubbles._anchors == BidBubbles.ANCHORS, "桌面版气泡锚点还原")
	test.check(table2.sidebar.visible, "桌面版信息栏常显")
	test.check(table2._info.mobile_bar() == null, "桌面版无手机顶栏")
	test.eq(float(table2.human_void_stamp.offset_left), 958.0, "桌面版无主印章位还原")
	test.eq(table2._crown_anim.human_target, CrownAnimator.CROWN_HUMAN_TARGET, "桌面版皇冠落点还原")
	test.eq(table2._bid_bubbles.font_max, BidBubbles.FONT_MAX, "桌面版气泡尺度还原")
	test.eq(table2._bid_bubbles.max_size, BidBubbles.MAX_SIZE, "桌面版气泡上限还原")
	test.eq(float(table2._piles.history_chip.offset_top), -196.0, "桌面版「历史」按钮位还原（捕获原值）")
	# 桌面还原 = 捕获档案回放（旧版这些值硬编码在控制器 else 分支，与 tscn 重复）
	test.eq(float(table2.action_bar.offset_bottom), 48.0, "桌面版按钮条底缘还原（tscn 捕获）")
	test.eq(float(table2.hint_label.offset_top), 54.0, "桌面版提示行上缘还原（tscn 捕获）")
	test.eq(float(table2.hint_label.offset_bottom), 80.0, "桌面版提示行下缘还原（tscn 捕获）")
	test.eq(float(table2.hand_area.offset_top), 86.0, "桌面版手牌区上缘还原（tscn 捕获）")
	test.eq(float(table2.hand_area.offset_bottom), -12.0, "桌面版手牌区下缘还原（tscn 捕获）")
	test.eq(float(table2.human_void_stamp.offset_top), -232.0, "桌面版无主印章距底还原（tscn 捕获）")
	test.eq(float(table2._piles.bottom_button.offset_left), 66.0, "桌面版「牌堆」按钮位还原（捕获原值）")
	await _release_table(table2)


## 虚线框随手牌基线（框顶 = 基线 − 内边距 10）：手机贴底 30 → 框 20，桌面 16 → 框 6——
## 框与牌永不脱节（手机分支框错位 24px 的回归锁）
func test_mobile_frame_alignment(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	for mode in [true, false]:
		AppSettings.mobile_ui = mode
		var table = load("res://scene/table/game_table.tscn").instantiate()
		tree.root.add_child(table)
		await tree.process_frame
		await tree.process_frame
		var label: String = "手机" if mode else "桌面"
		var base: float = table.hand_area.hand_base_y
		var frames: Array = []
		var cards_y: Array = []
		for c in table.hand_area.get_children():
			if c is DashedRoundedFrame and not c.is_queued_for_deletion():
				frames.append(c)
			if c is CardWidget and not c.is_queued_for_deletion():
				cards_y.append(float(c.position.y))
		test.check(frames.size() >= 1, label + "模式渲染虚线框")
		for f in frames:
			test.eq(float((f as Control).position.y), base - 10.0, label + "框顶=基线−内边距（对齐）")
		var lifted: float = table.hand_area.hand_card_size.y * table.hand_area.SELECT_LIFT_RATIO
		var all_on_baseline := true
		for y in cards_y:
			if not is_equal_approx(y, base) and not is_equal_approx(y, base - lifted):
				all_on_baseline = false
		test.check(all_on_baseline, label + "卡牌 y 全部对齐基线（选中上浮除外）")
		await _release_table(table)
	AppSettings.mobile_ui = false


## 对局中途切 UI 分支（PC 调试入口的实际用法）：手机 ⇄ 桌面状态与 UI 完整重建；
## 弹层居中锚随档案重锚（旧版 setup 时烘焙桌面十字锚、切换后弹层仍偏在让位
## 信息栏的位置）；切回桌面 = 捕获档案回放（桌面数值零硬编码）
func test_mobile_mode_switch_midgame(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	AppSettings.mobile_ui = true
	var table = load("res://scene/table/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	_deal(table.engine, 0)
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	# 手机态：弹层锚居屏幕正中（档案重锚，非 setup 烘焙值）
	test.check(is_equal_approx(float(table._trick_history.popup.anchor_left), 0.5),
		"手机态历史弹层锚居屏幕正中")
	test.check(is_equal_approx(float(table._piles.bottom_popup.anchor_left), 0.5),
		"手机态牌堆弹层锚居屏幕正中")
	# 手机 → 桌面：顶栏/面板销毁、信息栏恢复、手牌参数还原、弹层锚回十字中心
	AppSettings.mobile_ui = false
	table._apply_layout_mode()
	test.check(table._info.mobile_bar() == null, "切桌面：手机顶栏销毁")
	test.check(table.sidebar.visible, "切桌面：信息栏恢复")
	test.eq(table.hand_area.hand_card_size, Vector2(72, 100), "切桌面：手牌卡还原")
	test.check(is_equal_approx(float(table._trick_history.popup.anchor_left), 0.419),
		"切桌面：历史弹层锚回十字中心")
	test.check(is_equal_approx(float(table._piles.bottom_popup.anchor_left), 0.419),
		"切桌面：牌堆弹层锚回十字中心")
	# 桌面还原 = 捕获档案回放：此前硬编码在控制器 else 分支的值逐项回归
	test.eq(float(table.action_bar.offset_bottom), 48.0, "切桌面：按钮条底缘还原（捕获）")
	test.eq(float(table.hint_label.offset_top), 54.0, "切桌面：提示行上缘还原（捕获）")
	test.eq(float(table.hint_label.offset_bottom), 80.0, "切桌面：提示行下缘还原（捕获）")
	test.eq(float(table.hand_area.offset_top), 86.0, "切桌面：手牌区上缘还原（捕获）")
	test.eq(float(table.hand_area.offset_bottom), -12.0, "切桌面：手牌区下缘还原（捕获）")
	test.eq(float(table.human_void_stamp.offset_left), 958.0, "切桌面：无主印章位还原（捕获）")
	test.eq(float(table.human_void_stamp.offset_top), -232.0, "切桌面：无主印章距底还原（捕获）")
	test.eq(table._crown_anim.human_target, CrownAnimator.CROWN_HUMAN_TARGET, "切桌面：皇冠落点还原（捕获）")
	var widgets_desktop := 0
	for c in table.hand_area.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			widgets_desktop += 1
	test.eq(widgets_desktop, 19, "切桌面：手牌重渲 19 张")
	# 桌面 → 手机：顶栏重建、手牌参数再切
	AppSettings.mobile_ui = true
	table._apply_layout_mode()
	test.check(table._info.mobile_bar() != null, "切回手机：顶栏重建")
	test.check(not table.sidebar.visible, "切回手机：信息栏隐藏")
	test.eq(table.hand_area.hand_card_size, Vector2(96, 134), "切回手机：手牌卡再切")
	var widgets_mobile := 0
	for c in table.hand_area.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			widgets_mobile += 1
	test.eq(widgets_mobile, 19, "切回手机：手牌重渲 19 张")
	AppSettings.mobile_ui = false
	table._apply_layout_mode()
	await _release_table(table)


## 手机「更多」面板：☰ 打开即喂当前状态（局数/累计/手牌统计），✕/点窗外/再点 ☰
## 三种关闭方式，设置入口开设置弹层；顶栏局况/捉分分派与主牌槽语义同信息栏
func test_mobile_more_panel(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = await _spawn_table()
	# 手机分支覆写须在 spawn 之后（_spawn_table 强制桌面口径防 settings.cfg 污染）：
	# 旧版在 spawn 前置 true 被 reset → 桌面实例化 → _mobile_bar 为 null，首个断言处
	# 脚本错误中止、后续断言从未执行（框架不把脚本中止计失败，用例静默假绿）
	AppSettings.mobile_ui = true
	table._apply_layout_mode()
	await tree.process_frame
	_deal(table.engine, 0)
	# ☰ 开 → 再点 ☰ 关（toggle 语义）→ 再开
	var bar: MobileTopBar = table._info.mobile_bar()
	bar.more_pressed.emit()
	await tree.process_frame
	var panel: MobileMorePanel = table._info.more_panel()
	test.check(panel != null and panel.visible, "☰ 打开更多面板")
	test.check("第" in panel._round_label.text, "面板展示局数")
	test.check("甲" in panel._cumulative_label.text, "面板展示四家累计")
	test.check(not panel._stats_main.text.is_empty(), "面板展示手牌统计")
	bar.more_pressed.emit()
	await tree.process_frame
	test.check(table._info.more_panel() == null, "再点 ☰ 关闭（toggle 语义）")
	# ✕ 按钮关闭 → 再开
	bar.more_pressed.emit()
	await tree.process_frame
	panel = table._info.more_panel()
	test.check(panel != null, "再次打开")
	test.eq(panel._stats_grid.columns, 3, "点数统计三列排布（面板紧凑）")
	panel._close_btn.pressed.emit()
	await tree.process_frame
	test.check(table._info.more_panel() == null, "✕ 按钮关闭")
	# 设置入口：开设置弹层（与桌面同口径），清理后继续
	bar.more_pressed.emit()
	await tree.process_frame
	panel = table._info.more_panel()
	panel.settings_pressed.emit()
	await tree.process_frame
	test.check(tree.root.get_node_or_null("SettingsDialog") != null, "面板设置入口打开设置弹层")
	tree.root.get_node_or_null("SettingsDialog").queue_free()
	tree.root.get_node_or_null("SettingsDialogDim").queue_free()
	await tree.process_frame
	# 顶栏局况/捉分（当局信息 bar 分派）
	test.check("捉分" in (bar._captured as Label).text, "顶栏展示捉分")
	# 点窗外关闭（信息面引用清空）
	var evt := InputEventMouseButton.new()
	evt.button_index = MOUSE_BUTTON_LEFT
	evt.pressed = true
	table._info.more_panel().get_parent().get_node("MorePanelDim").gui_input.emit(evt)
	await tree.process_frame
	test.check(table._info.more_panel() == null, "点窗外关闭更多面板（引用清空）")
	# 顶栏手牌统计（图标+数字 ×4）：_refresh_stats 分派——未叫主=四门花色数（王不计入）
	table._refresh()
	var icons: Array = []
	for i in 4:
		icons.append(str((bar._suit_icons[i] as Label).text))
	var counts: Array = []
	for i in 4:
		counts.append(int((bar._suit_counts[i] as Label).text))
	test.check(icons == ["♠", "♥", "♣", "♦"], "未叫主统计展示四门花色图标")
	var jokers := 0
	for c in table.engine.get_hand(0):
		if c.is_joker():
			jokers += 1
	var total: int = counts[0] + counts[1] + counts[2] + counts[3]
	test.eq(total, 19 - jokers, "四门计数合计=手牌 19−王（叫主前王不计入）")
	# 拍卖+叫主（同帧直驱避 AI 竞速）：顶栏局况切「出牌庄」口径、统计主花色金色/含王
	for s in [1, 2, 3]:
		table.engine.submit_bid(s, GameEngine.BID_PASS)
	table.engine.submit_bid(0, GameEngine.BID_PASS)
	table.engine.submit_trump(0, Card.Suit.HEART, Card.RANK_9)
	table._refresh()
	test.check("出牌庄" in (bar._info as Label).text, "叫主后顶栏局况切出牌庄口径")
	# 揭主落位集成：飞牌落进顶栏主牌槽（守卫自愈 + 落位回调渲染，桌面同链路）；
	# 拍卖可能被 AI 竞速抢先定庄，按引擎实际主牌校验槽位牌面
	await tree.create_timer(0.3).timeout
	var slot_trump := false
	var trump: TrumpInfo = table.engine.trump
	for c in bar._slot.get_children():
		if c is CardWidget and c.card != null and trump != null \
				and c.card.suit == trump.suit and c.card.rank == trump.rank:
			slot_trump = true
	test.check(trump != null and slot_trump, "揭主落位后顶栏主牌槽显示正 R 牌面")
	var heart_count := 0
	for c in table.engine.get_hand(0):
		if table.engine.trump.is_trump(c):
			heart_count += 1
	var bar_main: Label = bar._suit_icons[0]
	test.eq(str(bar_main.text), "♥", "叫主后首位图标为主花色")
	test.check(bar_main.modulate.is_equal_approx(Color(1, 0.9, 0.4)), "主花色图标金色突出")
	test.eq(int((bar._suit_counts[0] as Label).text), heart_count, "主牌数（含王）")
	AppSettings.mobile_ui = false
	await _release_table(table)


## 回归（用户报告）：手机版经设置弹层关闭手机 UI 时，「更多」面板被直接销毁而
## 其全屏拦截遮罩（MorePanelDim）残留桌面——阴影盖住整个 UI、任何点击都无效。
## 分支切换须走面板 close() 清遮罩；本用例走完整真实路径（☰ 开面板 → 面板设置
## 入口 → 设置弹层切换「手机版 UI」→ on_changed 重应用布局）
func test_mobile_mode_off_via_settings_clears_dim(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = await _spawn_table()
	AppSettings.mobile_ui = true  # spawn 后覆写（_spawn_table 强制桌面口径防污染）
	table._apply_layout_mode()
	await tree.process_frame
	var bar: MobileTopBar = table._info.mobile_bar()
	bar.more_pressed.emit()  # ☰ 打开「更多」面板（遮罩 MorePanelDim 随之出现）
	await tree.process_frame
	test.check(table.get_node_or_null("MorePanelDim") != null, "面板打开时遮罩存在")
	# 面板设置入口 → 设置弹层 → 切换「手机版 UI」为关（触发 on_changed → 重应用布局）
	table._info.more_panel().settings_pressed.emit()
	await tree.process_frame
	var dialog: SettingsDialog = tree.root.get_node_or_null("SettingsDialog")
	test.check(dialog != null, "面板设置入口打开设置弹层")
	var mobile_btn: Button = null
	for c in dialog.get_children()[0].get_children():
		if c is Button and "手机版 UI" in (c as Button).text:
			mobile_btn = c
	test.check(mobile_btn != null, "找到「手机版 UI」切换按钮")
	mobile_btn.pressed.emit()
	await tree.process_frame
	# 遮罩随面板 close() 一并清理（旧版残留 → 全屏阴影挡死输入）；桌面信息面就位
	test.check(table.get_node_or_null("MorePanelDim") == null, "切换后遮罩随面板清理（无阴影残留）")
	test.check(table._info.more_panel() == null, "「更多」面板已销毁")
	test.check(table._info.mobile_bar() == null, "手机顶栏已销毁")
	test.check(table.sidebar.visible, "桌面信息栏恢复（后续操作可用）")
	# 设置弹层自身照常可关（完成按钮）
	var done: Button = null
	for c in dialog.get_children()[0].get_children():
		if c is Button and c.text == "完成":
			done = c
	done.pressed.emit()
	await tree.process_frame
	test.check(tree.root.get_node_or_null("SettingsDialog") == null, "设置弹层完成关闭")
	# 再切回手机（二次切换路径同样不残留遮罩）：开面板 → 直接 _apply_layout_mode 切桌面
	AppSettings.mobile_ui = true
	table._apply_layout_mode()
	await tree.process_frame
	table._info.mobile_bar().more_pressed.emit()
	await tree.process_frame
	test.check(table.get_node_or_null("MorePanelDim") != null, "再开面板遮罩恢复")
	AppSettings.mobile_ui = false
	table._apply_layout_mode()
	await tree.process_frame
	test.check(table.get_node_or_null("MorePanelDim") == null, "二次切换遮罩同样清理")
	test.check(table._info.mobile_bar() == null, "二次切换顶栏销毁")
	await _release_table(table)


## 分支未变时 _apply_layout_mode 早退：不重建顶栏/信息面（设置面板其它项变更也
## 走这里）——重建会造成主牌槽闪断与无谓的守卫基线重置
func test_apply_layout_mode_noop_when_mode_unchanged(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = await _spawn_table()
	var info_before = table._info
	table._apply_layout_mode()  # 桌面态重复应用
	test.check(table._info == info_before, "桌面态重复应用不重建信息面")
	AppSettings.mobile_ui = true
	table._apply_layout_mode()
	await tree.process_frame
	var bar: MobileTopBar = table._info.mobile_bar()
	var mobile_info = table._info
	table._apply_layout_mode()  # 手机态重复应用
	test.check(table._info == mobile_info, "手机态重复应用不重建信息面")
	test.check(table._info.mobile_bar() == bar, "顶栏实例保持（未销毁重建）")
	AppSettings.mobile_ui = false
	await _release_table(table)


## 手机分支完整交互链路（发牌动画 → 拍卖 → 叫主 → 扣底 → 出牌）：动画/交互/界面
## 覆盖手机口径——出牌落位按手机锚点组居中，手牌重渲按手机卡尺寸
func test_mobile_play_interaction_flow(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = await _spawn_table()
	table._ai_delay_scale = 1e9  # 挂起 UI AI：本用例直驱全部人类决策
	AppSettings.mobile_ui = true
	table._apply_layout_mode()
	await tree.process_frame
	_deal(table.engine, 0)
	var deadline := Time.get_ticks_msec() + 8000
	while table._deal_active and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	# 拍卖：庄家 0 号位底叫 130 由引擎自动完成，三家过 + 人类过 → 0 号位定庄叫主
	for s in [1, 2, 3]:
		table.engine.submit_bid(s, GameEngine.BID_PASS)
	table.engine.submit_bid(0, GameEngine.BID_PASS)
	table.engine.submit_trump(0, Card.Suit.SPADE, Card.RANK_9)
	await tree.process_frame
	# 扣底（人类）：底牌 8 张入手即预选，直接确认扣回
	test.check(table.hand_area.selected.size() == 8, "底牌入手即预选 8 张")
	table._submit_human_discard()
	await tree.process_frame
	test.check(table.engine.phase == GameEngine.Phase.TRICKS, "扣底后进入出牌阶段")
	# 出牌（人类领出单张）：手机口径下选择/提交照常
	table.hand_area.select_cards([table.engine.get_hand(0)[0]])
	table._submit_human_play()
	await tree.process_frame
	test.check(table.engine.current_plays.size() >= 1, "人类领出已入本轮")
	# 出牌落位在手机锚点带（十字居中，±1 卡高容差）
	var row: Control = null
	for c in table.trick_area.get_children():
		if c.name != "BottomCards" and not c.is_queued_for_deletion() and c.get_child_count() > 0:
			row = c
			break
	test.check(row != null, "出牌区已渲染牌行")
	if row != null:
		var expect: Vector2 = MobileLayout.TRICK_ANCHORS[0] * table.trick_area.size
		test.check(absf(row.position.y + row.size.y / 2.0 - expect.y) < 140.0,
			"出牌落位在手机锚点带（十字居中）")
	# 手牌按手机尺寸重渲（扣 8 出 1 → 18 张）
	var widgets := 0
	for c in table.hand_area.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			widgets += 1
	test.eq(widgets, 18, "手机口径手牌重渲 18 张")
	AppSettings.mobile_ui = false
	await _release_table(table)
