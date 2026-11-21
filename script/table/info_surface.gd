class_name InfoSurface
extends RefCounted
## 牌桌信息面（策略层）：桌面分支（顶栏局况 + 中央叫分提示 + 右侧 InfoSidebar）
## 与手机分支（顶栏当局信息 bar + 「更多」面板）的呈现差异全部收进本层——
## 控制器 _refresh* 只向本层喂数据，不含分支判断（依赖注入：控制器
## _apply_layout_mode 按分支装配实例并接线信号）。桌面节点在场景内（build 只
## 恢复可见性）；手机节点程序化创建，build/teardown 管理生命周期——「更多」
## 面板销毁必须走 close()（遮罩 MorePanelDim 由面板负责清理，直接 queue_free
## 面板会把全屏拦截遮罩残留桌面、挡死全部输入）。
## 基类方法为空缺省：分支不适用（如桌面无花色图标行）或由子类覆写。


signal settings_requested  ## 「更多」面板设置入口（手机分支；控制器接 _on_settings）
signal menu_requested      ## 「更多」面板主菜单入口（手机分支；控制器接 _on_menu）
signal refresh_requested   ## 面板打开需喂当前状态（手机分支；控制器接 _refresh）


## ============================= 生命周期 =============================

## 装配：创建分支专属节点并接通交互（须在任何喂数据前调用一次）
func build(_table: Control) -> void:
	pass


## 拆除：销毁分支专属节点与面板（分支切换/退场；遮罩清理见类注）
func teardown() -> void:
	pass


## ============================= 当局信息（三态互斥） =============================

## 拍卖期：叫分进程（桌面同时占中央提示位）
func set_auction_info(_round_index: int, _highest: int) -> void:
	pass


## 出牌期：局数 + 出牌庄 + 叫分
func set_play_info(_round_index: int, _banker_name: String, _contract: int) -> void:
	pass


## 发牌/抓牌期：庄家未定
func set_dealing_info(_round_index: int) -> void:
	pass


## 局数/四家累计/捉分（桌面并入信息栏「局面」块；手机=顶栏捉分 +「更多」面板）
func set_progress(_round_index: int, _cumulative: Array,
		_captured_points: int, _koudi_points: int) -> void:
	pass


## ============================= 手牌统计 =============================

## 花色图标组（手机顶栏专属：恒 4 组、主门金色、王计入主牌数；桌面无此呈现）
func set_suit_stats(_trump: TrumpInfo, _trump_count: int, _suit_counts: Dictionary) -> void:
	pass


## 统计文字行（桌面=信息栏；手机=「更多」面板，打开期间实时更新）
func update_stats(_main_text: String, _rows: Array) -> void:
	pass


## ============================= 主牌展示位 =============================

## 主牌牌面（null = 未叫主占位）
func set_trump(_card: Card) -> void:
	pass


## 主牌槽全局中心（揭主飞牌落点；须在布局完成后测量）
func trump_slot_center() -> Vector2:
	return Vector2.ZERO


## 主牌槽目标牌面尺寸（揭主飞牌渐缩终点）
func trump_slot_size() -> Vector2:
	return Vector2.ZERO


## ============================= 分支查询（控制器/测试触点） =============================

func is_mobile() -> bool:
	return false


func mobile_bar() -> MobileTopBar:
	return null


func more_panel() -> MobileMorePanel:
	return null


## 四家累计文案（两分支同口径，桌面信息栏与手机「更多」面板共用）
static func cumulative_text(cumulative: Array) -> String:
	return "累计：甲 %+d ｜ 乙 %+d\n　　　丙 %+d ｜ 丁 %+d" \
		% [cumulative[0], cumulative[1], cumulative[2], cumulative[3]]


## ============================= 桌面实现 =============================

