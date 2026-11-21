extends Control
## 牌桌控制器（M2 单机完整对局 / M4 联机对局）：人类恒为 0 号位（下方）。
## 单机：GameEngine 纯逻辑驱动 + AiPolicy 电脑；联机：TableView（可见性裁剪视图，
## 信号/查询面与引擎同构）驱动，AI 与他人动作来自服务器回放（本类只做呈现与转发）。
## 组件分工：HandArea（手牌区）/ PileViewer（牌堆弹层）/ ActionBar（操作按钮条）/
## TrumpRankPicker（叫主点数面板）/ CrownAnimator（皇冠动画）/
## BidBubbles（叫分对话气泡）/ DealAnimator（发牌动画）——各自持有职责状态。
## 刷新纪律：_refresh() 是唯一刷新入口，仅由引擎信号处理器调用；
## 按钮界面只由 *_required 处理器重建（ActionBar.reset 幂等清理）。
## 发牌动画：开局播放（单机开局/下一局、联机 game_start；快照恢复不播），期间
## _render_hand 挂起、拍卖表态挂起（AI 叫分与人类按钮等排序完成放行，见
## _on_deal_done 补跑），动画结束回调统一放行（DealAnimator 持有过渡牌面）。


const HUMAN_SEAT := 0
const AI_DELAY := 0.7
const AI_DISCARD_DELAY := 1.0  ## AI 庄家扣底节奏：关键决策点多停约 1 秒，太快看不清翻底
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

## 单机为 GameEngine，联机为 TableView（二者信号/查询面同构，鸭子类型驱动本控制器）
var engine
## 座位名（本地座位序，0 号位带「（你）」）：单机为默认常量；联机由房间成员旋转生成
var seat_names: Array = SEAT_NAMES.duplicate()
var _online := false              ## 联机模式（tree.root 上的 NetClient 挂起对局判定）
var _net: NetClient = null        ## 联机客户端门面（单机为 null）
var _sent_play := false           ## 联机：已提交出牌待回执（错误时需重建出牌按钮）
var _piles: PileViewer
var _trick_history := TrickHistoryPanel.new()
var _crown_anim := CrownAnimator.new()
var _trump_picker: TrumpRankPicker = null
var _trump_reveal := TrumpReveal.new()  ## 竞叫结束揭主动画（皇冠+主R牌双飞）
var _bid_bubbles := BidBubbles.new()    ## 叫分对话气泡（_refresh_seats 状态驱动）
var _deal_animator := DealAnimator.new()  ## 发牌动画（开局/下一局；快照恢复不播）
var _deal_active := false               ## 发牌动画进行中（_render_hand 挂起）
var _deal_shown_count := 0              ## 发牌逐拍已发张数（动画期间座位面板显示值，on_tick 驱动）
var _discard_button: Button = null       ## 扣底确认按钮（计数文案更新用）
var _pending_trump_suit := -1
var _last_trick_winner := -1
var _trick_display_cleared := false      ## 停留结束后已主动清空上一轮牌面
var _last_trump_shown = null             ## 上次送入信息栏的主牌（TrumpInfo 引用），避免重复重建

var _ai_timer: Timer
var _trick_timer: Timer
var _ai_delay_scale := 1.0  ## AI 延迟缩放（UI 测试调小以加速；_run_ai 按比例设置 wait_time）
var _mobile_ui := false                  ## 手机版 UI 分支生效中（设备特性或设置强制）
var _mobile_bar: MobileTopBar = null     ## 手机版顶栏（当局信息 bar；桌面为 null）
var _more_panel: MobileMorePanel = null  ## 手机版「更多」面板（打开态实例）
var trick_anchors := TRICK_ANCHORS       ## 出牌显示锚点（手机分支切 MobileLayout.TRICK_ANCHORS）
var _desktop_seat_anchors := {}          ## 桌面版座位锚点（_ready 捕获，切回桌面还原用）
var _desktop_bottom := Vector4()         ## 桌面版底部区偏移（捕获同上）
var _desktop_pile_history := Vector4()   ## 桌面版「历史」按钮位（捕获同上；手机分支搬移后还原）
var _desktop_pile_bottom := Vector4()    ## 桌面版「牌堆」按钮位（捕获同上）

