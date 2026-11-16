extends Control
## 牌桌控制器（M2 单机完整对局）：人类 0 号位（下方），其余三家为 AiPolicy 电脑。
## 引擎（GameEngine）纯逻辑驱动，本脚本只做呈现与输入转发。


const HUMAN_SEAT := 0
const AI_DELAY := 0.7
const TRICK_PAUSE := 1.0

const SEAT_NAMES := ["甲（你）", "乙（电脑）", "丙（电脑）", "丁（电脑）"]

## 出牌显示锚点（相对比例 ×TrickArea 尺寸）：对称十字——
## 你=下方、丙=信息板正下方、乙/丁=面板朝桌心一侧
const TRICK_ANCHORS := {
	0: Vector2(0.419, 0.55),
	1: Vector2(0.604, 0.408),
	2: Vector2(0.419, 0.267),
	3: Vector2(0.234, 0.408),
}

## 皇冠动画落点（相对比例 ×窗口尺寸；仅人类 0 号位使用——其余座位动态计算名字位置）
const CROWN_TARGETS := {
	0: Vector2(0.258, 0.672),
}

## 主牌桌区域中心（相对比例）：画面分为左「主牌桌区域」（x 0~82.8%）与
## 右「侧信息板区域」（82.8%~100%），皇冠在主牌桌区域正中央出现
const MAIN_TABLE_CENTER := Vector2(0.414, 0.5)

var engine: GameEngine
var selected: Array = []   # Array[Card]，选中的手牌引用
var select_mode := ""      # "" | "discard" | "play"
var _last_trick_winner := -1
var _pending_trump_suit := -1
var _crown: CrownBadge = null
var _last_trump_shown = null  ## 上次送入信息栏的主牌（TrumpInfo 引用），避免重复重建
var _card_widgets := {}       ## Card → CardWidget（手牌精准刷新，避免整排重建闪烁）
var _drag_selecting := false  ## 左键按住滑动批量选择中
var _drag_target := false     ## 本次拖选的目标态（选中/取消），滑过的牌对齐到该态

## 选中牌上浮高度 = 牌高的 20%（交互规范，AGENTS.md 第 6 章）
const SELECT_LIFT_RATIO := 0.2
const HAND_BASE_Y := 16.0  ## 手牌基准 y（虚线框 frame_y 6 + 内边距 10）

var _ai_timer: Timer
var _trick_timer: Timer
var _pile_popup: PanelContainer   ## 悬停查看某玩家出牌历史的弹出层
var _human_pile_chip: Button      ## 人类玩家（0 号位）的牌堆悬停入口

@onready var game_info: Label = $TopBar/GameInfoLabel
@onready var bid_center_label: Label = $BidCenterLabel
@onready var sidebar: InfoSidebar = $Sidebar
@onready var toast_label: Label = $ToastLabel
@onready var hint_label: Label = $BottomArea/HintLabel
@onready var action_bar: HBoxContainer = $BottomArea/ActionBar
@onready var hand_row: Control = $BottomArea/HandRow
@onready var trick_area: Control = $TrickArea
@onready var result_panel: PanelContainer = $ResultPanel

## 座位 → SeatPanel 组件实例（0 号位无座位面板，手牌即呈现）。
## 布局使出牌顺序 0→1→2→3 在屏幕上呈逆时针：你(下) → 乙(右) → 丙(上) → 丁(左)
@onready var seat_panels := {
	1: $SeatRight as SeatPanel,
	2: $SeatTop as SeatPanel,
	3: $SeatLeft as SeatPanel,
}


