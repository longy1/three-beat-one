extends Control
## 牌桌控制器（M2 单机完整对局）：人类 0 号位（下方），其余三家为 AiPolicy 电脑。
## 引擎（GameEngine）纯逻辑驱动，本脚本只做呈现与输入转发。


const HUMAN_SEAT := 0
const AI_DELAY := 0.7
const TRICK_PAUSE := 1.0

const SEAT_NAMES := ["甲（你）", "乙（电脑）", "丙（电脑）", "丁（电脑）"]

var engine: GameEngine
var selected: Array = []   # Array[Card]，选中的手牌引用
var select_mode := ""      # "" | "discard" | "play"
var _last_trick_winner := -1
var _pending_trump_suit := -1

var _ai_timer: Timer
var _trick_timer: Timer

@onready var game_info: Label = $TopBar/GameInfoLabel
@onready var trump_label: Label = $TopBar/TrumpLabel
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var toast_label: Label = $ToastLabel
@onready var hint_label: Label = $BottomArea/HintLabel
@onready var action_bar: HBoxContainer = $BottomArea/ActionBar
@onready var hand_row: Control = $BottomArea/HandRow
@onready var trick_area: Control = $TrickArea
@onready var result_panel: PanelContainer = $ResultPanel

## 座位 → 呈现节点（0 号位无座位面板，手牌即呈现）。
## 布局使出牌顺序 0→1→2→3 在屏幕上呈逆时针：你(下) → 乙(右) → 丙(上) → 丁(左)
@onready var seat_panels := {
	1: $SeatRight,
	2: $SeatTop,
	3: $SeatLeft,
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

	$TopBar/MenuButton.pressed.connect(_on_menu)
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
	engine.start_session()
	_refresh()


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
	_refresh()
	if seat == HUMAN_SEAT:
		_show_auction_bar()
	else:
		hint_label.text = "等待 %s 表态…" % SEAT_NAMES[seat]
		_run_ai(func(): engine.submit_bid(seat, AiPolicy.choose_bid(engine.hands[seat], engine.current_highest_bid())))


func _on_trump_required(seat: int) -> void:
	_refresh()
	if seat == HUMAN_SEAT:
		_show_trump_picker()
	else:
		hint_label.text = "等待 %s 叫主…" % SEAT_NAMES[seat]
		_run_ai(func():
			var choice: Dictionary = AiPolicy.choose_trump(engine.hands[seat])
			engine.submit_trump(seat, choice.suit, choice.rank))


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
	var main_label: Label = $StatsPanel/VBox/MainLabel
	var bits: Array[String] = []
	if trump == null:
		for s in Card.NORMAL_SUITS:
			bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		main_label.text = "未叫主 ｜ " + " ".join(bits)
	else:
		for s in Card.NORMAL_SUITS:
			if s != trump.suit:
				bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		main_label.text = "主 %d ｜ 副 %s" % [trump_count, " ".join(bits)]

	# 各点数数量（含王、2）
	var grid: GridContainer = $StatsPanel/VBox/RankGrid
	for child in grid.get_children():
		child.queue_free()
	var rank_counts := {}
	for c in hand:
		rank_counts[c.rank] = int(rank_counts.get(c.rank, 0)) + 1
	var rank_names := {
		Card.RANK_5: "5", Card.RANK_7: "7", Card.RANK_8: "8", Card.RANK_9: "9",
		Card.RANK_10: "10", Card.RANK_J: "J", Card.RANK_Q: "Q", Card.RANK_K: "K",
		Card.RANK_A: "A", Card.RANK_2: "2",
		Card.RANK_SMALL_JOKER: "小王", Card.RANK_BIG_JOKER: "大王",
	}
	for rank in [Card.RANK_5, Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10,
			Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A, Card.RANK_2,
			Card.RANK_SMALL_JOKER, Card.RANK_BIG_JOKER]:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 12)
		l.text = "%s×%d" % [rank_names[rank], int(rank_counts.get(rank, 0))]
		l.modulate = Color(1, 1, 1) if rank_counts.has(rank) else Color(1, 1, 1, 0.35)
		grid.add_child(l)


