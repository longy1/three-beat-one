extends SceneTree
## 联机部署链路探针（不入 test/ 注册表）：NetClient → node 代理端口 → 无头服务器。
## 用法：Godot --headless --path . -s <本文件路径> -- <代理端口> [昵称]
## 建房成功打印 PROBE_OK <房间码>；失败 PROBE_ERR/PROBE_TIMEOUT，退出码 1。

var _nc: Node
var _t0 := 0
var _stay := false
var _hello_only := false
var _created := false
var _tick := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var target := str(args[0]) if args.size() > 0 else "13003"
	var nick := str(args[1]) if args.size() > 1 else "探针"
	_stay = args.size() > 2 and str(args[2]) == "stay"
	_hello_only = args.size() > 2 and str(args[2]) == "hello"
	# 目标可为完整 ws(s):// URL，或纯端口数字（本机代理回环用）
	var url := target if target.begins_with("ws://") or target.begins_with("wss://") \
			else "ws://127.0.0.1:%s" % target
	_nc = load("res://net/net_client.gd").new()
	_nc.name = "ProbeNetClient"
	_nc.standalone = true
	root.add_child(_nc)
	_nc.hello_ok.connect(_on_hello)
	_nc.room_state_changed.connect(_on_room)
	_nc.net_error.connect(_on_err)
	_nc.connection_lost.connect(_on_lost)
	print("PROBE_CONNECT ", url)
	var err: int = _nc.connect_to(url, nick)
	if err != OK:
		print("PROBE_ERR connect_to ", err)
		quit(1)
		return
	_t0 = Time.get_ticks_msec()


func _on_hello(_nick: String) -> void:
	if _hello_only:
		print("PROBE_HELLO_OK ", _nc.my_name)
		quit(0)
		return
	_nc.request_create()


func _on_room(state: Dictionary) -> void:
	print("PROBE_OK ", str(state.get("code", "?")), " nick=", _nc.my_name,
			" members=", str(state.get("members", [])).length())
	if _stay and not _created:
		_created = true
		print("PROBE_STAY_BEGIN（连接保持观察 300s 切断行为）")
		return
	if not _stay:
		quit(0)


func _on_lost(_reason: String) -> void:
	var sec := (Time.get_ticks_msec() - _t0) / 1000
	print("PROBE_CUT 连接在 ", sec, "s 被切断")
	quit(2)


func _on_err(msg: String) -> void:
	print("PROBE_ERR ", msg)
	quit(1)


func _process(_delta: float) -> bool:
	var sec := (Time.get_ticks_msec() - _t0) / 1000
	if not _stay:
		if _t0 > 0 and sec > 15:
			print("PROBE_TIMEOUT")
			quit(1)
			return true
		return false
	# stay 模式：每 60s 报活，400s 仍连接则视为无 300s 切断
	if _created and sec >= _tick * 60:
		_tick += 1
		print("PROBE_TICK ", _tick, "min 连接存活")
	if sec > 400:
		print("PROBE_STABLE 400s 无切断")
		quit(0)
		return true
	return false
