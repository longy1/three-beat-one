class_name DashedRoundedFrame
extends Control
## 圆角虚线框（手牌分区底框）：四边虚线 + 四角实线圆弧。


var border_color := Color(1, 1, 1, 0.4)
var corner_radius := 14.0
var dash_length := 7.0
var line_width := 1.5


func _draw() -> void:
	var r := corner_radius
	var w := size.x
	var h := size.y
	if w <= 2 * r or h <= 2 * r:
		return
	# 四边虚线
	draw_dashed_line(Vector2(r, 0), Vector2(w - r, 0), border_color, line_width, dash_length)
	draw_dashed_line(Vector2(r, h), Vector2(w - r, h), border_color, line_width, dash_length)
	draw_dashed_line(Vector2(0, r), Vector2(0, h - r), border_color, line_width, dash_length)
	draw_dashed_line(Vector2(w, r), Vector2(w, h - r), border_color, line_width, dash_length)
	# 四角圆弧
	draw_arc(Vector2(r, r), r, PI, 1.5 * PI, 12, border_color, line_width, true)
	draw_arc(Vector2(w - r, r), r, 1.5 * PI, TAU, 12, border_color, line_width, true)
	draw_arc(Vector2(w - r, h - r), r, 0, 0.5 * PI, 12, border_color, line_width, true)
	draw_arc(Vector2(r, h - r), r, 0.5 * PI, PI, 12, border_color, line_width, true)
