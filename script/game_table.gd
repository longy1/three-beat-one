extends Control
## 牌桌控制器（M2 单机完整对局）：人类 0 号位（下方），其余三家为 AiPolicy 电脑。
## 引擎（GameEngine）纯逻辑驱动，本脚本只做呈现编排与输入转发。
## 组件分工：HandArea（手牌区）/ PileViewer（牌堆弹层）/ ActionBar（操作按钮条）/
## TrumpRankPicker（叫主点数面板）/ CrownAnimator（皇冠动画）——各自持有职责状态。
## 刷新纪律：_refresh() 是唯一刷新入口，仅由引擎信号处理器调用；
## 按钮界面只由 *_required 处理器重建（ActionBar.reset 幂等清理）。


const HUMAN_SEAT := 0
const AI_DELAY := 0.7
const AI_DISCARD_DELAY := 1.0  ## AI 庄家扣底节奏（2026-11-17）：关键决策点多停约 1 秒，太快看不清翻底
const TRICK_PAUSE := 1.5  ## 一轮结算后牌面停留时长；到期主动清空出牌桌

const SEAT_NAMES := ["甲（你）", "乙（电脑）", "丙（电脑）", "丁（电脑）"]

## 出牌显示锚点（相对比例 ×TrickArea 尺寸）：对称十字——
## 你=下方、丙=信息板正下方、乙/丁=面板朝桌心一侧
const TRICK_ANCHORS := {
	0: Vector2(0.419, 0.55),
	1: Vector2(0.604, 0.408),
	2: Vector2(0.419, 0.28),
	3: Vector2(0.234, 0.408),
}

var engine: GameEngine
var _piles: PileViewer
var _crown_anim := CrownAnimator.new()
var _trump_picker: TrumpRankPicker = null
var _discard_button: Button = null       ## 扣底确认按钮（计数文案更新用）
var _pending_trump_suit := -1
var _last_trick_winner := -1
var _trick_display_cleared := false      ## 停留结束后已主动清空上一轮牌面
var _last_trump_shown = null             ## 上次送入信息栏的主牌（TrumpInfo 引用），避免重复重建

var _ai_timer: Timer
var _trick_timer: Timer
var _ai_delay_scale := 1.0  ## AI 延迟缩放（UI 测试调小以加速；_run_ai 按比例设置 wait_time）

@onready var game_info: Label = $TopBar/GameInfoLabel
@onready var bid_center_label: Label = $BidCenterLabel
@onready var sidebar: InfoSidebar = $Sidebar
@onready var toast_label: Label = $ToastLabel
@onready var hint_label: Label = $BottomArea/HintLabel
@onready var action_bar: ActionBar = $BottomArea/ActionBar
@onready var hand_area: HandArea = $BottomArea/HandRow
@onready var trick_area: Control = $TrickArea
@onready var result_panel: PanelContainer = $ResultPanel
@onready var human_void_stamp: VoidStamp = $HumanVoidStamp
@onready var result_title: Label = $ResultPanel/VBox/ResultTitle
@onready var result_detail: Label = $ResultPanel/VBox/ResultDetail
@onready var result_next_button: Button = $ResultPanel/VBox/Buttons/NextButton
@onready var result_menu_button: Button = $ResultPanel/VBox/Buttons/MenuButton

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
	_trick_timer.timeout.connect(_on_trick_pause_ended)
	add_child(_trick_timer)

	sidebar.menu_pressed.connect(_on_menu)
	UiStyle.pad_button(result_next_button)
	UiStyle.pad_button(result_menu_button)
	result_next_button.pressed.connect(_on_next_game)
	result_menu_button.pressed.connect(_on_menu)
	human_void_stamp.visible = false  # 【无主】印章默认隐藏（公示后显示）

	engine = GameEngine.new()
	engine.auction_required.connect(_on_auction_required)
	engine.trump_required.connect(_on_trump_required)
	engine.discard_required.connect(_on_discard_required)
	engine.play_required.connect(_on_play_required)
	engine.trick_settled.connect(_on_trick_settled)
	engine.game_over.connect(_on_game_over)
	engine.engine_fault.connect(_on_engine_fault)

	hand_area.selection_changed.connect(_on_selection_changed)
	hand_area.select_capped.connect(func(): _toast("最多选择 8 张"))
	hand_area.play_requested.connect(_submit_human_play)
	_piles = PileViewer.new()
	_piles.setup(self)
	_piles.history_chip.mouse_entered.connect(func(): _piles.show_history(HUMAN_SEAT, engine.trick_history, SEAT_NAMES))
	_piles.history_chip.mouse_exited.connect(_piles.hide_timer.start)
	_piles.bottom_button.mouse_entered.connect(func():
		if engine.banker_seat == HUMAN_SEAT:
			_piles.show_bottom(engine.buried))
	_piles.bottom_button.mouse_exited.connect(_piles.hide_timer.start)
	for seat in seat_panels:
		var panel: SeatPanel = seat_panels[seat]
		panel.setup(seat)  # 注入座位号（组件悬停信号携带它定位牌堆）
		panel.pile_hovered.connect(func(s: int): _piles.show_history(s, engine.trick_history, SEAT_NAMES))
		panel.pile_exited.connect(_piles.hide_timer.start)  # 裸 Callable 直连；写成 func(): xxx.start 是求值不调用（曾致弹层永久滞留）

	engine.start_session()  # 同步发出首个 auction_required，由处理器完成首帧刷新


