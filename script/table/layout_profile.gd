class_name TableLayoutProfile
extends RefCounted
## 牌桌布局档案：桌面/手机两分支全部布局数值的单一载体（依赖注入的数据端）。
## 桌面档案由 capture() 从场景实例现值捕获——tscn 与组件类常量即桌面事实源，
## 代码不第二处复写桌面数值；手机档案由 mobile() 取自 MobileLayout 常量组。
## 应用端：控制器只摆布直属节点，组件各自实现 apply_layout(profile) 接收属于
## 自己的字段（[构4] 常量单一事实源；新增分支差异 = 档案加字段 + 归属组件接线）。
## 档案为只读值对象：构造后字段不再改写，应用方只读。


# —— 牌桌内程序化居中锚（弹层/动画出现点；桌面=主牌桌十字中心，手机=屏幕正中）——
var table_center := UiStyle.MAIN_TABLE_CENTER

# —— 底部区（BottomArea 容器与内部子件偏移）——
var bottom_offsets := Vector4.ZERO          # l/t/r/b（占位；桌面经 capture 取场景值）
var action_bar_offset_bottom := 0.0
var hint_offset_top := 0.0
var hint_offset_bottom := 0.0
var hand_offset_top := 0.0
var hand_offset_bottom := 0.0

# —— 手牌区参数（桌面缺省 = HandArea 类常量；手机 = MobileLayout）——
var hand_card_size := CardWidget.SIZE_NORMAL
var spacing_max := HandArea.SPACING_MAX
var spacing_min := HandArea.SPACING_MIN
var hand_base_y := HandArea.HAND_BASE_Y

# —— 座位面板 / 出牌显示 / 结算面板锚点 ——
var seat_anchors := {}                      # seat → Vector2 点锚
var trick_anchors := {}                     # seat → Vector2（比例 ×TrickArea 尺寸）
var result_anchor := UiStyle.MAIN_TABLE_CENTER

# —— 操作按钮条 ——
var button_min := Vector2(120, 44)
var button_font := 18

# —— 叫分气泡（桌面缺省 = BidBubbles 类常量）——
var bubble_anchors := BidBubbles.ANCHORS
var bubble_font_min := BidBubbles.FONT_MIN
var bubble_font_max := BidBubbles.FONT_MAX
var bubble_font_pass := BidBubbles.FONT_PASS
var bubble_max_size := BidBubbles.MAX_SIZE

# —— 专项落点（皇冠人类位 / 甲家无主印章 / 历史与牌堆入口按钮）——
var crown_human_target := CrownAnimator.CROWN_HUMAN_TARGET
var void_stamp_offsets := Vector4.ZERO      # l/t/r/b（占位；桌面经 capture 取场景值）
var entry_history_offs := Vector4.ZERO      # 同上
var entry_bottom_offs := Vector4.ZERO


