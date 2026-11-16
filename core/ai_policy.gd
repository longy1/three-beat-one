class_name AiPolicy
extends RefCounted
## AI 策略门面（单机适配层）：持有共享随机源，把引擎状态解包给纯策略模块。
## 实现分布：AiBidding（叫分 EV 模型）、AiPlay（叫主/扣底/出牌贪心）。
## 两者均为数据进/决策出（不持有引擎引用）——联机服务端可绕过本门面
## 直接调用纯模块（M4 预留）；M3 蒙特卡洛评估也在纯模块层替换。


const BID_PASS := GameEngine.BID_PASS

## AI 共享随机源（叫分竞叫概率等）；_static_init 中随机化；测试可注入种子
static var rng := RandomNumberGenerator.new()


static func _static_init() -> void:
	rng.randomize()


## ============================= 叫分（委托 AiBidding） =============================

## 手牌强度评分（校准工具/调试用）
static func hand_strength(hand: Array) -> int:
	return AiBidding.hand_strength(hand)


## 返回意向叫分或 BID_PASS
static func choose_bid(hand: Array, highest_bid: int) -> int:
	return AiBidding.choose_bid(hand, highest_bid, rng)


## ============================= 叫主 / 扣底 / 出牌（委托 AiPlay） =============================

static func choose_trump(hand: Array) -> Dictionary:
	return AiPlay.choose_trump(hand)


static func choose_discard(hand: Array, trump: TrumpInfo) -> Array:
	return AiPlay.choose_discard(hand, trump, GameEngine.BOTTOM_SIZE)


## 出牌：从引擎状态解包数据后交纯策略（联机服务端应直接调 AiPlay.choose_play）
static func choose_play(engine: GameEngine, seat: int) -> Array:
	return AiPlay.choose_play(engine.hands[seat], engine.trump, engine.current_plays, seat, engine.banker_seat)
