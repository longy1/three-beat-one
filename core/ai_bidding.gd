class_name AiBidding
extends RefCounted
## AI 叫分策略（M2 基线；M3 可升级为蒙特卡洛评估）。
## 数据进/决策出：不持有引擎引用、不读引擎内部状态，随机源由调用方注入——
## 联机服务端可按玩家独立实例化（M4 预留）。


const BID_PASS := -1  ## 放弃标识（与 GameEngine.BID_PASS 同值；此处自持以解耦引擎）


## 手牌强度评分（叫主前，不区分主副）：王/2/A/K 加权 + 对子 + 潜在拖拉机
static func hand_strength(hand: Array) -> int:
	var score := 0
	var groups := Combo.pair_groups(hand)
	for key in groups:
		var g: Array = groups[key]
		var c: Card = g[0]
		match c.rank:
			Card.RANK_BIG_JOKER: score += 30
			Card.RANK_SMALL_JOKER: score += 24
			Card.RANK_2: score += 7
			Card.RANK_A: score += 5
			Card.RANK_K: score += 2
		if g.size() >= 2:
			score += 6
	# 同花色相邻对（潜在拖拉机；K~A 禁连不计）
	var pairs_by_suit := {}
	for key in groups:
		var g: Array = groups[key]
		if g.size() >= 2:
			var k := str(g[0].suit)
			if not pairs_by_suit.has(k):
				pairs_by_suit[k] = []
			pairs_by_suit[k].append(g[0].rank)
	for k in pairs_by_suit:
		var ranks: Array = pairs_by_suit[k]
		ranks.sort()
		for i in ranks.size() - 1:
			if ranks[i + 1] - ranks[i] == 1 and not (ranks[i] == Card.RANK_K and ranks[i + 1] == Card.RANK_A):
				score += 9
	return score


## ── 叫分校准模型（2026-11-17 重校准：test/calibrate_bidding.gd，1260 局新出牌策略 AI 互搏）──
## 庄家平均收益（B=1）按「叫分档 × 手牌强度桶」查表；桶 [0,35)/[35,50)/[50,65)/[65,∞)，
## 插值中心近似 17.5/42.5/57.5/82.5。
## 校准结论（新出牌策略下）：仅强牌（≥65）在 130/135 为正期望（+0.40/+1.05），
## 150 及以上全负——庄闲双方都变强后坐庄收益收窄，AI 自然收敛到低叫分平滑竞叫。
## 校准值受出牌策略水平约束：出牌策略迭代后需重跑校准工具。
const BID_CALIB := {
	130: [-2.83, -0.56, -0.95, 0.40],
	135: [-2.85, -1.35, -1.80, 1.05],
	150: [-3.23, -1.50, -2.25, 0.10],
	165: [-3.97, -2.45, -1.90, 0.10],
	180: [-5.05, -3.10, -3.85, -0.80],
	200: [-5.30, -3.60, -2.35, -1.65],
}
const CALIB_CENTERS := [17.5, 42.5, 57.5, 82.5]


## 查表插值：给定叫分与手牌强度，返回校准的庄家平均收益
static func _calib_gain(b: int, s: float) -> float:
	var row: Array = BID_CALIB[b]
	if s <= CALIB_CENTERS[0]:
		return row[0]
	for i in range(CALIB_CENTERS.size() - 1):
		if s <= CALIB_CENTERS[i + 1]:
			var t: float = (s - CALIB_CENTERS[i]) / (CALIB_CENTERS[i + 1] - CALIB_CENTERS[i])
			return lerp(row[i], row[i + 1], t)
	return row[3]


## 返回意向叫分或 BID_PASS。
## 策略（2026-11-17 平滑化）：校准 EV 只用来选出「愿叫上限档」——期望 > 0.2 才愿意叫；
## -0.6~0.2 噪声区 40% 概率参与。实际叫分 = 当前最高 + 5，逐轮平滑递进到上限档，
## 不再一步跳档（130 一手叫到 150 体验差）；现最高已越过上限档则放弃。
static func choose_bid(hand: Array, highest_bid: int, rng: RandomNumberGenerator) -> int:
	var s: float = float(hand_strength(hand))
	var best_b := BID_PASS
	var best_gain := -999.0
	for b in [135, 150, 165, 180, 200]:
		if b <= highest_bid:
			continue
		var g: float = _calib_gain(b, s)
		if g > best_gain:
			best_gain = g
			best_b = b
	if best_b == BID_PASS:
		return BID_PASS
	var willing := best_gain > 0.2 or (best_gain > -0.6 and rng.randf() < 0.4)
	if not willing:
		return BID_PASS
	var step: int = highest_bid + 5
	if step > 200 or step > best_b:
		return BID_PASS  # 超封顶，或现最高已越过愿叫上限
	return step