@onready var game_info: Label = $TopBar/GameInfoLabel
@onready var top_bar: Control = $TopBar
@onready var bid_center_label: Label = $BidCenterLabel
@onready var background: ColorRect = $Background
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
	sidebar.settings_pressed.connect(_on_settings)
	background.gui_input.connect(_on_background_input)
	UiStyle.pad_button(result_next_button)
	UiStyle.pad_button(result_menu_button)
	result_next_button.pressed.connect(_on_next_game)
	result_menu_button.pressed.connect(_on_menu)
	human_void_stamp.visible = false  # 【无主】印章默认隐藏（公示后显示）

	_net = get_tree().root.get_node_or_null("NetClient") as NetClient
	_online = _net != null and _net.has_pending_game()
	if _online:
		engine = _net.make_view()
	else:
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
	_trick_history.setup(self)
	# 「历史」按钮：点击打开出牌历史面板（十字形一轮四家出牌 + 翻轮次，✕/点窗外关闭）
	_piles.history_chip.pressed.connect(func(): _trick_history.open(engine.trick_history, seat_names))
	_piles.bottom_button.mouse_entered.connect(func():
		if engine.banker_seat == HUMAN_SEAT:
			_piles.show_bottom(engine.buried))
	_piles.bottom_button.mouse_exited.connect(_piles.hide_timer.start)
	for seat in seat_panels:
		var panel: SeatPanel = seat_panels[seat]
		panel.setup(seat)  # 注入座位号（印章定位/测试断言用）
	_bid_bubbles.setup(self)
	# 捕获桌面版布局原值（手机分支切换后可还原；tscn 即桌面事实源）
	var bottom: Control = $BottomArea
	_desktop_bottom = Vector4(bottom.offset_left, bottom.offset_top, bottom.offset_right, bottom.offset_bottom)
	_desktop_pile_history = Vector4(_piles.history_chip.offset_left, _piles.history_chip.offset_top,
		_piles.history_chip.offset_right, _piles.history_chip.offset_bottom)
	_desktop_pile_bottom = Vector4(_piles.bottom_button.offset_left, _piles.bottom_button.offset_top,
		_piles.bottom_button.offset_right, _piles.bottom_button.offset_bottom)
	for seat in seat_panels:
		_desktop_seat_anchors[seat] = Vector2(seat_panels[seat].anchor_left, seat_panels[seat].anchor_top)
	_apply_layout_mode()

	if _online:
		_setup_online()
		# game_start（新局）播放发牌动画；snapshot（重连恢复）不播
		var will_deal: bool = _net.has_pending_game() \
			and str(_net.pending_game.get("t", "")) != NetProto.SNAPSHOT
		_deal_active = will_deal
		_net.start_pending()  # 灌入 game_start/snapshot → 同步信号链完成首帧刷新
		if will_deal:
			_start_deal_animation()
	else:
		_deal_active = true
		engine.start_session()  # 同步发出首个 auction_required，由处理器完成首帧刷新
		_start_deal_animation()


## ============================= 设置（主菜单/牌桌共用弹层） =============================

func _on_settings() -> void:
	SettingsDialog.create(get_tree().root, func():
		_apply_layout_mode()
		_render_hand())


## ============================= UI 分支（桌面 / 手机版独立布局） =============================