func _ready() -> void:
	_ai_timer = Timer.new()
	_ai_timer.one_shot = true
	_ai_timer.wait_time = AI_DELAY
	add_child(_ai_timer)
	_trick_timer = Timer.new()
	_trick_timer.one_shot = true
	_trick_timer.wait_time = TRICK_PAUSE
	add_child(_trick_timer)

	sidebar.menu_pressed.connect(_on_menu)
	UiStyle.pad_button($ResultPanel/VBox/Buttons/NextButton)
	UiStyle.pad_button($ResultPanel/VBox/Buttons/MenuButton2)
	$ResultPanel/VBox/Buttons/NextButton.pressed.connect(_on_next_game)
	$ResultPanel/VBox/Buttons/MenuButton2.pressed.connect(_on_menu)

	engine = GameEngine.new()
	engine.auction_required.connect(_on_auction_required)
	engine.trump_required.connect(_on_trump_required)
	engine.discard_required.connect(_on_discard_required)
	engine.play_required.connect(_on_play_required)
	engine.trick_settled.connect(_on_trick_settled)
	engine.game_over.connect(_on_game_over)
	engine.phase_changed.connect(func(_p): _refresh())
	_setup_pile_ui()
	engine.start_session()
	_refresh()


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


## ============================= 玩家牌堆（悬停查看出牌历史） =============================

func _setup_pile_ui() -> void:
	# 人类玩家（0 号位）入口：左下角小按钮（手牌居中，不遮挡）
	_human_pile_chip = Button.new()
	_human_pile_chip.text = "牌堆"
	_human_pile_chip.add_theme_font_size_override("font_size", 14)
	UiStyle.pad_button(_human_pile_chip)
	_human_pile_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_human_pile_chip.offset_left = 12
	_human_pile_chip.offset_right = 58
	_human_pile_chip.offset_top = -196
	_human_pile_chip.offset_bottom = -166
	_human_pile_chip.mouse_entered.connect(func(): _show_pile(HUMAN_SEAT))
	_human_pile_chip.mouse_exited.connect(_hide_pile)
	add_child(_human_pile_chip)
	# 电脑玩家入口：各自座位面板悬停（SeatPanel 组件信号）
	for seat in seat_panels:
		var panel: SeatPanel = seat_panels[seat]
		panel.setup(seat)  # 注入座位号（组件悬停信号携带它定位牌堆）
		panel.pile_hovered.connect(_show_pile)
		panel.pile_exited.connect(_hide_pile)
	# 弹出层（居中，不拦截鼠标）
	_pile_popup = PanelContainer.new()
	_pile_popup.name = "PilePopup"
	_pile_popup.visible = false
	_pile_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pile_popup.set_anchors_preset(Control.PRESET_CENTER)
	_pile_popup.offset_left = -340
	_pile_popup.offset_top = -230
	_pile_popup.offset_right = 340
	_pile_popup.offset_bottom = 230
	add_child(_pile_popup)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	_pile_popup.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)


## 悬停某座位：按旧→新列出该玩家每轮的出牌（赢轮标 ✓ 高亮）
func _show_pile(seat: int) -> void:
	if engine == null:
		return
	var title: Label = _pile_popup.get_node("VBox/Title")
	title.text = "%s 的出牌（旧 → 新）" % SEAT_NAMES[seat]
	var list: VBoxContainer = _pile_popup.get_node("VBox/Scroll/List")
	for child in list.get_children():
		child.queue_free()
	var history: Array = engine.trick_history
	if history.is_empty():
		var empty := Label.new()
		empty.text = "暂无出牌记录"
		empty.add_theme_font_size_override("font_size", 14)
		empty.modulate = Color(0.8, 0.85, 0.9)
		list.add_child(empty)
	var round_no := 0
	for th in history:
		round_no += 1
		for play in th.plays:
			if play.seat != seat:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var is_winner: bool = th.winner == seat
			var tag := Label.new()
			tag.text = ("✓ " if is_winner else "") + "第%d轮" % round_no
			tag.add_theme_font_size_override("font_size", 13)
			tag.custom_minimum_size = Vector2(70, 0)
			tag.modulate = Color(1, 0.85, 0.3) if is_winner else Color(0.8, 0.85, 0.9)
			row.add_child(tag)
			for c in play.cards:
				row.add_child(CardWidget.create(c, true, true))
			list.add_child(row)
	_pile_popup.visible = true


