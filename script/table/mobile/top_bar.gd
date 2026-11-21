class_name MobileTopBar
extends Control
## 手机版顶栏（当局信息 bar）：局况（庄/叫分）+ 主牌小牌面（揭主飞牌落点）+
## 捉分 + 「更多」按钮（打开 MorePanel：局数/累计/手牌统计/设置/菜单）。
## 仅移动分支使用，程序化构建；状态驱动——由控制器 _refresh 喂（[码1.4]）。

signal more_pressed

const SLOT_SIZE := CardWidget.SIZE_BAR  ## 主牌槽（36×50，CARD 第四档）

var _info: Label
var _captured: Label
var _slot: Control
var _more: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.12, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var sep := ColorRect.new()
	sep.color = Color(0.17, 0.29, 0.22)
	sep.anchor_left = 0.0
	sep.anchor_right = 1.0
	sep.anchor_top = 1.0
	sep.anchor_bottom = 1.0
	sep.offset_top = -1.0
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)

	_info = Label.new()
	_info.position = Vector2(16, 0)
	_info.size = Vector2(280, 56)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.85, 0.9, 0.87))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)

	_slot = Control.new()
	_slot.custom_minimum_size = SLOT_SIZE
	_slot.size = SLOT_SIZE
	_slot.position = Vector2(304, 3)
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot)
	set_trump(null)

	_captured = Label.new()
	_captured.position = Vector2(356, 0)
	_captured.size = Vector2(160, 56)
	_captured.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_captured.add_theme_font_size_override("font_size", 14)
	_captured.add_theme_color_override("font_color", Color(0.91, 0.94, 0.92))
	_captured.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_captured)

	_more = Button.new()
	_more.text = "更多"
	_more.anchor_left = 1.0
	_more.anchor_right = 1.0
	_more.offset_left = -92.0
	_more.offset_right = -44.0  # 右端给 Web 壳层 DOM 全屏按钮留位
	_more.offset_top = 8.0
	_more.offset_bottom = 48.0
	_more.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(_more)
	_more.pressed.connect(func(): more_pressed.emit())
	add_child(_more)


## 局况行：拍卖期显示叫分进程，此后显示出牌庄与叫分
func set_game_info(text: String) -> void:
	_info.text = text


## 闲家捉分（当局进行值）
func set_captured(text: String) -> void:
	_captured.text = text


## 主牌展示（语义与 InfoSidebar.set_trump 一致）：null = 未叫主占位（微透明牌背+问号）
func set_trump(card: Card) -> void:
	for child in _slot.get_children():
		child.queue_free()
	if card == null:
		var back := CardWidget.create_sized(null, false, SLOT_SIZE)
		back.modulate = Color(1, 1, 1, 0.45)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot.add_child(back)
		var q := Label.new()
		q.text = "?"
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 18)
		q.modulate = Color(0.72, 0.8, 0.95)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot.add_child(q)
	else:
		var w := CardWidget.create_sized(card, true, SLOT_SIZE)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot.add_child(w)


## 主牌槽全局中心（揭主飞牌落点；须在布局完成后测量）
func trump_slot_center() -> Vector2:
	return _slot.get_global_rect().get_center()
