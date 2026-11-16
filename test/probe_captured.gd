extends SceneTree

func _initialize() -> void:
	var table = load("res://scene/game_table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	var eng = table.engine
	var steps := 0
	var mismatches := 0
	while eng.phase != GameEngine.Phase.SETTLED and steps < 3000:
		steps += 1
		match eng.phase:
			GameEngine.Phase.AUCTION:
				var s: int = eng.auction_turn
				eng.submit_bid(s, AiPolicy.choose_bid(eng.hands[s], eng.current_highest_bid()))
			GameEngine.Phase.TRUMP:
				var ch: Dictionary = AiPolicy.choose_trump(eng.hands[eng.banker_seat])
				eng.submit_trump(eng.banker_seat, ch.suit, ch.rank)
			GameEngine.Phase.DISCARD:
				eng.submit_discard(eng.banker_seat, AiPolicy.choose_discard(eng.hands[eng.banker_seat], eng.trump))
			GameEngine.Phase.TRICKS:
				var s: int = eng.turn_seat
				var v: Dictionary = eng.submit_play(s, AiPolicy.choose_play(eng, s))
				if not v.legal:
					print("ILLEGAL seat=", s, " ", v.text)
				# 每步核对：引擎捉分 vs 信息栏显示
				var label: Label = table.get_node("Sidebar/VBox/CapturedLabel")
				var expect := str(eng.captured_points)
				if eng.captured_points > 0 and not label.text.contains(expect):
					mismatches += 1
					if mismatches <= 3:
						print("MISMATCH step=", steps, " engine=", eng.captured_points,
							" label=", label.text, " captured_total=", eng.captured_total if eng.get("captured_total") else "-")
	var lbl: Label = table.get_node("Sidebar/VBox/CapturedLabel")
	print("settled engine_captured=", eng.captured_points, " koudi=", eng.koudi_points)
	print("label=", lbl.text)
	print("mismatches=", mismatches, " steps=", steps)
	quit(0)
