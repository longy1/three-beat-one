class_name TestFramework
extends RefCounted
## 轻量测试框架：headless（test/run_tests.gd）与进程内（主菜单「自检」按钮）共用。
## 无第三方依赖；用例方法以 test_ 开头、接收一个 Assert 参数。


class Assert:
	extends RefCounted

	var failures: Array[String] = []
	var checks := 0

	func check(cond: bool, note := "") -> void:
		checks += 1
		if not cond:
			failures.append(note if note != "" else "断言失败")

	func eq(got, want, note := "") -> void:
		checks += 1
		if got != want:
			failures.append("%s：期望 %s，实际 %s" % [note, str(want), str(got)])

	func is_null(value, note := "") -> void:
		checks += 1
		if value != null:
			failures.append("%s：期望 null，实际 %s" % [note, str(value)])


class Result:
	extends RefCounted

	var total := 0
	var passed := 0
	var failures: Array[String] = []

	func all_passed() -> bool:
		return failures.is_empty()

	func summary() -> String:
		if failures.is_empty():
			return "✓ 全部通过：%d/%d 个用例" % [passed, total]
		var lines: Array[String] = ["✗ %d/%d 个用例失败：" % [failures.size(), total]]
		for f in failures:
			lines.append("  · " + f)
		return "\n".join(lines)


## 枚举套件实例的用例方法名（排序稳定；并行分片与运行共用）
static func test_methods(suite) -> Array[String]:
	var method_names: Array[String] = []
	var script: Script = suite.get_script()
	for m in script.get_script_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("test_") and not method_names.has(method_name):
			method_names.append(method_name)
	method_names.sort()
	return method_names


## 运行一组测试套件（每个套件为包含 test_ 方法的实例）。
## 支持 async 用例（含 await 的 UI 测试）：框架整体可被 await。
## only 非空时只跑列表内（「文件名::用例名」限定，供并行分片/指定用例使用）。
## 逐套件打印耗时（并行分片的配平依据），≥2s 的用例单独标 [slow]
static func run_suites(suites: Array, only: Array[String] = []) -> Result:
	var result := Result.new()
	for suite in suites:
		var script: Script = suite.get_script()
		var suite_name: String = script.resource_path.get_file() if script.resource_path != "" else str(script)
		# only 的限定符用无扩展名文件干（与 run_tests.gd 分片/指定用例一致），失败消息仍带 .gd 全名
		var suite_stem: String = script.resource_path.get_file().get_basename()
		var method_names := test_methods(suite)
		if only.size() > 0:
			method_names = method_names.filter(func(m: String): return only.has("%s::%s" % [suite_stem, m]))
			if method_names.is_empty():
				continue
		var t0 := Time.get_ticks_usec()
		for method_name in method_names:
			result.total += 1
			var a := Assert.new()
			var t1 := Time.get_ticks_usec()
			await suite.call(method_name, a)
			var test_sec := (Time.get_ticks_usec() - t1) / 1000000.0
			if test_sec >= 2.0:
				print("[slow] %s :: %s %.1fs" % [suite_name, method_name, test_sec])  # 耗时大户定位
			if a.failures.is_empty():
				result.passed += 1
			else:
				for failure in a.failures:
					result.failures.append("%s :: %s：%s" % [suite_name, method_name, failure])
		print("[suite] %s %d 用例 %.1fs" % [suite_name, method_names.size(), (Time.get_ticks_usec() - t0) / 1000000.0])
	return result
