extends SceneTree
## UI 冒烟测试（独立于单元套件，手动运行）：
##   Godot --headless --path . -s test/smoke_ui.gd
## 实例化牌桌场景，代人类玩家行动，跑完整一局；任何节点路径/脚本错误都会打印。
## 退出码 0 = 一局完整结束。

const GameTableScene := preload("res://scene/game_table.tscn")


func _initialize() -> void:
	var table = GameTableScene.instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	var engine = table.engine
	if engine == null:
		push_error("冒烟：场景 _ready 未执行（engine 为空）")
		quit(1)
		return

	var waited := 0.0
	while engine.phase != GameEngine.Phase.SETTLED and waited < 240.0:
		await create_timer(0.4).timeout
		waited += 0.4
		match engine.phase:
			GameEngine.Phase.AUCTION:
				if engine.auction.turn == 0:
					engine.submit_bid(0, AiPolicy.choose_bid(engine.hands[0], engine.current_highest_bid(), 0, engine.auction.bids))
			GameEngine.Phase.TRUMP:
				if engine.banker_seat == 0:
					var choice: Dictionary = AiPolicy.choose_trump(engine.hands[0])
					engine.submit_trump(0, choice.suit, choice.rank)
			GameEngine.Phase.DISCARD:
				if engine.banker_seat == 0:
					engine.submit_discard(0, AiPolicy.choose_discard(engine.hands[0], engine.trump))
			GameEngine.Phase.TRICKS:
				if engine.turn_seat == 0:
					var verdict: Dictionary = engine.submit_play(0, AiPolicy.choose_play(engine, 0))
					if not verdict.legal:
						push_error("冒烟：人类代打出牌非法 " + verdict.text)
	print("========================================")
	print("UI 冒烟：等待 %d 秒后 phase=%s（第 %d 局）" % [int(waited), GameEngine.Phase.keys()[engine.phase], engine.round_index])
	if engine.phase == GameEngine.Phase.SETTLED:
		var r: Dictionary = engine.last_game_result
		print("结果：庄家%s %d 级 ｜ 捉分 %d ｜ 总分 %d" % ["胜" if r.banker_won else "负", r.level, r.captured_total, r.total_score])
		print("✓ UI 冒烟通过")
		quit(0)
	else:
		print("✗ UI 冒烟超时未完成")
		quit(1)
