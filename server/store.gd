extends RefCounted
## 联机服务端持久存储：单文件追加日志库（SQLite 的纯 GDScript 平替定位——无第三方
## 依赖；接口形状与调用面不变，换存储只动本文件）。见 [划5]。
## 结构：每次变更向日志追加一行 JSON（op），启动时顺序回放重建内存态，读取全部走内存；
## 行数超阈值即压实为单行快照（临时文件 + rename 原子替换）；末行残缺（进程在写入
## 中途崩溃）回放时自动截断并自愈重写——崩溃安全。
## 三张「表」：
##   rooms       房间码 → 房主/建档时间（房间解散后留档）
##   room_scores 房间码 → 昵称 → { score 累计收益, games 局数 }
##   live_rooms  房间码 → 进行中房间的全量状态快照（服务端重启不散房，host_room 序列化）
## 昵称不持久化（在线占用制，见 room_manager._on_hello）。
## 旧版整文件 JSON（store.json）首次载入自动迁移为日志快照，迁移成功后移除旧文件。


const COMPACT_THRESHOLD := 256  ## 日志行数压实阈值

## op 类型（日志行）
const OP_SNAPSHOT := "snapshot"
const OP_ROOM := "room"
const OP_SCORES := "scores"
const OP_LIVE := "live"
const OP_LIVE_CLEAR := "live_clear"


var _path: String
var _legacy_path: String
var _data: Dictionary = {}
var _log_lines := 0  ## 当前日志行数（压实判定）


func _init(path: String = "user://sanhax_server/store.jsonl") -> void:
	_path = path
	# 旧版整文件 JSON 与日志库同名异扩展（store.jsonl ↔ store.json）
	_legacy_path = _path.get_base_dir().path_join(_path.get_file().get_basename() + ".json")
	_load()


## ============================= 接口面（调用方唯一入口） =============================

func record_room(code: String, owner_name: String) -> void:
	_apply({op = OP_ROOM, code = code, owner = owner_name, at = Time.get_datetime_string_from_system()})
	_append({op = OP_ROOM, code = code, owner = owner_name, at = _data.rooms[code].created_at})


## 一局结算：每名玩家累计收益与局数 +1（delta 为引擎 payments 分量，可为负）。
## rows: [{ name, delta }]
func add_scores(code: String, rows: Array) -> void:
	_apply({op = OP_SCORES, code = code, rows = rows})
	_append({op = OP_SCORES, code = code, rows = rows})


## 房间累计分快照：[{ name, score, games }]（按座位序排列由调用方负责，此处保持存储序）
func room_scores(code: String) -> Array:
	var rows: Array = []
	var room: Dictionary = _data.room_scores.get(code, {})
	for name in room:
		var entry: Dictionary = room[name]
		rows.append({"name": name, "score": int(entry.score), "games": int(entry.games)})
	return rows


## 进行中房间状态落盘（服务端重启不散房）：data 为 host_room 序列化的全量状态
func save_live_room(code: String, data: Dictionary) -> void:
	_apply({op = OP_LIVE, code = code, data = data})
	_append({op = OP_LIVE, code = code, data = data})


## 房间解散：进行中快照摘除（累计分留档不受影响）
func clear_live_room(code: String) -> void:
	if not _data.live_rooms.has(code):
		return
	_apply({op = OP_LIVE_CLEAR, code = code})
	_append({op = OP_LIVE_CLEAR, code = code})


## 已落盘的进行中房间（启动恢复用）：{ 房间码 → 状态字典 }（深拷贝）
func live_rooms() -> Dictionary:
	return _data.live_rooms.duplicate(true)


## ============================= 回放与压实 =============================

func _apply(op: Dictionary) -> void:
	match str(op.get("op", "")):
		OP_SNAPSHOT:
			var d: Dictionary = op.data
			_data = {}
			for key in ["rooms", "room_scores", "live_rooms"]:
				_data[key] = d.get(key, {}) if d.get(key, {}) is Dictionary else {}
		OP_ROOM:
			_data.rooms[str(op.code)] = {"owner": str(op.owner), "created_at": str(op.get("at", ""))}
		OP_SCORES:
			var room: Dictionary = _data.room_scores.get(str(op.code), {})
			for row in op.rows:
				var name: String = str(row.name)
				var entry: Dictionary = room.get(name, {"score": 0, "games": 0})
				entry.score = int(entry.score) + int(row.delta)
				entry.games = int(entry.games) + 1
				room[name] = entry
			_data.room_scores[str(op.code)] = room
		OP_LIVE:
			_data.live_rooms[str(op.code)] = op.data
		OP_LIVE_CLEAR:
			_data.live_rooms.erase(str(op.code))


func _load() -> void:
	_data = {"rooms": {}, "room_scores": {}, "live_rooms": {}}
	if FileAccess.file_exists(_path):
		var bad_offset := -1  ## 首个无法解析的行偏移（崩溃残行）：到此为止
		var f := FileAccess.open(_path, FileAccess.READ)
		if f != null:
			var good := 0
			while not f.eof_reached():
				var line := f.get_line()
				if line.strip_edges() == "":
					continue
				var op: Variant = JSON.parse_string(line)
				if op is Dictionary:
					_apply(op)
					good += 1
				else:
					bad_offset = good
					break
			f.close()
		if bad_offset >= 0:
			# 末段残缺：自愈为快照重写（回放已完成到坏行之前，内存态完整）
			push_warning("ServerStore: 日志尾部残缺已截断自愈 %s" % _path)
			_write_snapshot()
			return
	elif FileAccess.file_exists(_legacy_path):
		# 旧版整文件 JSON 迁移：载入 → 快照落盘 → 移除旧文件
		var raw := FileAccess.get_file_as_string(_legacy_path)
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_data = parsed
			_sanitize()
			_write_snapshot()
			DirAccess.remove_absolute(_legacy_path)
		return
	_sanitize()


## 结构兜底：缺表补空表（_apply 的 snapshot 分支已做同款校验，此处兜历史遗留）
func _sanitize() -> void:
	for key in ["rooms", "room_scores", "live_rooms"]:
		if not (_data.get(key) is Dictionary):
			_data[key] = {}


func _append(op: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var line := JSON.stringify(op)
	if not FileAccess.file_exists(_path):
		var fresh := FileAccess.open(_path, FileAccess.WRITE)
		if fresh == null:
			push_error("ServerStore: 日志创建失败 %s" % _path)
			return
		fresh.store_line(line)
		fresh.flush()
		fresh.close()
		_log_lines = 1
		return
	var f := FileAccess.open(_path, FileAccess.READ_WRITE)
	if f == null:
		push_error("ServerStore: 日志打开失败 %s" % _path)
		return
	f.seek_end()
	f.store_line(line)
	f.close()  # close 即落盘（flush 逐次强制刷盘在高频对局动作下开销过大）
	_log_lines += 1
	if _log_lines >= COMPACT_THRESHOLD:
		_write_snapshot()


## 压实：内存态写为单行快照，原子替换整份日志（临时文件 + rename）
func _write_snapshot() -> void:
	_log_lines = 1
	var payload := JSON.stringify({op = OP_SNAPSHOT, data = _data})
	var tmp := _path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f != null:
		f.store_line(payload)
		f.flush()
		f.close()
		if DirAccess.rename_absolute(tmp, _path) == OK:
			return
	# rename 失败（极端环境）退回直接写
	var direct := FileAccess.open(_path, FileAccess.WRITE)
	if direct != null:
		direct.store_line(payload)
		direct.flush()
		direct.close()
	else:
		push_error("ServerStore: 持久化失败 %s" % _path)
