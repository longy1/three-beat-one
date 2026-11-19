class_name CardWidget
extends Control
## 程序化卡牌控件（无外部素材）。花色着色、背面、选中高亮。

const RED_COLOR := Color(0.78, 0.15, 0.15)
const BLACK_COLOR := Color(0.15, 0.15, 0.2)
const BACK_COLOR := Color(0.15, 0.24, 0.46)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
## 三档尺寸（移动端触控口径）：NORMAL=手牌/出牌区≤2 张/揭主飞牌，
## MEDIUM=出牌区 3+ 张（拖拉机不遮挡姓名版），SMALL=历史面板/牌堆弹层/信息栏/底牌展示。
## iPhone 横屏（844×390pt，逻辑 1280×720 letterbox 缩放 ≈0.54）下手牌 ≈39×54pt 触摸目标。
const SIZE_NORMAL := Vector2(72, 100)
const SIZE_MEDIUM := Vector2(60, 86)
const SIZE_SMALL := Vector2(52, 76)

## 角标与中央花色布局（三档尺寸，索引同 size_kind：0 NORMAL / 1 SMALL / 2 MEDIUM）：
## 角标 = 点数、花色两行，各居其半区水平居中（共享同一条竖直中轴——Noto 里花色字形
## 为全角、点数为半角，只有居中能保证竖线对齐）；卡牌旋转对称，右下角同款 180° 镜像
const CORNER_FONT := [15, 13, 14]
const CORNER_WIDTH := [18.0, 14.0, 16.0]    ## 角标列宽（两行共用的竖直中轴）
const CORNER_HEIGHT := [44.0, 34.0, 38.0]   ## 角标区总高（每行各占一半）
const CENTER_FONT := [26, 18, 22]           ## 中央花色字号（调小让位上下角标，牌面正中）

## 王牌装饰布局（三档尺寸，索引同 size_kind：0 NORMAL / 1 SMALL / 2 MEDIUM）：
## 经典小丑牌版式——左右两列竖排 JOKER（右列 180° 倒置，无「大/王」角标，
## 红黑两色区分大小王），像素小丑居中（Balatro 像素风参考，纯色块程序化绘制）。
## 字母字号小于点数、字距紧凑；字母列贴左上角起排（右列镜像贴右下角）。
## 字母用等宽字体（Roboto Mono 子集，仅 J/O/K/E/R 五字形，1.2KB）——Noto 的比例
## 拉丁字形墨迹中心互有偏差，竖排会错位；等宽同 advance + 居中 = 墨迹成列
const JOKER_LETTER_FONT_FILE := preload("res://font/RobotoMono-Regular.subset.ttf")
const JOKER_LETTER_FONT := [11, 8, 9]
const JOKER_LETTER_POS := [Vector2(6, 3), Vector2(4, 3), Vector2(5, 3)]
const JOKER_LETTER_SIZE := [Vector2(16, 65), Vector2(12, 50), Vector2(14, 55)]
const JOKER_JESTER_CELL := [3.0, 2.0, 2.0]
const JOKER_JESTER_POS := [Vector2(24, 33), Vector2(18, 27), Vector2(22, 32)]

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
			back.add_theme_font_size_override("font_size", [36, 28, 32][2 if medium else (1 if small else 0)])
			back.modulate = Color(0.72, 0.8, 0.95)
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(back)
		return

	var is_red: bool = card.suit == Card.Suit.HEART or card.suit == Card.Suit.DIAMOND \
		or (card.is_joker() and card.rank == Card.RANK_BIG_JOKER)
	var color := RED_COLOR if is_red else BLACK_COLOR
	style.bg_color = Color(0.98, 0.97, 0.93)

	var size_kind := 2 if medium else (1 if small else 0)  # 0 normal / 1 small / 2 medium
	# 角标：点数上、花色下，两行各居其半区水平居中，共用同一条竖直中轴；
	# 卡牌旋转对称——右下角同款角标 180° 镜像。
	# 王牌无角标（经典小丑牌只有 JOKER 字样，红黑两色区分大小王）
	if not card.is_joker():
		var corner_w: float = CORNER_WIDTH[size_kind]
		var corner_h: float = CORNER_HEIGHT[size_kind]
		var corner_lines: Array[String] = [card.rank_label(), card.suit_label()]
		for flip in 2:
			var base := Vector2(4, 2)
			if flip == 1:
				base = Vector2(custom_minimum_size.x - corner_w - 4, custom_minimum_size.y - corner_h - 2)
			for i in 2:
				var line := Label.new()
				line.text = corner_lines[i]
				line.position = base + Vector2(0, corner_h * i / 2.0)
				line.size = Vector2(corner_w, corner_h / 2.0)
				line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				line.add_theme_font_size_override("font_size", CORNER_FONT[size_kind])
				line.modulate = color
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if flip == 1:
					line.pivot_offset = line.size / 2.0
					line.rotation_degrees = 180
				add_child(line)

	if card.is_joker():
		# 王牌：经典小丑牌版式——左右两列竖排 JOKER（右列整列 180° 倒置，
		# 大王红/小王黑沿用着色区分），中央像素小丑（帽色同步红/黑）
		var col_pos: Vector2 = JOKER_LETTER_POS[size_kind]
		var col_size: Vector2 = JOKER_LETTER_SIZE[size_kind]
		for flip in 2:
			var col_x := col_pos.x
			var base_y := col_pos.y  # 左列贴左上角；右列镜像贴右下角
			if flip == 1:
				col_x = custom_minimum_size.x - col_pos.x - col_size.x
				base_y = custom_minimum_size.y - col_pos.y - col_size.y
			for i in 5:
				var ch := Label.new()
				ch.text = "JOKER"[i]
				ch.add_theme_font_override("font", JOKER_LETTER_FONT_FILE)  # 等宽：竖排墨迹成列
				ch.add_theme_font_size_override("font_size", JOKER_LETTER_FONT[size_kind])
				ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				ch.position = Vector2(col_x, base_y + col_size.y * (i if flip == 0 else 4 - i) / 5.0)
				ch.size = Vector2(col_size.x, col_size.y / 5.0)
				ch.modulate = color
				ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if flip == 1:
					ch.pivot_offset = ch.size / 2.0
					ch.rotation_degrees = 180
				add_child(ch)
		var jester := PixelJester.new()
		jester.hat_color = BLACK_COLOR if card.rank == Card.RANK_SMALL_JOKER else RED_COLOR
		jester.cell = JOKER_JESTER_CELL[size_kind]
		jester.position = JOKER_JESTER_POS[size_kind]
		jester.size = Vector2(8, 11) * jester.cell
		jester.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(jester)
	else:
		var center := Label.new()
		center.text = _center_char()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)  # 牌面正中（横竖都居中）
		center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		center.add_theme_font_size_override("font_size", CENTER_FONT[size_kind])
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