func _hide_pile() -> void:
	if _pile_popup != null:
		_pile_popup.visible = false


func _on_next_game() -> void:
	result_panel.visible = false
	selected.clear()
	select_mode = ""
	_last_trick_winner = -1
	_clear_trick_area()
	engine.start_next_game()
	_refresh()


## ============================= 信号处理 =============================

func _on_auction_required(seat: int) -> void:
	# 新局拍卖开始：清除上一局的庄家皇冠
	if _crown != null:
		_crown.queue_free()
		_crown = null
	_refresh()
	if seat == HUMAN_SEAT:
		_show_auction_bar()
	else:
		hint_label.text = "等待 %s 表态…" % SEAT_NAMES[seat]
		_run_ai(func(): engine.submit_bid(seat, AiPolicy.choose_bid(engine.hands[seat], engine.current_highest_bid())))


func _on_trump_required(seat: int) -> void:
	_refresh()
	_play_crown_animation(seat)  # 拍卖结束：皇冠飞向出牌庄家
	if seat == HUMAN_SEAT:
		_show_trump_picker()
	else:
		hint_label.text = "等待 %s 叫主…" % SEAT_NAMES[seat]
		_run_ai(func():
			var choice: Dictionary = AiPolicy.choose_trump(engine.hands[seat])
			engine.submit_trump(seat, choice.suit, choice.rank))


