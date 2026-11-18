class_name TrumpRankPicker
extends PanelContainer
## 叫主点数选择面板（居中多排 2×6）：10 个点数按钮完整展示（R ∈ 5~2，不可为王）。
## 点锚 = 主牌桌十字中心 + grow BOTH（居中规范，[码4]）。


signal rank_picked(rank: int)


func _ready() -> void:
	# 居中规范：锚点 = 主牌桌十字中心，grow 向四周自适应（尺寸随内容）
	anchor_left = UiStyle.MAIN_TABLE_CENTER.x
	anchor_right = UiStyle.MAIN_TABLE_CENTER.x
	anchor_top = UiStyle.MAIN_TABLE_CENTER.y
	anchor_bottom = UiStyle.MAIN_TABLE_CENTER.y
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.text = "选择常主点数 R"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	for r in Card.RANKS:
		var rank: int = r
		var label_text: String
		if rank == Card.RANK_SMALL_JOKER:
			label_text = "小王"
		elif rank == Card.RANK_BIG_JOKER:
			label_text = "大王"
		else:
			label_text = Card.new(Card.Suit.JOKER, rank).label()
		var b := Button.new()
		b.text = label_text
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(92, 48)
		UiStyle.pad_button(b)
		b.pressed.connect(func(): rank_picked.emit(rank))
		grid.add_child(b)
