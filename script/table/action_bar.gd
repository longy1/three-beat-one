class_name ActionBar
extends HBoxContainer
## 操作按钮条（自 game_table.gd 拆出）：按钮生命周期的唯一所有者。
## 各 show_* 面板开头调用 reset()（幂等清理）——按钮界面只由 *_required
## 信号处理器重建，submit 提交方法不做任何清理（根治旧版同步信号重入时
## 「不得清理，否则把新按钮一并删掉」的竞态补丁）。


func reset() -> void:
	for child in get_children():
		child.queue_free()


func add_button(text: String, handler: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(120, 44)
	b.disabled = disabled
	UiStyle.pad_button(b)  # 文字与按钮边框留空 ≥ 半字号（UI 规范）
	b.pressed.connect(handler)
	add_child(b)
	return b
