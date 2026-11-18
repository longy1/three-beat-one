extends Control
## 联机入口（M4）：昵称 + 服务器地址 → 新建房间 / 凭码加入。
## 昵称经 ConfigFile 记忆（user://online.cfg）；连接/进房失败在状态行报错。
## NetClient 创建后挂 tree.root（名字固定 "NetClient"）跨场景存活；
## 进房成功由 NetClient 切到房间大厅（scene/room_lobby.tscn）。


const CFG_PATH := "user://online.cfg"
const LOBBY_SCENE := "res://scene/menu/room_lobby.tscn"
const DEFAULT_LOCAL_ADDR := "ws://127.0.0.1:9080"  ## 与场景 AddrEdit 默认值一致（本地调试）

var _net: NetClient = null
var _pending_join := ""  ## ""=建房；否则为要加入的房间码
var _proceeding := false

@onready var nick_edit: LineEdit = $Center/Panel/VBox/NickEdit
@onready var addr_edit: LineEdit = $Center/Panel/VBox/AddrEdit
@onready var code_edit: LineEdit = $Center/Panel/VBox/CodeRow/CodeEdit
@onready var status_label: Label = $Center/Panel/VBox/StatusLabel


func _ready() -> void:
	$Center/Panel/VBox/CreateButton.pressed.connect(_on_create)
	$Center/Panel/VBox/CodeRow/JoinButton.pressed.connect(_on_join)
	$Center/Panel/VBox/BackButton.pressed.connect(_on_back)
	_load_cfg()


func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		nick_edit.text = str(cfg.get_value("online", "nick", ""))
		var addr := str(cfg.get_value("online", "addr", ""))
		if addr != "":
			addr_edit.text = addr
	_prefill_web_addr()


## Web 平台地址预填：未记忆自定义地址（仍为场景默认本地值）时，改填当前页面站点
## （wss:// 同域，443 由 scheme 隐含）——公网部署（ZCode Sites 单 HTTPS 端口）下
## wss 经同端口 Upgrade 分流到服务器，玩家免输地址开箱即连；
## 桌面无 web 特性不生效，手动输入 host[:端口] / ws:// / wss:// 地址照常可用。
func _prefill_web_addr() -> void:
	if not OS.has_feature("web"):
		return
	var cur := addr_edit.text.strip_edges()
	if cur != "" and cur != DEFAULT_LOCAL_ADDR:
		return
	var host: Variant = JavaScriptBridge.eval("window.location.host", false)
	if host is String and str(host) != "":
		addr_edit.text = "wss://" + str(host)


func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "nick", nick_edit.text.strip_edges())
	cfg.set_value("online", "addr", addr_edit.text.strip_edges())
	cfg.save(CFG_PATH)


func _on_create() -> void:
	_submit("")


func _on_join() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "请输入房间码"
		return
	_submit(code)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scene/menu/main_menu.tscn")


func _submit(join_code: String) -> void:
	var nick := nick_edit.text.strip_edges()
	var check := NetProto.check_nick(nick)
	if check != "":
		status_label.text = check
		return
	var addr := addr_edit.text.strip_edges()
	if addr.is_empty():
		status_label.text = "请输入服务器地址"
		return
	if not addr.begins_with("ws://") and not addr.begins_with("wss://"):
		addr = "ws://" + addr
	_save_cfg()
	_pending_join = join_code
	_proceeding = false
	_set_busy(false)
	status_label.text = "连接中……"
	_net = NetClient.new()
	_net.name = "NetClient"
	get_tree().root.add_child(_net)
	_net.hello_ok.connect(_on_hello_ok)
	_net.room_state_changed.connect(_on_room_state)
	_net.net_error.connect(_on_net_error)
	var err := _net.connect_to(addr, nick)
	if err != OK:
		status_label.text = "无法创建连接"
		_net = null


func _on_hello_ok(_nick: String) -> void:
	if _pending_join == "":
		_net.request_create()
	else:
		_net.request_join(_pending_join)


func _on_room_state(_state: Dictionary) -> void:
	if _proceeding:
		return
	_proceeding = true
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_net_error(msg: String) -> void:
	_set_busy(true)
	status_label.text = msg
	_net = null  # NetClient 自毁（deferred），引用置空


## 进房后隐藏输入行（按钮失能），失败后恢复
func _set_busy(disabled: bool) -> void:
	$Center/Panel/VBox/CreateButton.disabled = disabled
	$Center/Panel/VBox/CodeRow/JoinButton.disabled = disabled
