class_name ReconnectOverlay
extends PanelContainer
## 断线等待重连弹层（M4）：连接失联后全屏微暗遮罩 + 居中面板，自动重连期间
## 展示进度（第 N 次 / 剩余秒数），[立即重连] 触发即时尝试，[返回主菜单] 放弃退出。
## 程序化构建（与 ScoresDialog 同口径：遮罩 + 面板 z_index 60，居中规范，
## 半字号留空 content_margin 15）；生命周期归 NetClient 管理（close 双双释放）。


var _dim: ColorRect
var _status: Label


static func create(parent: Node, on_retry: Callable, on_give_up: Callable) -> ReconnectOverlay:
	var dim := ColorRect.new()
	dim.name = "ReconnectDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var overlay := ReconnectOverlay.new()
	overlay.name = "ReconnectOverlay"
	overlay.z_index = 60
	parent.add_child(overlay)
	overlay._build(on_retry, on_give_up, dim)
	return overlay


func _build(on_retry: Callable, on_give_up: Callable, dim: ColorRect) -> void:
	_dim = dim
	# 锚点按当前场景取（UiStyle.center_anchor）：牌桌内=桌面十字中心，菜单/大厅=屏幕正中
	var center: Vector2 = UiStyle.center_anchor(self)
	anchor_left = center.x
	anchor_right = center.x
	anchor_top = center.y
	anchor_bottom = center.y
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
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)

	var title := Label.new()
	title.text = "与服务器的连接已断开"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	box.add_child(title)

	_status = Label.new()
	_status.text = "正在重连……"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 0)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	box.add_child(_status)

	var hint := Label.new()
	hint.text = "房间将为你保留，掉线回合由电脑代打"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var retry := Button.new()
	retry.text = "立即重连"
	retry.custom_minimum_size = Vector2(140, 42)
	retry.add_theme_font_size_override("font_size", 16)
	UiStyle.pad_button(retry)
	retry.pressed.connect(on_retry)
	row.add_child(retry)
	var give_up := Button.new()
	give_up.text = "返回主菜单"
	give_up.custom_minimum_size = Vector2(140, 42)
	give_up.add_theme_font_size_override("font_size", 16)
	UiStyle.pad_button(give_up)
	give_up.pressed.connect(on_give_up)
	row.add_child(give_up)


## 进度文案（由 NetClient 每次重试时刷新）
func set_status(text: String) -> void:
	_status.text = text


## 关闭：遮罩与面板一并释放（成功回房 / 放弃 / 超时出口共用）
func close() -> void:
	if _dim != null and is_instance_valid(_dim):
		_dim.queue_free()
		_dim = null
	queue_free()
