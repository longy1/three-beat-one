class_name TestFramework
extends RefCounted
## 轻量测试框架：headless（tests/run_tests.gd）与进程内（主菜单「自检」按钮）共用。
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


## 运行一组测试套件（每个套件为包含 test_ 方法的实例）
static func run_suites(suites: Array) -> Result:
	var result := Result.new()
	for suite in suites:
		var script: Script = suite.get_script()
		var suite_name: String = script.resource_path.get_file() if script.resource_path != "" else str(script)
		var method_names: Array[String] = []
		for m in script.get_script_method_list():
			var method_name: String = m["name"]
			if method_name.begins_with("test_") and not method_names.has(method_name):
				method_names.append(method_name)
		method_names.sort()
		for method_name in method_names:
			result.total += 1
			var a := Assert.new()
			suite.call(method_name, a)
			if a.failures.is_empty():
				result.passed += 1
			else:
				for failure in a.failures:
					result.failures.append("%s :: %s：%s" % [suite_name, method_name, failure])
	return result
