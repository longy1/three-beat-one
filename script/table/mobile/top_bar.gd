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
var _suit_icons: Array = []  ## 花色图标 Label ×4（与 set_suit_stats 条目对齐）
var _suit_counts: Array = []  ## 花色数字 Label ×4
var _more: Button


func _ready() -> void:
	# 全宽 bar（父=牌桌根）：右锚子件（「更多」按钮）基于此宽度定位
	anchor_right = 1.0
	offset_bottom = MobileLayout.BAR_HEIGHT
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
	_info.size = Vector2(268, 56)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.85, 0.9, 0.87))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)

	_slot = Control.new()
	_slot.custom_minimum_size = SLOT_SIZE
	_slot.size = SLOT_SIZE
	_slot.position = Vector2(296, 3)
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot)
	set_trump(null)

	_captured = Label.new()
	_captured.position = Vector2(344, 0)
	_captured.size = Vector2(96, 56)
	_captured.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_captured.add_theme_font_size_override("font_size", 14)
	_captured.add_theme_color_override("font_color", Color(0.91, 0.94, 0.92))
	_captured.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_captured)

	# 手牌统计（图标+数字 ×4，恒 4 组）：未叫主=四门花色数；叫主后=主牌数（金色
	# 图标）+ 三门副花色数——王计入主牌数，与桌面「主 X ｜ 副 ♥a ♣b ♦c」同口径
	var stat_x := 452.0
	for i in 4:
		var icon := Label.new()
		icon.position = Vector2(stat_x + i * 52.0, 0)
		icon.size = Vector2(20, 56)
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 15)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		_suit_icons.append(icon)
		var count := Label.new()
		count.position = Vector2(stat_x + i * 52.0 + 20, 0)
		count.size = Vector2(30, 56)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 15)
		count.add_theme_color_override("font_color", Color(0.85, 0.9, 0.87))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(count)
		_suit_counts.append(count)

	_more = Button.new()
	_more.text = "更多"
	_more.anchor_left = 1.0
	_more.anchor_right = 1.0
	# 右端避让 Web 壳层 ⛶ 全屏按钮（DOM：top 10 / right 10 / 46×38，hitbox
	# x∈[1224,1270]——按钮右缘收到 -64 留出 8px 空隙，防遮挡影响点击）
	_more.offset_left = -116.0
	_more.offset_right = -64.0
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


## 手牌统计（图标+数字 ×4）：entries = [{icon: 花色字符, count: int, main: bool}]——
## main（主牌花色）图标金色突出，红花色亮红、黑花色浅白（深底可读）
func set_suit_stats(entries: Array) -> void:
	for i in 4:
		if i >= entries.size():
			continue
		var icon: Label = _suit_icons[i]
		var count: Label = _suit_counts[i]
		var main: bool = entries[i].get("main", false)
		icon.text = entries[i]["icon"]
		count.text = str(entries[i]["count"])
		if main:
			icon.modulate = Color(1, 0.9, 0.4)  # 主牌花色金色突出
		elif entries[i]["icon"] in ["♥", "♦"]:
			icon.modulate = Color(0.95, 0.45, 0.45)  # 红花色亮红
		else:
			icon.modulate = Color(0.85, 0.9, 0.87)  # 黑花色浅白（深底可读）


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
