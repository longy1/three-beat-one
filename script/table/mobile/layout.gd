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
