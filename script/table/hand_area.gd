class_name HandArea
extends Control
## 手牌区组件（自 game_table.gd 拆出）：双虚线框分区（主牌/副牌，框序可设置）+ 排序布局
## + 选牌交互（点选 / 按住拖选 / 右键出牌 / 两指单击出牌 / 双击空白清空选择）
## + 选中态精准刷新。
## 首帧布局未就绪时挂起渲染请求，待尺寸有效后落地（根治旧版「兜底宽度 1100」补丁）。
## 呈现偏好读 AppSettings（主牌框在左/右、牌点数从大到小/从小到大），变更后由
## 控制器重渲整排生效。


signal selection_changed(count: int)  ## 选择数变化（扣底按钮计数等联动）
signal select_capped                  ## 扣底模式点选触顶（8 张，控制器 toast 提示）
signal play_requested                 ## 出牌模式下右键/两指直接提交（牌取自当前选择）


const SELECT_LIFT_RATIO := 0.2  ## 选中牌上浮 = 牌高 20%（[码4] 手牌交互）
const HAND_BASE_Y := 16.0       ## 手牌基准 y（虚线框 frame_y 6 + 内边距 10）
const LAYOUT_PAD := 10.0        ## 框内左右留空
const LAYOUT_GAP := 16.0        ## 主副框间距
const SPACING_MAX := 24.0       ## 相邻牌步距上限（紧凑重叠：露左缘角标条；出牌区同款）[码4]
const SPACING_MIN := 8.0        ## 相邻牌步距下限（拥挤时收紧）
const MIN_USABLE_WIDTH := 100.0 ## 尺寸低于此值视为布局未就绪


var select_mode := ""   # "" | "discard" | "play"；空串时交互关闭
var selected: Array = []  # Array[Card]，选中的手牌（引用来自最近一次 render 的手牌）

var _widgets := {}            # Card → CardWidget（精准刷新，避免整排重建闪烁）
var _drag_selecting := false  # 左键按住滑动批量选择中
var _drag_target := false     # 本次拖选的目标态（首张牌的新态），滑过的牌对齐到该态
var _render_pending := false  # 布局未就绪时挂起的渲染请求
var _pending_hand: Array = []
var _pending_trump: TrumpInfo = null
var _hit_cards: Array = []    # 视觉顺序的牌（命中测试用）
var _hit_x := []              # 各牌左缘 x（与 _hit_cards 对齐）
var _hit_w := []              # 各牌可命中宽度＝露出条带（末张整张）
var _active_touches := {}     # 触摸 index → 位置（两指单击出牌手势判定）
var _two_finger := false      # 第二指按下起记（两指手势进行中）
var _gesture_selected: Array = []  ## 两指手势开始时的选择快照（撤销触摸模拟点选副作用）


func _process(_delta: float) -> void:
	if _render_pending and size.x >= MIN_USABLE_WIDTH:
		_render_pending = false
		_do_render(_pending_hand, _pending_trump)


## ============================= 渲染 =============================

## 全量渲染手牌（分区 / 排序 / 布局；已选中的牌保留选中视觉）
func render(hand: Array, trump: TrumpInfo) -> void:
	# 选中集合对齐当前权威手牌：剪除已不在手牌中的陈旧引用（防「牌不在手中」
	# 整局卡死——快速连打/暂停期出牌的渲染竞争可留下已打出牌的引用，
	# 后续所有提交都会被引擎以 NOT_IN_HAND 拒绝；以渲染时的手牌为准自动自愈）
	var hand_keys := {}
	for c in hand:
		hand_keys[c.key()] = true
	selected = selected.filter(func(c): return hand_keys.has(c.key()))
	if size.x < MIN_USABLE_WIDTH:
		# 首帧布局未就绪：挂起请求，待 _process 检测到有效尺寸后一次性落地
		_render_pending = true
		_pending_hand = hand
		_pending_trump = trump
		return
	_do_render(hand, trump)


## 副牌显示排序：花色按 ♠→♥→♣→♦ 顺序分组（从左到右不变），组内点数按设置方向
## （默认从大到小，A 前 5 后）
static func _side_display_cmp(a: Card, b: Card, small_first: bool) -> bool:
	if a.suit != b.suit:
		return a.suit < b.suit
	return a.rank < b.rank if small_first else a.rank > b.rank


