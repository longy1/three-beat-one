class_name AppSettings
extends RefCounted
## 游戏设置（单一事实源）：手牌区呈现偏好。主菜单与牌桌的设置入口共用同一份
## 静态状态，变更即保存（ConfigFile user://settings.cfg）并即时生效——调用方
## （game_table）在 on_changed 回调里重渲手牌即可。

const CFG_PATH := "user://settings.cfg"

## 手牌区主牌框位置：左（默认）或右
enum MainSide { LEFT, RIGHT }
## 牌点数排序方向：组内从大到小（默认）或从小到大；花色分组从左到右不变
enum SortOrder { BIG_FIRST, SMALL_FIRST }

static var main_side: int = MainSide.LEFT
static var sort_order: int = SortOrder.BIG_FIRST
## 存储路径（测试可指向临时文件，避免覆写真实用户设置）
static var cfg_path: String = CFG_PATH


static func _static_init() -> void:
	load_settings()


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return
	main_side = cfg.get_value("hand", "main_side", MainSide.LEFT)
	sort_order = cfg.get_value("hand", "sort_order", SortOrder.BIG_FIRST)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hand", "main_side", main_side)
	cfg.set_value("hand", "sort_order", sort_order)
	cfg.save(cfg_path)
