extends RefCounted
## 组件用例：各可复用 UI 组件的功能与关联（[码4] 组件复用）。
## 组件自带统一尺寸/样式，实例只定位——改组件一处全部生效（规范见 [码3]）。


## CardWidget：正面角标/花色、红黑着色、牌背、翻面
func test_card_widget_face(test) -> void:
	var spade_k := CardWidget.create(Card.new(Card.Suit.SPADE, Card.RANK_K), true)
	var texts: Array[String] = []
	for c in spade_k.get_children():
		if c is Label:
			texts.append(c.text)
	test.check("K\n♠" in texts, "角标竖排显示点数+花色（点数上、花色下）")
	test.check("♠" in texts, "中心显示花色符号")
	# 黑桃着黑色、红桃着红色（label modulate）
	var black_ok := true
	for c in spade_k.get_children():
		if c is Label and c.modulate.r > 0.5:
			black_ok = false
	test.check(black_ok, "黑桃着黑色")
	var heart := CardWidget.create(Card.new(Card.Suit.HEART, Card.RANK_9), true)
	var heart_red := false
	for c in heart.get_children():
		if c is Label and c.modulate.r > 0.5:
			heart_red = true
	test.check(heart_red, "红桃着红色")
	# 大王着红色（约定）
	var big_joker := CardWidget.create(Card.new(Card.Suit.JOKER, Card.RANK_BIG_JOKER), true)
	var joker_red := false
	for c in big_joker.get_children():
		if c is Label and c.modulate.r > 0.5:
			joker_red = true
	test.check(joker_red, "大王着红色")


## CardWidget：牌背与空牌安全渲染
func test_card_widget_back(test) -> void:
	var w := CardWidget.create(Card.new(Card.Suit.SPADE, Card.RANK_A), false)
	var texts: Array[String] = []
	for c in w.get_children():
		if c is Label:
			texts.append(c.text)
	test.check("哈" in texts, "牌背显示哈字")
	var hidden := CardWidget.create(null, false)  # card=null 也走背面
	var hidden_ok := hidden.get_child_count() > 0
	test.check(hidden_ok, "null 牌安全渲染背面")