func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


## ============================= 引擎信号处理 =============================
## 纪律：座位非人类时统一 action_bar.reset()——按钮界面只在人类轮到时存在，
## submit 提交方法因此无须任何清理（旧版「不得清理」竞态补丁的根治点）。

func _on_auction_required(seat: int) -> void:
	_crown_anim.clear()  # 新局拍卖开始：清除上一局的庄家皇冠
	_refresh()
	if seat == HUMAN_SEAT:
		_show_auction_bar()
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 表态…" % SEAT_NAMES[seat]
		_run_ai(func(): engine.submit_bid(seat, AiPolicy.choose_bid(engine.hands[seat], engine.current_highest_bid())))


func _on_trump_required(seat: int) -> void:
	_refresh()
	_crown_anim.play(self, seat, seat_panels)  # 拍卖结束：皇冠飞向出牌庄家
	if seat == HUMAN_SEAT:
		_show_trump_picker()
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 叫主…" % SEAT_NAMES[seat]
		_run_ai(func():
			var choice: Dictionary = AiPolicy.choose_trump(engine.hands[seat])
			engine.submit_trump(seat, choice.suit, choice.rank))


func _on_discard_required(seat: int) -> void:
	_refresh()
	if seat == HUMAN_SEAT:
		hand_area.begin_select("discard")
		_show_discard_bar()
		_show_bottom_cards()
		_render_hand()
		# 底牌 8 张入手即呈选中（拿起）态：方便观察牌面，可直接确认扣回或调整
		hand_area.select_cards(engine.kitty)
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 扣底…" % SEAT_NAMES[seat]
		_run_ai(func(): engine.submit_discard(seat, AiPolicy.choose_discard(engine.hands[seat], engine.trump)), AI_DISCARD_DELAY)


func _on_play_required(seat: int) -> void:
	if _trick_timer.time_left > 0:
		await _trick_timer.timeout
		if not is_inside_tree():
			return
	# 停留窗口结束：清 ✓ 赢家标记并主动清空上一轮牌面（不再等新牌替换）
	_last_trick_winner = -1
	_trick_display_cleared = true
	_refresh()
	if seat == HUMAN_SEAT:
		hand_area.begin_select("play")
		_render_hand()
		_show_play_bar()
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 出牌…" % SEAT_NAMES[seat]
		_run_ai(func():
			var verdict: Dictionary = engine.submit_play(seat, AiPolicy.choose_play(engine, seat))
			if not verdict.legal:
				push_error("AI 出牌非法（座位 %d）：%s" % [seat, verdict.text]))


func _on_trick_settled(info: Dictionary) -> void:
	_last_trick_winner = info.winner
	_trick_display_cleared = false
	_refresh()
	_trick_timer.start()  # 结算停留 1.5s，到期主动清空牌面（_on_trick_pause_ended）


