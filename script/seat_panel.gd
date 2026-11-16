class_name SeatPanel
extends PanelContainer
## 座位信息面板组件（乙/丙/丁复用）：姓名 / 牌数 / 状态 + 悬停查看出牌历史。
## 组件自带统一尺寸（tscn 内 custom_minimum_size = 180×100，720p 基准）；
## 实例只负责定位（anchor 锚定左上角，不拉伸），改尺寸只需改组件一处。


signal pile_hovered(seat: int)
signal pile_exited

var seat := -1
var _style_normal: StyleBox
var _style_highlight: StyleBox


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): pile_hovered.emit(seat))
	mouse_exited.connect(func(): pile_exited.emit())
	# 行动指示：淡金色边框样式（复制常规样式 + 金边），不改变透明度
	_style_normal = get_theme_stylebox("panel")
	_style_highlight = _style_normal.duplicate()
	if _style_highlight is StyleBoxFlat:
		var flat := _style_highlight as StyleBoxFlat
		flat.set_border_width_all(2)
		flat.border_color = Color(1.0, 0.9, 0.55, 0.85)  # 淡金


func setup(p_seat: int) -> void:
	seat = p_seat


func set_info(title: String, count: String, status: String) -> void:
	($VBox/NameLabel as Label).text = title
	($VBox/CountLabel as Label).text = count
	($VBox/StatusLabel as Label).text = status


## 当前行动指示：淡金色边框（不改透明度）
func set_highlight(on: bool) -> void:
	add_theme_stylebox_override("panel", _style_highlight if on else _style_normal)


## 皇冠落点（中心）：名字文字左缘前方 4px、姓名行垂直居中（庄家标记动画用）。
## 组件封装：外部无须 get_node 穿透内部结构。名字未就绪时返回 Vector2.INF。
func crown_anchor(crown_width: float) -> Vector2:
	var name_label: Label = $VBox/NameLabel
	var font: Font = name_label.get_theme_font("font")
	if font == null or name_label.text.is_empty():
		return Vector2.INF
	var font_size: int = name_label.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var center_x: float = name_label.global_position.x + name_label.size.x / 2.0
	var row_y: float = name_label.global_position.y + name_label.size.y / 2.0
	# 名字文字左缘再往前留 4px，皇冠中心再往左半个冠宽
	return Vector2(center_x - text_w / 2.0 - 4.0 - crown_width / 2.0, row_y)