## SeatPanel：统一尺寸、信息更新、悬停信号携带座位号
func test_seat_panel_component(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var panel: SeatPanel = load("res://scene/seat_panel.tscn").instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	# 组件自带统一尺寸（规范：实例只定位）
	test.eq(panel.custom_minimum_size, Vector2(180, 100), "组件自带 180×100")
	panel.setup(3)
	panel.set_info("丁（电脑）", "17 张", "叫 135")
	test.eq(panel.get_node("VBox/NameLabel").text, "丁（电脑）", "姓名更新")
	test.eq(panel.get_node("VBox/CountLabel").text, "17 张", "牌数更新")
	test.eq(panel.get_node("VBox/StatusLabel").text, "叫 135", "状态更新")
	# 行动指示：淡金色边框（不改透明度）
	panel.set_highlight(true)
	var hl: StyleBox = panel.get_theme_stylebox("panel")
	test.check(hl is StyleBoxFlat and (hl as StyleBoxFlat).border_color.r > 0.9
		and (hl as StyleBoxFlat).border_width_left >= 2, "高亮 = 淡金边框")
	test.check(panel.modulate == Color.WHITE, "高亮不改变透明度")
	panel.set_highlight(false)
	var normal: StyleBox = panel.get_theme_stylebox("panel")
	test.check(normal is StyleBoxFlat and (normal as StyleBoxFlat).border_width_left < 2, "非高亮恢复常规边")
	panel.queue_free()
	await tree.process_frame


## InfoSidebar：统计行（含灰显）、局面、主牌展示、菜单信号
func test_info_sidebar_component(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var sb: InfoSidebar = load("res://scene/info_sidebar.tscn").instantiate()
	tree.root.add_child(sb)
	await tree.process_frame
	sb.update_stats("主 3 ｜ 副 ♥2 ♣1", [["5×1", true], ["大王×0", false]])
	test.eq(sb.get_node("VBox/MainLabel").text, "主 3 ｜ 副 ♥2 ♣1", "主副行更新")
	var grid: GridContainer = sb.get_node("VBox/RankGrid")
	test.eq(grid.get_child_count(), 2, "点数行数")
	test.check(grid.get_child(0).modulate.a > 0.9, "有牌行正常显示")
	test.check(grid.get_child(1).modulate.a < 0.6, "无牌行灰显")
	sb.set_state("闲家捉分 45", "累计：甲 +3")
	test.eq(sb.get_node("VBox/CapturedLabel").text, "闲家捉分 45", "捉分行")
	test.eq(sb.get_node("VBox/CumulativeLabel").text, "累计：甲 +3", "累计行")
	# 主牌展示：未叫主态 → 无字牌背微透明+问号（无哈字）；叫主后 → 正 R 牌面
	sb.set_trump(null)
	var stack: VBoxContainer = sb.get_node("VBox/TrumpRow/TrumpStack")
	test.check("未叫主" in stack.get_node("TrumpStateLabel").text, "未叫主注字")
	var slot: Control = stack.get_node("TrumpSlot")
	var has_back := false
	var has_question := false
	var has_ha_mark := false
	for c in slot.get_children():
		if c is CardWidget and c.card == null:
			has_back = true
		if c is Label:
			if c.text == "?":
				has_question = true
			if c.text == "哈":
				has_ha_mark = true
	test.check(has_back, "未叫主显示无字牌背")
	test.check(has_question and not has_ha_mark, "问号展示且无哈字")
	test.check(has_question and has_back and slot.get_child_count() >= 2, "问号叠于牌背")
	sb.set_trump(Card.new(Card.Suit.SPADE, Card.RANK_9))
	var has_trump := false
	for c in slot.get_children():
		if c is CardWidget and c.card != null and c.card.rank == Card.RANK_9:
			has_trump = true
	test.check(has_trump, "叫主后显示正 R 牌面")
	# 菜单信号
	var menu_pressed := [false]
	sb.menu_pressed.connect(func(): menu_pressed[0] = true)
	sb.get_node("VBox/MenuButton").pressed.emit()
	test.check(menu_pressed[0], "主菜单信号转发")
	sb.queue_free()
	await tree.process_frame


## UiStyle：按钮四向内边距 = 字号/2（半字号留空规范）
func test_ui_style_button_padding(test) -> void:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 18)
	UiStyle.pad_button(b)
	var sb: StyleBox = b.get_theme_stylebox("normal")
	test.eq(sb.content_margin_left, 9.0, "左留空 = 半字号")
	test.eq(sb.content_margin_top, 9.0, "上留空 = 半字号")
	test.eq(sb.content_margin_right, 9.0, "右留空 = 半字号")
	test.eq(sb.content_margin_bottom, 9.0, "下留空 = 半字号")
	b.free()


## 程序化绘制组件：设置尺寸后绘制流程不崩
func test_drawn_components(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var crown := CrownBadge.new()
	crown.size = Vector2(24, 18)
	tree.root.add_child(crown)
	var frame := DashedRoundedFrame.new()
	frame.size = Vector2(100, 80)
	tree.root.add_child(frame)
	var tiny := DashedRoundedFrame.new()
	tiny.size = Vector2(4, 4)  # 小于 2× 圆角半径，_draw 早退分支
	tree.root.add_child(tiny)
	await tree.process_frame
	test.eq(crown.size, Vector2(24, 18), "皇冠尺寸")
	test.check(frame.corner_radius > 0, "虚线框圆角参数")
	crown.queue_free()
	frame.queue_free()
	tiny.queue_free()
	await tree.process_frame


## 关联：牌桌控制器中三块 SeatPanel 实例的座位号注入正确
func test_table_seat_wiring(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var table = load("res://scene/table/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	test.eq(table.get_node("SeatTop").seat, 2, "丙 = 2")
	test.eq(table.get_node("SeatLeft").seat, 3, "丁 = 3")
	test.eq(table.get_node("SeatRight").seat, 1, "乙 = 1")
	table.queue_free()
	await tree.process_frame


## VoidStamp：【无主】印章默认隐藏，set_void_trump 点亮；SeatPanel 集成锚定右下角
## 回归（用户报告）：印章曾是 PanelContainer 直接子件，容器整面填充布局
## 会把 position 重置回内容区原点——印章被拽到左上角压住姓名。修复用 top_level 脱离布局树
func test_void_stamp_component(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var panel: SeatPanel = load("res://scene/seat_panel.tscn").instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	var stamp: VoidStamp = panel.get_node("VoidStamp")
	test.check(stamp != null, "面板自带无主印章子节点")
	test.check(not stamp.visible, "印章默认隐藏")
	test.check(stamp.top_level, "印章 top_level 脱离容器布局树（回归：曾遭 PanelContainer 整面布局拽位）")
	panel.set_info("丁（电脑）", "3 张", "")
	panel.set_void_trump(true)
	test.check(stamp.visible, "公示后印章显示")
	await tree.process_frame
	await tree.process_frame  # 容器排序后再断言（布局曾把印章拽回左上角）
	var expected: Vector2 = panel.global_position + panel.size \
		- VoidStamp.STAMP_SIZE - Vector2(SeatPanel.STAMP_MARGIN, SeatPanel.STAMP_MARGIN)
	test.check(stamp.position.distance_to(expected) < 4.0,
		"印章锚定面板右下角（期望 %s，实际 %s）" % [expected, stamp.position])
	panel.queue_free()
	# 独立实例绘制不崩（headless 下 _draw 早退/正常均不得报错）
	var solo := VoidStamp.new()
	tree.root.add_child(solo)
	await tree.process_frame
	solo.visible = true
	await tree.process_frame
	test.check(solo.visible, "独立印章可显示")
	solo.queue_free()


## HandArea：同模式连续轮次保留选择、模式切换清空、consume_selected 移除已打出
func test_hand_area_selection_retention(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var ha := HandArea.new()
	tree.root.add_child(ha)
	ha.size = Vector2(1000, 160)
	await tree.process_frame
	var hand := [Card.new(Card.Suit.SPADE, Card.RANK_A, 0), Card.new(Card.Suit.HEART, Card.RANK_7, 0), Card.new(Card.Suit.CLUB, Card.RANK_8, 0)]
	var trump_info := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	ha.render(hand, trump_info)
	await tree.process_frame
	ha.begin_select("play")
	ha._toggle_select(hand[0])
	ha._toggle_select(hand[1])
	test.eq(ha.selected.size(), 2, "选中 2 张")
	ha.begin_select("play")  # 新一轮同模式：不重置（选牌跨轮保留需求）
	test.eq(ha.selected.size(), 2, "同模式续轮保留选择")
	ha.consume_selected([hand[0]])  # 打出 ♠A
	test.eq(ha.selected.size(), 1, "已打出的牌从选择移除")
	test.check(ha.selected.has(hand[1]), "未打出的选择保留")
	ha.begin_select("discard")  # 模式切换：清空
	test.eq(ha.selected.size(), 0, "切换模式清空选择")
	ha.queue_free()


## HandArea：编程式 select_cards（扣底 8 张封顶）——底牌入手即选中的组件基础
func test_hand_area_select_cards_cap(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var ha := HandArea.new()
	tree.root.add_child(ha)
	ha.size = Vector2(1100, 160)
	await tree.process_frame
	var hand: Array = []
	for r in [Card.RANK_5, Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10, Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A]:
		hand.append(Card.new(Card.Suit.HEART, r, 0))
	hand.append(Card.new(Card.Suit.CLUB, Card.RANK_5, 0))
	ha.render(hand, null)
	await tree.process_frame
	ha.begin_select("discard")
	ha.select_cards(hand.slice(0, 9))  # 传 9 张，封顶 8
	test.eq(ha.selected.size(), 8, "扣底模式选牌封顶 8 张")
	ha.begin_select("play")
	ha.select_cards(hand)
	test.eq(ha.selected.size(), 10, "出牌模式无封顶")
	ha.queue_free()


## HandArea：主牌区牌力并列的副 R 按花色分组相邻（♠→♥→♣→♦）
func test_hand_area_trump_side_suit_grouping(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var ha := HandArea.new()
	tree.root.add_child(ha)
	ha.size = Vector2(1100, 160)
	await tree.process_frame
	var trump_info := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)
	var hand := [
		Card.new(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), Card.new(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0),
		Card.new(Card.Suit.SPADE, Card.RANK_9, 0),
		Card.new(Card.Suit.DIAMOND, Card.RANK_9, 1), Card.new(Card.Suit.CLUB, Card.RANK_9, 0),
		Card.new(Card.Suit.HEART, Card.RANK_9, 1), Card.new(Card.Suit.CLUB, Card.RANK_9, 1),
		Card.new(Card.Suit.HEART, Card.RANK_9, 0), Card.new(Card.Suit.DIAMOND, Card.RANK_9, 0),
		Card.new(Card.Suit.SPADE, Card.RANK_2, 0),
	]
	ha.render(hand, trump_info)
	await tree.process_frame
	var labels: Array[String] = []
	for c in ha.get_children():
		if c is CardWidget and not c.is_queued_for_deletion():
			labels.append(c.card.label())
	test.eq(labels, ["大王", "小王", "♠9", "♥9", "♥9", "♣9", "♣9", "♦9", "♦9", "♠2"],
		"副R 同花色相邻（♥♥♣♣♦♦），正R/正2 按牌力各归其位")
	ha.queue_free()


## 回归（用户报告「牌不在手中」整局卡死）：快速出牌+马上连打的渲染
## 竞争可在 selected 留下已打出牌的陈旧引用，此后所有提交都被引擎 NOT_IN_HAND 拒绝。
## 修复：render 以当前权威手牌为准自动剪除陈旧引用（结构性自愈，不依赖复现竞态）
func test_hand_area_render_prunes_stale_selection(test) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var ha := HandArea.new()
	tree.root.add_child(ha)
	ha.size = Vector2(1000, 160)
	await tree.process_frame
	var kept := Card.new(Card.Suit.HEART, Card.RANK_7, 0)   # 仍在手
	var played := Card.new(Card.Suit.SPADE, Card.RANK_A, 0)  # 已打出（引擎已移出）
	var hand := [kept, played]
	ha.render(hand, null)
	await tree.process_frame
	ha.begin_select("play")
	ha._toggle_select(kept)
	ha._toggle_select(played)
	test.eq(ha.selected.size(), 2, "两张均选中（含即将打出的牌）")
	# 引擎侧 ♠A 已被移出手牌 → 新一帧渲染以权威手牌为准
	hand.erase(played)
	ha.render(hand, null)
	await tree.process_frame
	test.eq(ha.selected.size(), 1, "陈旧引用（已打出的牌）被渲染剪除")
	test.check(ha.selected.has(kept), "保留仍在手中的选中")
	ha.queue_free()
