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
## 手机版 UI：强制启用移动端牌桌布局（调试入口；真机由设备特性自动判定）
static var mobile_ui: bool = false
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
	mobile_ui = cfg.get_value("ui", "mobile_ui", false)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hand", "main_side", main_side)
	cfg.set_value("hand", "sort_order", sort_order)
	cfg.set_value("ui", "mobile_ui", mobile_ui)
	cfg.save(cfg_path)


## 运行设备是否移动端（Godot 特性标签：原生 android/ios；Web 移动浏览器 web_android/web_ios）
static func is_mobile_device() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")


## 手机版 UI 生效口径：移动端设备自动启用，或设置项强制开启（PC 调试入口）
static func effective_mobile_ui() -> bool:
	return mobile_ui or is_mobile_device()