func _on_game_over(result: Dictionary) -> void:
	_refresh()
	hand_area.end_select()
	action_bar.reset()
	hint_label.text = ""
	# 末轮牌面停留结束后再弹结算面板
	if _trick_timer.time_left > 0:
		await _trick_timer.timeout
	if not is_inside_tree():
		return
	_show_result(result)


## 结算停留到期：清 ✓ 赢家标记、主动清空出牌桌（1.5 秒后，不依赖下一手替换）
func _on_trick_pause_ended() -> void:
	_last_trick_winner = -1
	_trick_display_cleared = true
	_refresh()


## 引擎内部一致性破坏（正常对局不会发生）：显性提示，冻结等待诊断
func _on_engine_fault(message: String) -> void:
	hint_label.text = "引擎异常：%s" % message
	_toast("引擎异常，对局已冻结（详见日志）")


func _run_ai(action: Callable, delay := AI_DELAY) -> void:
	_ai_timer.wait_time = delay * _ai_delay_scale
	_ai_timer.start()
	await _ai_timer.timeout
	if not is_inside_tree():
		return
	action.call()


## ============================= 人类操作面板 =============================

func _show_auction_bar() -> void:
	action_bar.reset()
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
			action_bar.add_button("叫 %d" % v, func(): _submit_human_bid(v))
		hint_label.text = "轮到你表态（当前最高 %d）" % highest
	action_bar.add_button("放弃", func(): _submit_human_bid(GameEngine.BID_PASS))


func _submit_human_bid(value: int) -> void:
	var verdict := engine.submit_bid(HUMAN_SEAT, value)
	if not verdict.ok:
		_toast(verdict.error)
	# 后续由下一个 *_required 处理器统一重建按钮（人类轮→新面板；AI 轮→reset）


func _show_trump_picker() -> void:
	action_bar.reset()
	_close_trump_picker()
	_pending_trump_suit = -1
	hint_label.text = "你是出牌庄家，请先叫主（看底牌之前）：选择主花色"
	var suits := [
		["♠ 黑桃", Card.Suit.SPADE], ["♥ 红桃", Card.Suit.HEART],
		["♣ 梅花", Card.Suit.CLUB], ["♦ 方块", Card.Suit.DIAMOND],
	]
	for entry in suits:
		var suit: int = entry[1]
		action_bar.add_button(entry[0], func(): _pick_trump_suit(suit))


func _pick_trump_suit(suit: int) -> void:
	_pending_trump_suit = suit
	action_bar.reset()
	hint_label.text = "主花色已选，再选常主点数 R（可任选，不必持有）"
	_trump_picker = TrumpRankPicker.new()
	_trump_picker.name = "TrumpRankPicker"
	_trump_picker.rank_picked.connect(_submit_human_trump)
	add_child(_trump_picker)


func _close_trump_picker() -> void:
	if _trump_picker != null:
		_trump_picker.queue_free()
		_trump_picker = null


func _submit_human_trump(rank: int) -> void:
	var verdict := engine.submit_trump(HUMAN_SEAT, _pending_trump_suit, rank)
	if not verdict.ok:
		_toast(verdict.error)
		return
	_close_trump_picker()
	# submit_trump 同步进入扣底阶段：discard_required 处理器已重建扣底界面


func _show_discard_bar() -> void:
	action_bar.reset()
	_discard_button = action_bar.add_button("确认扣底（0/8）", func(): _submit_human_discard())
	hint_label.text = "翻底完成：请从手牌选 8 张扣回（建议副牌分牌）"


func _submit_human_discard() -> void:
	if hand_area.selected.size() != GameEngine.BOTTOM_SIZE:
		_toast("须恰好选 8 张扣底（当前 %d 张）" % hand_area.selected.size())
		return
	var verdict := engine.submit_discard(HUMAN_SEAT, hand_area.selected.duplicate())
	if not verdict.ok:
		_toast(verdict.error)
		return
	# submit_discard 同步触发 play_required：处理器已重建出牌阶段界面
	_clear_bottom_cards()