## 叫主前主牌区（确定常主：王与所有 2）档位键：大王 2 > 小王 1 > 各 2 点 0
static func _pre_trump_rank_key(c: Card) -> int:
	if c.is_joker():
		return 2 if c.rank == Card.RANK_BIG_JOKER else 1
	return 0


## 手牌：德州扑克桌面式分区——主牌框、副牌框（圆角虚线框，框序按设置：主牌默认在左），
## 每个区域内从左至右按设置方向排序（默认从大到小；花色分组从左到右不变）。
## 叫主前同样分两块：王与所有 2（必然常主）进主牌框；四门花色普通牌进副牌框。
func _do_render(hand: Array, trump: TrumpInfo) -> void:
	for child in get_children():
		child.queue_free()
	_widgets.clear()
	_drag_selecting = false
	var trump_cards: Array = []
	var side_cards: Array = []
	for c in hand:
		var is_main: bool
		if trump != null:
			is_main = trump.is_trump(c)
		else:
			is_main = c.is_joker() or c.rank == Card.RANK_2
		if is_main:
			trump_cards.append(c)
		else:
			side_cards.append(c)
	# 主牌框：默认从大到小。叫主后按 3.1 牌力（大王→…→主5），
	# 牌力并列的副R/副2 再按花色分组（♠→♥→♣→♦）——同花色相邻便于识读；
	# 叫主前为确定常主：大王 → 小王 → 各 2（♠→♥→♣→♦）
	var small_first: bool = AppSettings.sort_order == AppSettings.SortOrder.SMALL_FIRST
	if trump != null:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			var pa: int = trump.card_power(a)
			var pb: int = trump.card_power(b)
			if pa != pb:
				return pa < pb if small_first else pa > pb
			if a.suit != b.suit:
				return a.suit < b.suit
			return a.copy < b.copy)
	else:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			var ra: int = _pre_trump_rank_key(a)
			var rb: int = _pre_trump_rank_key(b)
			if ra != rb:
				return ra < rb if small_first else ra > rb
			return a.suit < b.suit)
	# 副牌框：花色分组、组内按设置方向
	side_cards.sort_custom(func(a: Card, b: Card) -> bool:
		return _side_display_cmp(a, b, small_first))

	var groups: Array = []
	if not trump_cards.is_empty():
		groups.append(trump_cards)  # 叫主前=确定常主（王/2），叫主后=主牌类
	if not side_cards.is_empty():
		groups.append(side_cards)
	# 主牌框位置（设置）：默认主牌在左；在右时两框对调
	if AppSettings.main_side == AppSettings.MainSide.RIGHT and groups.size() == 2:
		groups.reverse()
	if groups.is_empty():
		return

	var avail: float = size.x
	var card_w := CardWidget.SIZE_NORMAL.x
	var card_h := CardWidget.SIZE_NORMAL.y
	var n := trump_cards.size() + side_cards.size()
	var spacing := SPACING_MAX
	if n > 2:
		spacing = (avail - LAYOUT_GAP - 4 * LAYOUT_PAD - 2 * card_w) / (n - 2)
	spacing = clampf(spacing, SPACING_MIN, SPACING_MAX)

	var widths: Array = []
	for g in groups:
		widths.append(card_w + spacing * (g.size() - 1) + 2 * LAYOUT_PAD)
	var total: float = 0.0
	for w in widths:
		total += w
	if groups.size() == 2:
		total += LAYOUT_GAP
	var x := (avail - total) / 2.0
	var frame_h := card_h + 2 * LAYOUT_PAD
	var frame_y := 6.0  # 固定纵向位置：不随布局高度变化，避免整排手牌上下漂移

	_hit_cards.clear()
	_hit_x.clear()
	_hit_w.clear()
	for i in groups.size():
		var g: Array = groups[i]
		var frame := DashedRoundedFrame.new()
		frame.position = Vector2(x, frame_y)
		frame.size = Vector2(widths[i], frame_h)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
		var cx: float = x + LAYOUT_PAD
		for c in g:
			var card_widget := CardWidget.create(c, true)
			var is_selected: bool = selected.has(c)
			card_widget.set_selected(is_selected)
			# 选中：金色边框 + 上浮 20% 牌高（交互规范）
			card_widget.position = Vector2(cx, HAND_BASE_Y - (card_h * SELECT_LIFT_RATIO if is_selected else 0))
			# 命中不由卡牌控件自理（整张矩形会在重叠区误命中），统一走 HandArea 条带测试
			card_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_widgets[c] = card_widget
			add_child(card_widget)
			_hit_cards.append(c)
			_hit_x.append(cx)
			cx += spacing
		x += widths[i] + (LAYOUT_GAP if i == 0 and groups.size() == 2 else 0.0)
	# 可命中宽度 = 该牌露出的条带（到下一张牌左缘为止）；末张无遮挡，整张可点
	for k in _hit_cards.size():
		var hit_w := card_w if k == _hit_cards.size() - 1 \
				else minf(card_w, maxf(0.0, _hit_x[k + 1] - _hit_x[k]))
		_hit_w.append(hit_w)


