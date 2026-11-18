extends Control
## 房间大厅（M4）：展示房间码与成员列表（座位序：甲乙丙丁），房主开始游戏。
## 人数不满时开始 → 询问「是否自动补充电脑玩家」：是 → 补满并开局；否 → 留在房间页。
## 选座：每行【落座】按钮（本行不显示）——空位挪入、他人占座互换，对局中不显示；
## 房主身份跟人不跟座。
## 成员进入/离开/掉线经 room_state_changed 重渲染（信号驱动，无轮询）。
## 退出房间/房间解散的分数弹窗由 NetClient 统一接管（本场景不重复处理）。


const SEAT_LETTERS := ["甲", "乙", "丙", "丁"]

var _net: NetClient = null
var _confirm_dim: ColorRect = null  ## 人数不满确认弹层（遮罩）
var _confirm_panel: PanelContainer = null

@onready var code_label: Label = $Center/Panel/VBox/CodeLabel
@onready var members_box: VBoxContainer = $Center/Panel/VBox/MembersBox
@onready var status_hint: Label = $Center/Panel/VBox/StatusHint
@onready var start_button: Button = $Center/Panel/VBox/ButtonRow/StartButton


func _ready() -> void:
	_net = get_tree().root.get_node_or_null("NetClient") as NetClient
	if _net == null:
		# 异常路径（未经联机菜单直开本场景）：回主菜单
		get_tree().change_scene_to_file("res://scene/menu/main_menu.tscn")
		return
	_net.room_state_changed.connect(_render)
	_net.net_error.connect(func(msg: String): status_hint.text = msg)
	_net.member_presence.connect(_on_member_presence)
	start_button.pressed.connect(_on_start)
	$Center/Panel/VBox/ButtonRow/LeaveButton.pressed.connect(func(): _net.leave_room())
	_render(_net.room_state)


func _render(state: Dictionary) -> void:
	if state.is_empty():
		return
	code_label.text = "房间码：%s" % str(state.code)
	for child in members_box.get_children():
		child.queue_free()
	var is_lobby: bool = str(state.status) == "LOBBY"
	for m in state.members:
		members_box.add_child(_member_row(m, is_lobby))
	start_button.visible = is_lobby and _net.am_i_owner()
	if not is_lobby:
		status_hint.text = "对局开始……"
	elif _net.am_i_owner():
		status_hint.text = "你是房主：成员到齐可直接开局；人数不满可补电脑"
	else:
		status_hint.text = "等待房主开始对局……"


## 成员离线/重连回房提示（成员列表行内已有「离线」标签，这里补等待口径）
func _on_member_presence(name: String, online: bool, grace: int) -> void:
	if online:
		status_hint.text = "「%s」已重连" % name
	elif grace > 0:
		status_hint.text = "「%s」掉线，等待重连（%d 秒内未归房间解散）" % [name, grace]
	else:
		status_hint.text = "「%s」掉线，等待重连" % name


## 成员行：座位描述 Label + 【落座】按钮（大厅内且非本行才显示）。
## 点空位挪入、点他人占座互换；对局中不显示（选座仅大厅阶段有效）
func _member_row(m: Dictionary, is_lobby: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var line := Label.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var seat := int(m.seat)
	var nick: String = str(m.name)
	if nick == "":
		line.text = "%d 号位 %s：（空位）" % [seat + 1, SEAT_LETTERS[seat]]
		line.add_theme_color_override("font_color", Color(0.55, 0.55, 0.5))
	else:
		var tags: Array[String] = []
		if seat == int(_net.room_state.get("owner_seat", 0)):
			tags.append("房主")
		if nick == _net.my_name:
			tags.append("你")
		if bool(m.is_ai):
			tags.append("电脑")
		if bool(m.offline):
			tags.append("离线")
		line.text = "%d 号位 %s：%s%s" % [seat + 1, SEAT_LETTERS[seat], nick,
			"" if tags.is_empty() else "（%s）" % "、".join(tags)]
		if bool(m.offline):
			line.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
	row.add_child(line)
	if is_lobby and seat != _net.my_seat:
		var sit_button := Button.new()
		sit_button.text = "落座"
		sit_button.add_theme_font_size_override("font_size", 14)
		sit_button.custom_minimum_size = Vector2(72, 36)
		sit_button.focus_mode = Control.FOCUS_NONE
		UiStyle.pad_button(sit_button)
		sit_button.pressed.connect(func(): _net.request_sit(seat))
		row.add_child(sit_button)
	return row


func _on_start() -> void:
	var humans := 0
	for m in _net.room_state.get("members", []):
		if str(m.name) != "" and not bool(m.is_ai):
			humans += 1
	if humans >= 4:
		_net.request_start(false)
		return
	_show_fill_confirm(humans)


## 人数不满：居中询问是否自动补充电脑玩家（是→补满开局；否→仅关闭弹层）
func _show_fill_confirm(humans: int) -> void:
	_close_confirm()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	# 大厅属非牌桌场景：确认弹层用屏幕正中（UiStyle.center_anchor 统一规则）
	var center: Vector2 = UiStyle.center_anchor(self)
	panel.anchor_left = center.x
	panel.anchor_right = center.x
	panel.anchor_top = center.y
	panel.anchor_bottom = center.y
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.24, 0.17)
	style.set_corner_radius_all(10)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "人数不满（%d/4）" % humans
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var ask := Label.new()
	ask.text = "是否自动补充电脑玩家？"
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.add_theme_font_size_override("font_size", 16)
	box.add_child(ask)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var yes := Button.new()
	yes.text = "是，补电脑并开局"
	yes.custom_minimum_size = Vector2(200, 42)
	yes.add_theme_font_size_override("font_size", 16)
	UiStyle.pad_button(yes)
	yes.pressed.connect(func():
		_close_confirm()
		_net.request_start(true))
	row.add_child(yes)
	var no := Button.new()
	no.text = "否，留在房间"
	no.custom_minimum_size = Vector2(160, 42)
	no.add_theme_font_size_override("font_size", 16)
	UiStyle.pad_button(no)
	no.pressed.connect(_close_confirm)
	row.add_child(no)
	add_child(panel)
	_confirm_dim = dim
	_confirm_panel = panel


func _close_confirm() -> void:
	if _confirm_panel != null and is_instance_valid(_confirm_panel):
		_confirm_panel.queue_free()
	if _confirm_dim != null and is_instance_valid(_confirm_dim):
		_confirm_dim.queue_free()
	_confirm_panel = null
	_confirm_dim = null