func _show_play_bar() -> void:
	action_bar.reset()
	action_bar.add_button("出牌", func(): _submit_human_play())
	if engine.current_plays.is_empty():
		hint_label.text = "由你领出：选 1/2/4 张构成牌型（单张 / 对子 / 拖拉机）；" \
			+ "三家均已无主时可多张主牌单张一起甩出"
	else:
		hint_label.text = "轮到你跟牌：选与领出张数相同的牌"


func _submit_human_play() -> void:
	var picked: Array = hand_area.selected.duplicate()
	var verdict: Dictionary = engine.submit_play(HUMAN_SEAT, picked)
	if not verdict.legal:
		_toast(verdict.text)
		return
	# 已打出的牌从选中集合移除，其余选择跨轮保留（出完一轮不重置选牌）
	hand_area.consume_selected(picked)
	# 立即清掉旧「出牌」按钮：出牌后常伴结算停留（1.5s），期间下一个 *_required
	# 处理器在 await 挂起、不会同步重建——不清会让旧按钮（还能点！）挂满停留期。
	# 安全性：人类出牌的下一手必为 AI 或进入结算，处理器重建都发生在挂起恢复之后，
	# 此处清理不会误删同步重建的新按钮（其余 submit_* 的下一个处理器是同步重建，
	# 那些仍遵守「submit 不做清理」纪律）。
	action_bar.reset()


## 手牌选择数变化：扣底按钮计数联动
func _on_selection_changed(count: int) -> void:
	if _discard_button != null and not _discard_button.is_queued_for_deletion():
		_discard_button.text = "确认扣底（%d/8）" % count


func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.visible = true
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_inside_tree():
			toast_label.visible = false)


## ============================= 呈现刷新（唯一入口 _refresh） =============================

func _refresh() -> void:
	if engine == null:
		return
	_refresh_top_bar()
	_refresh_seats()
	_refresh_trick_area()
	_refresh_stats()
	_render_hand()
	# 历史弹层悬停阅读期间历史增长 → 就地刷新（状态驱动：随引擎信号走，非定时轮询）
	_piles.refresh_history(engine.trick_history, SEAT_NAMES)
	# 庄家是自己时：皇冠下方「牌堆」按钮显示（扣底完成后才有底牌可看）
	var show_bottom := engine.banker_seat == HUMAN_SEAT \
		and (engine.phase == GameEngine.Phase.TRICKS or engine.phase == GameEngine.Phase.SETTLED)
	_piles.set_bottom_button_visible(show_bottom)


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
			sidebar.set_trump(Card.new(engine.trump.suit, engine.trump.rank))
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
		# 庄家由皇冠动画标记，面板不显示「抓牌/庄」文字
		var status := ""
		match engine.phase:
			GameEngine.Phase.AUCTION:
				if engine.has_passed(seat):
					status = "已放弃"
				elif engine.bid_value(seat) > 0:
					status = "叫 %d" % engine.bid_value(seat)
			GameEngine.Phase.TRICKS:
				if _last_trick_winner == seat:
					status = "✓ 上轮赢"
		panel.set_info(SEAT_NAMES[seat], "%d 张" % engine.hand_count(seat), status)
		var is_turn: bool = (engine.phase == GameEngine.Phase.AUCTION and engine.auction.turn == seat) \
			or (engine.phase == GameEngine.Phase.TRICKS and engine.turn_seat == seat)
		panel.set_highlight(is_turn)
		panel.set_void_trump(engine.trump_void_seats[seat])  # 【无主】公示印章（7.3）
	# 人类 0 号位无面板：印章盖在手牌区上方左侧（与历史按钮同列）
	human_void_stamp.visible = engine.trump_void_seats[HUMAN_SEAT]