## 皇冠：从主牌桌正中央放大出现，一边缩小一边减速移动，
## 停驻在出牌庄家名字首字之前，高度与名字字号一致。
func _play_crown_animation(seat: int) -> void:
	if _crown != null:
		_crown.queue_free()
	_crown = CrownBadge.new()
	_crown.size = Vector2(24, 18)  # 高度 = NameLabel 字号（18）
	_crown.pivot_offset = _crown.size / 2.0
	_crown.position = MAIN_TABLE_CENTER * size - _crown.size / 2.0  # 主牌桌区域正中央
	_crown.scale = Vector2(4, 4)
	_crown.z_index = 60
	add_child(_crown)
	await get_tree().process_frame  # 等待名字标签完成本帧布局
	if not is_inside_tree() or _crown == null:
		return
	var target: Vector2 = _crown_target(seat)
	var tw := create_tween()
	tw.set_parallel(true)
	# TRANS_CUBIC + EASE_OUT：起步快、逐渐减速（加速度减小）
	tw.tween_property(_crown, "position", target - _crown.size / 2.0, 1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_crown, "scale", Vector2.ONE, 1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 皇冠落点（中心）：庄家名字文字左缘前方；人类 0 号位无面板，用常量
func _crown_target(seat: int) -> Vector2:
	if seat == 0 or not seat_panels.has(seat):
		return CROWN_TARGETS[0] * size
	var name_label: Label = seat_panels[seat].get_node("VBox/NameLabel")
	var font: Font = name_label.get_theme_font("font")
	if font == null or name_label.text.is_empty():
		return CROWN_TARGETS[0] * size
	var font_size: int = name_label.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var center_x: float = name_label.global_position.x + name_label.size.x / 2.0
	var row_y: float = name_label.global_position.y + name_label.size.y / 2.0
	# 名字文字左缘再往前留 4px，皇冠中心再往左半个冠宽
	return Vector2(center_x - text_w / 2.0 - 4.0 - _crown.size.x / 2.0, row_y)


func _on_discard_required(seat: int) -> void:
	_refresh()
	if seat == HUMAN_SEAT:
		select_mode = "discard"
		selected.clear()
		_show_discard_bar()
		_show_bottom_cards()
		_render_hand()
	else:
		hint_label.text = "等待 %s 扣底…" % SEAT_NAMES[seat]
		_run_ai(func(): engine.submit_discard(seat, AiPolicy.choose_discard(engine.hands[seat], engine.trump)))


func _on_play_required(seat: int) -> void:
	if _trick_timer.time_left > 0:
		await _trick_timer.timeout
		if not is_inside_tree():
			return
	# 停留窗口结束：✓赢标记与牌面停留同步退场（先于新牌替换，避免多挂）
	_last_trick_winner = -1
	_refresh()
	if seat == HUMAN_SEAT:
		select_mode = "play"
		selected.clear()
		_render_hand()
		_show_play_bar()
	else:
		hint_label.text = "等待 %s 出牌…" % SEAT_NAMES[seat]
		_run_ai(func():
			var verdict: Dictionary = engine.submit_play(seat, AiPolicy.choose_play(engine, seat))
			if not verdict.legal:
				push_error("AI 出牌非法（座位 %d）：%s" % [seat, verdict.text]))


func _on_trick_settled(info: Dictionary) -> void:
	_last_trick_winner = info.winner
	_refresh()
	_trick_timer.start()


func _on_game_over(result: Dictionary) -> void:
	_refresh()
	select_mode = ""
	hint_label.text = ""
	# 末轮牌面停留 1 秒再弹结算面板
	if _trick_timer.time_left > 0:
		await _trick_timer.timeout
	if not is_inside_tree():
		return
	_show_result(result)


func _run_ai(action: Callable) -> void:
	_ai_timer.start()
	await _ai_timer.timeout
	if not is_inside_tree():
		return
	action.call()


## ============================= 人类操作面板 =============================

func _clear_action_bar() -> void:
	for child in action_bar.get_children():
		child.queue_free()


func _add_button(text: String, handler: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(120, 44)
	b.disabled = disabled
	UiStyle.pad_button(b)  # 文字与按钮边框留空 ≥ 半字号（UI 规范）
	b.pressed.connect(handler)
	action_bar.add_child(b)
	return b


func _show_auction_bar() -> void:
	_clear_action_bar()
	var highest := engine.current_highest_bid()
	if highest >= GameEngine.BID_CAP:
		hint_label.text = "叫分已封顶 200，只能放弃"
	else:
		var options: Array = []
		for increment in [5, 10, 15]:
			var v: int = highest + increment
			if v <= GameEngine.BID_CAP and not options.has(v):
				options.append(v)
		if not options.has(GameEngine.BID_CAP):
			options.append(GameEngine.BID_CAP)
		for v in options:
			_add_button("叫 %d" % v, func(): _submit_human_bid(v))
		hint_label.text = "轮到你表态（当前最高 %d）" % highest
	_add_button("放弃", func(): _submit_human_bid(GameEngine.BID_PASS))


func _submit_human_bid(value: int) -> void:
	var verdict := engine.submit_bid(HUMAN_SEAT, value)
	if not verdict.ok:
		_toast(verdict.error)
		return
	_clear_action_bar()


func _show_trump_picker() -> void:
	_clear_action_bar()
	_pending_trump_suit = -1
	hint_label.text = "你是出牌庄家，请先叫主（看底牌之前）：选择主花色"
	var suits := [
		["♠ 黑桃", Card.Suit.SPADE], ["♥ 红桃", Card.Suit.HEART],
		["♣ 梅花", Card.Suit.CLUB], ["♦ 方块", Card.Suit.DIAMOND],
	]
	for entry in suits:
		var suit: int = entry[1]
		_add_button(entry[0], func(): _pick_trump_suit(suit))


func _pick_trump_suit(suit: int) -> void:
	_pending_trump_suit = suit
	_clear_action_bar()
	hint_label.text = "主花色已选，再选常主点数 R（可任选，不必持有）"
	for r in Card.RANKS:
		var rank: int = r
		_add_button(Card.new(Card.Suit.JOKER, rank).label().replace("王", ""), func(): _submit_human_trump(rank))


func _submit_human_trump(rank: int) -> void:
	var verdict := engine.submit_trump(HUMAN_SEAT, _pending_trump_suit, rank)
	if not verdict.ok:
		_toast(verdict.error)
		return
	_clear_action_bar()


func _show_discard_bar() -> void:
	_clear_action_bar()
	_add_button("确认扣底（0/8）", func(): _submit_human_discard())
	hint_label.text = "翻底完成：请从手牌选 8 张扣回（建议副牌分牌）"


func _submit_human_discard() -> void:
	if selected.size() != GameEngine.BOTTOM_SIZE:
		_toast("须恰好选 8 张扣底（当前 %d 张）" % selected.size())
		return
	var verdict := engine.submit_discard(HUMAN_SEAT, selected.duplicate())
	if not verdict.ok:
		_toast(verdict.error)
		return
	select_mode = ""
	selected.clear()
	_clear_action_bar()
	_clear_bottom_cards()
	_refresh()


func _show_play_bar() -> void:
	_clear_action_bar()
	_add_button("出牌", func(): _submit_human_play())
	if engine.current_plays.is_empty():
		hint_label.text = "由你领出：选 1/2/4 张构成牌型（单张 / 对子 / 拖拉机）"
	else:
		hint_label.text = "轮到你跟牌：选与领出张数相同的牌"


func _submit_human_play() -> void:
	var verdict: Dictionary = engine.submit_play(HUMAN_SEAT, selected.duplicate())
	if not verdict.legal:
		_toast(verdict.text)
		return
	selected.clear()
	select_mode = ""
	_clear_action_bar()
	_refresh()


func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.visible = true
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_inside_tree():
			toast_label.visible = false)


## ============================= 呈现刷新 =============================

func _refresh() -> void:
	if engine == null:
		return
	_refresh_top_bar()
	_refresh_seats()
	_refresh_trick_area()
	_refresh_stats()
	_render_hand()
	if select_mode == "discard":
		_update_discard_button()


## 右下角手牌统计：主牌数量、副牌各花色数量、各点数数量（含王、2）
func _refresh_stats() -> void:
	if engine.hands.is_empty():
		return
	var hand: Array = engine.get_hand(HUMAN_SEAT)
	var trump := engine.trump
	var suit_chars := ["♠", "♥", "♣", "♦"]

	# 主副计数（叫主前王无花色，不计入花色）
	var trump_count := 0
	var suit_counts := {Card.Suit.SPADE: 0, Card.Suit.HEART: 0, Card.Suit.CLUB: 0, Card.Suit.DIAMOND: 0}
	for c in hand:
		if trump != null:
			if trump.is_trump(c):
				trump_count += 1
			else:
				suit_counts[c.suit] += 1
		elif not c.is_joker():
			suit_counts[c.suit] += 1
	var bits: Array[String] = []
	if trump == null:
		for s in Card.NORMAL_SUITS:
			bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		var main_text: String = "未叫主 ｜ " + " ".join(bits)
		var rank_rows := _build_rank_rows(hand)
		sidebar.update_stats(main_text, rank_rows)
	else:
		for s in Card.NORMAL_SUITS:
			if s != trump.suit:
				bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		sidebar.update_stats("主 %d ｜ 副 %s" % [trump_count, " ".join(bits)], _build_rank_rows(hand))


## 各点数数量行（含王、2）：[{text, present}]
func _build_rank_rows(hand: Array) -> Array:
	var rank_counts := {}
	for c in hand:
		rank_counts[c.rank] = int(rank_counts.get(c.rank, 0)) + 1
	var rank_names := {
		Card.RANK_5: "5", Card.RANK_7: "7", Card.RANK_8: "8", Card.RANK_9: "9",
		Card.RANK_10: "10", Card.RANK_J: "J", Card.RANK_Q: "Q", Card.RANK_K: "K",
		Card.RANK_A: "A", Card.RANK_2: "2",
		Card.RANK_SMALL_JOKER: "小王", Card.RANK_BIG_JOKER: "大王",
	}
	var rows: Array = []
	for rank in [Card.RANK_5, Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10,
			Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A, Card.RANK_2,
			Card.RANK_SMALL_JOKER, Card.RANK_BIG_JOKER]:
		rows.append([
			"%s×%d" % [rank_names[rank], int(rank_counts.get(rank, 0))],
			rank_counts.has(rank),
		])
	return rows


func _refresh_top_bar() -> void:
	var info := "第 %d 局" % engine.round_index
	if engine.phase == GameEngine.Phase.AUCTION:
		# 叫分提示显示在主牌桌正中央（本土用语，不用「拍卖」）
		bid_center_label.text = "叫分中（最高 %d）" % engine.current_highest_bid()
	elif engine.banker_seat >= 0:
		info += " ｜ 出牌庄 %s" % SEAT_NAMES[engine.banker_seat]
		if engine.contract > 0:
			info += " ｜ 叫分 %d" % engine.contract
	game_info.text = info
	if engine.phase != GameEngine.Phase.AUCTION:
		bid_center_label.text = ""
	# 主牌提示：一张「正 R」牌面放入信息栏（仅叫主变化时重建）
	if engine.trump != _last_trump_shown:
		_last_trump_shown = engine.trump
		if engine.trump != null:
			sidebar.set_trump(Card.new(engine.trump.suit, engine.trump.rank, 0))
		else:
			sidebar.set_trump(null)
	# 信息栏「局面」块
	var captured := "闲家捉分 %d" % engine.captured_points
	if engine.koudi_points > 0:
		captured += "（含抠底 %d）" % engine.koudi_points
	sidebar.set_state(captured, "累计：甲 %+d ｜ 乙 %+d\n　　　丙 %+d ｜ 丁 %+d" \
		% [engine.cumulative[0], engine.cumulative[1], engine.cumulative[2], engine.cumulative[3]])


func _refresh_seats() -> void:
	for seat in seat_panels:
		var panel: SeatPanel = seat_panels[seat]
		# 庄家由皇冠动画标记，面板不再显示「抓牌/庄」文字
		var status := ""
		match engine.phase:
			GameEngine.Phase.AUCTION:
				if engine.bids.size() > seat:
					if engine.bids[seat].passed:
						status = "已放弃"
					elif engine.bids[seat].value > 0:
						status = "叫 %d" % engine.bids[seat].value
			GameEngine.Phase.TRICKS:
				if _last_trick_winner == seat:
					status = "✓ 上轮赢"
		panel.set_info(SEAT_NAMES[seat], "%d 张" % engine.hand_count(seat), status)
		var is_turn: bool = (engine.phase == GameEngine.Phase.AUCTION and engine.auction_turn == seat) \
			or (engine.phase == GameEngine.Phase.TRICKS and engine.turn_seat == seat)
		panel.set_highlight(is_turn)


func _refresh_trick_area() -> void:
	_clear_trick_area()
	# 本轮各家出牌：TrickArea 为全屏层，锚点即屏幕绝对坐标（TRICK_ANCHORS 常量）。
	# 每家出牌显示在自己座位带内（你=手牌正上方、丙=上带右侧、
	# 乙/丁=面板朝向桌心一侧），互不遮挡座位信息。
	# 结算后 current_plays 已清空，改用 last_trick 快照停留展示（约 1 秒）
	var shown: Array = engine.current_plays
	if shown.is_empty():
		shown = engine.last_trick
	for play in shown:
		var seat: int = play.seat
		var box := VBoxContainer.new()
		var name_row := HBoxContainer.new()
		_add_name_label(name_row, SEAT_NAMES[seat])
		if _last_trick_winner == seat:
			_add_name_label(name_row, " ✓赢", Color(1, 0.85, 0.3))
		box.add_child(name_row)
		var cards_row := HBoxContainer.new()
		cards_row.add_theme_constant_override("separation", 3)
		for c in play.cards:
			cards_row.add_child(CardWidget.create(c, true, true))
		box.add_child(cards_row)
		trick_area.add_child(box)
		var width: int = play.cards.size() * 48 + 8
		var base: Vector2 = TRICK_ANCHORS[seat] * trick_area.size  # 相对锚点 × 层尺寸
		box.position = base - Vector2(width / 2.0, 12)
	# 新一轮开始（无快照、至多只有领出）时清除赢家标记
	if engine.last_trick.is_empty() and engine.current_plays.size() <= 1:
		_last_trick_winner = -1


func _add_name_label(row: HBoxContainer, text: String, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = color
	row.add_child(l)
	row.alignment = BoxContainer.ALIGNMENT_CENTER


func _clear_trick_area() -> void:
	for child in trick_area.get_children():
		if child.name != "BottomCards":
			child.queue_free()


## 人类庄家翻底阶段：中央展示 8 张底牌（仅本人可见，规则 2）
func _show_bottom_cards() -> void:
	_clear_bottom_cards()
	var box := VBoxContainer.new()
	box.name = "BottomCards"
	var title := Label.new()
	title.text = "底牌（仅你可见）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 4)
	for c in engine.peek_bottom(HUMAN_SEAT):
		cards_row.add_child(CardWidget.create(c, true, true))
	box.add_child(cards_row)
	trick_area.add_child(box)
	box.position = Vector2(0.419, 0.417) * trick_area.size - Vector2(220, 40)  # 牌桌中央


func _clear_bottom_cards() -> void:
	var node := trick_area.get_node_or_null("BottomCards")
	if node != null:
		node.queue_free()


func _update_discard_button() -> void:
	for child in action_bar.get_children():
		if child is Button:
			child.text = "确认扣底（%d/8）" % selected.size()


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
func _render_hand() -> void:
	for child in hand_row.get_children():
		child.queue_free()
	_card_widgets.clear()
	_drag_selecting = false
	if engine == null or engine.hands.is_empty():
		return
	var trump := engine.trump
	var trump_cards: Array = []
	var side_cards: Array = []
	for c in engine.get_hand(HUMAN_SEAT):
		var is_main: bool
		if trump != null:
			is_main = trump.is_trump(c)
		else:
			is_main = c.is_joker() or c.rank == Card.RANK_2
		if is_main:
			trump_cards.append(c)
		else:
			side_cards.append(c)
	# 主牌区（左框）：从大到小。叫主后按 3.1 牌力（大王→…→主5）；
	# 叫主前为确定常主：大王 → 小王 → 各 2（♠→♥→♣→♦）
	if trump != null:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return trump.card_power(a) > trump.card_power(b))
	else:
		trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
			return _pre_trump_main_key(a) > _pre_trump_main_key(b))
	# 副牌区（右框）：花色分组、组内从大到小
	side_cards.sort_custom(_side_display_cmp)

	var groups: Array = []
	if trump != null and not trump_cards.is_empty():
		groups.append(trump_cards)
	if not side_cards.is_empty():
		groups.append(side_cards)
	if groups.is_empty():
		return

	var avail: float = hand_row.size.x
	if avail < 100:
		avail = 1100.0  # 首帧布局未就绪时的兜底宽度
	var card_w := CardWidget.SIZE_NORMAL.x
	var card_h := CardWidget.SIZE_NORMAL.y
	var pad := 10.0
	var gap := 16.0
	var n := trump_cards.size() + side_cards.size()
	var spacing := 40.0
	if n > 2:
		spacing = (avail - gap - 4 * pad - 2 * card_w) / (n - 2)
	spacing = clampf(spacing, 8, 40)

	var widths: Array = []
	for g in groups:
		widths.append(card_w + spacing * (g.size() - 1) + 2 * pad)
	var total: float = 0.0
	for w in widths:
		total += w
	if groups.size() == 2:
		total += gap
	var x := (avail - total) / 2.0
	var frame_h := card_h + 2 * pad
	var frame_y := 6.0  # 固定纵向位置：不随布局高度变化，避免整排手牌上下漂移

	for i in groups.size():
		var g: Array = groups[i]
		var frame := DashedRoundedFrame.new()
		frame.position = Vector2(x, frame_y)
		frame.size = Vector2(widths[i], frame_h)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_row.add_child(frame)
		var cx: float = x + pad
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
						_on_hand_card_left_press(card_ref)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						_on_hand_card_right_press())
			_card_widgets[c] = card_widget
			hand_row.add_child(card_widget)
			cx += spacing
		x += widths[i] + (gap if i == 0 and groups.size() == 2 else 0.0)


