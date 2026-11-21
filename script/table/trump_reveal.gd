class_name TrumpReveal
extends RefCounted
## 竞叫结束揭主动画：主 R 牌面与皇冠一同从主牌桌中央出现，
## 牌面飞至主牌展示位（桌面=信息栏、手机=顶栏），飞行中渐缩至目标槽位尺寸，
## 落位后由控制器把牌面放进主牌展示位。
## 生命周期与 CrownAnimator 一致：新局拍卖开始时 clear()。


const CENTER_SCALE := 2.2  ## 中央出现时的放大倍数（相对 SIZE_NORMAL；与皇冠 ×4 呼应，牌面略小）

var fly_duration := CrownAnimator.FLY_DURATION  ## 飞行时长（UI 测试调小以加速）
var active := false                             ## 揭主动画进行中（期间信息栏不显示主牌）

var _card_widget: CardWidget = null
var _tween: Tween = null


## 揭主期间标记（控制器据此跳过信息栏主牌的即时刷新）
func begin() -> void:
	active = true


## 清理飞行牌面并结束标记（同时杀掉飞行 tween：飞行被打断时落位回调不再
## 触发，主牌展示位由控制器守卫自愈重渲——本方法复位 active 即恢复守卫放行）
func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _card_widget != null:
		_card_widget.queue_free()
		_card_widget = null
	active = false


## 播放飞牌动画：trump_card = 主 R 牌（trump.suit/rank）；
## target = 主牌展示位的全局中心坐标（trump_slot_center 测量，分支感知）；
## target_size = 落点目标牌面尺寸（trump_slot_size：桌面 SIZE_SMALL、手机 SIZE_BAR）——
## 飞行渐缩至该尺寸，落位视觉与槽位重建牌面零跳变（旧版恒缩回 72×100：桌面与
## 52×76 槽位一次跳变、手机 36×50 槽位放大成用户可见的不匹配）；
## on_done = 落位回调（控制器把主牌放入主牌展示位并 clear()）
func play(root: Control, trump_card: Card, target: Vector2, target_size: Vector2, on_done: Callable) -> void:
	clear()
	active = true
	_card_widget = CardWidget.create(trump_card, true)
	# pivot 居中（皇冠同款）：缩放围绕牌面中心，任意缩放下视觉中心恒 = position + 半尺寸
	# ——起点居中于牌桌中央、终点居中于目标槽位（缺省 pivot=左上角，×2.2 时起点偏右下）
	_card_widget.pivot_offset = CardWidget.SIZE_NORMAL / 2.0
	_card_widget.position = UiStyle.table_center(root) * root.size - CardWidget.SIZE_NORMAL / 2.0
	_card_widget.scale = Vector2(CENTER_SCALE, CENTER_SCALE)
	_card_widget.z_index = 60
	root.add_child(_card_widget)
	var tw := root.create_tween()
	_tween = tw
	tw.set_parallel(true)
	# TRANS_CUBIC + EASE_OUT：起步快、逐渐减速（与皇冠动画一致）
	tw.tween_property(_card_widget, "position", target - CardWidget.SIZE_NORMAL / 2.0, fly_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 缩放终点 = 目标尺寸 / NORMAL（两轴独立换算，落位视觉尺寸恰为目标槽位尺寸）
	tw.tween_property(_card_widget, "scale", target_size / CardWidget.SIZE_NORMAL, fly_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(on_done)