func _refresh_trick_area() -> void:
	_clear_trick_area()
	# 本轮各家出牌：TrickArea 为全屏层，锚点即屏幕绝对坐标（TRICK_ANCHORS 常量）。
	# 每家出牌显示在自己座位带内（你=手牌正上方、丙=上带右侧、
	# 乙/丁=面板朝向桌心一侧），互不遮挡座位信息。
	# 结算后 current_plays 已清空，改用 get_last_trick() 派生快照停留展示；
	# 停留结束（_on_trick_pause_ended）主动清空，不再显示上一轮
	var shown: Array = engine.current_plays
	if shown.is_empty() and not _trick_display_cleared:
		shown = engine.get_last_trick()
	for play in shown:
		var seat: int = play.seat
		# 出牌区只渲染牌（归属信息在姓名版）；赢家标记见姓名版「✓ 上轮赢」。
		# 卡牌尺寸按张数自适应：≤2 张正常、≥3 张中号（拖拉机不遮挡姓名版）
		var card_size: Vector2 = CardWidget.SIZE_NORMAL if play.cards.size() <= 2 \
				else CardWidget.SIZE_MEDIUM
		var cards_row := HBoxContainer.new()
		cards_row.add_theme_constant_override("separation", 4)
		for c in play.cards:
			cards_row.add_child(CardWidget.create_sized(c, true, card_size))
		trick_area.add_child(cards_row)
		var width: float = play.cards.size() * (card_size.x + 4)
		var base: Vector2 = TRICK_ANCHORS[seat] * trick_area.size  # 相对锚点 × 层尺寸
		cards_row.position = base - Vector2(width / 2.0, card_size.y / 2.0)


func _clear_trick_area() -> void:
	for child in trick_area.get_children():
		if child.name != "BottomCards":
			child.queue_free()


## 人类庄家翻底阶段：中央展示 8 张底牌（仅本人可见，规则 2）。
## 居中规范：点锚主牌桌十字中心 + grow BOTH（尺寸随内容向四周自适应），
## 与 PileViewer 弹层/ResultPanel 同口径；StyleBoxFlat 半字号留空（最大字号 14 → 8）。
func _show_bottom_cards() -> void:
	_clear_bottom_cards()
	var panel := PanelContainer.new()
	panel.name = "BottomCards"
	panel.anchor_left = UiStyle.MAIN_TABLE_CENTER.x
	panel.anchor_right = UiStyle.MAIN_TABLE_CENTER.x
	panel.anchor_top = UiStyle.MAIN_TABLE_CENTER.y
	panel.anchor_bottom = UiStyle.MAIN_TABLE_CENTER.y
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 50
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.24, 0.17)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
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
	panel.add_child(box)
	trick_area.add_child(panel)


func _clear_bottom_cards() -> void:
	var node := trick_area.get_node_or_null("BottomCards")
	if node != null:
		node.queue_free()


func _render_hand() -> void:
	hand_area.render(engine.get_hand(HUMAN_SEAT), engine.trump)


func _on_next_game() -> void:
	result_panel.visible = false
	_last_trick_winner = -1
	_trick_display_cleared = false
	_clear_trick_area()
	engine.start_next_game()


## ============================= 结算面板 =============================

func _show_result(result: Dictionary) -> void:
	var side := "闲家胜" if not result.banker_won else "庄家胜"
	result_title.text = "%s %d 级！" % [side, result.level]
	result_title.modulate = Color(1, 0.9, 0.4) if result.banker_won else Color(0.5, 0.95, 0.6)
	var koudi_text := "无"
	if result.koudi_points > 0:
		var multiplier: int = 2 if result.koudi_points == result.buried_points * 2 else 1
		koudi_text = "底牌 %d 分 × %d = %d" % [result.buried_points, multiplier, result.koudi_points]
	var lines := [
		"出牌庄家：%s ｜ 叫分 %d" % [SEAT_NAMES[result.banker_seat], result.contract],
		"闲家捉分 %d ＋ 抠底 %d ＝ %d" % [result.captured_points, result.koudi_points, result.captured_total],
		"总分 %d ＋ 捉分 ＝ %s（胜线 205）" % [result.contract, str(result.total_score)],
		"抠底：%s" % koudi_text,
		"本局收益：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d（B=1）" % [result.payments[0], result.payments[1], result.payments[2], result.payments[3]],
		"累计：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d" % [result.cumulative[0], result.cumulative[1], result.cumulative[2], result.cumulative[3]],
	]
	result_detail.text = "\n".join(lines)
	result_panel.visible = true
