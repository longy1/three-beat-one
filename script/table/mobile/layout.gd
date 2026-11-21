class_name MobileLayout
extends RefCounted
## 手机版 UI 分支的布局常量组（独立分支：布局/尺寸/组件与桌面版解耦各自迭代，
## 仅游戏规则与流程复用）。数值均按 720p 设计基准，由控制器 _apply_layout_mode
## 应用（桌面还原值取自场景/tscn 原值，不在此处）[码4]。

## 手牌卡尺寸（桌面 SIZE_NORMAL 72×100；iPhone 触摸目标 ≈52×72pt）
const HAND_CARD_SIZE := Vector2(96, 134)
## 手牌步距（桌面 24/8）：更大间距利于识读与点按
const SPACING_MAX := 40.0
const SPACING_MIN := 12.0
## 手牌行内卡牌基线 y（相对 HandArea）：贴底 12px = 行高 − 卡高 − 12
const HAND_BASE_Y := 30.0
## 底部区（ActionBar/HintLabel/HandRow 容器）偏移：全屏 90% 手牌（64 左右边距）
const BOTTOM_LEFT := 64.0
const BOTTOM_TOP := -276.0
const BOTTOM_RIGHT := -64.0
const BOTTOM_BOTTOM := -8.0
## 出牌显示锚点（相对比例 ×TrickArea）：十字中心移到屏宽正中
const TRICK_ANCHORS := {
	0: Vector2(0.5, 0.60),
	1: Vector2(0.60, 0.47),
	2: Vector2(0.5, 0.34),
	3: Vector2(0.40, 0.47),
}
## 座位面板锚点（点锚）：丙上带居中、乙/丁对称贴左右两缘
const SEAT_ANCHORS := {
	1: Vector2(0.85, 0.40),   ## 乙（右）
	2: Vector2(0.4297, 0.144), ## 丙（上）
	3: Vector2(0.0094, 0.40),  ## 丁（左）
}
## 叫分气泡锚点（尾巴尖角贴近面板/手牌区缘）
const BUBBLE_ANCHORS := {
	0: Vector2(0.5, 0.744),
	1: Vector2(0.84, 0.469),
	2: Vector2(0.5, 0.292),
	3: Vector2(0.159, 0.469),
}
## 操作按钮（桌面 120×44/字号 18）
const BUTTON_MIN := Vector2(150, 52)
const BUTTON_FONT := 19
## 手机顶栏（当局信息 bar）
const BAR_HEIGHT := 56.0

## BottomArea 内子件偏移（ActionBar 底缘 / HintLabel 上下缘 / HandArea 上下缘，相对 BottomArea）
const ACTION_BAR_OFFSET_BOTTOM := 52.0
const HINT_OFFSET_TOP := 56.0
const HINT_OFFSET_BOTTOM := 84.0
const HAND_OFFSET_TOP := 92.0
const HAND_OFFSET_BOTTOM := -8.0
## 甲家无主印章位（左下点锚：x 为绝对坐标、y 为距根底缘距离；桌面 958..1014 / 距底 232..176）
const VOID_STAMP_LEFT := 1120.0
const VOID_STAMP_RIGHT := 1176.0
const VOID_STAMP_TOP := -250.0
const VOID_STAMP_BOTTOM := -194.0
## 「历史」「牌堆」入口按钮位（根节点左下点锚，Vector4 = l/t/r/b；桌面 12..58·66..118 / 距底 196..166
## ——手机手牌框顶更低（基线 566），按钮上移与框顶留出间隙，避让「你」位出牌卡（y 382..482））
const ENTRY_HISTORY_OFFS := Vector4(12.0, -210.0, 58.0, -180.0)
const ENTRY_BOTTOM_OFFS := Vector4(66.0, -210.0, 118.0, -180.0)
## 甲家皇冠落点（人类 0 号位，比例×根尺寸）：手机入口按钮行（距底 210..180）内、
## 牌堆按钮右侧（桌面 0.108×0.749 = 按钮 y 524..554 行内；手机按钮行 y 510..540）
const CROWN_HUMAN_TARGET := Vector2(0.108, 0.729)
## 叫分气泡尺度（桌面 FONT 17/44/15、上限 430×180 ≈ 中央空白 960×430 的 1/3）：
## 手机中央空白 y 56~444（高 388）→ 上限 1/3 ≈ 130 高，字号同比收紧
const BUBBLE_FONT_MIN := 15
const BUBBLE_FONT_MAX := 36
const BUBBLE_FONT_PASS := 13
const BUBBLE_MAX_SIZE := Vector2(360, 130)
