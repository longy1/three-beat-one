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


## ── 叫分校准模型（2026-11-16 蒙特卡洛校准：test/calibrate_bidding.gd，1260 局 AI 互搏）──
## 庄家平均收益（B=1）按「叫分档 × 手牌强度桶」查表；强度桶中心 17.5/42.5/57.5/82.5。
## 校准结论：仅极强牌（≥65）叫 130/150 为正期望（+0.85/+0.45）；180/200 一律负期望。
## 校准值受出牌策略水平约束：出牌策略迭代后需重跑校准工具。
const BID_CALIB := {
	130: [-4.43, -1.14, -0.81, 0.85],
	135: [-3.26, -2.45, -0.45, 0.40],
	150: [-3.00, -2.35, -2.20, 0.45],
	165: [-3.12, -4.13, -2.45, -0.75],
	180: [-4.89, -4.05, -2.65, -1.55],
	200: [-5.35, -4.56, -3.15, -1.95],
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
## 策略（期望收益模型）：对每个可叫档位查校准收益表（含强度插值），
## 取期望最大者——仅当期望 > 0.2 直接叫；接近打平（-0.6~0.2）时 40% 概率
## 参与竞叫；明显负期望一律放弃。130 档 = 底叫被动坐庄（不主动叫）。
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
	if best_gain > 0.2:
		return best_b
	if best_gain > -0.6 and rng.randf() < 0.4:
		return BID_PASS
	return BID_PASS
