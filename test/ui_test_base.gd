class_name UiTestBase
extends TestBase
## UI 套件共享基类（doc/coding.md §5 UI 用例模式）：
## headless 实例化牌桌场景 + 加速计时器 + 标准发牌注入 + 帧暂停。


## 实例化一个干净的牌桌场景并等两帧（布局就绪）；把 AI/停留计时器调快
func _spawn_table():
	var tree: SceneTree = Engine.get_main_loop()
	var table = load("res://scene/table/game_table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	# 加速 UI 定时器：测试不必等待真实的 AI 节奏与结算停留
	#（AI 延迟经 _ai_delay_scale 缩放：0.7s/1.0s 均收敛到 ~0.01s）
	table._ai_delay_scale = 0.014
	table._trick_timer.wait_time = 0.01
	table._trump_reveal.fly_duration = 0.01
	return table


func _release_table(table) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	table.queue_free()
	await tree.process_frame


## 注入标准发牌（固定顺序牌堆切分，内容不重要）并指定抓牌庄家
func _deal(eng: GameEngine, dealer: int) -> void:
	var deck := Card.full_deck()
	var hands: Array = []
	for s in 4:
		hands.append(deck.slice(s * 19, (s + 1) * 19))
	eng.start_session_with_deal(dealer, hands, deck.slice(76, 84))


## 等约一个物理帧（供 UI 信号处理器中的计时器走完）
func tree_pause() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	await tree.create_timer(0.05).timeout
