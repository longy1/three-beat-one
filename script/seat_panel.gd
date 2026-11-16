class_name SeatPanel
extends PanelContainer
## 座位信息面板组件（乙/丙/丁复用）：姓名 / 牌数 / 状态 + 悬停查看出牌历史。
## 组件自带统一尺寸（tscn 内 custom_minimum_size = 180×100，720p 基准）；
## 实例只负责定位（anchor 锚定左上角，不拉伸），改尺寸只需改组件一处。


signal pile_hovered(seat: int)
signal pile_exited

var seat := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): pile_hovered.emit(seat))
	mouse_exited.connect(func(): pile_exited.emit())


func setup(p_seat: int) -> void:
	seat = p_seat


func set_info(title: String, count: String, status: String) -> void:
	($VBox/NameLabel as Label).text = title
	($VBox/CountLabel as Label).text = count
	($VBox/StatusLabel as Label).text = status


func set_highlight(on: bool) -> void:
	modulate = Color(1.15, 1.12, 0.85) if on else Color.WHITE
