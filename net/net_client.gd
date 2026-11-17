class_name NetClient
extends Node
## 联机客户端（M4）：独立 WebSocketMultiplayerPeer + JSON 文本包 + 心跳。
## 生命周期：联机菜单创建后挂到 tree.root（节点名固定 "NetClient"），跨场景切换存活；
## 房间关闭/主动退出/连接失联 → 累计分数弹窗 → 确定 → 回主菜单 → 自毁。
## 职责边界：本类负责连接、协议摄取（座位旋转）、视图（TableView）持有与场景路由；
## 对局动作的应用在 TableView，牌桌 UI 交互在 game_table（经信号接线）。
## 隐藏信息纪律：只读消息里的 my_hand/kitty/buried（本人的），不解析他人任何牌面。


signal hello_ok(nick: String)
signal net_error(msg: String)
signal room_state_changed(state: Dictionary)
signal game_started(data: Dictionary)  ## game_start / snapshot 到达（进牌桌或原地重开）
signal game_finished(result: Dictionary)  ## 终局回放（已旋转）——统计/测试用
## 动作已应用到视图（kind/本地座位/是否超时托管）
signal remote_action(kind: String, seat: int, auto: bool)
signal scores_updated(rows: Array)
signal room_closed(rows: Array, reason: String)
signal connection_lost(reason: String)

const HEARTBEAT_INTERVAL := 5.0
const TABLE_SCENE := "res://scene/game_table.tscn"
const MENU_SCENE := "res://scene/main_menu.tscn"

var view: TableView = null           ## 对局视图（进牌桌时由 game_table 建立并复用至解散）
var my_seat := -1                    ## 真座位（0~3）；旋转基准
var my_name := ""
var hello_done := false              ## 服务器已确认昵称（hello_ok 到达）
var room_state: Dictionary = {}      ## 最近一次 room_state（真座位空间，大厅按座位直排）
var scores_rows: Array = []          ## 房间累计分（服务器权威，弹窗数据源）
var pending_game: Dictionary = {}    ## 待进牌桌的 game_start / snapshot
## 测试钩子：记录全部收到的消息（可见性断言用；默认关闭零开销）
var debug_record := false
var recorded: Array = []
## 测试钩子：不切场景，game_start/snapshot 直接灌入视图（headless 回环集成测试用）
var standalone := false

var _peer: WebSocketMultiplayerPeer = null
var _hb: Timer
var _connected := false
var _leaving := false                ## 主动退出流程中（room_closed 回执不再重复弹窗）
var _dialog_open := false
var _act_backlog: Array = []         ## 视图未建立期间到达的消息（重连进场的帧间隙）


func _ready() -> void:
	_hb = Timer.new()
	_hb.wait_time = HEARTBEAT_INTERVAL
	_hb.timeout.connect(_on_heartbeat)
	add_child(_hb)


## ============================= 连接与请求 =============================

## 发起连接；连上后自动 hello（昵称注册/重连判定在服务器）
func connect_to(url: String, nick: String) -> Error:
	my_name = nick
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(url)
	if err != OK:
		return err
	return OK


func request_create() -> void:
	send_msg({"t": NetProto.CREATE})


func request_join(code: String) -> void:
	send_msg({"t": NetProto.JOIN, "code": code})


func request_start(fill_ai: bool) -> void:
	send_msg({"t": NetProto.START, "fill_ai": fill_ai})


func request_next() -> void:
	send_msg({"t": NetProto.NEXT})


## 主动退出：先发 leave，再本地立即弹累计分窗（不等服务器回执）
func leave_room() -> void:
	_leaving = true
	send_msg({"t": NetProto.LEAVE})
	_show_scores_dialog("已退出房间")


## 对局操作（kind: bid/trump/discard/play；payload 按协议）
func send_act(kind: String, payload: Dictionary) -> void:
	var msg := {"t": NetProto.ACT, "kind": kind}
	for key in payload:
		msg[key] = payload[key]
	send_msg(msg)


## 我扣底：先本地暂存所选 8 张（回放不含牌面，视图自行移除）再发送
func send_discard(cards: Array) -> void:
	if view != null:
		view.set_pending_discard(cards)
	send_act(NetProto.KIND_DISCARD, {"cards": NetProto.keys_of(cards)})


func send_msg(msg: Dictionary) -> bool:
	if _peer == null or not _connected:
		return false
	# 每条消息自带发送方 unique_id（服务器路由依据——独立 WebSocketPeer 的
	# get_packet_peer 在服务端不返回真实来源 id，故路由信息由协议层携带）
	msg["pid"] = _peer.get_unique_id()
	_peer.set_target_peer(NetProto.SERVER_ID)
	var err := _peer.put_packet(JSON.stringify(msg).to_utf8_buffer())
	if err != OK:
		_on_connection_lost()
		return false
	return true


