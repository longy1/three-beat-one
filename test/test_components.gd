extends RefCounted
## 组件用例：各可复用 UI 组件的功能与关联（AGENTS.md 第 7 章）。
## 组件自带统一尺寸/样式，实例只定位——改组件一处全部生效（规范见第 6 章）。


## CardWidget：正面角标/花色、红黑着色、牌背、翻面
func test_card_widget_face(test) -> void:
	var spade_k := CardWidget.create(Card.new(Card.Suit.SPADE, Card.RANK_K), true)
	var texts: Array[String] = []
	for c in spade_k.get_children():
		if c is Label:
			texts.append(c.text)
	test.check("♠K" in texts, "角标显示花色+点数")
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


## CardWidget：牌背与翻面
func test_card_widget_back(test) -> void:
	var w := CardWidget.create(Card.new(Card.Suit.SPADE, Card.RANK_A), true)
	w.set_face_up(false)
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
	panel.set_highlight(true)
	test.check(panel.modulate.r > 1.0, "高亮态")
	panel.set_highlight(false)
	test.check(panel.modulate == Color.WHITE, "非高亮恢复")
	# 悬停信号携带注入的座位号
	var got := [-1]
	panel.pile_hovered.connect(func(s: int): got[0] = s)
	panel.mouse_entered.emit()
	test.eq(got[0], 3, "悬停信号携带座位号")
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
	# 主牌展示：未叫主态 → 问号+注字；叫主后 → 正 R 牌面
	sb.set_trump(null)
	var stack: VBoxContainer = sb.get_node("VBox/TrumpRow/TrumpStack")
	test.check("未叫主" in stack.get_node("TrumpStateLabel").text, "未叫主注字")
	var slot: Control = stack.get_node("TrumpSlot")
	var has_back := false
	for c in slot.get_children():
		if c is CardWidget and c.card == null:
			has_back = true
	test.check(has_back, "未叫主显示牌背")
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
	var table = load("res://scene/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	test.eq(table.get_node("SeatTop").seat, 2, "丙 = 2")
	test.eq(table.get_node("SeatLeft").seat, 3, "丁 = 3")
	test.eq(table.get_node("SeatRight").seat, 1, "乙 = 1")
	table.queue_free()
	await tree.process_frame
