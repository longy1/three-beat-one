class_name TrumpReveal
extends RefCounted
## 竞叫结束揭主动画：主 R 牌面与皇冠一同从主牌桌中央出现，
## 牌面飞至信息栏主牌展示位，落位后由控制器把牌面放进信息栏。
## 生命周期与 CrownAnimator 一致：新局拍卖开始时 clear()。


const CENTER_SCALE := 2.2  ## 中央出现时的放大倍数（与皇冠 ×4 呼应，牌面略小）

var fly_duration := CrownAnimator.FLY_DURATION  ## 飞行时长（UI 测试调小以加速）
var active := false                             ## 揭主动画进行中（期间信息栏不显示主牌）

var _card_widget: CardWidget = null


## 揭主期间标记（控制器据此跳过信息栏主牌的即时刷新）
func begin() -> void:
	active = true


## 清理飞行牌面并结束标记
func clear() -> void:
	if _card_widget != null:
		_card_widget.queue_free()
		_card_widget = null
	active = false


## 播放飞牌动画：trump_card = 主 R 牌（trump.suit/rank）；
## target = 信息栏主牌展示位的全局中心坐标（InfoSidebar.trump_slot_center 测量）；
## on_done = 落位回调（控制器把主牌放入信息栏并 clear()）
func play(root: Control, trump_card: Card, target: Vector2, on_done: Callable) -> void:
	clear()
	active = true
	_card_widget = CardWidget.create(trump_card, true)
	_card_widget.position = UiStyle.MAIN_TABLE_CENTER * root.size - CardWidget.SIZE_NORMAL / 2.0
	_card_widget.scale = Vector2(CENTER_SCALE, CENTER_SCALE)
	_card_widget.z_index = 60
	root.add_child(_card_widget)
	var tw := root.create_tween()
	tw.set_parallel(true)
	# TRANS_CUBIC + EASE_OUT：起步快、逐渐减速（与皇冠动画一致）
	tw.tween_property(_card_widget, "position", target - CardWidget.SIZE_NORMAL / 2.0, fly_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card_widget, "scale", Vector2.ONE, fly_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(on_done)