## UI 分支应用器：手机版为独立 UI 分支（布局/尺寸/组件与桌面解耦各自迭代，
## 仅游戏规则与流程复用）——顶栏当局信息 bar + 「更多」面板、无右侧栏、大手牌
## 贴底（96×134，宽 ≈90% 屏）、出牌十字居中、乙/丁贴缘、按钮加大；桌面版完全
## 保持场景原样。判定 = 移动端设备特性自动启用，或设置项强制开启（PC 调试入口，
## AppSettings.effective_mobile_ui）。布局常量组见 MobileLayout。
func _apply_layout_mode() -> void:
	_mobile_ui = AppSettings.effective_mobile_ui()
	var bottom: Control = $BottomArea
	if _mobile_bar != null:
		_mobile_bar.queue_free()
		_mobile_bar = null
	if _more_panel != null:
		_more_panel.queue_free()
		_more_panel = null
	if _mobile_ui:
		_mobile_bar = MobileTopBar.new()
		_mobile_bar.more_pressed.connect(_toggle_more_panel)
		add_child(_mobile_bar)
		# 重建顶栏后守卫基线失效：置空让 _refresh 守卫自愈重渲主牌（防重建丢主牌显示）
		_last_trump_shown = null
		# 结算面板居屏幕正中（手机无右侧栏偏置；桌面分支锚回十字中心）
		var rc: Vector2 = UiStyle.table_center(self)
		result_panel.anchor_left = rc.x
		result_panel.anchor_right = rc.x
		result_panel.anchor_top = rc.y
		result_panel.anchor_bottom = rc.y
		sidebar.visible = false
		top_bar.visible = false
		bid_center_label.visible = false
		bottom.offset_left = MobileLayout.BOTTOM_LEFT
		bottom.offset_top = MobileLayout.BOTTOM_TOP
		bottom.offset_right = MobileLayout.BOTTOM_RIGHT
		bottom.offset_bottom = MobileLayout.BOTTOM_BOTTOM
		action_bar.offset_bottom = MobileLayout.ACTION_BAR_OFFSET_BOTTOM
		hint_label.offset_top = MobileLayout.HINT_OFFSET_TOP
		hint_label.offset_bottom = MobileLayout.HINT_OFFSET_BOTTOM
		hand_area.offset_top = MobileLayout.HAND_OFFSET_TOP
		hand_area.offset_bottom = MobileLayout.HAND_OFFSET_BOTTOM
		for seat in seat_panels:
			var a: Vector2 = MobileLayout.SEAT_ANCHORS[seat]
			seat_panels[seat].anchor_left = a.x
			seat_panels[seat].anchor_top = a.y
		trick_anchors = MobileLayout.TRICK_ANCHORS
		hand_area.hand_card_size = MobileLayout.HAND_CARD_SIZE
		hand_area.spacing_max = MobileLayout.SPACING_MAX
		hand_area.spacing_min = MobileLayout.SPACING_MIN
		hand_area.hand_base_y = MobileLayout.HAND_BASE_Y
		action_bar.button_min = MobileLayout.BUTTON_MIN
		action_bar.button_font = MobileLayout.BUTTON_FONT
		_bid_bubbles.set_anchors(MobileLayout.BUBBLE_ANCHORS)
		_bid_bubbles.set_metrics(MobileLayout.BUBBLE_FONT_MIN, MobileLayout.BUBBLE_FONT_MAX,
			MobileLayout.BUBBLE_FONT_PASS, MobileLayout.BUBBLE_MAX_SIZE)
		# 入口按钮/皇冠人类落点/无主印章：桌面基准随手机布局搬移（数据在 MobileLayout）
		_piles.set_entry_offsets(MobileLayout.ENTRY_HISTORY_OFFS, MobileLayout.ENTRY_BOTTOM_OFFS)
		_crown_anim.human_target = MobileLayout.CROWN_HUMAN_TARGET
		human_void_stamp.offset_left = MobileLayout.VOID_STAMP_LEFT
		human_void_stamp.offset_right = MobileLayout.VOID_STAMP_RIGHT
		human_void_stamp.offset_top = MobileLayout.VOID_STAMP_TOP
		human_void_stamp.offset_bottom = MobileLayout.VOID_STAMP_BOTTOM
	else:
		sidebar.visible = true
		top_bar.visible = true
		bid_center_label.visible = true
		bottom.offset_left = _desktop_bottom.x
		bottom.offset_top = _desktop_bottom.y
		bottom.offset_right = _desktop_bottom.z
		bottom.offset_bottom = _desktop_bottom.w
		action_bar.offset_bottom = 48.0
		hint_label.offset_top = 54.0
		hint_label.offset_bottom = 80.0
		hand_area.offset_top = 86.0
		hand_area.offset_bottom = -12.0
		for seat in seat_panels:
			var a: Vector2 = _desktop_seat_anchors[seat]
			seat_panels[seat].anchor_left = a.x
			seat_panels[seat].anchor_top = a.y
		trick_anchors = TRICK_ANCHORS
		hand_area.hand_card_size = CardWidget.SIZE_NORMAL
		hand_area.spacing_max = HandArea.SPACING_MAX
		hand_area.spacing_min = HandArea.SPACING_MIN
		hand_area.hand_base_y = HandArea.HAND_BASE_Y
		action_bar.button_min = Vector2(120, 44)
		action_bar.button_font = 18
		_bid_bubbles.set_anchors(BidBubbles.ANCHORS)
		_bid_bubbles.set_metrics(BidBubbles.FONT_MIN, BidBubbles.FONT_MAX,
			BidBubbles.FONT_PASS, BidBubbles.MAX_SIZE)
		# 结算面板锚回桌面十字中心（tscn 原值）
		result_panel.anchor_left = UiStyle.MAIN_TABLE_CENTER.x
		result_panel.anchor_right = UiStyle.MAIN_TABLE_CENTER.x
		result_panel.anchor_top = UiStyle.MAIN_TABLE_CENTER.y
		result_panel.anchor_bottom = UiStyle.MAIN_TABLE_CENTER.y
		_piles.set_entry_offsets(_desktop_pile_history, _desktop_pile_bottom)
		_crown_anim.human_target = CrownAnimator.CROWN_HUMAN_TARGET
		human_void_stamp.offset_left = 958.0
		human_void_stamp.offset_right = 1014.0
		human_void_stamp.offset_top = -232.0
		human_void_stamp.offset_bottom = -176.0
	# 分支切换重排手牌（开局引擎 hands 未发时不渲染，避免越界；开局后有牌随切随渲）
	if not _deal_active and not engine.hands.is_empty():
		_render_hand()


