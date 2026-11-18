extends RefCounted
## 联机服务端持久存储（M4 先顶方案）：本地 JSON 文件。
## 接口形状对齐后续 SQLite 落地（换存储时仅替换本文件，调用方不动——见 [划5]）。
## 三张「表」：
##   players     昵称 → 注册信息（全局注册制：昵称永久唯一）
##   rooms       房间码 → 房主/建档时间（房间解散后留档）
##   room_scores 房间码 → 昵称 → { score 累计收益, games 局数 }
## 每次变更即整文件原子落盘（临时文件 + rename），服务端重启数据不丢。


var _path: String
var _data: Dictionary = {}


func _init(path: String = "user://sanhax_server/store.json") -> void:
	_path = path
	_load()


func has_player(nick: String) -> bool:
	return _data.players.has(nick)


func register_player(nick: String) -> void:
	_data.players[nick] = {"created_at": Time.get_datetime_string_from_system()}
	_save()


func record_room(code: String, owner_name: String) -> void:
	_data.rooms[code] = {"owner": owner_name, "created_at": Time.get_datetime_string_from_system()}
	_save()


## 一局结算：每名玩家累计收益与局数 +1（delta 为引擎 payments 分量，可为负）。
## rows: [{ name, delta }]
func add_scores(code: String, rows: Array) -> void:
	var room: Dictionary = _data.room_scores.get(code, {})
	for row in rows:
		var name: String = row.name
		var entry: Dictionary = room.get(name, {"score": 0, "games": 0})
		entry.score = int(entry.score) + int(row.delta)
		entry.games = int(entry.games) + 1
		room[name] = entry
	_data.room_scores[code] = room
	_save()


## 房间累计分快照：[{ name, score, games }]（按座位序排列由调用方负责，此处保持存储序）
func room_scores(code: String) -> Array:
	var rows: Array = []
	var room: Dictionary = _data.room_scores.get(code, {})
	for name in room:
		var entry: Dictionary = room[name]
		rows.append({"name": name, "score": int(entry.score), "games": int(entry.games)})
	return rows


func _load() -> void:
	if FileAccess.file_exists(_path):
		var raw := FileAccess.get_file_as_string(_path)
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_data = parsed
	for key in ["players", "rooms", "room_scores"]:
		if not (_data.get(key) is Dictionary):
			_data[key] = {}


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var payload := JSON.stringify(_data, "  ")
	var tmp := _path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f != null:
		f.store_string(payload)
		f.close()
		if DirAccess.rename_absolute(tmp, _path) == OK:
			return
	# rename 失败（极端环境）退回直接写
	var direct := FileAccess.open(_path, FileAccess.WRITE)
	if direct != null:
		direct.store_string(payload)
		direct.close()
	else:
		push_error("ServerStore: 持久化失败 %s" % _path)
