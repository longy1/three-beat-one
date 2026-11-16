class_name TestBase
extends RefCounted
## 测试套件共享基类：造牌助手 + 通用夹具（♠ 主 R=9 / Phase 别名）。
## 各套件 extends TestBase 后直接使用 C() 与 trump，消除逐文件重复。


const Phase := GameEngine.Phase

# A.2.2 推演前提：♠ 为主花色，R = 9（规则用例的基准主牌）
var trump := TrumpInfo.new(Card.Suit.SPADE, Card.RANK_9)


## 造牌助手（花色、点数、副号）
func C(suit: int, rank: int, copy := 0) -> Card:
	return Card.new(suit, rank, copy)