## ☰ 按钮：开「更多」面板（重复点按/点窗外/✕ 关闭）；打开即喂当前状态
func _toggle_more_panel() -> void:
	if _more_panel != null:
		_more_panel.close()
		_more_panel = null
		return
	_more_panel = MobileMorePanel.create(self, _on_settings, _on_menu)
	_more_panel.closed.connect(func(): _more_panel = null)
	_refresh()


## 主牌展示位分派：桌面=信息栏槽位；手机=顶栏主牌槽（守卫自愈逻辑共用）
func _set_trump_display(card: Card) -> void:
	if _mobile_ui:
		_mobile_bar.set_trump(card)
	else:
		sidebar.set_trump(card)


## 主牌槽全局中心（揭主飞牌落点）
func _trump_slot_center() -> Vector2:
	return _mobile_bar.trump_slot_center() if _mobile_ui else sidebar.trump_slot_center()


## 主牌槽目标牌面尺寸（揭主飞牌的渐缩终点；与 _trump_slot_center 同源分支感知）
func _trump_slot_size() -> Vector2:
	return _mobile_bar.trump_slot_size() if _mobile_ui else sidebar.trump_slot_size()


## 双击牌桌空白（背景层）：清空手牌选择（把选中的牌全部放回）
func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		hand_area.clear_selection()


## ============================= 发牌动画 =============================

## 开局发牌动画：先做一次真实渲染（展开目标位的测量来源）并隐藏真实牌面与
## 虚线框（牌未分区排序前框位与牌不对齐），动画结束回调里重渲放行（虚线框
## 随排序完成一起展现）。播放期间 _render_hand 全部挂起；逐拍回调驱动各家
## 座位面板张数随发牌增长。
func _start_deal_animation() -> void:
	_deal_active = true
	hand_area.render(engine.get_hand(HUMAN_SEAT), engine.trump)
	hand_area.set_frames_visible(false)
	hand_area.set_widgets_visible(false)
	_deal_animator.play(self, hand_area, engine.get_hand(HUMAN_SEAT), _on_deal_done, _on_deal_tick)


## 发牌逐拍回调：记录已发张数并刷新座位面板（各家张数随发牌一张一张增加）
func _on_deal_tick(count: int) -> void:
	_deal_shown_count = count
	if _deal_active:
		_refresh_seats()


func _on_deal_done() -> void:
	_deal_active = false
	_render_hand()
	hand_area.set_frames_visible(true)
	# 发牌期间被挂起的拍卖在此放行：以引擎状态为准补跑（期间 AI 未表态或联机
	# 远端回放已到，都按当前轮转处理；拍卖已结束则后续阶段处理器早已接管）
	if engine.phase == GameEngine.Phase.AUCTION:
		_on_auction_required(engine.auction.turn)


func _on_menu() -> void:
	if _online:
		_net.leave_room()  # 主动退出：本地弹累计分窗 → 确定 → 主菜单（NetClient 统一接管）
		return
	get_tree().change_scene_to_file("res://scene/menu/main_menu.tscn")


## 联机接入（M4）：座位名按房间成员旋转生成；接 NetClient 回放/错误/房间状态信号
func _setup_online() -> void:
	seat_names = _net.table_seat_names()
	_net.remote_action.connect(_on_remote_action)
	_net.net_error.connect(_on_net_error)
	_net.room_state_changed.connect(_on_net_room_state)
	_net.member_presence.connect(_on_member_presence)