## ============================= 选牌交互 =============================
## 左键单击切换选中；按住左键滑动批量选择相邻牌（以首张的目标态对齐）；
## 右键在出牌模式下直接提交出牌（引擎校验，非法则提示原因）；
## 触摸设备两指单击 = 右键出牌（撤销手势期间触摸模拟的鼠标点选副作用后提交）；
## 双击手牌区空白 = 清空选择（把选中的牌全部放回）。

## 进入选牌模式：同模式连续轮次（如逐轮出牌）保留已选——出完一轮不重置选牌，
# 仅在模式切换（扣底→出牌 / 新局）时清空
func begin_select(mode: String) -> void:
	_two_finger = false
	_active_touches.clear()
	_gesture_selected = []
	if select_mode != mode:
		select_mode = mode
		clear_selection()
	else:
		select_mode = mode


func end_select() -> void:
	_two_finger = false
	_active_touches.clear()
	_gesture_selected = []
	select_mode = ""
	clear_selection()


## 提交成功后移除已打出的牌（保持其余选择跨轮存续；引用来自 render 时的手牌）
func consume_selected(cards: Array) -> void:
	var keep: Array = []
	for s in selected:
		var played := false
		for c in cards:
			if s.same_card(c):
				played = true
				break
		if not played:
			keep.append(s)
	if keep.size() != selected.size():
		selected = keep
		selection_changed.emit(selected.size())


## 编程式选中一组牌（如庄家翻底后预选底牌 8 张，便于观察与直接扣回）。
## 走与点选相同的上限规则（扣底模式 8 张封顶）；仅选牌模式下可用。
func select_cards(cards: Array) -> void:
	if select_mode == "":
		return
	for c in cards:
		if selected.has(c):
			continue
		if select_mode == "discard" and selected.size() >= GameEngine.BOTTOM_SIZE:
			break
		selected.append(c)
		_apply_card_visual(c, true)
	selection_changed.emit(selected.size())


func clear_selection() -> void:
	if selected.is_empty():
		return
	selected.clear()
	for card in _widgets:
		_apply_card_visual(card, false)
	selection_changed.emit(0)


## 当前手牌的真实展示位（Card → 全局中心坐标）：发牌动画的展开目标位。
## 须在 render 落地后调用（布局未就绪时返回空表）
func card_positions() -> Dictionary:
	var out := {}
	for card in _widgets:
		var widget: CardWidget = _widgets[card]
		if is_instance_valid(widget) and not widget.is_queued_for_deletion():
			out[card] = widget.get_global_rect().get_center()
	return out


## 真实手牌显隐（发牌动画期间隐藏真实牌面，动画结束后由控制器重渲放行）
func set_widgets_visible(v: bool) -> void:
	for card in _widgets:
		var widget: CardWidget = _widgets[card]
		if is_instance_valid(widget):
			widget.modulate.a = 1.0 if v else 0.0


func _on_card_left_press(card: Card) -> void:
	if select_mode == "":
		return
	_toggle_select(card)
	_drag_selecting = true
	_drag_target = selected.has(card)  # 首张牌的新态作为本次拖选目标


func _drag_hover(card: Card) -> void:
	if select_mode == "" or not _drag_selecting:
		return
	if selected.has(card) == _drag_target:
		return
	if _drag_target:
		if select_mode == "discard" and selected.size() >= GameEngine.BOTTOM_SIZE:
			return
		selected.append(card)
	else:
		selected.erase(card)
	_apply_card_visual(card, selected.has(card))
	selection_changed.emit(selected.size())