func _refresh_top_bar() -> void:
	var info := "第 %d 局" % engine.round_index
	if engine.phase == GameEngine.Phase.AUCTION:
		info += " ｜ 叫分拍卖中（最高 %d）" % engine.current_highest_bid()
	elif engine.banker_seat >= 0:
		info += " ｜ 抓牌庄 %s ｜ 出牌庄 %s" % [SEAT_NAMES[engine.dealer_seat], SEAT_NAMES[engine.banker_seat]]
		if engine.contract > 0:
			info += " ｜ 叫分 %d" % engine.contract
	game_info.text = info
	if engine.trump != null:
		var suit_char: String = ["♠", "♥", "♣", "♦"][engine.trump.suit]
		var rank_name := Card.new(Card.Suit.JOKER, engine.trump.rank).label().replace("王", "")
		trump_label.text = "主：%s ｜ R = %s" % [suit_char, rank_name]
	else:
		trump_label.text = "未叫主"
	var score := "闲家捉分 %d" % engine.captured_points
	if engine.koudi_points > 0:
		score += "（含抠底 %d）" % engine.koudi_points
	score += " ｜ 累计 甲%+d 乙%+d 丙%+d 丁%+d" % [engine.cumulative[0], engine.cumulative[1], engine.cumulative[2], engine.cumulative[3]]
	score_label.text = score


func _refresh_seats() -> void:
	for seat in seat_panels:
		var panel: PanelContainer = seat_panels[seat]
		var name_label: Label = panel.get_node("VBox/NameLabel")
		var count_label: Label = panel.get_node("VBox/CountLabel")
		var status_label: Label = panel.get_node("VBox/StatusLabel")
		var title: String = SEAT_NAMES[seat]
		if engine.dealer_seat == seat:
			title += " ·抓牌"
		if engine.banker_seat == seat:
			title += " ·庄"
		name_label.text = title
		count_label.text = "%d 张" % engine.hand_count(seat)
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
		status_label.text = status
		var is_turn: bool = (engine.phase == GameEngine.Phase.AUCTION and engine.auction_turn == seat) \
			or (engine.phase == GameEngine.Phase.TRICKS and engine.turn_seat == seat)
		panel.modulate = Color(1.15, 1.12, 0.85) if is_turn else Color.WHITE


func _refresh_trick_area() -> void:
	_clear_trick_area()
	# 本轮各家出牌（与座位布局一致，逆时针）：0 下、1 右、2 上、3 左
	var anchors := {
		0: Vector2(320, 210),
		1: Vector2(560, 105),
		2: Vector2(320, 10),
		3: Vector2(80, 105),
	}
	for play in engine.current_plays:
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
		box.position = anchors[seat] - Vector2(width / 2.0, 12)
	if engine.current_plays.is_empty():
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
	box.position = Vector2(320, 110) - Vector2(220, 30)


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


## 手牌：德州扑克桌面式分区——左框主牌、右框副牌（圆角虚线框），
## 每个区域内从左至右按从大到小排列。
func _render_hand() -> void:
	for child in hand_row.get_children():
		child.queue_free()
	if engine == null or engine.hands.is_empty():
		return
	var trump := engine.trump
	var trump_cards: Array = []
	var side_cards: Array = []
	for c in engine.get_hand(HUMAN_SEAT):
		if trump != null and trump.is_trump(c):
			trump_cards.append(c)
		else:
			side_cards.append(c)
	# 主牌区：3.1 牌力从大到小（大王最左 → 主5 最右）
	trump_cards.sort_custom(func(a: Card, b: Card) -> bool:
		return trump.card_power(a) > trump.card_power(b))
	# 副牌区：花色分组、组内从大到小；叫主前无主牌区，全部进副牌区
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
	var frame_y := 2.0
	if hand_row.size.y > frame_h + 8:
		frame_y = (hand_row.size.y - frame_h) / 2.0

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
			card_widget.position = Vector2(cx, frame_y + pad - (8 if is_selected else 0))
			var card_ref: Card = c
			card_widget.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_toggle_select(card_ref))
			hand_row.add_child(card_widget)
			cx += spacing
		x += widths[i] + (gap if i == 0 and groups.size() == 2 else 0.0)


func _toggle_select(card: Card) -> void:
	if select_mode == "":
		return
	if selected.has(card):
		selected.erase(card)
	else:
		if select_mode == "discard" and selected.size() >= GameEngine.BOTTOM_SIZE:
			_toast("最多选择 8 张")
			return
		selected.append(card)
	_render_hand()
	if select_mode == "discard":
		_update_discard_button()


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
