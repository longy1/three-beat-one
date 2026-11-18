extends TestBase
## 架构守护（规范固化为可执行检查，[码1] + [构]）：
## - core/ 纯逻辑约束：不得出现 Node/场景/时序/文件系统依赖——这是
##   「联机服务端可直接复用 core」的机器检查（M4 预留）
## - AI 纯策略模块不依赖引擎类型（数据进/决策出）
## - 代码零日期戳/史志类注记（迁 [史]，规范见 [码2]）


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


## 代码零史志类注记（规范见 [码2] / [史]）：注释只描述当前行为与
## 规则出处，日期戳与「变更/更新」类记录一律迁 [史]。扫描全部 .gd（注释与
## 字符串都算）；关键词拆串、命中文案避开关键词本身——本文件不触发自匹配。
func _collect_code_files(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path + "/" + name
		if dir.current_is_dir() and not name.begins_with("."):
			_collect_code_files(full, out)
		elif name.ends_with(".gd") or name.ends_with(".py"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func test_no_changelog_comments(test) -> void:
	var regex := RegEx.new()
	test.check(regex.compile("20\\d\\d-\\d\\d-\\d\\d") == 0, "日期戳正则可编译")
	var keywords: Array[String] = ["更新记" + "录", "更新日" + "志", "变更记" + "录", "变更" + "史"]
	var files: Array = []
	for d in ["res://core", "res://net", "res://script", "res://server", "res://test", "res://tool"]:
		_collect_code_files(d, files)
	var violations := 0
	for f in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var hit := ""
			if regex.search(lines[i]) != null:
				hit = "日期戳"
			else:
				for kw in keywords:
					if lines[i].contains(kw):
						hit = kw
						break
			if hit != "":
				violations += 1
				test.check(false, "%s:%d 疑似史志类注记（命中「%s」）→ 按规范迁 [史]：%s" %
					[f, i + 1, hit, String(lines[i]).strip_edges()])
	test.eq(violations, 0, "代码零日期戳/史志类注记（走 [史]），扫描 %d 个 .gd" % files.size())


## 文档引用令牌守护（注册表单一事实源 = AGENTS.md §5 文档同步要求）：代码里的
## [规N]/[码N]/[构N]/[史]/[划N] 必须已注册，且带节号时该节号真实存在于目标文档的
## 「## N.」标题。文档改名/搬迁只改注册表一处，悬空引用由本用例抓红。
func _doc_sections(path: String) -> Dictionary:
	var sections := {}
	if not FileAccess.file_exists(path):
		return sections
	var int_re := RegEx.new()
	int_re.compile("\\d+")
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s: String = String(line)
		if s.begins_with("## "):
			var m: RegExMatch = int_re.search(s.substr(3))
			if m != null:
				sections[int(m.get_string())] = true
	return sections


func test_doc_tokens_valid(test) -> void:
	var registry := {
		"规": "res://doc/三打哈规则.md",
		"码": "res://doc/coding.md",
		"构": "res://doc/重构规范.md",
		"史": "res://doc/update.md",
		"划": "res://doc/三打哈-Godot工程计划.md",
	}
	var token_re := RegEx.new()
	test.check(token_re.compile("\\[([规码构史划])([0-9.]*)\\]") == 0, "令牌正则可编译")
	var section_cache := {}
	var files: Array = []
	for d in ["res://core", "res://net", "res://script", "res://server", "res://test", "res://tool"]:
		_collect_code_files(d, files)
	var violations := 0
	for f in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var matches: Array = token_re.search_all(String(lines[i]))
			for mi in matches:
				var hit: RegExMatch = mi
				var tag: String = hit.get_string(1)
				var num: String = hit.get_string(2)
				if not registry.has(tag):
					violations += 1
					test.check(false, "%s:%d 未注册令牌 [%s]（注册表见 AGENTS.md §5）" % [f, i + 1, tag])
					continue
				if tag == "史":
					if num != "":
						violations += 1
						test.check(false, "%s:%d [史] 为裸令牌不带节号（update.md 按日期归档）" % [f, i + 1])
					continue
				if num == "":
					if not FileAccess.file_exists(registry[tag]):
						violations += 1
						test.check(false, "%s:%d 令牌 [%s] 指向的文档缺失：%s" % [f, i + 1, tag, registry[tag]])
					continue
				if not section_cache.has(tag):
					section_cache[tag] = _doc_sections(registry[tag])
				var sections: Dictionary = section_cache[tag]
				var head: int = int(num.split(".")[0])
				if not sections.has(head):
					violations += 1
					test.check(false, "%s:%d 悬空节号 [%s%s]：%s 无 §%s" % [f, i + 1, tag, num, registry[tag], head])
	test.eq(violations, 0, "文档引用令牌全部有效（已注册 + 节号存在），扫描 %d 个代码文件" % files.size())


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
