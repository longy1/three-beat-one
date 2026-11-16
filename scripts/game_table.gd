extends Control
## 牌桌场景桩（M2 实现：拍卖、叫主、翻底/扣底、逐轮出牌、抠底与结算）。


func _ready() -> void:
	$Center/VBox/BackButton.pressed.connect(_on_back)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
