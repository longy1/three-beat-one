extends TestBase
## 服务端存储用例（server/store.gd，单文件追加日志库）：
## 分数累计/房间留档跨实例持久、进行中房间快照落盘与摘除、
## 日志压实、崩溃残行自愈、旧版 store.json 自动迁移。


func _fresh_path(name: String) -> String:
	var path := "user://test_store_%s.jsonl" % name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var legacy := path.get_base_dir().path_join("test_store_%s.json" % name)
	if FileAccess.file_exists(legacy):
		DirAccess.remove_absolute(legacy)
	return path


## 基线：分数累计、房间留档、跨实例（重开实例）不丢
func test_scores_and_rooms_persistence(test) -> void:
	var path := _fresh_path("base")
	var store: RefCounted = load("res://server/store.gd").new(path)
	store.record_room("ROOM01", "测试玩家甲")
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": 30}, {"name": "电脑·乙", "delta": -10}])
	store.add_scores("ROOM01", [{"name": "测试玩家甲", "delta": -15}, {"name": "电脑·乙", "delta": 5}])
	var store2: RefCounted = load("res://server/store.gd").new(path)
	var rows: Array = store2.room_scores("ROOM01")
	test.eq(rows.size(), 2, "两行累计分")
	var by_name := {}
	for row in rows:
		by_name[str(row.name)] = row
	test.eq(int(by_name["测试玩家甲"].score), 15, "30 + (-15) = 15")
	test.eq(int(by_name["测试玩家甲"].games), 2, "两局")
	test.eq(int(by_name["电脑·乙"].score), -5, "-10 + 5 = -5")
	DirAccess.remove_absolute(path)


## 进行中房间快照：落盘 / 重开实例可读 / 摘除后消失（累计分留档不受影响）
func test_live_rooms_roundtrip(test) -> void:
	var path := _fresh_path("live")
	var store: RefCounted = load("res://server/store.gd").new(path)
	store.record_room("ROOM02", "甲")
	store.save_live_room("ROOM02", {"code": "ROOM02", "status": "GAME", "members": [{"name": "甲"}]})
	store.save_live_room("ROOM03", {"code": "ROOM03", "status": "LOBBY"})
	store.clear_live_room("ROOM03")
	var store2: RefCounted = load("res://server/store.gd").new(path)
	var live: Dictionary = store2.live_rooms()
	test.eq(live.size(), 1, "仅 ROOM02 进行中")
	test.check(live.has("ROOM02") and not live.has("ROOM03"), "摘除的房间不再出现")
	test.eq(str(live["ROOM02"].status), "GAME", "快照内容完整")
	test.eq(store2.room_scores("ROOM02").size(), 0, "无对局结算即无累计分（留档独立）")
	DirAccess.remove_absolute(path)


## 日志压实：超过阈值后整份日志收敛为单行快照，数据仍完整
func test_log_compaction(test) -> void:
	var path := _fresh_path("compact")
	var store: RefCounted = load("res://server/store.gd").new(path)
	for i in 60:
		store.add_scores("ROOMC", [{"name": "玩家%d" % (i % 4), "delta": i}])
	# 阈值 256 行：60 次追加 + 初始快照未压实
	var lines := _line_count(path)
	test.check(lines > 1 and lines < 256, "未到阈值不压实（%d 行）" % lines)
	for i in 220:
		store.add_scores("ROOMC", [{"name": "玩家%d" % (i % 4), "delta": 1}])
	var after := _line_count(path)
	test.check(after > 0 and after < 256, "超阈值触发压实（%d 行，远低于阈值）" % after)
	var store2: RefCounted = load("res://server/store.gd").new(path)
	var by_name := {}
	for row in store2.room_scores("ROOMC"):
		by_name[str(row.name)] = row
	test.eq(int(by_name["玩家0"].games), 70, "压实后数据完整（玩家0 局数）")
	DirAccess.remove_absolute(path)


## 崩溃残行自愈：日志尾部半行（写入中途崩溃）回放时截断，内存态保留坏行之前的完整数据
func test_corrupt_tail_self_heal(test) -> void:
	var path := _fresh_path("crash")
	var store: RefCounted = load("res://server/store.gd").new(path)
	store.record_room("ROOMX", "甲")
	store.add_scores("ROOMX", [{"name": "甲", "delta": 20}])
	# 模拟崩溃：在日志尾部追加一行残缺 JSON
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_line('{"op":"scores","code":"ROOMX","rows":[{"name":"甲","delt')
	f.close()
	var store2: RefCounted = load("res://server/store.gd").new(path)
	var rows: Array = store2.room_scores("ROOMX")
	test.eq(rows.size(), 1, "残行之前的 op 已回放")
	test.eq(int(rows[0].score), 20, "20 分未丢")
	test.eq(int(rows[0].games), 1, "残行未生效")
	# 自愈：日志已重写为完整快照（新实例继续追加不再遇到残行）
	store2.add_scores("ROOMX", [{"name": "甲", "delta": 5}])
	var store3: RefCounted = load("res://server/store.gd").new(path)
	test.eq(int(store3.room_scores("ROOMX")[0].score), 25, "自愈后继续正常追加")
	DirAccess.remove_absolute(path)


## 旧版整文件 JSON（store.json）自动迁移为日志库，旧文件移除、数据完整
func test_legacy_json_migration(test) -> void:
	var path := _fresh_path("legacy")
	var legacy := path.get_base_dir().path_join("test_store_legacy.json")
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		rooms = {"ROOMOLD": {"owner": "老玩家", "created_at": "旧档时间"}},
		room_scores = {"ROOMOLD": {"老玩家": {"score": 42, "games": 3}}},
	}))
	f.close()
	var store: RefCounted = load("res://server/store.gd").new(path)
	var rows: Array = store.room_scores("ROOMOLD")
	test.eq(rows.size(), 1, "旧数据已载入")
	test.eq(int(rows[0].score), 42, "分数迁移完整")
	test.eq(int(rows[0].games), 3, "局数迁移完整")
	test.check(not FileAccess.file_exists(legacy), "迁移成功后旧文件移除")
	# 迁移产物跨实例可读（落盘为日志快照）
	var store2: RefCounted = load("res://server/store.gd").new(path)
	test.eq(store2.room_scores("ROOMOLD").size(), 1, "迁移后持久化")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path)


func _line_count(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			n += 1
	f.close()
	return n
