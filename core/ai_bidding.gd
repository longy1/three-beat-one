class_name AiBidding
extends RefCounted
## AI 叫分策略（M2 基线；M3 可升级为蒙特卡洛评估）。
## 数据进/决策出：不持有引擎引用、不读引擎内部状态，随机源由调用方注入——
## 联机服务端可按玩家独立实例化（M4 预留）。


const BID_PASS := -1  ## 放弃标识（与 GameEngine.BID_PASS 同值；此处自持以解耦引擎）
const BASE_BID := 130  ## 抓牌庄家底叫（与 Auction.DEALER_BASE_BID 同值；自持解耦）


## ── 扫荡概率模型（2026-11-18 叫分迭代；探 200 与放宽参与为用户定夺）──
## 规则依据 7.2 跟牌强制：庄家连续领主牌对/拖拉机，闲家有主必须跟，每轮按领出
## 张数 1:1 抽干——扫荡成立 ⇔ 我方持主 ≥ 每家闲家持主。概率抬升愿叫上限档
## （≥0.30→165 / ≥0.60→180 / ≥0.85→200）并在 ≥0.5 时特批参与（EV 弱负也叫）。
## 规则 9 胜线 205：叫 200 时闲家只需捉 5 分，即使扫荡成功也几乎守不住，
## 故 200 仅极端概率（≥0.85）可探。设计锚点：平均手 ≈0.4~0.55；四王级强手
## ≈0.6~0.8；M≥14 长主手 ≈1.0；对手加叫 200 可把四王手压下一档。
const SWEEP_SLOPE := 0.10         ## 持主余量（张）→ 概率斜率
const SWEEP_SPREAD := 2.0         ## 「最大一家持主」高于均摊的散布余量
const EVIDENCE_SLOPE := 0.04      ## 对手加叫每 1 分折算的期望持主增量
const CTRL_BASE := 0.30           ## 控制系数基底（全低散主牌时领出压不住）
const CTRL_PER_PAIR := 0.08       ## 每个主牌对子的控制加成
const CTRL_PER_TRACTOR := 0.20    ## 每个主牌拖拉机的控制加成
const CTRL_PER_PERMANENT := 0.06  ## 每张常主（王/2/R）的控制加成
const CTRL_PERMANENT_CAP := 8     ## 常主控制加成封顶张数
const SWEEP_GATE_P := 0.5         ## 扫荡特批参与门槛（概率）
const SWEEP_GATE_FLOOR := -2.0    ## 扫荡特批允许的 EV 下限（弱负也参与）
const SWEEP_EXTREME_P := 0.85     ## 极端扫荡门槛：无视 EV 放手一搏（现最高 ≥180 时
                                  ## 扫描只剩 200 档、EV −2.98，中段特批够不着）


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