func _on_heartbeat() -> void:
	if _connected:
		send_msg({"t": NetProto.PING})


func drop_connection() -> void:
	## 测试钩子：模拟断线
	if _peer != null:
		_peer.close()


## ============================= 视图与场景路由 =============================

## 牌桌 _ready 调用：取得（或复用）视图
func make_view() -> TableView:
	if view == null:
		view = TableView.new()
	return view


## 牌桌 _ready 调用：把 pending 的 game_start/snapshot 灌入视图（触发首帧信号链）
func start_pending() -> void:
	if pending_game.is_empty():
		return
	var data := pending_game
	pending_game = {}
	if str(data.t) == NetProto.SNAPSHOT:
		view.restore(data)
	else:
		view.load_game(data)
	_flush_backlog()


func has_pending_game() -> bool:
	return not pending_game.is_empty()


func am_i_owner() -> bool:
	return int(room_state.get("owner_seat", 0)) == my_seat


## 本地座位序的座位名（0 号位带「（你）」）：联机牌桌的 SEAT_NAMES 替代。
## 成员按真座位给，本地序旋转（AI 昵称自带「电脑·」前缀）。
func table_seat_names() -> Array:
	var out: Array = ["甲（你）", "乙", "丙", "丁"]
	for i in 4:
		var m = _member_at(NetProto.unrot_seat(i, my_seat))
		if m != null and str(m.name) != "":
			var display: String = str(m.name)
			if i == 0:
				display += "（你）"
			if bool(m.get("offline", false)):
				display += "（离线）"
			out[i] = display
	return out


func _member_at(seat: int):
	for m in room_state.get("members", []):
		if int(m.seat) == seat:
			return m
	return null


func _flush_backlog() -> void:
	var backlog := _act_backlog
	_act_backlog = []
	for msg in backlog:
		_handle(msg)


## game_start / snapshot 统一座位旋转（真座位 → 本地座位）：视图只认本地空间，
## 本地玩家恒为 0 号位。标量含座位的字段逐个旋转；按座位下标的数组用 rot_array；
## 嵌套回放（出牌/历史轮/终局结果）内的 seat 字段逐项旋转。
func _rotate_game_data(data: Dictionary) -> Dictionary:
	var my := my_seat
	if my <= 0:
		return data  # 0 号位（房主）恒等映射
	var out := data.duplicate(true)
	out.dealer = NetProto.rot_seat(int(data.dealer), my)
	out.counts = NetProto.rot_array(data.counts, my)
	out.cumulative = NetProto.rot_array(data.cumulative, my)
	if str(data.get("t", "")) == NetProto.SNAPSHOT:
		out.banker = NetProto.rot_seat(int(data.banker), my)
		if data.has("auction_turn"):
			out.auction_turn = NetProto.rot_seat(int(data.auction_turn), my)
		if data.has("bids"):
			out.bids = NetProto.rot_array(data.bids, my)
		if data.has("turn_seat"):
			out.turn_seat = NetProto.rot_seat(int(data.turn_seat), my)
		if data.has("void_seats"):
			out.void_seats = NetProto.rot_array(data.void_seats, my)
		if data.has("current_plays"):
			out.current_plays = _rot_plays(data.current_plays, my)
		if data.has("trick_history"):
			var ths: Array = []
			for th in data.trick_history:
				ths.append({"plays": _rot_plays(th.plays, my),
					"winner": NetProto.rot_seat(int(th.winner), my)})
			out.trick_history = ths
		if data.get("last_result") != null:
			out.last_result = _normalize_result(data.last_result, my)
	return out


func _rot_plays(plays: Array, my: int) -> Array:
	var out: Array = []
	for p in plays:
		out.append({"seat": NetProto.rot_seat(int(p.seat), my), "cards": p.cards, "role": p.role})
	return out


## 终局结果归一：座位旋转 + 整型还原（JSON 往返会把整型变浮点，直接透传会让
## 结算面板 %d 格式化与用例 eq 失真）。game_over 与 snapshot.last_result 共用。
func _normalize_result(raw: Dictionary, my: int) -> Dictionary:
	var r: Dictionary = raw.duplicate(true)
	r.round = int(raw.round)
	r.banker_seat = NetProto.rot_seat(int(raw.banker_seat), my)
	r.contract = int(raw.contract)
	r.captured_points = int(raw.captured_points)
	r.koudi_points = int(raw.koudi_points)
	r.buried_points = int(raw.buried_points)
	r.captured_total = int(raw.captured_total)
	r.total_score = int(raw.total_score)
	r.level = int(raw.level)
	var payments: Array = []
	for p in NetProto.rot_array(raw.payments, my):
		payments.append(int(p))
	r.payments = payments
	var cumulative: Array = []
	for c in NetProto.rot_array(raw.cumulative, my):
		cumulative.append(int(c))
	r.cumulative = cumulative
	return r