## 从桌面场景实例捕获布局档案（在首次分支应用前调用，组件成员仍是桌面缺省值）。
## 依赖显式注入（piles/bubbles/crown 为控制器持有的组件实例），不做隐藏字段探取。
static func capture(table, piles: PileViewer, bubbles: BidBubbles,
		crown: CrownAnimator) -> TableLayoutProfile:
	var p := TableLayoutProfile.new()
	var bottom: Control = table.get_node("BottomArea")
	p.bottom_offsets = Vector4(bottom.offset_left, bottom.offset_top,
		bottom.offset_right, bottom.offset_bottom)
	p.action_bar_offset_bottom = table.action_bar.offset_bottom
	p.hint_offset_top = table.hint_label.offset_top
	p.hint_offset_bottom = table.hint_label.offset_bottom
	p.hand_offset_top = table.hand_area.offset_top
	p.hand_offset_bottom = table.hand_area.offset_bottom
	p.hand_card_size = table.hand_area.hand_card_size
	p.spacing_max = table.hand_area.spacing_max
	p.spacing_min = table.hand_area.spacing_min
	p.hand_base_y = table.hand_area.hand_base_y
	p.button_min = table.action_bar.button_min
	p.button_font = table.action_bar.button_font
	for seat in table.seat_panels:
		var panel: SeatPanel = table.seat_panels[seat]
		p.seat_anchors[seat] = Vector2(panel.anchor_left, panel.anchor_top)
	p.trick_anchors = table.trick_anchors.duplicate(true)
	p.result_anchor = Vector2(table.result_panel.anchor_left, table.result_panel.anchor_top)
	p.bubble_anchors = bubbles._anchors.duplicate(true)
	p.bubble_font_min = bubbles.font_min
	p.bubble_font_max = bubbles.font_max
	p.bubble_font_pass = bubbles.font_pass
	p.bubble_max_size = bubbles.max_size
	p.crown_human_target = crown.human_target
	p.void_stamp_offsets = Vector4(table.human_void_stamp.offset_left,
		table.human_void_stamp.offset_top, table.human_void_stamp.offset_right,
		table.human_void_stamp.offset_bottom)
	p.entry_history_offs = Vector4(piles.history_chip.offset_left,
		piles.history_chip.offset_top, piles.history_chip.offset_right,
		piles.history_chip.offset_bottom)
	p.entry_bottom_offs = Vector4(piles.bottom_button.offset_left,
		piles.bottom_button.offset_top, piles.bottom_button.offset_right,
		piles.bottom_button.offset_bottom)
	return p


## 手机版布局档案（数值单一事实源 = MobileLayout 常量组）
static func mobile() -> TableLayoutProfile:
	var p := TableLayoutProfile.new()
	p.table_center = UiStyle.SCREEN_CENTER
	p.bottom_offsets = Vector4(MobileLayout.BOTTOM_LEFT, MobileLayout.BOTTOM_TOP,
		MobileLayout.BOTTOM_RIGHT, MobileLayout.BOTTOM_BOTTOM)
	p.action_bar_offset_bottom = MobileLayout.ACTION_BAR_OFFSET_BOTTOM
	p.hint_offset_top = MobileLayout.HINT_OFFSET_TOP
	p.hint_offset_bottom = MobileLayout.HINT_OFFSET_BOTTOM
	p.hand_offset_top = MobileLayout.HAND_OFFSET_TOP
	p.hand_offset_bottom = MobileLayout.HAND_OFFSET_BOTTOM
	p.hand_card_size = MobileLayout.HAND_CARD_SIZE
	p.spacing_max = MobileLayout.SPACING_MAX
	p.spacing_min = MobileLayout.SPACING_MIN
	p.hand_base_y = MobileLayout.HAND_BASE_Y
	p.seat_anchors = MobileLayout.SEAT_ANCHORS.duplicate(true)
	p.trick_anchors = MobileLayout.TRICK_ANCHORS.duplicate(true)
	p.result_anchor = UiStyle.SCREEN_CENTER
	p.button_min = MobileLayout.BUTTON_MIN
	p.button_font = MobileLayout.BUTTON_FONT
	p.bubble_anchors = MobileLayout.BUBBLE_ANCHORS.duplicate(true)
	p.bubble_font_min = MobileLayout.BUBBLE_FONT_MIN
	p.bubble_font_max = MobileLayout.BUBBLE_FONT_MAX
	p.bubble_font_pass = MobileLayout.BUBBLE_FONT_PASS
	p.bubble_max_size = MobileLayout.BUBBLE_MAX_SIZE
	p.crown_human_target = MobileLayout.CROWN_HUMAN_TARGET
	p.void_stamp_offsets = Vector4(MobileLayout.VOID_STAMP_LEFT,
		MobileLayout.VOID_STAMP_TOP, MobileLayout.VOID_STAMP_RIGHT,
		MobileLayout.VOID_STAMP_BOTTOM)
	p.entry_history_offs = MobileLayout.ENTRY_HISTORY_OFFS
	p.entry_bottom_offs = MobileLayout.ENTRY_BOTTOM_OFFS
	return p
