class_name VoidStamp
extends Control
## 【无主】圆形红印章（程序化绘制）：主牌轮未出主牌的公示标记（规则 7.3）。
## 电脑座位盖在 SeatPanel 右下角；人类 0 号位盖在手牌区上方左侧。
## 斜置 + 半透明，模拟手盖章效果；不参与交互。


const STAMP_SIZE := Vector2(56, 56)  # 720p 基准
const INK := Color(0.82, 0.16, 0.12, 0.88)  # 印泥红


func _ready() -> void:
	custom_minimum_size = STAMP_SIZE
	size = STAMP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation_degrees = -12  # 轻微斜置，像手盖的章
	visible = false


func _draw() -> void:
	var center := STAMP_SIZE / 2.0
	var radius := STAMP_SIZE.x / 2.0 - 3.0
	# 双圈印章边框（外粗内细）
	draw_arc(center, radius, 0.0, TAU, 48, INK, 3.0)
	draw_arc(center, radius - 4.5, 0.0, TAU, 48, INK, 1.0)
	# 「无主」两字（默认主题字体；文案新增字符须重跑字体子集化）
	var font := get_theme_default_font()
	var font_size := 19
	var text_width: float = font.get_string_size("无主", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(text_width / 2.0, -7.0), "无主",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
