extends Node
## 联机服务端中枢（M4）：WebSocket 监听、peer↔昵称注册、房间表、消息分发、掉线扫描。
## 传输：独立 WebSocketMultiplayerPeer（不挂高层 multiplayer API）+ JSON 文本包；
## 发送方识别：消息自带 pid（客户端 unique_id，协议层约定）；定向发送用
## set_target_peer + put_packet。
## 掉线判定：周期向所有已知 peer 发探测 ping（客户端回 pong 刷新活跃时间）；
## 发送失败或超过 heartbeat_timeout 无任何消息 → 判掉线 → 房间成员进入宽限期。


const PORT_DEFAULT := 9080
const SWEEP_INTERVAL := 5.0        ## 掉线扫描周期（秒）
const HEARTBEAT_TIMEOUT := 15.0    ## 无任何消息判掉线的阈值（秒）
const CODE_LEN := 4
## 房间码字符集：去混淆（无 I/L/O/0/1）
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

## 测试可调
var sweep_interval := SWEEP_INTERVAL
var heartbeat_timeout := HEARTBEAT_TIMEOUT
## 传导给房间的计时缩放（超时托管/离线宽限/AI 节拍）
var time_scale := 1.0

var _peer: WebSocketMultiplayerPeer
var _store: RefCounted = null
var _rooms := {}           # 房间码 → host_room 节点
var _peer_nick := {}       # peer_id → 昵称（hello 后有效；在线占用判定）
var _peer_last_seen := {}  # peer_id → 毫秒时间戳
var _sweep_timer: Timer


func start(port: int, store: RefCounted) -> Error:
	_store = store
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		return err
	_sweep_timer = Timer.new()
	_sweep_timer.wait_time = sweep_interval
	_sweep_timer.timeout.connect(_on_sweep)
	add_child(_sweep_timer)
	if is_inside_tree():
		_sweep_timer.start()
	else:
		# -s 测试环境：树尚未激活（_initialize 同步段），推迟到下一帧启动
		_sweep_timer.start.call_deferred()
	return OK


func listening_port() -> int:
	return _peer.get_local_port() if _peer != null else -1


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var packet := _peer.get_packet()
		var msg: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if msg is Dictionary:
			_dispatch(msg)


func _now_ms() -> int:
	return Time.get_ticks_msec()


func _send(peer_id: int, msg: Dictionary) -> Error:
	if _peer == null:
		return ERR_UNAVAILABLE
	_peer.set_target_peer(peer_id)
	return _peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


func send_to(peer_id: int, msg: Dictionary) -> void:
	_send(peer_id, msg)


func broadcast_room(room: Node, msg: Dictionary) -> void:
	for m in room.members:
		if m != null and not m.is_ai and m.peer_id > 0:
			_send(m.peer_id, msg)


## ============================= 消息分发 =============================

## 发送方身份来自消息自带 pid（客户端 unique_id）：独立 WebSocketPeer 的
## get_packet_peer() 在服务端不返回真实来源 id，路由信息由协议层携带。
func _dispatch(msg: Dictionary) -> void:
	var peer_id: int = int(msg.get("pid", 0))
	if peer_id <= 0:
		return  # 无来源标识的消息忽略
	_peer_last_seen[peer_id] = _now_ms()
	var t: String = msg.get("t", "")
	match t:
		NetProto.PING:
			_send(peer_id, {"t": NetProto.PONG})
		NetProto.HELLO:
			_on_hello(peer_id, msg)
		NetProto.CREATE:
			_on_create(peer_id)
		NetProto.JOIN:
			_on_join(peer_id, msg)
		NetProto.LEAVE:
			_on_leave(peer_id)
		NetProto.START:
			_on_start(peer_id, msg)
		NetProto.NEXT:
			_on_next(peer_id)
		NetProto.ACT:
			var room := _room_of_peer(peer_id)
			if room != null:
				room.handle_act(peer_id, msg)
			else:
				_send(peer_id, {"t": NetProto.ERR, "msg": "你不在任何房间中"})
		_:
			pass  # 探测空包/未知消息忽略


func _on_hello(peer_id: int, msg: Dictionary) -> void:
	var nick: String = str(msg.get("nick", "")).strip_edges()
	var check := NetProto.check_nick(nick)
	if check != "":
		_send(peer_id, {"t": NetProto.ERR, "msg": check})
		return
	# 同 peer 重复 hello（客户端重试）：直接确认
	if _peer_nick.get(peer_id, "") == nick:
		_send(peer_id, {"t": NetProto.HELLO_OK, "nick": nick})
		return
	# 断线重连：昵称命中存活房间的离线成员 → 直接回房（不占新注册名额）
	for room in _rooms.values():
		var m = room.member_by_name(nick)
		if m != null and not m.is_ai and m.offline:
			_peer_nick[peer_id] = nick
			_send(peer_id, {"t": NetProto.HELLO_OK, "nick": nick})
			room.reconnect(peer_id, nick)
			return
	# 全局注册制：昵称已注册（含历史）→ 拒绝
	if _store.has_player(nick) or _peer_nick.values().has(nick):
		_send(peer_id, {"t": NetProto.ERR, "msg": "昵称「%s」已被占用" % nick})
		return
	_store.register_player(nick)
	_peer_nick[peer_id] = nick
	_send(peer_id, {"t": NetProto.HELLO_OK, "nick": nick})


