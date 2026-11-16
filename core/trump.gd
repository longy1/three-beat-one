class_name TrumpInfo
extends RefCounted
## 叫主结果与主牌体系（规则 3）。
## 叫主 = 出牌庄家在看底牌之前指定主花色 + 常主点数 R（3.2）。

## "主牌类"标记：主花色牌 + 全部常主（3.3）。副牌类用具体花色值（Card.Suit）表示。
const CLASS_TRUMP := -1

var suit: int = Card.Suit.SPADE  ## 主花色
var rank: int = Card.RANK_2      ## 常主点数 R，可任选（含 2 本身，3.2）


func _init(p_suit: int = Card.Suit.SPADE, p_rank: int = Card.RANK_2) -> void:
	suit = p_suit
	rank = p_rank


## 常主：大王、小王、所有 2、点数 R 的所有牌（3.2）。常主脱离原花色（3.3）。
func is_permanent_trump(card: Card) -> bool:
	return card.is_joker() or card.rank == Card.RANK_2 or card.rank == rank


## 主牌类 = 常主 + 主花色普通牌（3.3）
func is_trump(card: Card) -> bool:
	return is_permanent_trump(card) or card.suit == suit


## 牌的归属类：主牌类返回 CLASS_TRUMP；副牌类返回其花色。
## 常主脱离原花色：♣2、♣R 不算 ♣ 牌（3.3，跟花色判定依据）。
func effective_suit(card: Card) -> int:
	if is_trump(card):
		return CLASS_TRUMP
	return card.suit


## 单张牌力全序（3.1）：
## 大王 > 小王 > 正R > 副R > 正2 > 副2 > 主花色 A>…>5 > 副花色 A>…>5
## R=2 时无独立 R 档（正2 即正R，3.2），本映射天然成立。
func card_power(card: Card) -> int:
	if card.is_joker():
		return 800 if card.rank == Card.RANK_BIG_JOKER else 700
	if card.rank == rank:
		return 600 if card.suit == suit else 500  # 正R / 副R
	if card.rank == Card.RANK_2:
		return 400 if card.suit == suit else 300  # 正2 / 副2
	if card.suit == suit:
		return 200 + card.rank  # 主花色普通牌 205~214
	return card.rank  # 副花色普通牌 5~14（一切主牌类 > 一切副牌类）
