class_name SettingsDialog
extends PanelContainer
## 游戏设置弹层：手牌区主牌框位置（左/右）、牌点数排序方向（从大到小/从小到大）、
## 手机版 UI（调试，关/开）。各项均为循环切换按钮（点按翻转并即时保存生效，
## AppSettings 单一事实源）；on_changed 在每次变更时回调（牌桌据此重应用布局与
## 重渲手牌）。程序化构建（与 ScoresDialog 同口径：遮罩 + 居中锚点
## UiStyle.center_anchor + 面板 z_index 60 + content_margin 15）。【完成】关闭。
## 主菜单设置入口与牌桌右下信息栏设置入口共用本弹层。


var _changed: Callable
var _main_button: Button
var _order_button: Button
var _mobile_button: Button


static func create(parent: Node, on_changed: Callable) -> SettingsDialog:
	var dim := ColorRect.new()
	dim.name = "SettingsDialogDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var dialog := SettingsDialog.new()
	dialog.name = "SettingsDialog"
	dialog.z_index = 60
	parent.add_child(dialog)
	dialog._build(func():
		dim.queue_free()
		dialog.queue_free())
	dialog._changed = on_changed
	return dialog


func _build(on_close: Callable) -> void:
	var anchor_pt: Vector2 = UiStyle.center_anchor(self)
	anchor_left = anchor_pt.x
	anchor_right = anchor_pt.x
	anchor_top = anchor_pt.y
	anchor_bottom = anchor_pt.y
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.24, 0.17)
	style.set_corner_radius_all(10)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(380, 0)
	add_child(box)

	var title := Label.new()
	title.text = "游戏设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	box.add_child(title)

	# 手牌区主牌框位置：左 ⇄ 右
	_main_button = _row_button(box, "手牌区主牌", _main_text())
	_main_button.pressed.connect(func():
		AppSettings.main_side = AppSettings.MainSide.RIGHT \
			if AppSettings.main_side == AppSettings.MainSide.LEFT else AppSettings.MainSide.LEFT
		_apply_change(_main_button, _main_text()))
	# 牌点数排序方向：从大到小 ⇄ 从小到大
	_order_button = _row_button(box, "牌点数排序", _order_text())
	_order_button.pressed.connect(func():
		AppSettings.sort_order = AppSettings.SortOrder.SMALL_FIRST \
			if AppSettings.sort_order == AppSettings.SortOrder.BIG_FIRST else AppSettings.SortOrder.BIG_FIRST
		_apply_change(_order_button, _order_text()))
	# 手机版 UI（调试）：关 ⇄ 开（移动端设备自动生效；PC 经此调试入口强制开启验证）
	_mobile_button = _row_button(box, "手机版 UI", _mobile_text())
	_mobile_button.pressed.connect(func():
		AppSettings.mobile_ui = not AppSettings.mobile_ui
		_apply_change(_mobile_button, _mobile_text()))

	var done := Button.new()
	done.text = "完成"
	done.custom_minimum_size = Vector2(120, 40)
	done.add_theme_font_size_override("font_size", 18)
	UiStyle.pad_button(done)
	done.pressed.connect(on_close)
	var center := CenterContainer.new()
	center.add_child(done)
	box.add_child(center)


func _row_button(box: VBoxContainer, label: String, value_text: String) -> Button:
	var b := Button.new()
	b.text = "%s：%s（点按切换）" % [label, value_text]
	b.custom_minimum_size = Vector2(360, 44)
	b.add_theme_font_size_override("font_size", 16)
	UiStyle.pad_button(b)
	box.add_child(b)
	return b


func _apply_change(button: Button, value_text: String) -> void:
	AppSettings.save_settings()
	button.text = button.text.get_slice("：", 0) + "：" + value_text + "（点按切换）"
	if _changed.is_valid():
		_changed.call()


func _main_text() -> String:
	return "在左" if AppSettings.main_side == AppSettings.MainSide.LEFT else "在右"


func _order_text() -> String:
	return "从大到小" if AppSettings.sort_order == AppSettings.SortOrder.BIG_FIRST else "从小到大"


func _mobile_text() -> String:
	return "开" if AppSettings.mobile_ui else "关"