func _on_create(peer_id: int) -> void:
	var nick: String = _peer_nick.get(peer_id, "")
	if nick == "":
		_send(peer_id, {"t": NetProto.ERR, "msg": "请先输入昵称"})
		return
	if _room_of_peer(peer_id) != null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "你已在房间中，请先退出"})
		return
	var code := _gen_code()
	var room: Node = load("res://server/host_room.gd").new()
	room.name = "Room_" + code
	room.setup(self, code, nick, _store)
	room.time_scale = time_scale
	room.closed.connect(_on_room_closed)
	add_child(room)
	room.add_member(nick, peer_id)
	_store.record_room(code, nick)
	_rooms[code] = room
	_send(peer_id, room.build_room_state())


func _on_join(peer_id: int, msg: Dictionary) -> void:
	var nick: String = _peer_nick.get(peer_id, "")
	if nick == "":
		_send(peer_id, {"t": NetProto.ERR, "msg": "请先输入昵称"})
		return
	if _room_of_peer(peer_id) != null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "你已在房间中，请先退出"})
		return
	var code: String = str(msg.get("code", "")).strip_edges().to_upper()
	var room: Node = _rooms.get(code)
	if room == null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "房间不存在或已解散"})
		return
	if room.status != room.STATUS_LOBBY:
		_send(peer_id, {"t": NetProto.ERR, "msg": "该房间对局进行中，无法加入"})
		return
	var existing = room.member_by_name(nick)
	if existing != null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "你已在该房间中"})
		return
	if room.human_count() >= 4:
		_send(peer_id, {"t": NetProto.ERR, "msg": "房间已满（4/4）"})
		return
	room.add_member(nick, peer_id)
	room.broadcast_room_state()


func _on_leave(peer_id: int) -> void:
	var room := _room_of_peer(peer_id)
	if room == null:
		return
	var nick: String = _peer_nick.get(peer_id, "")
	_peer_nick.erase(peer_id)
	room.close("「%s」主动退出" % nick)


func _on_start(peer_id: int, msg: Dictionary) -> void:
	var room := _room_of_peer(peer_id)
	if room == null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "你不在任何房间中"})
		return
	if _peer_nick.get(peer_id, "") != room.owner_name:
		_send(peer_id, {"t": NetProto.ERR, "msg": "只有房主可以开始对局"})
		return
	var err: String = room.start_game(bool(msg.get("fill_ai", false)))
	if err != "":
		_send(peer_id, {"t": NetProto.ERR, "msg": err})


func _on_next(peer_id: int) -> void:
	var room := _room_of_peer(peer_id)
	if room == null:
		_send(peer_id, {"t": NetProto.ERR, "msg": "你不在任何房间中"})
		return
	if _peer_nick.get(peer_id, "") != room.owner_name:
		_send(peer_id, {"t": NetProto.ERR, "msg": "只有房主可以开下一局"})
		return
	var err: String = room.next_game()
	if err != "":
		_send(peer_id, {"t": NetProto.ERR, "msg": err})


func _room_of_peer(peer_id: int) -> Node:
	for room in _rooms.values():
		if room.member_by_peer(peer_id) != null:
			return room
	return null


func _on_room_closed(room: Node) -> void:
	_rooms.erase(room.code)


## ============================= 掉线扫描 =============================

func _on_sweep() -> void:
	var now := _now_ms()
	var dead: Array = []
	for peer in _peer_nick:
		_peer.set_target_peer(peer)
		var send_err := _peer.put_packet(JSON.stringify({"t": NetProto.PING}).to_utf8_buffer())
		var stale: bool = now - int(_peer_last_seen.get(peer, 0)) > heartbeat_timeout * 1000.0
		if send_err != OK or stale:
			dead.append(peer)
	for peer in dead:
		var nick: String = _peer_nick.get(peer, "")
		_peer_nick.erase(peer)
		_peer_last_seen.erase(peer)
		var room := _room_of_nick(nick)
		if room != null:
			var m = room.member_by_name(nick)
			if m != null:
				room.mark_offline(m.seat)


func _room_of_nick(nick: String) -> Node:
	for room in _rooms.values():
		var m = room.member_by_name(nick)
		if m != null and not m.is_ai:
			return room
	return null


func _gen_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	while true:
		var code := ""
		for i in CODE_LEN:
			code += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""