## ============================= 手牌交互 =============================
## 左键单击切换选中；按住左键滑动批量选择相邻牌（以首张的目标态对齐）；
## 右键在出牌模式下直接提交出牌（引擎校验，非法则提示原因）。

func _on_hand_card_left_press(card: Card) -> void:
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
	if select_mode == "discard":
		_update_discard_button()


func _on_hand_card_right_press() -> void:
	if select_mode == "play" and not selected.is_empty():
		_submit_human_play()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_selecting = false  # 左键松开（任何位置）结束拖选
	elif event is InputEventMouseMotion and _drag_selecting:
		# 按住鼠标期间 Godot 把 motion 路由给按下时的控件（mouse_focus 捕获），
		# 相邻牌收不到 gui_input——此处对全部手牌做全局命中测试
		for card in _card_widgets:
			var w: CardWidget = _card_widgets[card]
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
			_toast("最多选择 8 张")
			return
		selected.append(card)
		_apply_card_visual(card, true)
	if select_mode == "discard":
		_update_discard_button()


## 精准更新一张牌的选中视觉（金边 + 上浮 20%），不重建整排手牌
func _apply_card_visual(card: Card, sel: bool) -> void:
	var widget: CardWidget = _card_widgets.get(card)
	if widget == null:
		return
	widget.set_selected(sel)
	widget.position.y = HAND_BASE_Y - (CardWidget.SIZE_NORMAL.y * SELECT_LIFT_RATIO if sel else 0)


