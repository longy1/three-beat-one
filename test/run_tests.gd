extends SceneTree
## headless 测试入口：
##   Godot --headless --path . -s test/run_tests.gd                    # 全量（顺序）
##   Godot --headless --path . -s test/run_tests.gd -- --suite=test_online,test_ui
##   Godot --headless --path . -s test/run_tests.gd -- --shard=0/4     # 并行分片（配 test/run_tests_parallel.sh）
##   Godot --headless --path . -s test/run_tests.gd -- --tests=test_online::test_store_persistence
## 分片按「文件名::用例名」的稳定哈希分配（新用例自动纳入分片，零维护）；
## 在线回环端口/存储按 TEST_PORT_OFFSET 环境变量偏移（分片脚本为每分片注入，避免端口冲突）。
## --result-file=路径 把结果摘要写入文件（并行合并用）。全部通过退出码 0，否则 1（便于 CI）。

const TestFramework := preload("res://test/test_framework.gd")

const SUITES := SuiteRegistry.SUITES


func _initialize() -> void:
	var opts := _parse_args(OS.get_cmdline_user_args())
	var suites: Array = []
	for suite_script in SUITES:
		var stem: String = _stem(suite_script)
		if opts.suites.size() > 0 and not opts.suites.has(stem):
			continue
		suites.append(suite_script.new())

	var only: Array[String] = []
	if opts.tests.size() > 0:
		only = opts.tests
	elif opts.shard_n > 0:
		only = _shard_selection(suites, opts.shard_k, opts.shard_n)

	var result: TestFramework.Result = await TestFramework.run_suites(suites, only)
	print("========================================")
	print("三打哈 · 规则引擎 + UI 回归测试%s" % _shard_label(opts))
	print("========================================")
	print(result.summary())
	if opts.result_file != "":
		var f := FileAccess.open(opts.result_file, FileAccess.WRITE)
		if f != null:
			f.store_string(result.summary())
	quit(0 if result.all_passed() else 1)


func _shard_label(opts: Dictionary) -> String:
	return "（分片 %d/%d）" % [opts.shard_k, opts.shard_n] if opts.shard_n > 0 else ""


func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts := {"suites": [], "tests": [], "shard_k": 0, "shard_n": 0, "result_file": ""}
	for arg in args:
		if arg.begins_with("--suite="):
			for stem in arg.trim_prefix("--suite=").split(",", false):
				opts.suites.append(stem.strip_edges())
		elif arg.begins_with("--tests="):
			for t in arg.trim_prefix("--tests=").split(",", false):
				opts.tests.append(t.strip_edges())
		elif arg.begins_with("--shard="):
			var parts: PackedStringArray = arg.trim_prefix("--shard=").split("/")
			opts.shard_k = parts[0].to_int()
			opts.shard_n = parts[1].to_int() if parts.size() > 1 else 0
		elif arg.begins_with("--result-file="):
			opts.result_file = arg.trim_prefix("--result-file=")
	return opts


func _stem(suite_script: GDScript) -> String:
	return (suite_script.resource_path as String).get_file().get_basename()


## 分片选择：按「文件名::用例名」稳定哈希取模，属于本分片的用例名列表
func _shard_selection(suites: Array, k: int, n: int) -> Array[String]:
	var only: Array[String] = []
	for suite in suites:
		var stem := _stem(suite.get_script())
		for method_name in TestFramework.test_methods(suite):
			if _shard_of("%s::%s" % [stem, method_name], n) == k:
				only.append("%s::%s" % [stem, method_name])
	return only


## 稳定字符串哈希（跨进程跨次运行一致，不用内建 hash 的随机种子）
func _shard_of(key: String, n: int) -> int:
	var h := 0
	for i in key.length():
		h = (h * 131 + key.unicode_at(i)) & 0x7FFFFFFF
	return h % n