## 像素小丑（王牌装饰）：8×11 色块网格——黄铃红帽（小王黑帽）、白脸、蓝身，
## Balatro 像素风参考的程序化重绘；整簇先铺一圈深色底再叠色块（像素风描边，
## 与米色牌面分离），无图片素材。
class PixelJester:
	extends Control

	var hat_color := Color(0.78, 0.15, 0.15)  ## 帽色：大王红 / 小王黑
	var cell := 3.0                           ## 单格边长（随卡牌档位缩放）

	## 0 空 / 1 帽 / 2 铃 / 3 脸 / 4 眼 / 5 身（8 列 × 11 行）
	const MAP := [
		"20000002",
		"01100110",
		"01100110",
		"01111110",
		"03333330",
		"03433430",
		"03333330",
		"00333300",
		"05355350",
		"05555550",
		"00555500",
	]

	func _draw() -> void:
		var outline := maxf(1.0, cell * 0.4)
		for y in MAP.size():
			var row: String = MAP[y]
			for x in row.length():
				if row[x] == "0":
					continue
				draw_rect(Rect2(x * cell - outline, y * cell - outline, cell + outline * 2.0, cell + outline * 2.0),
						Color(0.2, 0.2, 0.25))
		for y in MAP.size():
			var row: String = MAP[y]
			for x in row.length():
				var kind := row[x].to_int()
				if kind == 0:
					continue
				draw_rect(Rect2(x * cell, y * cell, cell, cell), _color_for(kind))

	func _color_for(kind: int) -> Color:
		match kind:
			1:
				return hat_color
			2:
				return Color(0.95, 0.78, 0.3)  # 铃（黄）
			3:
				return Color(1, 1, 1)          # 脸（白）
			4:
				return Color(0.15, 0.15, 0.2)  # 眼（深）
			_:
				return Color(0.36, 0.52, 0.78)  # 身（蓝）
