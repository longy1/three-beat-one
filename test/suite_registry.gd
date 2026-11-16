class_name SuiteRegistry
extends RefCounted
## 测试套件注册表（单一事实源）：run_tests.gd（headless CI）与
## main_menu.gd（进程内自检）共用，消除双处清单漂移。


const SUITES := [
	preload("res://test/test_card.gd"),
	preload("res://test/test_trump.gd"),
	preload("res://test/test_combo.gd"),
	preload("res://test/test_follow.gd"),
	preload("res://test/test_trick.gd"),
	preload("res://test/test_appendix_a.gd"),
	preload("res://test/test_game.gd"),
	preload("res://test/test_ai_policy.gd"),
	preload("res://test/test_architecture.gd"),
	preload("res://test/test_components.gd"),
	preload("res://test/test_flow.gd"),
	preload("res://test/test_ui.gd"),
]