## 成员离线/重连回房提示（等待重连口径：掉线者回合由服务器托管，宽限内可随时回房）
func _on_member_presence(name: String, online: bool, grace: int) -> void:
	if online:
		_toast("「%s」已重连" % name)
	elif grace > 0:
		_toast("「%s」掉线，等待重连（%d 秒内未归房间解散）" % [name, grace])
	else:
		_toast("「%s」掉线，等待重连" % name)


## 房间状态变化（成员掉线/重连）：刷新座位名（离线标注）与面板
func _on_net_room_state(_state: Dictionary) -> void:
	if not _online or engine == null:
		return
	seat_names = _net.table_seat_names()
	_refresh()


## ============================= 联机回放处理（M4） =============================

## 远端动作已应用到视图之后：托管提示、扣底弹层关闭、出牌回执清标记。
## 牌面刷新全部由视图信号驱动，这里只做视图信号覆盖不到的 UI 收尾。
func _on_remote_action(kind: String, seat: int, auto: bool) -> void:
	if auto:
		_toast("%s 超时，已托管" % seat_names[seat])
	match kind:
		NetProto.KIND_DISCARD:
			_clear_bottom_cards()
		NetProto.KIND_PLAY:
			if seat == HUMAN_SEAT:
				_sent_play = false  # 自己出牌的回执到达（已打出的牌由 _render_hand 自动剪除）
		_:
			pass


## 服务器拒绝（竞态/异常）：toast 提示；自己刚提交的出牌需重建出牌按钮
func _on_net_error(msg: String) -> void:
	_toast(msg)
	if _sent_play:
		_sent_play = false
		_show_play_bar()


## 下一局（房主开新局）/ 重连恢复：原地重灌对局（NetClient 路由调用）。
## game_start（新局）播放发牌动画；snapshot（重连恢复）直接灌入不播
func _on_net_game_started(data: Dictionary) -> void:
	result_panel.visible = false
	_trick_timer.stop()  # 上一局结算停留可能未到期（重连恢复路径），防御性停表
	_last_trick_winner = -1
	_trick_display_cleared = false
	_last_trump_shown = null
	_clear_trick_area()
	_crown_anim.clear()
	_trump_reveal.clear()
	_deal_animator.clear()
	hand_area.end_select()
	if str(data.t) == NetProto.SNAPSHOT:
		_deal_active = false
		engine.restore(data)
		_toast("已重连，对局状态已恢复")
	else:
		_deal_active = true  # 先于引擎信号置位：game_start 的首个 auction_required 挂起至动画结束
		engine.load_game(data)
		_start_deal_animation()


## ============================= 引擎信号处理 =============================
## 纪律：座位非人类时统一 action_bar.reset()——按钮界面只在人类轮到时存在，
## submit 提交方法因此无须任何清理（旧版「不得清理」竞态补丁的根治点）。

func _on_auction_required(seat: int) -> void:
	_crown_anim.clear()  # 新局拍卖开始：清除上一局的庄家皇冠
	_trump_reveal.clear()  # 及揭主牌面（正常对局不会残留，防御性清理）
	_refresh()
	if _deal_active:
		return  # 发牌/排序动画未完：AI 不表态、人类不出拍卖条（气泡等状态驱动
		# 刷新照常）；动画结束 _on_deal_done 按引擎当前轮转补跑本处理器
	if seat == HUMAN_SEAT:
		_show_auction_bar()
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 表态…" % seat_names[seat]
		if _online:
			return  # 联机：远端动作由服务器回放驱动（AI/托管代打均在服务端）
		_run_ai(func(): engine.submit_bid(seat, AiPolicy.choose_bid(engine.hands[seat], engine.current_highest_bid(), seat, engine.auction.bids)))


func _on_trump_required(seat: int) -> void:
	_refresh()
	_crown_anim.play(self, seat, seat_panels)  # 拍卖结束：皇冠飞向出牌庄家
	if seat == HUMAN_SEAT:
		_show_trump_picker()
	else:
		action_bar.reset()
		hint_label.text = "等待 %s 叫主…" % seat_names[seat]
		if _online:
			return  # 联机：远端动作由服务器回放驱动
		_run_ai(func():
			var choice: Dictionary = AiPolicy.choose_trump(engine.hands[seat])
			engine.submit_trump(seat, choice.suit, choice.rank))


