class_name InfoSidebar
extends PanelContainer
## 右侧竖直信息栏（独立组件）：手牌统计 + 局面 + 主菜单入口。
## 与牌桌场景解耦，独立呈现信息。


signal menu_pressed


func _ready() -> void:
	var menu_button: Button = $VBox/MenuButton
	UiStyle.pad_button(menu_button)  # 文字与按钮边框留空 ≥ 半字号（UI 规范）
	menu_button.pressed.connect(func(): menu_pressed.emit())


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