func _route_game_data(data: Dictionary) -> void:
	# 已在联机牌桌 → 原地重灌（下一局/重连恢复）；否则挂 pending 后切牌桌场景
	var cs := get_tree().current_scene
	if cs != null and cs.get("_net") == self and cs.has_method("_on_net_game_started"):
		cs._on_net_game_started(data)
		return
	pending_game = data
	get_tree().change_scene_to_file(TABLE_SCENE)


func _standalone_load(data: Dictionary) -> void:
	## 测试钩子路径：不切场景，直接建视图灌入并放行积压消息
	if view == null:
		make_view()
	if str(data.t) == NetProto.SNAPSHOT:
		view.restore(data)
	else:
		view.load_game(data)
	game_started.emit(data)
	_flush_backlog()


## ============================= 轮询与消息摄取 =============================

func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		if not _connected:
			_connected = true
			_hb.start()
			send_msg({"t": NetProto.HELLO, "nick": my_name})
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			var msg: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if msg is Dictionary:
				_handle(msg)
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if _connected:
			_on_connection_lost()
		else:
			# 连接失败（服务器未启动/地址错误）：交回菜单报错
			net_error.emit("无法连接服务器")
			_destroy()


func _handle(msg: Dictionary) -> void:
	if debug_record:
		recorded.append(msg.duplicate(true))
	var t: String = str(msg.get("t", ""))
	match t:
		NetProto.HELLO_OK:
			my_name = str(msg.nick)
			hello_done = true
			hello_ok.emit(my_name)
		NetProto.ERR:
			net_error.emit(str(msg.msg))
		NetProto.ROOM_STATE:
			room_state = msg
			my_seat = -1
			for m in msg.members:
				if str(m.name) == my_name:
					my_seat = int(m.seat)
			room_state_changed.emit(room_state)
		NetProto.GAME_START:
			var data := _rotate_game_data(msg)
			if standalone:
				_standalone_load(data)
			else:
				_route_game_data(data)
		NetProto.SNAPSHOT:
			var data := _rotate_game_data(msg)
			if standalone:
				_standalone_load(data)
			else:
				_route_game_data(data)
		NetProto.ACT:
			if view == null:
				_act_backlog.append(msg)
				return
			var seat := NetProto.rot_seat(int(msg.seat), my_seat)
			var auto: bool = bool(msg.get("auto", false))
			var payload := msg.duplicate()
			payload.counts = NetProto.rot_array(msg.counts, my_seat)  # 张数按真座位下标 → 本地下标
			view.apply_act(str(msg.kind), seat, payload)
			remote_action.emit(str(msg.kind), seat, auto)
		NetProto.KITTY:
			if view == null:
				_act_backlog.append(msg)
				return
			view.apply_kitty(NetProto.cards_of(msg.cards))
		NetProto.GAME_OVER:
			if view == null:
				_act_backlog.append(msg)
				return
			var r := _normalize_result(msg.result, my_seat)
			view.apply_game_over(r)
			game_finished.emit(r)
		NetProto.SCORES:
			scores_rows = msg.rows
			scores_updated.emit(scores_rows)
		NetProto.MEMBER_OFFLINE:
			for m in room_state.get("members", []):
				if int(m.seat) == int(msg.seat):
					m.offline = true
			room_state_changed.emit(room_state)
		NetProto.ROOM_CLOSED:
			scores_rows = msg.rows
			room_closed.emit(scores_rows, str(msg.reason))
			if not _leaving:
				_show_scores_dialog(str(msg.reason))
		_:
			pass  # pong/未知消息忽略


## ============================= 收尾（弹窗 → 主菜单 → 自毁） =============================

func _on_connection_lost() -> void:
	if _leaving or _dialog_open:
		return
	_connected = false
	_peer = null  # 停止轮询：断线后 status 恒为 DISCONNECTED，不置空会每帧重入本分支
	# 尚未进过房间（连接失败）：交回菜单报错，不弹分数窗
	if room_state.is_empty() and view == null:
		net_error.emit("无法连接服务器")
		_destroy()
		return
	_show_scores_dialog("与服务器的连接已断开")


func _show_scores_dialog(reason: String) -> void:
	if _dialog_open:
		return
	_dialog_open = true
	ScoresDialog.create(get_tree().root, scores_rows, my_name, reason, _back_to_menu)


func _back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
	_destroy()


func _destroy() -> void:
	# 场景切换可能正在排程，延后一帧自毁
	queue_free.call_deferred()
