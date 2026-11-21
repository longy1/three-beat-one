class_name DealAnimator
extends RefCounted
## 发牌动画（表现层，不阻塞对局逻辑）：开局牌桌中央出现背面牌叠，逐拍一张一张
## 发牌——每拍约 0.2 秒，自己手牌多一张（在汇聚槽翻正面现身，按发牌顺序排成
## 紧凑行），各家座位面板的牌数计数经 on_tick 回调同步逐拍增加（无飞行牌）；
## 全部到齐后从两边往中间收拢到一张，最后展开到真实牌序布局——展开前把牌按
## 目标位 x 升序重排容器子节点（途中牌与牌的遮盖关系与排序后一致），每张以
## 【相同时长】平移至应处位置（目标位取自 HandArea 已渲染的真实卡牌位——
## 控制器先做一次测量渲染并隐藏，动画结束回调里重渲放行；不复制布局数学，
## 单一事实源仍是 HandArea._do_render [码4]）。
## speed 为时长缩放（UI 测试调大以加速）；场景退出/清理时安全早退（[构3.3]）。


const TICK := 0.2          ## 发牌节拍：每张约 0.2 秒一张
const LAND_FADE := 0.08    ## 落位翻正面现身的淡入时长
const CLUMP_DELAY := 0.25  ## 到齐后收拢前的停顿
const COLLAPSE_DUR := 0.4  ## 收拢时长
const EXPAND_DUR := 0.55   ## 展开时长（各牌同长平移，同时起步同时到位）

var speed := 1.0  ## 时长缩放（>1 加速；UI 测试与 smoke 用）
var active := false

var _root: Control = null
var _hand_area: HandArea = null
var _deck_stack: Control = null
var _clump_holder: Control = null  ## 我方牌容器（子节点序即 z 序，展开前重排）
var _clump: Array = []             ## 我方到手牌控件（汇聚/收拢/展开阶段）
var _clump_cards: Array = []       ## 与 _clump 对齐的牌引用（展开目标位对号）
var _clump_slots: Array = []       ## 与 _clump 对齐的汇聚槽全局中心（提前算好）
var _on_done: Callable


