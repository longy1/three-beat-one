extends SceneTree
## 出牌历史面板视觉验收辅助（**非 headless** 运行，窗口会短暂弹出）：
## 跑迷你局两轮 → 点击打开出牌历史面板 → 抓视口存 PNG。
## 用法：Godot_v4.7.2-stable_win64.exe --path . -s tool/capture_history_panel.gd
## 输出：build/panel_capture.png（build/ 已忽略不入库）。

const OUT := "build/panel_capture.png"


func _initialize() -> void:
	_capture()


func _capture() -> void:
	var table = load("res://scene/table/game_table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	table._ai_delay_scale = 0.02
	table._trick_timer.wait_time = 0.05
	var eng: GameEngine = table.engine
	# 迷你局（庄 3 = AI，两轮打空）：庄家 10 张自扣 8 留 2 张主牌连赢两轮；
	# 拍卖/叫主/扣底/AI 出牌由处理器自驱，人类叫分与出牌在此代点
	var hands := [
		[Card.new(Card.Suit.HEART, Card.RANK_7, 0), Card.new(Card.Suit.HEART, Card.RANK_8, 0)],
		[Card.new(Card.Suit.SPADE, Card.RANK_J, 0), Card.new(Card.Suit.SPADE, Card.RANK_5, 0)],
		[Card.new(Card.Suit.HEART, Card.RANK_7, 1), Card.new(Card.Suit.DIAMOND, Card.RANK_7, 0)],
		[Card.new(Card.Suit.SPADE, Card.RANK_A, 0), Card.new(Card.Suit.SPADE, Card.RANK_K, 0),
			Card.new(Card.Suit.HEART, Card.RANK_7, 2), Card.new(Card.Suit.HEART, Card.RANK_10, 0),
			Card.new(Card.Suit.HEART, Card.RANK_J, 0), Card.new(Card.Suit.HEART, Card.RANK_Q, 0),
			Card.new(Card.Suit.DIAMOND, Card.RANK_8, 0), Card.new(Card.Suit.DIAMOND, Card.RANK_10, 0),
			Card.new(Card.Suit.DIAMOND, Card.RANK_Q, 0), Card.new(Card.Suit.DIAMOND, Card.RANK_J, 0)],
	]
	var bottom: Array = []
	var bottom_ranks := [Card.RANK_7, Card.RANK_8, Card.RANK_9, Card.RANK_10,
		Card.RANK_J, Card.RANK_Q, Card.RANK_K, Card.RANK_A]
	for i in 8:
		bottom.append(Card.new(Card.Suit.CLUB, bottom_ranks[i], 0))
	eng.start_session_with_deal(3, hands, bottom)
	var guard := 0
	while eng.phase != GameEngine.Phase.TRICKS and guard < 100:
		guard += 1
		if eng.phase == GameEngine.Phase.AUCTION and eng.auction.turn == 0:
			eng.submit_bid(0, GameEngine.BID_PASS)
		await create_timer(0.05).timeout
	guard = 0
	while eng.turn_seat != 0 and eng.phase == GameEngine.Phase.TRICKS and guard < 100:
		guard += 1
		await create_timer(0.05).timeout
	eng.submit_play(0, [eng.hands[0][0]])
	guard = 0
	while eng.turn_seat != 0 and eng.phase == GameEngine.Phase.TRICKS and guard < 100:
		guard += 1
		await create_timer(0.05).timeout
	eng.submit_play(0, [eng.hands[0][0]])
	guard = 0
	while eng.phase == GameEngine.Phase.TRICKS and guard < 100:
		guard += 1
		await create_timer(0.05).timeout
	# 打开面板并等渲染落地
	table._trick_history.open(eng.trick_history, table.SEAT_NAMES)
	for i in 5:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("已保存 %s（%d 轮历史）" % [OUT, eng.trick_history.size()])
	quit()
