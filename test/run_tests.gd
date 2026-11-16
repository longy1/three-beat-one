extends SceneTree
## headless 测试入口：
##   Godot --headless --path . -s test/run_tests.gd
## 全部通过退出码 0，否则 1（便于 CI）。

const TestFramework := preload("res://test/test_framework.gd")

const SUITES := SuiteRegistry.SUITES


func _initialize() -> void:
	var suites: Array = []
	for suite_script in SUITES:
		suites.append(suite_script.new())
	var result: TestFramework.Result = await TestFramework.run_suites(suites)
	print("========================================")
	print("三打哈 · 规则引擎 + UI 回归测试")
	print("========================================")
	print(result.summary())
	quit(0 if result.all_passed() else 1)
