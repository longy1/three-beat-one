class_name CrownBadge
extends Control
## 程序化皇冠（庄家标记）：三尖冠体 + 底座 + 宝石，纯 draw 无素材。


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	var gold := Color(1.0, 0.82, 0.25)
	var gold_dark := Color(0.85, 0.62, 0.12)
	# 冠体：左尖 → 左谷 → 中尖 → 右谷 → 右尖
	var pts := PackedVector2Array([
		Vector2(0, h * 0.78),
		Vector2(0, h * 0.28),
		Vector2(w * 0.22, h * 0.58),
		Vector2(w * 0.5, 0.0),
		Vector2(w * 0.78, h * 0.58),
		Vector2(w, h * 0.28),
		Vector2(w, h * 0.78),
	])
	draw_colored_polygon(pts, gold)
	# 底座
	draw_rect(Rect2(0, h * 0.78, w, h * 0.22), gold_dark)
	# 宝石
	draw_circle(Vector2(w * 0.5, h * 0.62), minf(w, h) * 0.11, Color(0.85, 0.25, 0.25))
	# 轮廓
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, gold_dark, 1.0, true)
