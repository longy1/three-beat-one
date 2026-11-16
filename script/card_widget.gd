class_name CardWidget
extends Control
## 程序化卡牌控件（无外部素材）。花色着色、背面、选中高亮。

const RED_COLOR := Color(0.78, 0.15, 0.15)
const BLACK_COLOR := Color(0.15, 0.15, 0.2)
const BACK_COLOR := Color(0.15, 0.24, 0.46)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const SIZE_NORMAL := Vector2(60, 86)
const SIZE_MEDIUM := Vector2(50, 72)
const SIZE_SMALL := Vector2(44, 64)

var card: Card = null
var face_up := true
var selected := false
var back_mark := "哈"  ## 背面中央标记字；置空则背面无字（如信息栏未叫主态，仅问号）


static func create(p_card: Card, p_face_up: bool, small := false, p_back_mark := "哈") -> CardWidget:
	var w := CardWidget.new()
	w.card = p_card
	w.face_up = p_face_up
	w.back_mark = p_back_mark
	var sz := SIZE_SMALL if small else SIZE_NORMAL
	w.custom_minimum_size = sz
	w.size = sz
	w._refresh()
	return w


## 指定尺寸创建（出牌区按张数自适应：拖拉机等 4 张用中号，避免遮挡姓名版）
static func create_sized(p_card: Card, p_face_up: bool, p_size: Vector2, p_back_mark := "哈") -> CardWidget:
	var w := CardWidget.new()
	w.card = p_card
	w.face_up = p_face_up
	w.back_mark = p_back_mark
	w.custom_minimum_size = p_size
	w.size = p_size
	w._refresh()
	return w


func _refresh() -> void:
	for child in get_children():
		child.queue_free()

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	if selected:
		style.border_color = SELECTED_COLOR
	else:
		style.border_color = Color(0.5, 0.5, 0.55)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var small := custom_minimum_size == SIZE_SMALL
	var medium := custom_minimum_size == SIZE_MEDIUM

	if not face_up or card == null:
		style.bg_color = BACK_COLOR
		if back_mark != "":
			var back := Label.new()
			back.text = back_mark
			back.set_anchors_preset(Control.PRESET_FULL_RECT)
			back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			back.add_theme_font_size_override("font_size", [32, 24, 28][2 if medium else (1 if small else 0)])
			back.modulate = Color(0.72, 0.8, 0.95)
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(back)
		return

	var is_red: bool = card.suit == Card.Suit.HEART or card.suit == Card.Suit.DIAMOND \
		or (card.is_joker() and card.rank == Card.RANK_BIG_JOKER)
	var color := RED_COLOR if is_red else BLACK_COLOR
	style.bg_color = Color(0.98, 0.97, 0.93)

	var size_kind := 2 if medium else (1 if small else 0)  # 0 normal / 1 small / 2 medium
	var corner := Label.new()
	corner.text = card.label()
	corner.position = Vector2(4, 3)
	corner.add_theme_font_size_override("font_size", [14, 12, 13][size_kind])
	corner.modulate = color
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)

	var center := Label.new()
	center.text = _center_char()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_theme_font_size_override("font_size", [30, 22, 26][size_kind])
	center.modulate = color
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)


func _center_char() -> String:
	if card.is_joker():
		return "王"
	return ["♠", "♥", "♣", "♦"][card.suit]


func set_selected(v: bool) -> void:
	if selected == v:
		return
	selected = v
	_refresh()


func set_face_up(v: bool) -> void:
	face_up = v
	_refresh()
