class_name ScoresDialog
extends PanelContainer
## 房间累计分数弹层（M4）：有成员退出/掉线/主动离开时展示本房间累计分，
## [确定] → 回主菜单。居中规范：UiStyle.MAIN_TABLE_CENTER 点锚 + grow BOTH，
## 程序化构建（一次性弹层，容器在代码，遵循「内容在脚本」边界）。
## 半字号留空：面板 content_margin 15（最大字号 24 的一半 12 的惯例上限，与 ResultPanel 同口径）。


static func create(parent: Node, rows: Array, my_name: String, reason: String, on_ok: Callable) -> ScoresDialog:
	## 全屏微暗遮罩（拦截点击）+ 居中面板；确定后两者一并释放再回调
	var dim := ColorRect.new()
	dim.name = "ScoresDialogDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var dialog := ScoresDialog.new()
	dialog.name = "ScoresDialog"
	dialog.z_index = 60
	parent.add_child(dialog)
	dialog._build(rows, my_name, reason, func():
		dim.queue_free()
		dialog.queue_free()
		on_ok.call())
	return dialog


func _build(rows: Array, my_name: String, reason: String, on_ok: Callable) -> void:
	# 锚点按当前场景取（UiStyle.center_anchor）：牌桌内=桌面十字中心，菜单/大厅=屏幕正中
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
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)

	var title := Label.new()
	title.text = "房间累计分数"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	box.add_child(title)

	var reason_label := Label.new()
	reason_label.text = reason
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(360, 0)
	reason_label.add_theme_font_size_override("font_size", 14)
	reason_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	box.add_child(reason_label)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "本房间还没有对局记录"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 16)
		box.add_child(empty)
	for row in rows:
		var line := Label.new()
		var display: String = str(row.name)
		if display == my_name:
			display += "（你）"
		line.text = "%s：%+d 分（%d 局）" % [display, int(row.score), int(row.games)]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 16)
		box.add_child(line)

	var ok_button := Button.new()
	ok_button.text = "确定"
	ok_button.custom_minimum_size = Vector2(120, 40)
	ok_button.add_theme_font_size_override("font_size", 18)
	UiStyle.pad_button(ok_button)
	ok_button.pressed.connect(on_ok)
	var center := CenterContainer.new()
	center.add_child(ok_button)
	box.add_child(center)