## ── 叫分校准模型（2026-11-17 重校准：test/calibrate_bidding.gd，守门协调 + 牌力分级 +
## 下分门槛细化出牌策略下 ×2 轮加权均值）──
## 庄家平均收益（B=1）按「叫分档 × 手牌强度桶」查表；桶 [0,35)/[35,50)/[50,65)/[65,∞)，
## 插值中心近似 17.5/42.5/57.5/82.5。
## 校准结论：强牌（≥65）在 130~150 弱正期望（+0.17/+0.15/+0.33，150 档最优）——下分门槛
## 细化后闲家不再向庄家必赢轮白送分，庄家收益较上版整体回落；165 及以上明确负，
## 愿叫上限档维持 150，实际叫分仍 最高+5 平滑递进。
## 校准值受出牌策略水平约束：出牌策略迭代后需重跑校准工具。
const BID_CALIB := {
	130: [-3.55, -3.13, -1.31, 0.17],
	135: [-3.68, -2.82, -1.82, 0.15],
	150: [-4.71, -2.79, -1.88, 0.33],
	165: [-4.12, -3.69, -3.40, -0.72],
	180: [-6.25, -3.42, -3.75, -1.32],
	200: [-5.25, -4.97, -4.08, -2.98],
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


## 扫荡对手主牌的概率估计（2026-11-18 叫分迭代）。
## opponent_raises 为对手主动加叫值列表（>130，每座位取最新值，可空 = 无证据）。
## 流程：假想定主（复用 AiPlay.choose_trump，即拍后我会做的选择）→ 手中主牌 m →
## 底牌期望主（底牌 8 张来自未见牌，按比例取期望；加叫者常主「锁」在手不落底 →
## 即时下调）→ 我方期望持主 M（扣底策略不扣常主，仅被迫时扣 → 19 封顶）→
## 对手最大持主估计 est_max（加叫者按 均摊+增量 抬升，其余对手分摊剩余）→
## 控制系数 C（常主与对/拖决定领出能否持续压制）→ P = 基础概率 × C。
static func sweep_prob(hand: Array, opponent_raises: Array = []) -> float:
	var hypo: Dictionary = AiPlay.choose_trump(hand)
	var hypo_suit: int = hypo.suit
	var hypo_rank: int = hypo.rank
	var trump := TrumpInfo.new(hypo_suit, hypo_rank)
	var trump_cards: Array = []
	for c in hand:
		if trump.is_trump(c):
			trump_cards.append(c)
	# 全副牌主数：R=2 时 2 与 R 重合（王 4 + 二/R 8 + 主花色普通 18）；否则 36
	var total_trump := 30 if trump.rank == Card.RANK_2 else 36
	# 加叫证据：对手叫分 r → 期望持主增量 Δ=(r−130)×0.04，汇总为「锁走」的持主
	var deltas: Array = []
	var locked := 0.0
	for r in opponent_raises:
		var rv: int = r
		var d: float = float(rv - BASE_BID) * EVIDENCE_SLOPE
		deltas.append(d)
		locked += d
	# 底牌期望主：底牌 8 张来自 84−手牌数 张未见牌；加叫者锁走的常主不在其中
	var unseen := 84 - hand.size()
	var pool := float(total_trump - trump_cards.size())
	var kitty0: float = 8.0 * pool / float(unseen)
	var kitty: float = 8.0 * maxf(pool - locked, 0.0) / float(unseen)
	var m_expect: float = minf(19.0, float(trump_cards.size()) + kitty)
	var opp_total: float = float(total_trump) - m_expect
	# 对手最大持主估计：无证据均摊为锚，加叫者抬升 Δ，其余对手分摊剩余（主牌总量固定）
	var base_mu: float = (float(total_trump) - minf(19.0, float(trump_cards.size()) + kitty0)) / 3.0
	var sum_mu_raise := 0.0
	var mu_max := base_mu
	for d in deltas:
		var dv: float = d
		sum_mu_raise += base_mu + dv
		mu_max = maxf(mu_max, base_mu + dv)
	var mu_others: float = maxf(opp_total - sum_mu_raise, 0.0) / float(maxi(3 - deltas.size(), 1))
	var est_max: float = maxf(mu_max, mu_others) + SWEEP_SPREAD
	# 控制系数：常主越多领出越必胜；对/拖每轮抽得更多且更难被闲家压过
	var permanent := 0
	for c in trump_cards:
		if trump.is_permanent_trump(c):
			permanent += 1
	var control: float = CTRL_BASE + CTRL_PER_PAIR * float(FollowRule.list_pairs(trump_cards, TrumpInfo.CLASS_TRUMP, trump).size()) \
		+ CTRL_PER_TRACTOR * float(FollowRule.list_tractors(trump_cards, TrumpInfo.CLASS_TRUMP, trump).size()) \
		+ CTRL_PER_PERMANENT * float(mini(permanent, CTRL_PERMANENT_CAP))
	control = clampf(control, CTRL_BASE, 1.0)
	var margin: float = m_expect - est_max
	return clampf(0.5 + margin * SWEEP_SLOPE, 0.0, 1.0) * control


## 座位叫分值数组 → 对手主动加叫列表。底叫 130 为强制表态不算证据；
## 已放弃对手的历史加叫仍算证据（其确曾持有相应实力）。
static func _opponent_raises(my_seat: int, seat_bids: Array) -> Array:
	var raises: Array = []
	for s in seat_bids.size():
		if s == my_seat:
			continue
		var v: int = seat_bids[s]
		if v > BASE_BID:
			raises.append(v)
	return raises


## 扫荡概率 → 愿叫上限上探档（用户定夺 2026-11-18：允许探至封顶 200）。
## 返回 0 表示不上探（maxi 后维持 EV 表选出的上限档）。
static func _sweep_cap(p: float) -> int:
	if p >= SWEEP_EXTREME_P:
		return 200
	if p >= 0.60:
		return 180
	if p >= 0.30:
		return 165
	return 0


## 返回意向叫分或 BID_PASS。
## 策略（2026-11-17 平滑化 + 2026-11-18 扫荡迭代）：校准 EV 只用来选出「愿叫上限档」
## ——期望 > 0.2 才愿意叫；-0.6~0.2 噪声区 40% 概率参与；扫荡概率 ≥ SWEEP_GATE_P
## 且 EV 弱负（> SWEEP_GATE_FLOOR）时扫荡特批参与。实际叫分 = 当前最高 + 5，逐轮
## 平滑递进到上限档；扫荡概率按 _sweep_cap 抬升上限（对手加叫即时压低概率）。
## my_seat/seat_bids 提供拍卖叫分证据（缺省无证据，行为同旧版）。
static func choose_bid(hand: Array, highest_bid: int, rng: RandomNumberGenerator,
		my_seat := -1, seat_bids: Array = []) -> int:
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
	var sweep := sweep_prob(hand, _opponent_raises(my_seat, seat_bids))
	var willing := best_gain > 0.2 or (best_gain > -0.6 and rng.randf() < 0.4)
	if not willing and sweep >= SWEEP_EXTREME_P:
		willing = true  # 极端扫荡：抽干对手主牌几成定局，放手一搏（用户定夺 2026-11-18）
	if not willing and sweep >= SWEEP_GATE_P and best_gain > SWEEP_GATE_FLOOR:
		willing = true  # 扫荡特批：抽干对手主牌的把握足以补偿弱负期望
	if not willing:
		return BID_PASS
	best_b = maxi(best_b, _sweep_cap(sweep))
	var step: int = highest_bid + 5
	if step > 200 or step > best_b:
		return BID_PASS  # 超封顶，或现最高已越过愿叫上限
	return step
