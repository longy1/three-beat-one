extends Control
## 主菜单：开始对局、自检按钮（进程内复用 test/ 全部用例，含 UI 回归）、退出。
## Web 特性守卫（OS.has_feature("web")）：退出按钮隐藏（浏览器中 quit() 无效）、
## 自检按钮隐藏（test/ 已被导出过滤排除，运行时不可用）。


func _ready() -> void:
	$Center/Panel/VBox/StartButton.pressed.connect(_on_start)
	$Center/Panel/VBox/SelfTestButton.pressed.connect(_on_self_test)
	$Center/Panel/VBox/QuitButton.pressed.connect(_on_quit)
	if OS.has_feature("web"):
		$Center/Panel/VBox/QuitButton.visible = false
		$Center/Panel/VBox/SelfTestButton.visible = false


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scene/game_table.tscn")


func _on_self_test() -> void:
	var label: Label = $Center/Panel/VBox/ResultLabel
	label.text = "自检运行中……"
	# test/ 一律运行时动态加载：导出过滤排除 test/* 后，任何静态 preload 都会让
	# 整份脚本在导出环境解析失败（_ready 不执行、按钮全部失去处理器）——Web 实测踩坑
	var framework: GDScript = load("res://test/test_framework.gd")
	var registry: GDScript = load("res://test/suite_registry.gd")
	var suites: Array = []
	for suite_script in registry.SUITES:
		suites.append(suite_script.new())
	var result = await framework.run_suites(suites)
	label.text = result.summary()


func _on_quit() -> void:
	get_tree().quit()
