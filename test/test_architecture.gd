extends TestBase
## 架构守护（规范固化为可执行检查，AGENTS.md 第 4 章 + doc/重构规范.md）：
## - core/ 纯逻辑约束：不得出现 Node/场景/时序/文件系统依赖——这是
##   「联机服务端可直接复用 core」的机器检查（M4 预留）
## - AI 纯策略模块不依赖引擎类型（数据进/决策出）


## core 纯逻辑：剥离注释后扫描禁用依赖
func test_core_purity(test) -> void:
	var forbidden := [
		"extends Node", "get_node", "@onready", "preload(", "load(",
		"await ", "Timer", "SceneTree", "change_scene", "print(",
		"OS.", "FileAccess", "DirAccess", "Thread",
	]
	var dir := DirAccess.open("res://core")
	test.check(dir != null, "core 目录可访问")
	if dir == null:
		return
	var violations := 0
	var checked := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			checked += 1
			var text := FileAccess.get_file_as_string("res://core/" + file_name)
			for line in text.split("\n"):
				var code: String = String(line).split("#")[0]
				for token in forbidden:
					if code.contains(token):
						violations += 1
						test.check(false, "%s 含禁用依赖「%s」：%s" % [file_name, token, String(line).strip_edges()])
		file_name = dir.get_next()
	test.eq(violations, 0, "core 无 Node/场景/时序/IO 依赖")
	test.check(checked >= 11, "core 脚本数量 ≥ 11（实际 %d，拆分模块未被误删）" % checked)


## C/S 预留：AI 纯策略模块不引用引擎类型（AiPolicy 门面除外；只查代码，不查注释）
func test_ai_modules_do_not_reference_engine(test) -> void:
	for path in ["res://core/ai_bidding.gd", "res://core/ai_play.gd"]:
		var text := FileAccess.get_file_as_string(path)
		var code_only: Array[String] = []
		for line in text.split("\n"):
			var code: String = String(line).split("#")[0]
			if not code.is_empty():
				code_only.append(code)
		var joined := "\n".join(code_only)
		test.check(not joined.contains("GameEngine"), "%s 不依赖引擎类型（数据进/决策出）" % path)


## C/S 预留：submit_* 是唯一状态变更入口（引擎公开面不含其他写方法）
func test_engine_public_api_is_submit_only(test) -> void:
	var script: GDScript = load("res://core/game.gd")
	for m in script.get_script_method_list():
		var name: String = m["name"]
		if name.begins_with("_") or name == "_static_init":
			continue
		if name.begins_with("submit_") or name.begins_with("start_"):
			continue
		# 其余公开方法必须是无副作用的查询/信号工具（此处以白名单守护）
		var queries := ["current_highest_bid", "has_passed", "bid_value", "get_hand", "hand_count",
			"is_defender", "get_last_trick", "peek_bottom"]
		test.check(queries.has(name) or name.begins_with("_"),
			"公开方法 %s 不在查询白名单内（新增写入口须走 submit_*）" % name)