func _on_discard_required(seat: int) -> void:
	# 揭主双飞：叫主完成的此刻皇冠已飞向庄家，主 R 牌从中央飞向主牌展示位
	# （桌面=信息栏、手机=顶栏，落点/尺寸均分支感知；飞行渐缩至目标槽位尺寸）。
	# 主牌标识 = 守卫自愈渲染：飞行中（_trump_reveal.active）_refresh_top_bar 跳过，
	# 落位回调里按分支放入主牌展示位并记 _last_trump_shown；若飞行被 clear() 打断
	# （新局/新拍卖的防御性清理，回调不再触发），active 已复位 → 下次 _refresh 由
	# 守卫重渲——根治旧版「落位回调丢失 + _last_trump_shown 引用比较永久跳过」的
	# 标识消失（回调必须走 _set_trump_display 分派：写死 sidebar 会把手机顶栏
	# 主牌槽永久留在未叫主占位态）
	var trump_card := Card.new(engine.trump.suit, engine.trump.rank)
	_trump_reveal.play(self, trump_card, _trump_slot_center(), _trump_slot_size(), func():
		_last_trump_shown = engine.trump
		_set_trump_display(trump_card)
		_trump_reveal.clear())
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
		hint_label.text = "等待 %s 扣底…" % seat_names[seat]
		if _online:
			return  # 联机：远端动作由服务器回放驱动（AI/托管代打均在服务端）
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
		hint_label.text = "等待 %s 出牌…" % seat_names[seat]
		if _online:
			return  # 联机：远端动作由服务器回放驱动
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
	var highest: int = engine.current_highest_bid()
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
	if _online:
		_net.send_act(NetProto.KIND_BID, {"value": value})
		return  # 回放驱动状态推进；服务器拒绝经 net_error toast（按钮保留可重试）
	var verdict: Dictionary = engine.submit_bid(HUMAN_SEAT, value)
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
	if _online:
		_net.send_act(NetProto.KIND_TRUMP, {"suit": _pending_trump_suit, "rank": rank})
		_close_trump_picker()
		return  # 翻底私有下发 + 扣底阶段均由回放驱动
	var verdict: Dictionary = engine.submit_trump(HUMAN_SEAT, _pending_trump_suit, rank)
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
	if _online:
		_net.send_discard(hand_area.selected.duplicate())
		return  # 扣底弹层由 discard 回放到达时统一关闭
	var verdict: Dictionary = engine.submit_discard(HUMAN_SEAT, hand_area.selected.duplicate())
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
	if _online:
		_sent_play = true
		_net.send_act(NetProto.KIND_PLAY, {"cards": NetProto.keys_of(hand_area.selected.duplicate())})
		# 与单机同理由：出牌后常伴结算停留，期间处理器挂起不重建——立即清掉旧按钮
		# （合法性由服务器权威判定；拒绝经 net_error 重建出牌按钮）
		action_bar.reset()
		return
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
	# 历史面板打开期间有新轮次结算 → 就地刷新（状态驱动：随引擎信号走，非定时轮询）
	_trick_history.refresh(engine.trick_history)
	# 庄家是自己时：皇冠下方「牌堆」按钮显示（扣底完成后才有底牌可看）
	var show_bottom: bool = engine.banker_seat == HUMAN_SEAT \
		and (engine.phase == GameEngine.Phase.TRICKS or engine.phase == GameEngine.Phase.SETTLED)
	_piles.set_bottom_button_visible(show_bottom)


