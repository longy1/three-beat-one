class_name PileViewer
extends RefCounted
## 牌堆查看器（自 game_table.gd 拆出）：人类「历史」按钮、庄家「牌堆」按钮、
## 出牌历史与底牌两个居中弹层，以及 0.35s 延迟隐藏计时器（防移出误隐）。
## 数据由控制器注入（show_history/show_bottom），组件不持有引擎引用。


const HIDE_DELAY := 0.35  ## 移出入口后延迟隐藏秒数（期间重新进入则取消）
const HISTORY_MIN_WIDTH := 300.0  ## 历史弹层最小宽度（容纳 轮次标签 + 4 张小牌）
const HISTORY_MAX_ROWS := 4       ## 可视行数上限：超出走滚动（ScrollContainer 最小高度为 0，不设则整层塌缩只剩标题条）

var hide_timer: Timer
var history_chip: Button        ## 人类玩家出牌历史入口（左下，始终显示）
var bottom_button: Button       ## 庄家是自己时的「牌堆」入口（皇冠下方，悬停看底牌）
var history_popup: PanelContainer
var bottom_popup: PanelContainer
var showing_seat := -1          ## 历史弹层当前展示的座位（-1 = 未展示；悬停期间历史增长时就地刷新用）


func setup(root: Control) -> void:
	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = HIDE_DELAY
	hide_timer.timeout.connect(hide_all)
	root.add_child(hide_timer)
	# 人类玩家出牌历史入口：左下角小按钮（文字「历史」，悬停查看自己的出牌记录）
	history_chip = Button.new()
	history_chip.text = "历史"
	history_chip.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(history_chip)
	history_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	history_chip.offset_left = 12
	history_chip.offset_right = 58
	history_chip.offset_top = -196
	history_chip.offset_bottom = -166
	root.add_child(history_chip)
	# 庄家是自己时的「牌堆」入口：皇冠下方（左下固定），悬停查看底牌堆
	bottom_button = Button.new()
	bottom_button.text = "牌堆"
	bottom_button.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(bottom_button)
	bottom_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_button.offset_left = 70
	bottom_button.offset_right = 122
	bottom_button.offset_top = -100
	bottom_button.offset_bottom = -70
	bottom_button.visible = false
	root.add_child(bottom_button)
	history_popup = _build_popup(root, "PilePopup")
	_build_history_contents()
	bottom_popup = _build_popup(root, "BottomPopup")
	_build_bottom_contents()


## 悬停某座位：按旧→新列出该玩家每轮的出牌（赢轮标 ✓ 高亮）
func show_history(seat: int, trick_history: Array, seat_names: Array) -> void:
	showing_seat = seat
	_fill_history(seat, trick_history, seat_names)
	history_popup.visible = true
	hide_timer.stop()


## 弹层仍可见（鼠标停在面板/弹层上阅读）而历史增长时：就地重建行内容。
## 状态驱动（由 trick_settled → _refresh 调用），非定时轮询；保留滚动位置。
func refresh_history(trick_history: Array, seat_names: Array) -> void:
	if showing_seat < 0 or not history_popup.visible:
		return
	var scroll: ScrollContainer = history_popup.get_node("VBox/Scroll")
	var keep_y: float = scroll.get_v_scroll_bar().value
	_fill_history(showing_seat, trick_history, seat_names)
	# 行重建后容器重新布局，max_value 变化在新布局落地后才生效——延迟恢复滚动位置
	scroll.get_v_scroll_bar().set_value.call_deferred(keep_y)


## 弹层行内容填充（show_history / refresh_history 公共路径）
func _fill_history(seat: int, trick_history: Array, seat_names: Array) -> void:
	var title: Label = history_popup.get_node("VBox/Title")
	title.text = "%s 的出牌（旧 → 新）" % seat_names[seat]
	var list: VBoxContainer = history_popup.get_node("VBox/Scroll/List")
	for child in list.get_children():
		child.queue_free()
	if trick_history.is_empty():
		var empty := Label.new()
		empty.text = "暂无出牌记录"
		empty.add_theme_font_size_override("font_size", 14)
		empty.modulate = Color(0.8, 0.85, 0.9)
		list.add_child(empty)
	var round_no := 0
	var row_count := 0
	for th in trick_history:
		round_no += 1
		for play in th.plays:
			if play.seat != seat:
				continue
			row_count += 1
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var is_winner: bool = th.winner == seat
			var tag := Label.new()
			tag.text = ("✓ " if is_winner else "") + "第%d轮" % round_no
			tag.add_theme_font_size_override("font_size", 13)
			tag.custom_minimum_size = Vector2(70, 0)
			tag.modulate = Color(1, 0.85, 0.3) if is_winner else Color(0.8, 0.85, 0.9)
			row.add_child(tag)
			for c in play.cards:
				row.add_child(CardWidget.create(c, true, true))
			list.add_child(row)
	# 滚动区高度随内容自适应、超上限滚动（回归 2026-11-17：不设则整层塌缩只剩标题条）
	var row_h: float = CardWidget.SIZE_SMALL.y + 4.0
	var scroll: ScrollContainer = history_popup.get_node("VBox/Scroll")
	scroll.custom_minimum_size = Vector2(HISTORY_MIN_WIDTH, minf(float(row_count), float(HISTORY_MAX_ROWS)) * row_h)
	# 显隐与计时器只归 show_history 管——refresh 不得触碰（否则移出后的延迟隐藏会被无限续命）


## 庄家是自己时：悬停「牌堆」按钮查看所扣底牌（2 行 × 4 张，仅自己可见）
func show_bottom(cards: Array) -> void:
	var title: Label = bottom_popup.get_node("VBox/Title")
	title.text = "你的底牌（仅你可见）"
	var grid: GridContainer = bottom_popup.get_node("VBox/Grid")
	for child in grid.get_children():
		child.queue_free()
	for c in cards:
		grid.add_child(CardWidget.create(c, true, true))
	bottom_popup.visible = true
	hide_timer.stop()


func set_bottom_button_visible(v: bool) -> void:
	bottom_button.visible = v
	if not v:
		bottom_popup.visible = false


func hide_all() -> void:
	if history_popup != null:
		history_popup.visible = false
	if bottom_popup != null:
		bottom_popup.visible = false
	showing_seat = -1


## 居中弹层骨架：点锚 = 主牌桌十字中心，grow 向四周自适应（尺寸随内容）
func _build_popup(root: Control, popup_name: String) -> PanelContainer:
	var popup := PanelContainer.new()
	popup.name = popup_name
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.mouse_entered.connect(hide_timer.stop)
	popup.mouse_exited.connect(hide_timer.start)
	popup.anchor_left = UiStyle.MAIN_TABLE_CENTER.x
	popup.anchor_right = UiStyle.MAIN_TABLE_CENTER.x
	popup.anchor_top = UiStyle.MAIN_TABLE_CENTER.y
	popup.anchor_bottom = UiStyle.MAIN_TABLE_CENTER.y
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(popup)
	return popup


func _build_history_contents() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	history_popup.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)


func _build_bottom_contents() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	bottom_popup.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
