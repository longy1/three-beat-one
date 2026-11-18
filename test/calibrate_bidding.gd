extends SceneTree
## 叫分校准工具（平衡用，不注册进测试套件）：
##   Godot --headless --path . -s test/calibrate_bidding.gd
## 对「固定叫分 b × 庄家手牌强度分桶」做拒绝采样模拟，
## 统计闲家捉分分布、庄胜率、平均级数与庄家期望收益 → 打印校准表。

const B_LEVELS := [135, 150, 165, 180, 200]
const B130 := 130  # 底叫档（其它全 pass）
const TRIALS_PER_CELL := 200
const STRENGTH_BINS := [[0, 35], [35, 50], [50, 65], [65, 999]]

var rng := RandomNumberGenerator.new()


func C(s: int, r: int, c := 0) -> Card:
	return Card.new(s, r, c)


func _initialize() -> void:
	rng.randomize()
	var results := {}  # key "b_lo_hi" -> {n, wins, capt:[], gain:[]}
	var eng := GameEngine.new()
	var total_target := B_LEVELS.size() * STRENGTH_BINS.size() * TRIALS_PER_CELL + TRIALS_PER_CELL
	var done := 0
	var attempts := 0
	# 全部目标格：5 个主动叫分档 × 4 强度桶 + 130 底叫档 × 4 桶（庄家不主动叫，其它全 pass）
	var all_cells: Array = []
	for b in B_LEVELS:
		for bin in STRENGTH_BINS:
			all_cells.append([b, bin[0], bin[1]])
	for bin in STRENGTH_BINS:
		all_cells.append([B130, bin[0], bin[1]])

	while done < total_target and attempts < 60000:
		attempts += 1
		eng.start_session(rng.randi_range(1, 999999))
		# 强制 0 号坐庄：按其手牌强度做拒绝采样，从“尚未跑满的格”里随机挑一个匹配格
		var s: int = AiPolicy.hand_strength(eng.hands[0])
		var candidates: Array = []
		for c in all_cells:
			var key := "%d_%d_%d" % [c[0], c[1], c[2]]
			var n: int = results.get(key, {}).get("n", 0) if results.has(key) else 0
			if n < TRIALS_PER_CELL and s >= c[1] and s < c[2]:
				candidates.append(c)
		if candidates.is_empty():
			continue
		var cell: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
		var b: int = cell[0]
		# 拍卖：0 叫 b（130 档 = 不叫），其余强制放弃
		if b != B130:
			eng.submit_bid(0, b)
		for seat in [1, 2, 3]:
			eng.submit_bid(seat, GameEngine.BID_PASS)
		if eng.phase != GameEngine.Phase.TRUMP:
			continue
		var ch: Dictionary = AiPolicy.choose_trump(eng.hands[0])
		eng.submit_trump(0, ch.suit, ch.rank)
		eng.submit_discard(0, AiPolicy.choose_discard(eng.hands[0], eng.trump))
		var guard := 0
		while eng.phase == GameEngine.Phase.TRICKS and guard < 300:
			guard += 1
			var seat: int = eng.turn_seat
			eng.submit_play(seat, AiPolicy.choose_play(eng, seat))
		if eng.phase != GameEngine.Phase.SETTLED:
			continue
		var r: Dictionary = eng.last_game_result
		var key := "%d_%d_%d" % [b, cell[1], cell[2]]
		if not results.has(key):
			results[key] = {n = 0, wins = 0, capt = [], gain = 0.0}
		var rec: Dictionary = results[key]
		rec.n += 1
		if r.banker_won:
			rec.wins += 1
		rec.gain += r.payments[0]
		rec.capt.append(r.captured_total)
		done += 1
		if done % 60 == 0:
			print("progress done=%d/%d attempts=%d" % [done, total_target, attempts])

	print("===CALIB===")
	for c in all_cells:
		var key := "%d_%d_%d" % [c[0], c[1], c[2]]
		if not results.has(key) or results[key].n == 0:
			continue
		var rec: Dictionary = results[key]
		var mu := 0.0
		for x in rec.capt:
			mu += x
		mu /= rec.capt.size()
		var varian := 0.0
		for x in rec.capt:
			varian += (x - mu) * (x - mu)
		varian /= maxf(1.0, rec.capt.size() - 1)
		print("CELL b=%d s=[%d,%d) n=%d win%%=%.1f mu=%.1f sigma=%.1f avg_gain=%.2f" %
			[c[0], c[1], c[2], rec.n, 100.0 * rec.wins / rec.n, mu, sqrt(varian), rec.gain / rec.n])
	print("===END===")
	quit(0)
