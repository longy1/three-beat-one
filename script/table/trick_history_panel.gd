class_name TrickHistoryPanel
extends RefCounted
## 出牌历史面板：点击【历史】打开，居中弹层以十字形展示
## 一轮四家出牌（与牌桌出牌摆位同构、窗口更小，赢家 ✓ 金标）。
## 中央下方 【<<】【<】【>】【>>】 翻第一页/上一页/下一页/最后一轮；
## 右上角 ✕ 或点击窗口外（全屏微暗遮罩）关闭。
## 打开期间新轮次结算由控制器经 refresh() 状态驱动收敛页码（非定时轮询）。
## 数据由控制器注入（open/refresh），组件不持有引擎引用。

const CARD_SIZE := CardWidget.SIZE_SMALL  ## 52×76
const CROSS_AREA := Vector2(520, 280)     ## 十字摆位区尺寸（弹层内容主体）
const NAME_FONT := 13                     ## 座位名字号（赢家 ✓ 金标同款）
## 弹层内十字摆位（相对比例 × 十字区尺寸）：你=下、丙=上、乙=右、丁=左，
## 与牌桌 TRICK_ANCHORS 的座位方位同构（弹层更小，比例重新分布留出边距）
const CROSS_ANCHORS := {
	0: Vector2(0.5, 0.76),
	1: Vector2(0.8, 0.47),
	2: Vector2(0.5, 0.2),
	3: Vector2(0.2, 0.47),
}

var popup: PanelContainer
var backdrop: ColorRect           ## 全屏微暗遮罩：点击窗口外任意处关闭
var cross_area: Control
var page_label: Label
var close_button: Button
var _btn_first: Button
var _btn_prev: Button
var _btn_next: Button
var _btn_last: Button
var _history: Array = []
var _seat_names: Array = []
var _page := 0                    ## 当前轮次页（0 = 第 1 轮 … size-1 = 最后一轮；打开时定位最后一轮）


func setup(root: Control) -> void:
	# 全屏遮罩：透明拦截点击（MOUSE_FILTER_STOP 不依赖可见色），点击即关；
	# z_index=10：盖过桌面级浮层（如扣底阶段的底牌展示 z=1），见 game_table 层级约定
	backdrop = ColorRect.new()
	backdrop.name = "HistoryBackdrop"
	backdrop.color = Color(0, 0, 0, 0.12)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	backdrop.z_index = 10
	backdrop.gui_input.connect(_on_backdrop_input)
	root.add_child(backdrop)
	# 弹层本体：点锚主牌桌十字中心 + grow BOTH（居中规范，与各弹层同口径）
	popup = PanelContainer.new()
	popup.name = "TrickHistoryPopup"
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.z_index = 10
	popup.anchor_left = UiStyle.MAIN_TABLE_CENTER.x
	popup.anchor_right = UiStyle.MAIN_TABLE_CENTER.x
	popup.anchor_top = UiStyle.MAIN_TABLE_CENTER.y
	popup.anchor_bottom = UiStyle.MAIN_TABLE_CENTER.y
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	# 半字号留空（§7）：面板最大字号 16 → content margin 8；底色沿用主题面板样式
	var sb: StyleBox = popup.get_theme_stylebox("panel").duplicate()
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	popup.add_theme_stylebox_override("panel", sb)
	root.add_child(popup)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	popup.add_child(vbox)
	var header := HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "出牌历史"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "✕"
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.custom_minimum_size = Vector2(26, 26)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	cross_area = Control.new()
	cross_area.name = "CrossArea"
	cross_area.custom_minimum_size = CROSS_AREA
	cross_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cross_area)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)
	_btn_first = _nav_button(footer, "<<", _go_first)
	_btn_prev = _nav_button(footer, "<", _go_prev)
	_btn_next = _nav_button(footer, ">", _go_next)
	_btn_last = _nav_button(footer, ">>", _go_last)
	page_label = Label.new()
	page_label.name = "PageLabel"
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(page_label)


## 打开：定位到最后一轮（无历史时展示空态）
func open(trick_history: Array, seat_names: Array) -> void:
	_history = trick_history
	_seat_names = seat_names
	_page = maxi(_history.size() - 1, 0)
	_render()
	backdrop.visible = true
	popup.visible = true


## 关闭（✕ / 点击窗口外）
func close() -> void:
	popup.visible = false
	backdrop.visible = false


func is_open() -> bool:
	return popup.visible


## 打开期间有新轮次结算 → 就地重渲染当前页（页码收敛到合法范围）；关闭后无效
func refresh(trick_history: Array) -> void:
	if not popup.visible:
		return
	_history = trick_history
	_page = clampi(_page, 0, maxi(_history.size() - 1, 0))
	_render()


func _go_first() -> void:
	_page = 0
	_render()


func _go_prev() -> void:
	_page = maxi(_page - 1, 0)
	_render()


func _go_next() -> void:
	_page = mini(_page + 1, maxi(_history.size() - 1, 0))
	_render()


func _go_last() -> void:
	_page = maxi(_history.size() - 1, 0)
	_render()


func _nav_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(b)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 渲染当前轮次：十字摆位四家出牌（赢家 ✓ 金标），页码与导航可用态
func _render() -> void:
	for child in cross_area.get_children():
		child.queue_free()
	var n := _history.size()
	if n == 0:
		page_label.text = "暂无出牌记录"
		_update_nav()
		return
	var th: Dictionary = _history[_page]
	for play in th.plays:
		var seat: int = play.seat
		var group := VBoxContainer.new()
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_theme_constant_override("separation", 2)
		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var is_winner: bool = th.winner == seat
		name_label.text = ("✓ " if is_winner else "") + str(_seat_names[seat])
		name_label.add_theme_font_size_override("font_size", NAME_FONT)
		name_label.modulate = Color(1, 0.85, 0.3) if is_winner else Color(0.85, 0.9, 0.95)
		group.add_child(name_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in play.cards:
			row.add_child(CardWidget.create_sized(c, true, CARD_SIZE))
		group.add_child(row)
		cross_area.add_child(group)
		# 十字摆位：锚点 × 十字区尺寸，按内容估算尺寸居中回退
		#（与牌桌 _refresh_trick_area 同口径：不等待布局帧，按常量估算）
		var base: Vector2 = CROSS_ANCHORS[seat] * CROSS_AREA
		var est_w: float = maxf(play.cards.size() * (CARD_SIZE.x + 4.0), 80.0)
		var est_h: float = 20.0 + CARD_SIZE.y
		group.position = base - Vector2(est_w / 2.0, est_h / 2.0)
	_update_nav()


## 页码文案与四按钮边界禁用态（首/末页对应按钮不可用）
func _update_nav() -> void:
	if _history.size() > 0:
		page_label.text = "第 %d / %d 轮" % [_page + 1, _history.size()]
	else:
		page_label.text = "暂无出牌记录"
	_btn_first.disabled = _page <= 0
	_btn_prev.disabled = _page <= 0
	_btn_next.disabled = _page >= _history.size() - 1
	_btn_last.disabled = _page >= _history.size() - 1