## 桌面信息面：场景三件套（TopBar/GameInfoLabel、BidCenterLabel、Sidebar），
## 无专属生命周期——build 恢复可见性（手机分支曾隐藏它们），teardown 仅断引用。
class DesktopInfoSurface extends InfoSurface:
	var _game_info: Label
	var _bid_center: Label
	var _sidebar: InfoSidebar


	func build(table: Control) -> void:
		_game_info = table.game_info
		_bid_center = table.bid_center_label
		_sidebar = table.sidebar
		table.top_bar.visible = true
		_bid_center.visible = true
		_sidebar.visible = true


	func teardown() -> void:
		_game_info = null
		_bid_center = null
		_sidebar = null


	func set_auction_info(round_index: int, highest: int) -> void:
		_game_info.text = "第 %d 局" % round_index
		_bid_center.text = "叫分中（最高 %d）" % highest


	func set_play_info(round_index: int, banker_name: String, contract: int) -> void:
		var info := "第 %d 局" % round_index
		info += " ｜ 出牌庄 %s" % banker_name
		if contract > 0:
			info += " ｜ 叫分 %d" % contract
		_game_info.text = info
		_bid_center.text = ""


	func set_dealing_info(round_index: int) -> void:
		_game_info.text = "第 %d 局" % round_index
		_bid_center.text = ""


	func set_progress(_round_index: int, cumulative: Array,
			captured_points: int, koudi_points: int) -> void:
		var captured := "闲家捉分 %d" % captured_points
		if koudi_points > 0:
			captured += "（含抠底 %d）" % koudi_points
		_sidebar.set_state(captured, cumulative_text(cumulative))


	func update_stats(main_text: String, rows: Array) -> void:
		_sidebar.update_stats(main_text, rows)


	func set_trump(card: Card) -> void:
		_sidebar.set_trump(card)


	func trump_slot_center() -> Vector2:
		return _sidebar.trump_slot_center()


	func trump_slot_size() -> Vector2:
		return _sidebar.trump_slot_size()


## ============================= 手机实现 =============================

## 手机信息面：MobileTopBar（程序化顶栏，build 创建/teardown 销毁）+
## MobileMorePanel（打开态管理：☰ 开关、三种关闭路径、打开即经 refresh_requested
## 请求喂数据；teardown 走 close() 连遮罩一并清理）。
class MobileInfoSurface extends InfoSurface:
	var _table: Control = null
	var _bar: MobileTopBar = null
	var _more: MobileMorePanel = null


	func build(table: Control) -> void:
		_table = table
		_bar = MobileTopBar.new()
		_bar.more_pressed.connect(_toggle_more)
		table.add_child(_bar)
		# 桌面三件套让位（切回桌面由 DesktopInfoSurface.build 恢复可见性）
		table.sidebar.visible = false
		table.top_bar.visible = false
		table.bid_center_label.visible = false


	func teardown() -> void:
		if _more != null:
			_more.close()  # closed 信号处理器置空 _more；遮罩 MorePanelDim 随之清理
		if _bar != null:
			_bar.queue_free()
		_bar = null
		_table = null


	func _toggle_more() -> void:
		if _more != null:
			_more.close()
			return
		_more = MobileMorePanel.create(_table,
			func() -> void: settings_requested.emit(),
			func() -> void: menu_requested.emit())
		_more.closed.connect(func(): _more = null)
		refresh_requested.emit()  # 打开即喂当前状态


	func set_auction_info(_round_index: int, highest: int) -> void:
		_bar.set_game_info("叫分中（最高 %d）" % highest)


	func set_play_info(_round_index: int, banker_name: String, contract: int) -> void:
		_bar.set_game_info("出牌庄 %s · 叫分 %d" % [banker_name, contract])


	func set_dealing_info(_round_index: int) -> void:
		_bar.set_game_info("抓牌中…")


	func set_progress(round_index: int, cumulative: Array,
			captured_points: int, _koudi_points: int) -> void:
		_bar.set_captured("捉分 %d" % captured_points)
		if _more != null:
			_more.set_state("第 %d 局" % round_index, cumulative_text(cumulative))


	func set_suit_stats(trump: TrumpInfo, trump_count: int, suit_counts: Dictionary) -> void:
		# 图标+数字恒 4 组：叫主后主门金色突出（王计入主牌数）；未叫主=四门花色
		var suit_chars := ["♠", "♥", "♣", "♦"]
		var entries: Array = []
		if trump != null:
			entries.append({"icon": suit_chars[trump.suit], "count": trump_count, "main": true})
		for s in Card.NORMAL_SUITS:
			if trump == null or s != trump.suit:
				entries.append({"icon": suit_chars[s], "count": suit_counts[s], "main": false})
		_bar.set_suit_stats(entries)


	func update_stats(main_text: String, rows: Array) -> void:
		if _more != null:
			_more.update_stats(main_text, rows)


	func set_trump(card: Card) -> void:
		_bar.set_trump(card)


	func trump_slot_center() -> Vector2:
		return _bar.trump_slot_center()


	func trump_slot_size() -> Vector2:
		return _bar.trump_slot_size()


	func is_mobile() -> bool:
		return true


	func mobile_bar() -> MobileTopBar:
		return _bar


	func more_panel() -> MobileMorePanel:
		return _more