## 右下角手牌统计：主牌数量、副牌各花色数量、各点数数量（含王、2）
func _refresh_stats() -> void:
	if engine.hands.is_empty():
		return
	var hand: Array = engine.get_hand(HUMAN_SEAT)
	var trump: TrumpInfo = engine.trump
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
	var main_text: String
	var rank_rows: Array = _build_rank_rows(hand)
	if trump == null:
		for s in Card.NORMAL_SUITS:
			bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		main_text = "未叫主 ｜ " + " ".join(bits)
	else:
		for s in Card.NORMAL_SUITS:
			if s != trump.suit:
				bits.append("%s%d" % [suit_chars[s], suit_counts[s]])
		main_text = "主 %d ｜ 副 %s" % [trump_count, " ".join(bits)]
	# 手机顶栏：花色图标+数字（叫主后主花色金色突出、王计入主牌数；未叫主=四门；
	# 恒 4 组，与桌面「主 X ｜ 副 ♥a ♣b ♦c」同口径）
	if _mobile_ui and _mobile_bar != null:
		var entries: Array = []
		if trump != null:
			entries.append({"icon": suit_chars[trump.suit], "count": trump_count, "main": true})
		for s in Card.NORMAL_SUITS:
			if trump == null or s != trump.suit:
				entries.append({"icon": suit_chars[s], "count": suit_counts[s], "main": false})
		_mobile_bar.set_suit_stats(entries)
	# 统计分派：桌面=信息栏；手机=「更多」面板（打开期间实时更新）
	if _mobile_ui:
		if _more_panel != null:
			_more_panel.update_stats(main_text, rank_rows)
	else:
		sidebar.update_stats(main_text, rank_rows)


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
		info += " ｜ 出牌庄 %s" % seat_names[engine.banker_seat]
		if engine.contract > 0:
			info += " ｜ 叫分 %d" % engine.contract
	# 顶栏分派：桌面=原顶栏/中央提示/信息栏局面块；手机=当局信息 bar（局数/累计进「更多」面板）
	if _mobile_ui:
		var bar_text := ""
		if engine.phase == GameEngine.Phase.AUCTION:
			bar_text = "叫分中（最高 %d）" % engine.current_highest_bid()
		elif engine.banker_seat >= 0:
			bar_text = "出牌庄 %s · 叫分 %d" % [seat_names[engine.banker_seat], engine.contract]
		else:
			bar_text = "抓牌中…"
		_mobile_bar.set_game_info(bar_text)
		_mobile_bar.set_captured("捉分 %d" % engine.captured_points)
	else:
		game_info.text = info
	if engine.phase != GameEngine.Phase.AUCTION:
		bid_center_label.text = ""
	# 主牌提示：一张「正 R」牌面放入主牌展示位（仅叫主变化时重建；揭主飞行期间跳过
	# ——落位回调渲染；飞行被打断时 active 复位，此处守卫自愈重渲）
	if engine.trump != _last_trump_shown and not _trump_reveal.active:
		_last_trump_shown = engine.trump
		_set_trump_display(Card.new(engine.trump.suit, engine.trump.rank) if engine.trump != null else null)
	# 「局面」块：桌面=信息栏；手机=「更多」面板（打开期间实时更新）
	var captured := "闲家捉分 %d" % engine.captured_points
	if engine.koudi_points > 0:
		captured += "（含抠底 %d）" % engine.koudi_points
	if _mobile_ui:
		if _more_panel != null:
			_more_panel.set_state("第 %d 局" % engine.round_index,
				"累计：甲 %+d ｜ 乙 %+d\n　　　丙 %+d ｜ 丁 %+d" \
				% [engine.cumulative[0], engine.cumulative[1], engine.cumulative[2], engine.cumulative[3]])
	else:
		sidebar.set_state(captured, "累计：甲 %+d ｜ 乙 %+d\n　　　丙 %+d ｜ 丁 %+d" \
			% [engine.cumulative[0], engine.cumulative[1], engine.cumulative[2], engine.cumulative[3]])


