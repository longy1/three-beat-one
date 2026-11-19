class_name InfoSidebar
extends PanelContainer
## 右侧竖直信息栏（独立组件）：手牌统计 + 局面 + 主菜单入口。
## 与牌桌场景解耦，独立呈现信息。


signal menu_pressed
signal settings_pressed  ## 设置入口（牌桌右下信息栏；主菜单另有同款入口）


func _ready() -> void:
	var menu_button: Button = $VBox/MenuButton
	UiStyle.pad_button(menu_button)  # 文字与按钮边框留空 ≥ 半字号（UI 规范）
	menu_button.pressed.connect(func(): menu_pressed.emit())
	var settings_button: Button = $VBox/SettingsButton
	UiStyle.pad_button(settings_button)
	settings_button.pressed.connect(func(): settings_pressed.emit())
	set_trump(null)


## 主牌展示位的全局中心坐标（揭主动画的飞行落点；须在布局完成后测量）
func trump_slot_center() -> Vector2:
	var slot: Control = $VBox/TrumpRow/TrumpStack/TrumpSlot
	return slot.get_global_rect().get_center()


## 主牌展示：一张「正 R」牌面（主花色 + R，如 ♠ 主 R=2 → ♠2）。
## 未叫主：牌背微透明 + 居中问号，下方注明「未叫主」。
func set_trump(card: Card) -> void:
	var slot: Control = $VBox/TrumpRow/TrumpStack/TrumpSlot
	var state_label: Label = $VBox/TrumpRow/TrumpStack/TrumpStateLabel
	for child in slot.get_children():
		child.queue_free()
	if card == null:
		# 未叫主：无字牌背微透明 + 问号（问号颜色与牌背哈字一致）
		var back := CardWidget.create(null, false, true, "")
		back.modulate = Color(1, 1, 1, 0.45)
		slot.add_child(back)
		var q := Label.new()
		# 半角 ?（不用全角 ？）：全角标点的墨迹只占字符格左半，Label 按整格居中会整体偏左
		q.text = "?"
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 24)
		q.modulate = Color(0.72, 0.8, 0.95)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(q)
		state_label.text = "未叫主"
		state_label.modulate = Color(0.75, 0.8, 0.78)
	else:
		slot.modulate = Color.WHITE
		slot.add_child(CardWidget.create(card, true, true))
		state_label.text = ""


## 手牌统计：主牌/副牌行 + 各点数行（rows: [{text, present}]，present=false 灰显）
func update_stats(main_text: String, rows: Array) -> void:
	($VBox/MainLabel as Label).text = main_text
	var grid: GridContainer = $VBox/RankGrid
	for child in grid.get_children():
		child.queue_free()
	for row in rows:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 12)
		l.text = row[0]
		l.modulate = Color(1, 1, 1) if row[1] else Color(1, 1, 1, 0.35)
		grid.add_child(l)


## 局面：闲家捉分与四家累计收益
func set_state(captured: String, cumulative: String) -> void:
	($VBox/CapturedLabel as Label).text = captured
	($VBox/CumulativeLabel as Label).text = cumulative
