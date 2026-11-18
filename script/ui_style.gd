class_name UiStyle
extends RefCounted
## UI 规范工具（[码4]）：布局锚点常量 + 半字号留空。
## - 按钮：按其字号设置四向 content margin（ UiStyle.pad_button ）
## - 面板：在 tscn 中用 StyleBoxFlat content_margin_* 落实（InfoSidebar 8 / SeatPanel 9 /
##   ResultPanel 15，均 ≈ 各自最大字号的一半）
## 豁免：无边框的裸文字（Toast/提示行/顶栏）、卡牌角标（扑克牌角标贴角为惯例设计）。


## 主牌桌区域十字中心（相对比例）：左右对齐丙面板中轴（x 0.419）、
## 上下对齐乙/丁面板中轴（y 0.408）——所有居中展示组件的统一锚点（单一事实源）
const MAIN_TABLE_CENTER := Vector2(0.419, 0.408)

## 屏幕正中（相对比例）：非牌桌场景（主菜单/联机菜单/房间大厅）的居中弹层锚点
const SCREEN_CENTER := Vector2(0.5, 0.5)


## 居中弹层锚点规则：牌桌场景内对齐主牌桌十字中心（与牌面/组件同轴）；
## 其它场景（主菜单/联机菜单/房间大厅）用屏幕正中——桌面对齐只在牌桌内有意义
static func center_anchor(node: Node) -> Vector2:
	if node == null or node.get_tree() == null:
		return SCREEN_CENTER
	var cs: Node = node.get_tree().current_scene
	if cs != null and cs.get("_net") != null:  # 联机牌桌（挂 NetClient 的 game_table）
		return MAIN_TABLE_CENTER
	return SCREEN_CENTER


## 给按钮设置四向内边距 = 字号/2（至少 6px），保证文字不贴按钮边框
static func pad_button(b: Button) -> void:
	var fs: int = b.get_theme_font_size("font_size")
	if fs <= 0:
		fs = 16
	var m: float = maxf(fs / 2.0, 6.0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBox = b.get_theme_stylebox(state)
		if sb == null:
			continue
		var copy: StyleBox = sb.duplicate()
		copy.content_margin_left = m
		copy.content_margin_right = m
		copy.content_margin_top = m
		copy.content_margin_bottom = m
		b.add_theme_stylebox_override(state, copy)
