class_name Card
extends RefCounted
## 单张扑克牌（规则 1 基本设定、8.1 分牌）。
## 纯逻辑数据类：不依赖场景节点，单机与联机服务端共用同一份代码。


enum Suit { SPADE = 0, HEART = 1, CLUB = 2, DIAMOND = 3, JOKER = 4 }

# 点数编码（仅作身份标识；牌力全序依赖叫主状态，见 TrumpInfo.card_power）
const RANK_5 := 5
const RANK_7 := 7
const RANK_8 := 8
const RANK_9 := 9
const RANK_10 := 10
const RANK_J := 11
const RANK_Q := 12
const RANK_K := 13
const RANK_A := 14
const RANK_2 := 15
const RANK_SMALL_JOKER := 16
const RANK_BIG_JOKER := 17

# 两副牌剔除 3、4、6 后的可用点数（规则 1）
const RANKS := [
	RANK_5, RANK_7, RANK_8, RANK_9, RANK_10,
	RANK_J, RANK_Q, RANK_K, RANK_A, RANK_2,
]
const NORMAL_SUITS := [Suit.SPADE, Suit.HEART, Suit.CLUB, Suit.DIAMOND]

const _SUIT_CHARS := ["♠", "♥", "♣", "♦", ""]
const _RANK_CHARS := {
	RANK_5: "5", RANK_7: "7", RANK_8: "8", RANK_9: "9", RANK_10: "10",
	RANK_J: "J", RANK_Q: "Q", RANK_K: "K", RANK_A: "A", RANK_2: "2",
	RANK_SMALL_JOKER: "小王", RANK_BIG_JOKER: "大王",
}

var suit: int = Suit.SPADE
var rank: int = RANK_5
var copy := 0  ## 副号（0/1）：两副牌同花同点各一张


func _init(p_suit: int = Suit.SPADE, p_rank: int = RANK_5, p_copy: int = 0) -> void:
	suit = p_suit
	rank = p_rank
	copy = p_copy


func is_joker() -> bool:
	return suit == Suit.JOKER


## 同花色同点数（两副牌的"同张"，规则 7.2 选牌自由的基础）
func same_identity(other: Card) -> bool:
	return suit == other.suit and rank == other.rank


## 完全相同（含副号）；真实对局中手牌内不会出现
func same_card(other: Card) -> bool:
	return suit == other.suit and rank == other.rank and copy == other.copy


## 值身份键（花色+点数+副号）：两副牌内唯一。
## 引擎提交契约按值匹配（UI/联机消息可传等值副本，无须持有原引用）。
func key() -> String:
	return "%d_%d_%d" % [suit, rank, copy]


## 从值身份键还原等值副本（联机消息按 key 传牌，落地还原；键格式见 key()）。
static func from_key(key_text: String) -> Card:
	var parts := key_text.split("_")
	return Card.new(int(parts[0]), int(parts[1]), int(parts[2]))


## 分牌分值：5=5 分、10=10 分、K=10 分，其余 0（规则 8.1）。
## 分牌身份与分值不随常主化改变（如 R=5 时正5/副5 仍是 5 分牌）。
func points() -> int:
	if rank == RANK_5:
		return 5
	if rank == RANK_10 or rank == RANK_K:
		return 10
	return 0


## 两副去 3/4/6 的完整 84 张牌（规则 1）
static func full_deck() -> Array[Card]:
	var deck: Array[Card] = []
	for s in NORMAL_SUITS:
		for r in RANKS:
			for c in 2:
				deck.append(Card.new(s, r, c))
	for c in 2:
		deck.append(Card.new(Suit.JOKER, RANK_SMALL_JOKER, c))
		deck.append(Card.new(Suit.JOKER, RANK_BIG_JOKER, c))
	return deck


## 全牌总分，恒为 200（规则 8.1）
static func deck_points() -> int:
	var total := 0
	for s in NORMAL_SUITS:
		for r in RANKS:
			total += Card.new(s, r).points() * 2
	return total


## 显示名（如 ♠9、大王）；避免覆盖原生 Object.to_string
func label() -> String:
	if is_joker():
		return _RANK_CHARS[rank]
	return _SUIT_CHARS[suit] + _RANK_CHARS[rank]


## 点数字符（如 A、10、大）；卡牌角标竖排用（点数上、花色下）
func rank_label() -> String:
	return _RANK_CHARS[rank]


## 花色字符（♠♥♣♦）；王无花色返回空串
func suit_label() -> String:
	return "" if is_joker() else _SUIT_CHARS[suit]


static func cards_to_string(cards: Array) -> String:
	var parts: Array[String] = []
	for c in cards:
		parts.append(c.label())
	return " ".join(parts)