## 播放完整发牌动画。前提：控制器已做一次真实渲染（布局就绪）并隐藏真实牌面。
## my_hand 为本地玩家手牌（引擎数组序 = 发牌顺序）；on_tick = 逐拍回调
## （参数 = 已发张数，控制器驱动各家座位面板计数随发牌增长）。
func play(root: Control, hand_area: HandArea, my_hand: Array,
		on_done: Callable, on_tick: Callable = Callable()) -> void:
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
	# 我方汇聚槽（提前算好：发牌顺序紧凑行，居中于手牌区）与预建正面牌（隐藏待落位）。
	# 行基线 y 与真实手牌行同步（取测量位任一牌的全局中心 y——同排固定 HAND_BASE_Y；
	# 旧版「手牌区中心上方 8px」比实际手牌行偏高，用户报告改同步）
	var clump_center := Vector2(hand_area.get_global_rect().get_center().x,
		hand_area.get_global_rect().get_center().y)
	for pos: Vector2 in positions.values():
		clump_center.y = pos.y
		break
	var n := my_hand.size()
	var gather_spacing: float = HandArea.SPACING_MAX
	if n > 1:
		gather_spacing = clampf(
			(hand_area.get_global_rect().size.x - 2.0 * CardWidget.SIZE_NORMAL.x) / (n - 1.0),
			HandArea.SPACING_MIN, HandArea.SPACING_MAX)
	_clump_holder = Control.new()
	_clump_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clump_holder.z_index = 42
	root.add_child(_clump_holder)
	for i in n:
		var card: Card = my_hand[i]
		var w := CardWidget.create(card, true)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		w.modulate.a = 0.0
		w.position = clump_center - CardWidget.SIZE_NORMAL / 2.0 \
			+ Vector2((i - (n - 1) / 2.0) * gather_spacing, 0)
		_clump_holder.add_child(w)
		_clump.append(w)
		_clump_cards.append(card)
		_clump_slots.append(clump_center + Vector2((i - (n - 1) / 2.0) * gather_spacing, 0))
	# 逐拍发牌（无飞行牌，用户需求：只保留手牌一张一张变多）：每拍我方牌在汇聚槽
	# 翻正面现身，各家牌数计数经 on_tick 同步 +1（控制器刷新座位面板张数）
	if on_tick.is_valid():
		on_tick.call(0)
	for i in n:
		if not _guard():
			return
		var landed: CardWidget = _clump[i]
		var fade := root.create_tween()
		fade.tween_property(landed, "modulate:a", 1.0, LAND_FADE / speed)
		if on_tick.is_valid():
			on_tick.call(i + 1)
		if i < n - 1:
			await tree.create_timer(TICK / speed).timeout
	if not _guard():
		return
	_deck_stack.queue_free()
	_deck_stack = null
	# 停顿后两边往中间收拢到一张
	await tree.create_timer(CLUMP_DELAY / speed).timeout
	if not _guard():
		return
	for w in _clump:
		var tw := root.create_tween()
		tw.tween_property(w, "position", clump_center - CardWidget.SIZE_NORMAL / 2.0, \
			COLLAPSE_DUR / speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tree.create_timer(COLLAPSE_DUR / speed).timeout
	if not _guard():
		return
	# 展开到真实牌序布局：先按目标位 x 升序重排容器子节点（途中遮盖关系与排序后
	# 一致：右牌盖左牌，与 HandArea 渲染 z 序相同），再每张同长平移至测量位；
	# 结束后清场并由回调放行真实渲染（位置与 z 序均已一致，替换无跳变）
	var targets: Array = []
	for idx in _clump.size():
		targets.append(_clump_target(positions, _clump_cards[idx], idx))
	var order: Array = []
	for idx in _clump.size():
		order.append(idx)
	order.sort_custom(func(a: int, b: int) -> bool: return targets[a].x < targets[b].x)
	for k in order.size():
		_clump_holder.move_child(_clump[order[k]], k)
	for idx in _clump.size():
		var tw := root.create_tween()
		tw.tween_property(_clump[idx], "position", targets[idx] - CardWidget.SIZE_NORMAL / 2.0, \
			EXPAND_DUR / speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tree.create_timer(EXPAND_DUR / speed).timeout
	if not _guard():
		return
	clear()
	if _on_done.is_valid():
		_on_done.call()


## 展开目标位：按牌对号取测量位（发牌时引擎手牌序 = 动画顺序），缺失时
## 按索引均布于手牌区（防御；y 仍取测量行基线，与真实手牌行同步）
func _clump_target(positions: Dictionary, card: Card, idx: int) -> Vector2:
	if positions.has(card):
		return positions[card]
	var rect: Rect2 = _hand_area.get_global_rect()
	var y := rect.get_center().y
	for pos: Vector2 in positions.values():
		y = pos.y
		break
	return Vector2(rect.position.x + 36 + idx * HandArea.SPACING_MAX, y)


## 每个等待点后的安全守卫：场景退出/被清理即终止动画链
func _guard() -> bool:
	if not active or _root == null or not is_instance_valid(_root) or not _root.is_inside_tree():
		clear()
		return false
	return true


## 清场（所有动画控件释放；结束/中断共用；我方牌随容器一并释放）
func clear() -> void:
	active = false
	if _deck_stack != null and is_instance_valid(_deck_stack):
		_deck_stack.queue_free()
	_deck_stack = null
	if _clump_holder != null and is_instance_valid(_clump_holder):
		_clump_holder.queue_free()
	_clump_holder = null
	_clump.clear()
	_clump_cards.clear()
	_clump_slots.clear()
	_root = null
	_hand_area = null
