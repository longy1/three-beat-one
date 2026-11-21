class_name MobileMorePanel
extends Control
## 手机版「更多」面板（☰ 打开）：局数、四家累计、手牌统计、设置/主菜单入口。
## 居中弹层（全屏遮罩 + 面板，ScoresDialog/SettingsDialog 口径；点窗外/✕ 关闭）。
## 仅移动分支使用；状态驱动——打开期间由控制器 _refresh 喂（update_stats/set_state）。

signal settings_pressed
signal menu_pressed
signal closed  ## 面板已关闭（点窗外/✕；控制器清引用）

var _round_label: Label
var _cumulative_label: Label
var _stats_main: Label
var _stats_grid: GridContainer


## 构建遮罩 + 居中面板并挂到 parent（控制器随后喂数据）；callers 接两个入口信号
static func create(parent: Control, on_settings: Callable, on_menu: Callable) -> MobileMorePanel:
	var dim := ColorRect.new()
	dim.name = "MorePanelDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var panel := MobileMorePanel.new()
	panel.name = "MobileMorePanel"
	panel.z_index = 55
	parent.add_child(panel)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			panel.close())
	panel._build(on_settings, on_menu)
	return panel


func _build(on_settings: Callable, on_menu: Callable) -> void:
	# 屏幕正中点锚（移动端不偏桌面十字）
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.17, 0.12)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.91, 0.72, 0.29)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(380, 0)
	add_child(box)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "更多"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 32)
	close_btn.add_theme_font_size_override("font_size", 15)
	UiStyle.pad_button(close_btn)
	close_btn.pressed.connect(func(): close())
	title_row.add_child(close_btn)
	box.add_child(title_row)

	_round_label = Label.new()
	_round_label.add_theme_font_size_override("font_size", 13)
	_round_label.add_theme_color_override("font_color", Color(0.6, 0.71, 0.65))
	box.add_child(_round_label)

	_cumulative_label = Label.new()
	_cumulative_label.add_theme_font_size_override("font_size", 13)
	_cumulative_label.add_theme_color_override("font_color", Color(0.78, 0.85, 0.8))
	box.add_child(_cumulative_label)

	var line1 := ColorRect.new()
	line1.color = Color(0.17, 0.29, 0.22)
	line1.custom_minimum_size = Vector2(0, 1)
	box.add_child(line1)

	var stats_head := Label.new()
	stats_head.text = "手牌统计"
	stats_head.add_theme_font_size_override("font_size", 13)
	stats_head.add_theme_color_override("font_color", Color(0.6, 0.71, 0.65))
	box.add_child(stats_head)
	_stats_main = Label.new()
	_stats_main.add_theme_font_size_override("font_size", 14)
	_stats_main.add_theme_color_override("font_color", Color(0.91, 0.94, 0.92))
	box.add_child(_stats_main)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 1
	box.add_child(_stats_grid)

	var line2 := ColorRect.new()
	line2.color = Color(0.17, 0.29, 0.22)
	line2.custom_minimum_size = Vector2(0, 1)
	box.add_child(line2)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var settings := Button.new()
	settings.text = "设置"
	settings.custom_minimum_size = Vector2(150, 44)
	settings.add_theme_font_size_override("font_size", 15)
	UiStyle.pad_button(settings)
	settings.pressed.connect(func(): settings_pressed.emit())
	buttons.add_child(settings)
	var menu := Button.new()
	menu.text = "返回主菜单"
	menu.custom_minimum_size = Vector2(150, 44)
	menu.add_theme_font_size_override("font_size", 15)
	UiStyle.pad_button(menu)
	menu.pressed.connect(func(): menu_pressed.emit())
	buttons.add_child(menu)
	box.add_child(buttons)


func close() -> void:
	closed.emit()
	var dim := get_parent().get_node_or_null("MorePanelDim")
	if dim != null:
		dim.queue_free()
	queue_free()


## 手牌统计（与桌面 InfoSidebar.update_stats 同构：main_text + 点数行 rows）
func update_stats(main_text: String, rows: Array) -> void:
	_stats_main.text = main_text
	for child in _stats_grid.get_children():
		child.queue_free()
	for row in rows:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 12)
		l.text = row[0]
		l.modulate = Color(1, 1, 1) if row[1] else Color(1, 1, 1, 0.35)
		_stats_grid.add_child(l)


## 局数与四家累计（跨局信息，不上顶栏）
func set_state(round_text: String, cumulative_text: String) -> void:
	_round_label.text = round_text
	_cumulative_label.text = cumulative_text
