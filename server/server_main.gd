extends Node
## 联机服务器入口（M4）：无头 Godot 进程跑本场景，承载 WebSocket 监听与房间逻辑。
## 启动：Godot --headless --path . res://server/server_main.tscn [-- --port 9080]
## 数据：user://sanhax_server/store.json（昵称注册表/房间留档/房间累计分，重启不丢）；
## 进行中的房间随进程消亡（重启即解散，分数已持久）。


func _ready() -> void:
	var port := _parse_port()
	var store: RefCounted = load("res://server/store.gd").new()
	var manager: Node = load("res://server/room_manager.gd").new()
	manager.name = "RoomManager"
	add_child(manager)
	var err: Error = manager.start(port, store)
	if err != OK:
		push_error("联机服务器启动失败（端口 %d 可能被占用）：%s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("==============================================")
	print("三打哈联机服务器已启动")
	print("监听端口：%d（客户端地址 ws://<本机IP>:%d）" % [port, port])
	print("数据文件：%s" % store._path)
	print("按 Ctrl+C / 关闭窗口停止服务器")
	print("==============================================")


func _parse_port() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			return int(args[i + 1])
	return load("res://server/room_manager.gd").PORT_DEFAULT