func _refresh_seats() -> void:
	for seat in seat_panels:
		var panel: SeatPanel = seat_panels[seat]
		# 庄家由皇冠动画标记，面板不显示「抓牌/庄」文字；叫分/放弃由气泡呈现（不占状态行）
		var status := ""
		if engine.phase == GameEngine.Phase.TRICKS and _last_trick_winner == seat:
			status = "✓ 上轮赢"
		# 发牌动画期间：面板张数随逐拍计数增长（DealAnimator on_tick 驱动），
		# 动画结束后回归引擎权威值（用户需求：各家张数随发牌一张一张增加）
		var shown_count: int = engine.hand_count(seat)
		if _deal_active:
			shown_count = mini(_deal_shown_count, shown_count)
		panel.set_info(seat_names[seat], "%d 张" % shown_count, status)
		var is_turn: bool = (engine.phase == GameEngine.Phase.AUCTION and engine.auction.turn == seat) \
			or (engine.phase == GameEngine.Phase.TRICKS and engine.turn_seat == seat)
		panel.set_highlight(is_turn)
		panel.set_void_trump(engine.trump_void_seats[seat])  # 【无主】公示印章（7.3）
	# 人类 0 号位无面板：印章盖在手牌区上方左侧（与历史按钮同列）
	human_void_stamp.visible = engine.trump_void_seats[HUMAN_SEAT]
	# 叫分对话气泡：状态驱动（每座位最新表态，更高分出现时清低分气泡；
	# 拍卖结束即全清）。发牌/排序动画期间挂起不显示——庄家底叫 130 亦然，
	# 排序完成后随拍卖呈现一起出现（用户需求）
	if engine.phase == GameEngine.Phase.AUCTION and not _deal_active:
		_bid_bubbles.apply(engine.auction.bids, engine.current_highest_bid())
	else:
		_bid_bubbles.clear_all()


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
		# 卡牌尺寸按张数自适应：≤2 张正常、≥3 张中号；相邻牌重叠步距与手牌紧凑
		# 口径一致（读实例 spacing_max——手机分支 40 与手牌步距同口径，桌面还原后
		# 值相同，后牌盖前牌各露左缘角标条），多张组合不再摊成全宽横排（与手牌同款摆法）
		var card_size: Vector2 = CardWidget.SIZE_NORMAL if play.cards.size() <= 2 \
				else CardWidget.SIZE_MEDIUM
		var cards_row := Control.new()
		cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 出牌区不收输入，避免重叠区挡点
		var step: float = hand_area.spacing_max
		for i in play.cards.size():
			var widget := CardWidget.create_sized(play.cards[i], true, card_size)
			widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
			widget.position = Vector2(i * step, 0)
			cards_row.add_child(widget)
		var base: Vector2 = trick_anchors[seat] * trick_area.size  # 相对锚点 × 层尺寸（分支可切）
		cards_row.size = Vector2(card_size.x + (play.cards.size() - 1) * step, card_size.y)
		cards_row.position = base - cards_row.size / 2.0
		trick_area.add_child(cards_row)


func _clear_trick_area() -> void:
	for child in trick_area.get_children():
		if child.name != "BottomCards":
			child.queue_free()


## 人类庄家翻底阶段：中央展示 8 张底牌（仅本人可见，规则 2）。
## 居中规范：点锚主牌桌十字中心 + grow BOTH（尺寸随内容向四周自适应），
## 与 PileViewer 弹层/ResultPanel 同口径；StyleBoxFlat 半字号留空（最大字号 14 → 8）。
## 层级约定：z_index=1 只比桌面（出牌区 z=0）高一层，不遮历史/牌堆弹层（z=10）
## 与结算面板——z_index 只影响绘制不影响输入命中，弹层靠树序后置天然优先接收点击。
func _show_bottom_cards() -> void:
	_clear_bottom_cards()
	var panel := PanelContainer.new()
	panel.name = "BottomCards"
	panel.anchor_left = UiStyle.table_center(self).x
	panel.anchor_right = UiStyle.table_center(self).x
	panel.anchor_top = UiStyle.table_center(self).y
	panel.anchor_bottom = UiStyle.table_center(self).y
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 1
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
	if _deal_active:
		return  # 发牌动画进行中：真实渲染挂起（动画结束回调统一放行）
	hand_area.render(engine.get_hand(HUMAN_SEAT), engine.trump)


func _on_next_game() -> void:
	if _online:
		_net.request_next()  # 服务器重开 → 广播新 game_start → _on_net_game_started 原地重灌
		return
	result_panel.visible = false
	_last_trick_winner = -1
	_trick_display_cleared = false
	_clear_trick_area()
	_deal_animator.clear()
	_deal_active = true  # 先于引擎信号置位：新局首个 auction_required 挂起至动画结束
	engine.start_next_game()
	_start_deal_animation()


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
		"出牌庄家：%s ｜ 叫分 %d" % [seat_names[result.banker_seat], result.contract],
		"闲家捉分 %d ＋ 抠底 %d ＝ %d" % [result.captured_points, result.koudi_points, result.captured_total],
		"总分 %d ＋ 捉分 ＝ %s（胜线 205）" % [result.contract, str(result.total_score)],
		"抠底：%s" % koudi_text,
		"本局收益：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d（B=1）" % [result.payments[0], result.payments[1], result.payments[2], result.payments[3]],
		"累计：甲 %+d ｜ 乙 %+d ｜ 丙 %+d ｜ 丁 %+d" % [result.cumulative[0], result.cumulative[1], result.cumulative[2], result.cumulative[3]],
	]
	result_detail.text = "\n".join(lines)
	# 联机：只有房主能开下一局，其余人显示等待
	result_next_button.visible = not _online or _net.am_i_owner()
	result_panel.visible = true