func _on_card_right_press() -> void:
	if select_mode == "play" and not selected.is_empty():
		play_requested.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_selecting = false  # 左键松开（任何位置）结束拖选
	elif event is InputEventMouseMotion and _drag_selecting:
		# 按住鼠标期间 Godot 把 motion 路由给按下时的控件（mouse_focus 捕获），
		# 相邻牌收不到 gui_input——用与点击相同的条带命中测试
		# （Control 无 Node2D.to_local，祖先链纯平移：全局坐标 − 全局位置 = 局部坐标）
		var card := _hit_card_at(get_global_mouse_position() - get_global_position())
		if card != null:
			_drag_hover(card)
	elif event is InputEventScreenTouch:
		_handle_touch(event)


## 两指单击出牌手势：首指按下即快照当前选择（先于触摸模拟的鼠标点选副作用）；
## 第二指按下（且至少一指在本区内）确认手势；两指全部抬起时撤销手势期间的
## 模拟点选（恢复快照），出牌模式下直接提交出牌——与右键出牌等效的触屏入口
func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var first: bool = _active_touches.is_empty()
		_active_touches[event.index] = event.position
		if first:
			_gesture_selected = selected.duplicate()
		elif _active_touches.size() == 2 and not _two_finger:
			var inside := false
			var rect := get_global_rect()
			for pos in _active_touches.values():
				if rect.has_point(pos):
					inside = true
					break
			if inside:
				_two_finger = true
	else:
		_active_touches.erase(event.index)
		if _two_finger and _active_touches.is_empty():
			_two_finger = false
			_finish_two_finger_tap()


func _finish_two_finger_tap() -> void:
	# 撤销本手势期间触摸模拟的鼠标点选（恢复手势前的选择与视觉），再按模式提交
	if _gesture_selected != selected:
		selected = _gesture_selected.duplicate()
		_resync_selection_visuals()
		selection_changed.emit(selected.size())
	if select_mode == "play" and not selected.is_empty():
		play_requested.emit()


func _resync_selection_visuals() -> void:
	for card in _widgets:
		var widget: CardWidget = _widgets[card]
		var sel: bool = selected.has(card)
		if widget.selected != sel:
			widget.set_selected(sel)
			widget.position.y = HAND_BASE_Y \
				- (CardWidget.SIZE_NORMAL.y * SELECT_LIFT_RATIO if sel else 0)


## 条带命中测试：每张牌只有露出的条带可命中（各框末张整张），返回命中的牌或 null。
## 条带互不相交，从右往左找到即返回；y 范围随选中上浮扩展（浮起的牌真占据了那块）
func _hit_card_at(point: Vector2) -> Card:
	var card_h := CardWidget.SIZE_NORMAL.y
	for k in range(_hit_cards.size() - 1, -1, -1):
		var card: Card = _hit_cards[k]
		var lift := card_h * SELECT_LIFT_RATIO if selected.has(card) else 0.0
		var y_top := HAND_BASE_Y - lift
		if point.x >= _hit_x[k] and point.x < _hit_x[k] + _hit_w[k] \
				and point.y >= y_top and point.y < y_top + card_h:
			return card
	return null


## 点击入口：卡牌控件不收输入（mouse_filter IGNORE），事件落到 HandArea 后按条带命中分发
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var card := _hit_card_at(event.position)
		if card == null:
			# 双击手牌区空白（未命中任何牌）：清空选择（把选中的牌全部放回）
			if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
				clear_selection()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_left_press(card)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_card_right_press()


func _toggle_select(card: Card) -> void:
	if select_mode == "":
		return
	if selected.has(card):
		selected.erase(card)
		_apply_card_visual(card, false)
	else:
		if select_mode == "discard" and selected.size() >= GameEngine.BOTTOM_SIZE:
			select_capped.emit()
			return
		selected.append(card)
		_apply_card_visual(card, true)
	selection_changed.emit(selected.size())


## 精准更新一张牌的选中视觉（金边 + 上浮 20%），不重建整排手牌
func _apply_card_visual(card: Card, sel: bool) -> void:
	var widget: CardWidget = _widgets.get(card)
	if widget == null:
		return
	widget.set_selected(sel)
	widget.position.y = HAND_BASE_Y - (CardWidget.SIZE_NORMAL.y * SELECT_LIFT_RATIO if sel else 0)
