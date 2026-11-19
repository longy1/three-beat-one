class_name DealAnimator
extends RefCounted
## 发牌动画（表现层，不阻塞对局逻辑）：开局牌桌中央出现背面牌叠，按发牌顺序
## 逐轮 4 张背面飞入各家手牌位（闲家牌到座位面板即隐没）；自己的牌全部到齐后
## 翻成正面手牌样式，先按发牌顺序挤成一坨（未排序、未分常主），再从两边往中间
## 收拢到一张，最后向左右展开到真实牌序布局（目标位取自 HandArea 已渲染的
## 真实卡牌位——控制器先做一次测量渲染并隐藏，动画结束回调里重渲放行）。
## speed 为时长缩放（UI 测试调大以加速）；场景退出/清理时安全早退（[构3.3]）。


const WAVE_COUNT := 19        ## 每家 19 张（规则 1）
const WAVE_INTERVAL := 0.09   ## 每轮发牌间隔（与单张飞行时长一致，不重叠）
const FLIP_STAGGER := 0.015   ## 自己的牌翻正面逐张间隔
const CLUMP_DELAY := 0.25     ## 翻面完成到收拢的停顿
const COLLAPSE_DUR := 0.4     ## 收拢时长
const EXPAND_DUR := 0.55      ## 展开时长

var speed := 1.0  ## 时长缩放（>1 加速；UI 测试与 smoke 用）
var active := false

var _root: Control = null
var _hand_area: HandArea = null
var _fliers: Array = []       ## 飞行牌控件池（每轮复用 4 张）
var _deck_stack: Control = null
var _clump: Array = []        ## 我方到手牌控件（收拢/展开阶段）
var _clump_cards: Array = []  ## 与 _clump 对齐的牌引用（展开目标位对号）
var _on_done: Callable


## 播放完整发牌动画。前提：控制器已做一次真实渲染（布局就绪）并隐藏真实牌面。
## my_hand 为本地玩家手牌（引擎数组序 = 发牌顺序）。
func play(root: Control, hand_area: HandArea, seat_panels: Dictionary, my_hand: Array,
		on_done: Callable) -> void:
	clear()
	_root = root
	_hand_area = hand_area
	_on_done = on_done
	active = true
	var tree: SceneTree = root.get_tree()
	# 等测量渲染落地（首帧布局/挂起渲染未就绪时多等几帧）
	var positions: Dictionary = hand_area.card_positions()
	var tries := 0
	while positions.is_empty() and tries < 60 and is_instance_valid(root):
		await tree.process_frame
		positions = hand_area.card_positions()
		tries += 1
	if not _guard():
		return
	# 中央牌叠（3 张错位背面示意整副）
	_deck_stack = Control.new()
	_deck_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_stack.z_index = 40
	root.add_child(_deck_stack)
	var deck_center: Vector2 = UiStyle.MAIN_TABLE_CENTER * root.size
	for i in 3:
		var back := CardWidget.create(null, false, true)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.position = deck_center - CardWidget.SIZE_NORMAL / 2.0 + Vector2(i * 2.0, -i * 2.0)
		_deck_stack.add_child(back)
	# 飞行牌池（4 张，每轮复用）
	for i in 4:
		var w := CardWidget.create(null, false, true)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.z_index = 41
		w.visible = false
		root.add_child(w)
		_fliers.append(w)

	for round_i in WAVE_COUNT:
		if not _guard():
			return
		for seat in 4:
			var w: CardWidget = _fliers[seat]
			w.visible = true
			w.position = deck_center - CardWidget.SIZE_SMALL / 2.0
			var tw := root.create_tween()
			tw.tween_property(w, "position", _seat_target(root, seat, hand_area, seat_panels), \
				WAVE_INTERVAL / speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tree.create_timer(WAVE_INTERVAL / speed).timeout
	if not _guard():
		return
	_deck_stack.queue_free()
	_deck_stack = null
	for w in _fliers:
		w.visible = false

	# 我方牌入手：翻正面（逐张淡入）→ 按发牌顺序挤成一坨（未排序、未分常主）
	var clump_center: Vector2 = hand_area.get_global_rect().get_center() + Vector2(0, -8)
	var i := 0
	for card in my_hand:
		if not _guard():
			return
		var w := CardWidget.create(card, true)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.z_index = 42
		w.modulate.a = 0.0
		w.position = clump_center - CardWidget.SIZE_NORMAL / 2.0 \
			+ Vector2((i - my_hand.size() / 2.0) * 6.0, 0)
		root.add_child(w)
		_clump.append(w)
		_clump_cards.append(card)
		var tw := root.create_tween()
		tw.tween_property(w, "modulate:a", 1.0, 0.12 / speed)
		i += 1
		await tree.create_timer(FLIP_STAGGER / speed).timeout
	if not _guard():
		return
	await tree.create_timer(CLUMP_DELAY / speed).timeout
	# 两边往中间收拢到一张
	if not _guard():
		return
	for w in _clump:
		var tw := root.create_tween()
		tw.tween_property(w, "position", clump_center - CardWidget.SIZE_NORMAL / 2.0, \
			COLLAPSE_DUR / speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tree.create_timer(COLLAPSE_DUR / speed).timeout
	if not _guard():
		return
	# 向左右展开到真实牌序布局（按牌对号测量位）；结束后清场并由回调放行真实渲染
	for idx in _clump.size():
		var target: Vector2 = _clump_target(positions, _clump_cards[idx], idx)
		var tw := root.create_tween()
		tw.tween_property(_clump[idx], "position", target - CardWidget.SIZE_NORMAL / 2.0, \
			EXPAND_DUR / speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tree.create_timer(EXPAND_DUR / speed).timeout
	if not _guard():
		return
	clear()
	if _on_done.is_valid():
		_on_done.call()


## 展开目标位：按牌对号取测量位（发牌时引擎手牌序 = 动画顺序），缺失时
## 按索引均布于手牌区（防御）
func _clump_target(positions: Dictionary, card: Card, idx: int) -> Vector2:
	if positions.has(card):
		return positions[card]
	var rect: Rect2 = _hand_area.get_global_rect()
	return Vector2(rect.position.x + 36 + idx * HandArea.SPACING_MAX, rect.get_center().y)


## 飞行目标：闲家 = 座位面板中心；我 = 手牌区中心
func _seat_target(root: Control, seat: int, hand_area: HandArea, seat_panels: Dictionary) -> Vector2:
	if seat == 0 or not seat_panels.has(seat):
		return hand_area.get_global_rect().get_center()
	return seat_panels[seat].get_global_rect().get_center()


## 每个等待点后的安全守卫：场景退出/被清理即终止动画链
func _guard() -> bool:
	if not active or _root == null or not is_instance_valid(_root) or not _root.is_inside_tree():
		clear()
		return false
	return true


## 清场（所有动画控件释放；结束/中断共用）
func clear() -> void:
	active = false
	if _deck_stack != null and is_instance_valid(_deck_stack):
		_deck_stack.queue_free()
	_deck_stack = null
	for w in _fliers:
		if is_instance_valid(w):
			w.queue_free()
	_fliers.clear()
	for w in _clump:
		if is_instance_valid(w):
			w.queue_free()
	_clump.clear()
	_clump_cards.clear()
	_root = null
	_hand_area = null
