class_name UiStyle
extends RefCounted
## UI 规范工具（AGENTS.md 第 6 章）：文字与最近边框的留空 ≥ 半个字号。
## - 按钮：按其字号设置四向 content margin（ UiStyle.pad_button ）
## - 面板：在 tscn 中用 StyleBoxFlat content_margin_* 落实（InfoSidebar 8 / SeatPanel 9 /
##   ResultPanel 15，均 ≈ 各自最大字号的一半）
## 豁免：无边框的裸文字（Toast/提示行/顶栏）、卡牌角标（扑克牌角标贴角为惯例设计）。


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
