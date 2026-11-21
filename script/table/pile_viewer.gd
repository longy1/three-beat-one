class_name PileViewer
extends RefCounted
## 牌堆查看器：左下「历史」「牌堆」两个入口按钮 + 庄家底牌悬停弹层。
## 「历史」点击打开 TrickHistoryPanel（出牌历史面板，控制器接线，组件外持有）；
## 「牌堆」悬停查看所扣底牌（仅庄家是自己时显示），0.1s 延迟隐藏（防移出误隐）。
## 数据由控制器注入（show_bottom），组件不持有引擎引用。


const HIDE_DELAY := 0.1  ## 移出入口后延迟隐藏秒数（粘滞；期间重新进入则取消。用户定夺 0.1s）

var hide_timer: Timer
var history_chip: Button        ## 人类玩家出牌历史入口（左下，始终显示）
var bottom_button: Button       ## 庄家是自己时的「牌堆」入口（「历史」右侧，悬停看底牌）
var bottom_popup: PanelContainer


func setup(root: Control) -> void:
	hide_timer = Timer.new()
	hide_timer.one_shot = true
	hide_timer.wait_time = HIDE_DELAY
	hide_timer.timeout.connect(hide_all)
	root.add_child(hide_timer)
	# 人类玩家出牌历史入口：左下角小按钮（点击打开出牌历史面板）
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
	# 庄家是自己时的「牌堆」入口：「历史」右侧同一行（放皇冠下方会遮挡手牌）
	bottom_button = Button.new()
	bottom_button.text = "牌堆"
	bottom_button.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(bottom_button)
	bottom_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_button.offset_left = 66
	bottom_button.offset_right = 118
	bottom_button.offset_top = -196
	bottom_button.offset_bottom = -166
	bottom_button.visible = false
	root.add_child(bottom_button)
	bottom_popup = _build_popup(root, "BottomPopup")
	_build_bottom_contents()


## 悬停「牌堆」按钮：查看所扣底牌（2 行 × 4 张，仅自己可见）
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


## 悬停类自动隐藏入口（面板/弹层移出）：延迟启动
func request_hide() -> void:
	hide_timer.start()


func hide_all() -> void:
	if bottom_popup != null:
		bottom_popup.visible = false


## 居中弹层骨架：点锚 = 主牌桌十字中心，grow 向四周自适应（尺寸随内容）。
## z_index=10：桌面级弹层（盖过扣底阶段底牌展示 z=1，见 game_table 层级约定）。
## 移出弹层走 request_hide（0.1s 粘滞延迟）
func _build_popup(root: Control, popup_name: String) -> PanelContainer:
	var popup := PanelContainer.new()
	popup.name = popup_name
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.z_index = 10
	popup.mouse_entered.connect(hide_timer.stop)
	popup.mouse_exited.connect(request_hide)
	popup.anchor_left = UiStyle.table_center(root).x
	popup.anchor_right = UiStyle.table_center(root).x
	popup.anchor_top = UiStyle.table_center(root).y
	popup.anchor_bottom = UiStyle.table_center(root).y
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(popup)
	return popup


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
