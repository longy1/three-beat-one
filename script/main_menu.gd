extends Control
## 主菜单：开始对局、自检按钮（进程内复用 test/ 全部用例，含 UI 回归）、退出。


const TestFramework := preload("res://test/test_framework.gd")

const SUITES := SuiteRegistry.SUITES


func _ready() -> void:
	$Center/Panel/VBox/StartButton.pressed.connect(_on_start)
	$Center/Panel/VBox/SelfTestButton.pressed.connect(_on_self_test)
	$Center/Panel/VBox/QuitButton.pressed.connect(_on_quit)


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scene/game_table.tscn")


func _on_self_test() -> void:
	var label: Label = $Center/Panel/VBox/ResultLabel
	label.text = "自检运行中……"
	var suites: Array = []
	for suite_script in SUITES:
		suites.append(suite_script.new())
	var result: TestFramework.Result = await TestFramework.run_suites(suites)
	label.text = result.summary()


func _on_quit() -> void:
	get_tree().quit()
