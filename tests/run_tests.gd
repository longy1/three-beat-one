extends SceneTree
## headless 测试入口（M1 验收命令）：
##   Godot --headless --path . -s tests/run_tests.gd
## 全部通过退出码 0，否则 1（便于 CI）。

const TestFramework := preload("res://tests/test_framework.gd")

const SUITES := [
	preload("res://tests/test_card.gd"),
	preload("res://tests/test_trump.gd"),
	preload("res://tests/test_combo.gd"),
	preload("res://tests/test_follow.gd"),
	preload("res://tests/test_trick.gd"),
	preload("res://tests/test_appendix_a.gd"),
	preload("res://tests/test_game.gd"),
	preload("res://tests/test_ai_policy.gd"),
]


func _initialize() -> void:
	var suites: Array = []
	for suite_script in SUITES:
		suites.append(suite_script.new())
	var result: TestFramework.Result = TestFramework.run_suites(suites)
	print("========================================")
	print("三打哈 · M1 规则引擎测试")
	print("========================================")
	print(result.summary())
	quit(0 if result.all_passed() else 1)
