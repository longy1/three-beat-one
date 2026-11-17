class_name HandArea
extends Control
## 手牌区组件（自 game_table.gd 拆出）：双虚线框分区（左主牌右副牌）+ 排序布局
## + 选牌交互（点选 / 按住拖选 / 右键出牌）+ 选中态精准刷新。
## 首帧布局未就绪时挂起渲染请求，待尺寸有效后落地（根治旧版「兜底宽度 1100」补丁）。


signal selection_changed(count: int)  ## 选择数变化（扣底按钮计数等联动）
signal select_capped                  ## 扣底模式点选触顶（8 张，控制器 toast 提示）
signal play_requested                 ## 出牌模式下右键直接提交（牌取自当前选择）


const SELECT_LIFT_RATIO := 0.2  ## 选中牌上浮 = 牌高 20%（AGENTS.md 第 6 章交互规范）
const HAND_BASE_Y := 16.0       ## 手牌基准 y（虚线框 frame_y 6 + 内边距 10）
const LAYOUT_PAD := 10.0        ## 框内左右留空
const LAYOUT_GAP := 16.0        ## 主副框间距
const SPACING_MAX := 40.0       ## 相邻牌最大间距
const SPACING_MIN := 8.0        ## 相邻牌最小间距（拥挤时收紧）
const MIN_USABLE_WIDTH := 100.0 ## 尺寸低于此值视为布局未就绪


var select_mode := ""   # "" | "discard" | "play"；空串时交互关闭
var selected: Array = []  # Array[Card]，选中的手牌（引用来自最近一次 render 的手牌）

var _widgets := {}            # Card → CardWidget（精准刷新，避免整排重建闪烁）
var _drag_selecting := false  # 左键按住滑动批量选择中
var _drag_target := false     # 本次拖选的目标态（首张牌的新态），滑过的牌对齐到该态
var _render_pending := false  # 布局未就绪时挂起的渲染请求
var _pending_hand: Array = []
var _pending_trump: TrumpInfo = null


func _process(_delta: float) -> void:
	if _render_pending and size.x >= MIN_USABLE_WIDTH:
		_render_pending = false
		_do_render(_pending_hand, _pending_trump)


## ============================= 渲染 =============================

## 全量渲染手牌（分区 / 排序 / 布局；已选中的牌保留选中视觉）
func render(hand: Array, trump: TrumpInfo) -> void:
	# 选中集合对齐当前权威手牌：剪除已不在手牌中的陈旧引用（2026-11-17 修复
	# 「牌不在手中」整局卡死——快速连打/暂停期出牌的渲染竞争可留下已打出牌的引用，
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


## 副牌显示排序：花色按 ♠→♥→♣→♦ 顺序分组，组内点数从大到小（A 前 5 后）
static func _side_display_cmp(a: Card, b: Card) -> bool:
	if a.suit != b.suit:
		return a.suit < b.suit
	return a.rank > b.rank


## 叫主前左区（确定常主：王与所有 2）排序键：大王 > 小王 > 各 2（♠→♥→♣→♦）
static func _pre_trump_main_key(c: Card) -> Array:
	if c.is_joker():
		return [2 if c.rank == Card.RANK_BIG_JOKER else 1, 0]
	return [0, -c.suit]


## 手牌：德州扑克桌面式分区——左框主牌、右框副牌（圆角虚线框），
## 每个区域内从左至右按从大到小排列。
## 叫主前同样分两块：王与所有 2（必然常主）进左框；四门花色普通牌进右框。
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
	# 主牌区（左框）：从大到小。叫主后按 3.1 牌力（大王→…→主5），
	# 牌力并列的副R/副2 再按花色分组（♠→♥→♣→♦）——同花色相邻便于识读；
	# 叫主前为确定常主：大王 → 小王 → 各 2（♠→♥→♣→♦）
	if trump != null:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			var pa: int = trump.card_power(a)
			var pb: int = trump.card_power(b)
			if pa != pb:
				return pa > pb
			if a.suit != b.suit:
				return a.suit < b.suit
			return a.copy < b.copy)
	else:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return _pre_trump_main_key(a) > _pre_trump_main_key(b))
	# 副牌区（右框）：花色分组、组内从大到小
	side_cards.sort_custom(_side_display_cmp)

	var groups: Array = []
	if not trump_cards.is_empty():
		groups.append(trump_cards)  # 叫主前=确定常主（王/2），叫主后=主牌类
	if not side_cards.is_empty():
		groups.append(side_cards)
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
			var card_ref: Card = c
			card_widget.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						_on_card_left_press(card_ref)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						_on_card_right_press())
			_widgets[c] = card_widget
			add_child(card_widget)
			cx += spacing
		x += widths[i] + (LAYOUT_GAP if i == 0 and groups.size() == 2 else 0.0)


## ============================= 选牌交互 =============================
## 左键单击切换选中；按住左键滑动批量选择相邻牌（以首张的目标态对齐）；
## 右键在出牌模式下直接提交出牌（引擎校验，非法则提示原因）。

## 进入选牌模式：同模式连续轮次（如逐轮出牌）保留已选——出完一轮不重置选牌，
# 仅在模式切换（扣底→出牌 / 新局）时清空
func begin_select(mode: String) -> void:
	if select_mode != mode:
		select_mode = mode
		clear_selection()
	else:
		select_mode = mode


func end_select() -> void:
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
		# 相邻牌收不到 gui_input——对全部手牌做全局命中测试（引擎行为适配，非兜底）
		for card in _widgets:
			var w: CardWidget = _widgets[card]
			if w.get_global_rect().has_point(w.get_global_mouse_position()):
				_drag_hover(card)
				break


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
