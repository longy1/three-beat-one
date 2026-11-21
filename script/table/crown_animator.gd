class_name CrownAnimator
extends RefCounted
## 皇冠庄家标记动画（自 game_table.gd 拆出）：从主牌桌正中央 ×4 出现，
## TRANS_CUBIC EASE_OUT 1s 一边缩小一边减速，飞至出牌庄家名字首字之前停驻，
## 高度与名字字号一致；人类 0 号位无面板，落手牌上方按钮行（历史/牌堆按钮右侧，不随牌变动）。


const CROWN_HUMAN_TARGET := Vector2(0.108, 0.749)  ## 相对窗口比例：手牌上方按钮行、牌堆按钮右侧（不遮挡手牌；桌面默认值）
const CROWN_SIZE := Vector2(24, 18)  ## 高度 = NameLabel 字号（18）
const FLY_DURATION := 1.0


var human_target := CROWN_HUMAN_TARGET  ## 人类 0 号位落点（比例×根尺寸；布局档案下发）


## 应用布局档案（分支切换）：人类 0 号位皇冠落点
func apply_layout(p: TableLayoutProfile) -> void:
	human_target = p.crown_human_target

var _crown: CrownBadge = null


func clear() -> void:
	if _crown != null:
		_crown.queue_free()
		_crown = null


## 播放动画（await 一帧等名字标签布局；场景退出时安全早退）
func play(root: Control, seat: int, seat_panels: Dictionary) -> void:
	clear()
	_crown = CrownBadge.new()
	_crown.size = CROWN_SIZE
	_crown.pivot_offset = CROWN_SIZE / 2.0
	_crown.position = UiStyle.table_center(root) * root.size - CROWN_SIZE / 2.0  # 主牌桌区域正中央
	_crown.scale = Vector2(4, 4)
	_crown.z_index = 60
	root.add_child(_crown)
	await root.get_tree().process_frame  # 等待名字标签完成本帧布局
	if not root.is_inside_tree() or _crown == null:
		return
	var target := _target(root, seat, seat_panels)
	var tw := root.create_tween()
	tw.set_parallel(true)
	# TRANS_CUBIC + EASE_OUT：起步快、逐渐减速（加速度减小）
	tw.tween_property(_crown, "position", target - CROWN_SIZE / 2.0, FLY_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_crown, "scale", Vector2.ONE, FLY_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 皇冠落点（中心）：庄家名字文字左缘前方（SeatPanel.crown_anchor 封装测量）；
## 人类 0 号位或名字未就绪时用 human_target（分支感知，控制器覆写）
func _target(root: Control, seat: int, seat_panels: Dictionary) -> Vector2:
	if seat == 0 or not seat_panels.has(seat):
		return human_target * root.size
	var anchor: Vector2 = seat_panels[seat].crown_anchor(CROWN_SIZE.x)
	if anchor.x == Vector2.INF.x:
		return human_target * root.size
	return anchor