## ============================= 结算面板 =============================

func _show_result(result: Dictionary) -> void:
	var title: Label = result_panel.get_node("VBox/ResultTitle")
	var detail: Label = result_panel.get_node("VBox/ResultDetail")
	var side := "闲家胜" if not result.banker_won else "庄家胜"
	title.text = "%s %d 级！" % [side, result.level]
	title.modulate = Color(1, 0.9, 0.4) if result.banker_won else Color(0.5, 0.95, 0.6)
	var koudi_text := "无"
	if result.koudi_points > 0:
		var multiplier: int = 2 if result.koudi_points == result.bottom_points * 2 else 1
		koudi_text = "底牌 %d 分 × %d = %d" % [result.bottom_points, multiplier, result.koudi_points]
	var lines := [
		"出牌庄家：%s ｜ 叫分 %d" % [SEAT_NAMES[result.banker_seat], result.contract],
		"闲家捉分 %d ＋ 抠底 %d ＝ %d" % [result.captured_points, result.koudi_points, result.captured_total],
		"总分 %d ＋ 捉分 ＝ %s（胜线 205）" % [result.contract, str(result.total_score)],
		"抠底：%s" % koudi_text,
		"本局收益：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d（B=1）" % [result.payments[0], result.payments[1], result.payments[2], result.payments[3]],
		"累计：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d" % [result.cumulative[0], result.cumulative[1], result.cumulative[2], result.cumulative[3]],
	]
	detail.text = "\n".join(lines)
	result_panel.visible = true
