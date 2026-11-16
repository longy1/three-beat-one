extends SceneTree

func _initialize() -> void:
	var table = load("res://scene/game_table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	var eng = table.engine
	# 1) 跑几轮真实出牌，让闲家捉分上涨
	var steps := 0
	while eng.phase == GameEngine.Phase.AUCTION and steps < 60:
		steps += 1
		var s: int = eng.auction_turn
		if s == 0:
			table._submit_human_bid(GameEngine.BID_PASS)
		else:
			eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid()))
	steps = 0
	while eng.phase != GameEngine.Phase.SETTLED and steps < 200:
		steps += 1
		if eng.phase == GameEngine.Phase.TRUMP:
			var ch: Dictionary = AiPolicy.choose_trump(eng.hands[eng.banker_seat])
			eng.submit_trump(eng.banker_seat, ch.suit, ch.rank)
		elif eng.phase == GameEngine.Phase.DISCARD:
			eng.submit_discard(eng.banker_seat, AiPolicy.choose_discard(eng.hands[eng.banker_seat], eng.trump))
		else:
			var s: int = eng.turn_seat
			eng.submit_play(s, AiPolicy.choose_play(eng, s))
		if steps % 8 == 0:
			var lbl: Label = table.get_node("Sidebar/VBox/CapturedLabel")
			print("step=", steps, " engine_captured=", eng.captured_points, " label=", lbl.text)
	await create_timer(0.1).timeout
	var lbl2: Label = table.get_node("Sidebar/VBox/CapturedLabel")
	print("final engine=", eng.captured_points, " label=", lbl2.text)
	print("trick_history=", eng.trick_history.size())
	# 2) 悬停历史按钮 → 弹层
	var chip: Button = table._human_pile_chip
	print("chip_visible=", chip.visible, " text=", chip.text)
	chip.mouse_entered.emit()
	await process_frame
	var popup = table.get_node_or_null("PilePopup")
	print("pile_popup_visible=", popup.visible if popup else "null",
		" rows=", popup.get_node("VBox/Scroll/List").get_child_count() if popup else -1)
	# 3) 底牌按钮（庄=自己时）
	print("bottom_btn_visible=", table._bottom_pile_button.visible, " banker=", eng.banker_seat)
	quit(0)
