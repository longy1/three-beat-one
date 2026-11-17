class_name SeatPanel
extends PanelContainer
## 座位信息面板组件（乙/丙/丁复用）：姓名 / 牌数 / 状态
## + 【无主】红印章（右下角，规则 7.3 公示）。
## 组件自带统一尺寸（tscn 内 custom_minimum_size = 180×100，720p 基准）；
## 实例只负责定位（anchor 锚定左上角，不拉伸），改尺寸只需改组件一处。
## （2026-11-17 历史面板重做：悬停查看历史路径移除，出牌历史走 TrickHistoryPanel。）


const STAMP_MARGIN := 6.0  ## 印章与面板右下角的留空

var seat := -1
var _style_normal: StyleBox
var _style_highlight: StyleBox
var _void_stamp: VoidStamp


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_void_stamp = VoidStamp.new()
	_void_stamp.name = "VoidStamp"
	# PanelContainer 会对全部 Control 子件做整面填充布局（直接赋 position 每次排序都被重置，
	# 曾致印章被拽到左上角压住姓名）；top_level 脱离布局树，用全局坐标自行定位
	_void_stamp.top_level = true
	add_child(_void_stamp)
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


## 【无主】公示印章（规则 7.3）：主牌轮未出主牌时盖上，盖在面板右下角（压在内容之上）
func set_void_trump(on: bool) -> void:
	_void_stamp.visible = on
	if on:
		_place_void_stamp()
		_place_void_stamp.call_deferred()  # 本帧容器排序完成后再校准一次
		_void_stamp.z_index = 5


## 印章锚定面板右下角（top_level：position 即全局坐标）
func _place_void_stamp() -> void:
	_void_stamp.global_position = global_position + size \
		- VoidStamp.STAMP_SIZE - Vector2(STAMP_MARGIN, STAMP_MARGIN)


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
