extends TestBase
## FollowRule 用例（规则 7.2 跟牌/杀/垫、附录 B.1 决策树）。
## 前提：♠ 主、R=9 —— 继承自 TestBase.trump。


func verdict(hand: Array, play: Array, lead) -> Dictionary:
	return FollowRule.is_legal(hand, play, lead, trump)


func lead_of(cards: Array) -> Combo:
	return Combo.detect(cards, trump)


## 领出：牌型任选，须为合法牌型且来自手牌（7.1.3）
func test_lead_rules(test) -> void:
	var hand := [C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1), C(Card.Suit.HEART, Card.RANK_5, 0)]
	var v := verdict(hand, [hand[0], hand[1], hand[2], hand[3]], null)
	test.check(v.legal, "领出合法拖拉机")
	test.eq(v.role, FollowRule.Role.LEAD, "领出角色")
	test.eq(verdict(hand, [hand[0], hand[1], hand[2]], null).reason, FollowRule.Reason.WRONG_COUNT, "3 张不能领出")
	test.eq(verdict(hand, [hand[0], hand[1], C(Card.Suit.HEART, Card.RANK_5, 1)], null).reason,
		FollowRule.Reason.NOT_IN_HAND, "不能打出不在手中的牌")
	test.eq(verdict(hand, [hand[0], hand[2], hand[4], C(Card.Suit.HEART, Card.RANK_5, 1)], null).reason,
		FollowRule.Reason.NOT_IN_HAND, "不成牌型的 4 张首先因缺牌被拒")
	var dup := verdict(hand, [hand[0], hand[0]], null)
	test.eq(dup.reason, FollowRule.Reason.DUPLICATE_CARD, "同一张牌不能重复打出")


## 副牌单张轮：有 S 必跟 S（7.2.1）
func test_side_single_must_follow_s(test) -> void:
	var hand := [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_5, 0)]
	var lead := lead_of([C(Card.Suit.CLUB, Card.RANK_A, 0)])
	var v := verdict(hand, [hand[1]], lead)
	test.check(not v.legal, "有 ♣ 必须跟 ♣")
	test.eq(v.reason, FollowRule.Reason.MUST_FOLLOW_TYPE, "拒绝原因")
	test.check(verdict(hand, [hand[0]], lead).legal, "跟 ♣5 合法")


## 副牌单张轮：无 S → 杀可选或自由垫（7.2.3）
func test_side_single_no_s_free(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_5, 1)]
	var lead := lead_of([C(Card.Suit.CLUB, Card.RANK_A, 0)])
	test.eq(verdict(hand, [hand[0]], lead).role, FollowRule.Role.DISCARD, "无 ♣ 垫 ♥5 自由")
	test.eq(verdict(hand, [hand[1]], lead).role, FollowRule.Role.KILL, "♠5 单张 = 杀（可选）")


## A.3 甲：有 ♣ 无拖拉机 → S 打尽 + 补足，必输（7.2.2）
func test_side_tractor_s_exhaust_fill(test) -> void:
	var hand := [C(Card.Suit.CLUB, Card.RANK_10, 1), C(Card.Suit.CLUB, Card.RANK_5, 0),
		C(Card.Suit.DIAMOND, Card.RANK_7, 0), C(Card.Suit.DIAMOND, Card.RANK_8, 0)]
	var lead := lead_of([
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1)])
	var play := hand.duplicate()
	var v := verdict(hand, play, lead)
	test.check(v.legal, "♣ 牌打尽 + 凑数合法")
	test.eq(v.role, FollowRule.Role.EXHAUST_FILL, "打尽补足角色")
	# 少打一张 ♣ → 违反打尽（补牌须与手牌为同一引用）
	var filler := C(Card.Suit.HEART, Card.RANK_A, 0)
	var hand_all: Array = [hand[0], hand[1], hand[2], hand[3], filler]
	var bad := [hand[0], hand[2], hand[3], filler]
	test.eq(verdict(hand_all, bad, lead).reason,
		FollowRule.Reason.MUST_EXHAUST_S, "不能扣下 ♣5 不打")
	# 张数不符
	test.eq(verdict(hand, [hand[0], hand[2], hand[3]], lead).reason, FollowRule.Reason.WRONG_COUNT, "张数须相等")


## A.3 乙：无 ♣ → 垫两对完全自由（"垫其他花色不强求出对子"，7.2 垫牌）
func test_side_tractor_free_discard(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_8, 0), C(Card.Suit.HEART, Card.RANK_8, 1),
		C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_9, 1)]
	var lead := lead_of([
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1)])
	var v := verdict(hand, hand.duplicate(), lead)
	test.check(v.legal, "垫 ♥88♥99 合法")
	test.eq(v.role, FollowRule.Role.DISCARD, "垫牌角色（副牌拖拉机救不了）")


## A.3 丙：无 ♣ → 主牌拖拉机杀（7.2.3）
func test_side_tractor_kill(test) -> void:
	var hand := [C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]
	var lead := lead_of([
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1)])
	var v := verdict(hand, hand.duplicate(), lead)
	test.check(v.legal, "♠88♠99 杀合法（R=9 在链中）")
	test.eq(v.role, FollowRule.Role.KILL, "杀角色")


## S 牌多于领出张数：S 对子优先选出（【强制】；文档示例中 ♣66 因 6 已剔除不可构造，
## 以 ♣77/♣1010 等价替代验证）
func test_s_exhaust_pair_priority(test) -> void:
	var hand := [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_7, 1),
		C(Card.Suit.CLUB, Card.RANK_10, 0), C(Card.Suit.CLUB, Card.RANK_10, 1),
		C(Card.Suit.CLUB, Card.RANK_K, 0)]
	var lead := lead_of([
		C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1),
		C(Card.Suit.CLUB, Card.RANK_J, 0), C(Card.Suit.CLUB, Card.RANK_J, 1)])
	# ♣77 与 ♣1010 不相邻 → 无 ♣ 拖拉机 → 走打尽分支
	test.check(verdict(hand, [hand[0], hand[1], hand[2], hand[3]], lead).legal, "两对全出合法")
	test.eq(verdict(hand, [hand[0], hand[1], hand[2], hand[4]], lead).reason,
		FollowRule.Reason.S_PAIR_PRIORITY, "拆 ♣1010 留散 ♣K 违反 S 对子优先")
	var filler_a := C(Card.Suit.HEART, Card.RANK_A, 0)
	var filler_k := C(Card.Suit.HEART, Card.RANK_K, 0)
	var hand_with_fillers: Array = [hand[0], hand[1], hand[2], hand[3], hand[4], filler_a, filler_k]
	test.eq(verdict(hand_with_fillers, [hand[0], hand[1], filler_a, filler_k], lead).reason,
		FollowRule.Reason.MUST_EXHAUST_S, "S 牌多于张数时只能从 S 中选")
	# S 牌恰等于张数 → 全部打出
	var hand2 := [C(Card.Suit.CLUB, Card.RANK_7, 0), C(Card.Suit.CLUB, Card.RANK_K, 0),
		C(Card.Suit.HEART, Card.RANK_A, 0)]
	var lead2 := lead_of([C(Card.Suit.CLUB, Card.RANK_Q, 0), C(Card.Suit.CLUB, Card.RANK_Q, 1)])
	test.check(verdict(hand2, [hand2[0], hand2[1]], lead2).legal, "两张 ♣ 全出")
	test.eq(verdict(hand2, [hand2[0], hand2[2]], lead2).reason, FollowRule.Reason.MUST_EXHAUST_S, "扣 ♣K 违反打尽")


## A.5 乙：有 ♣ 对子必须跟对子（不强制压，7.2.1）
func test_side_pair_must_follow(test) -> void:
	var hand := [C(Card.Suit.CLUB, Card.RANK_5, 0), C(Card.Suit.CLUB, Card.RANK_5, 1),
		C(Card.Suit.SPADE, Card.RANK_9, 0), C(Card.Suit.SPADE, Card.RANK_9, 1)]
	var lead := lead_of([C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)])
	test.check(verdict(hand, [hand[0], hand[1]], lead).legal, "♣55 跟 ♣KK 合法（不强制压）")
	var kill_try := verdict(hand, [hand[2], hand[3]], lead)
	test.check(not kill_try.legal, "有 ♣ 对子时不能用 ♠99 杀")
	test.eq(kill_try.reason, FollowRule.Reason.MUST_FOLLOW_TYPE, "拒绝原因")


## A.5 丁：无 ♣ → 杀可选，可垫牌保留主牌实力（"杀的保留权"）
func test_side_pair_kill_optional(test) -> void:
	var hand := [C(Card.Suit.DIAMOND, Card.RANK_Q, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 0),
		C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1)]
	var lead := lead_of([C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)])
	test.eq(verdict(hand, [hand[0], hand[1]], lead).role, FollowRule.Role.DISCARD, "垫 ♦Q♦J 保留杀")
	test.eq(verdict(hand, [hand[2], hand[3]], lead).role, FollowRule.Role.KILL, "♠AA 杀也可选")


## 副牌对子轮：散主牌不成杀型 → 垫必输（"杀与散主牌"）
func test_side_pair_scattered_trump_discard(test) -> void:
	var hand := [C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_9, 0),
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0)]
	var lead := lead_of([C(Card.Suit.CLUB, Card.RANK_K, 0), C(Card.Suit.CLUB, Card.RANK_K, 1)])
	test.eq(verdict(hand, [hand[0], hand[1]], lead).role, FollowRule.Role.DISCARD, "大王+小王式散主牌作垫（此处 ♠8+♠9 非对子）")


## A.4 主牌单张轮：有主必跟（7.2 领出主牌时）
func test_main_single_must_follow(test) -> void:
	var lead := lead_of([C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0)])
	# 丁：♠10 属主花色普通牌，必须跟
	var ding := [C(Card.Suit.SPADE, Card.RANK_10, 0), C(Card.Suit.HEART, Card.RANK_A, 0)]
	test.check(verdict(ding, [ding[0]], lead).legal, "♠10 跟小王")
	test.eq(verdict(ding, [ding[0]], lead).role, FollowRule.Role.FOLLOW_TYPE, "跟主牌角色")
	test.eq(verdict(ding, [ding[1]], lead).reason, FollowRule.Reason.MUST_FOLLOW_TYPE, "有主牌不能垫 ♥A")
	# 甲：大王更大
	var jia := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0)]
	test.eq(verdict(jia, [jia[0]], lead).role, FollowRule.Role.FOLLOW_TYPE, "大王跟主牌轮")
	# 乙：♥2 常主脱离花色，可跟主牌轮（3.3）
	var yi := [C(Card.Suit.HEART, Card.RANK_2, 0)]
	test.eq(verdict(yi, [yi[0]], lead).role, FollowRule.Role.FOLLOW_TYPE, "♥2（副2）跟主牌轮")
	# 无任何主牌 → 垫副牌
	var none := [C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0)]
	test.eq(verdict(none, [none[0]], lead).role, FollowRule.Role.DISCARD, "无主牌垫副牌")


## 主牌对子轮：有主牌对子必须跟（选牌自由：多组任选）
func test_main_pair_must_follow(test) -> void:
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1),
		C(Card.Suit.SPADE, Card.RANK_5, 0)]
	var lead := lead_of([C(Card.Suit.SPADE, Card.RANK_A, 0), C(Card.Suit.SPADE, Card.RANK_A, 1)])
	test.check(verdict(hand, [hand[2], hand[3]], lead).legal, "♠88 跟 ♠AA（不强制压）")
	test.eq(verdict(hand, [hand[0], hand[1]], lead).role, FollowRule.Role.FOLLOW_TYPE, "大王对也是主牌对（任选）")
	test.eq(verdict(hand, [hand[2], hand[4]], lead).reason, FollowRule.Reason.MUST_FOLLOW_TYPE, "♠8♠9 非对子不能跟对子轮")


## 主牌拖拉机轮：主牌打尽 + 常主对子优先垫出（【强制】）
func test_main_tractor_exhaust_perm_priority(test) -> void:
	var lead := lead_of([
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1)])
	# 无主牌拖拉机（大王对 + 散主牌），主牌 5 张 > 4 → 主牌内挑选
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_J, 0), C(Card.Suit.SPADE, Card.RANK_Q, 0)]
	test.check(verdict(hand, [hand[0], hand[1], hand[2], hand[3]], lead).legal, "大王对 + 主牌凑数合法")
	test.eq(verdict(hand, [hand[0], hand[2], hand[3], hand[4]], lead).reason,
		FollowRule.Reason.PERMANENT_PAIR_PRIORITY, "拆大王对违反常主对子优先")
	var filler := C(Card.Suit.HEART, Card.RANK_A, 0)
	var hand_with_filler: Array = [hand[0], hand[1], hand[2], hand[3], hand[4], filler]
	var mixed := verdict(hand_with_filler, [hand[0], hand[1], hand[2], filler], lead)
	test.check(not mixed.legal, "主牌够时不能垫进副牌")
	test.eq(mixed.reason, FollowRule.Reason.MUST_EXHAUST_TRUMP, "主牌打尽")


## 主牌拖拉机轮：主牌不足张数 → 全部主牌 + 副牌补足
func test_main_tractor_insufficient_fill(test) -> void:
	var lead := lead_of([
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1)])
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.SPADE, Card.RANK_5, 0),
		C(Card.Suit.HEART, Card.RANK_A, 0), C(Card.Suit.HEART, Card.RANK_K, 0), C(Card.Suit.HEART, Card.RANK_Q, 0)]
	test.check(verdict(hand, [hand[0], hand[1], hand[2], hand[3]], lead).legal, "主牌全出 + 副牌补足")
	test.eq(verdict(hand, [hand[0], hand[2], hand[3], hand[4]], lead).reason,
		FollowRule.Reason.MUST_EXHAUST_TRUMP, "扣下 ♠5 违反主牌打尽")


## 领出主牌拖拉机、唯一主牌拖拉机是四王 → 必须打出（7.2 四王）
func test_four_jokers_must_play(test) -> void:
	var lead := lead_of([
		C(Card.Suit.SPADE, Card.RANK_7, 0), C(Card.Suit.SPADE, Card.RANK_7, 1),
		C(Card.Suit.SPADE, Card.RANK_8, 0), C(Card.Suit.SPADE, Card.RANK_8, 1)])
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1),
		C(Card.Suit.SPADE, Card.RANK_5, 0)]
	var v := verdict(hand, [hand[0], hand[1], hand[2], hand[3]], lead)
	test.check(v.legal, "四王强制打出")
	test.eq(v.role, FollowRule.Role.FOLLOW_TYPE, "四王跟主牌拖拉机")
	var refuse := verdict(hand, [hand[0], hand[1], hand[2], hand[4]], lead)
	test.check(not refuse.legal, "不能拆四王")
	test.eq(refuse.reason, FollowRule.Reason.MUST_FOLLOW_TYPE, "唯一同型必须出")


## 副牌轮四王是可选杀（A.6 甲刻意保留到末轮的前提）
func test_four_jokers_optional_on_side_lead(test) -> void:
	var hand := [C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 1),
		C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 1)]
	var lead := lead_of([
		C(Card.Suit.DIAMOND, Card.RANK_J, 0), C(Card.Suit.DIAMOND, Card.RANK_J, 1),
		C(Card.Suit.DIAMOND, Card.RANK_10, 0), C(Card.Suit.DIAMOND, Card.RANK_10, 1)])
	test.eq(verdict(hand, hand.duplicate(), lead).role, FollowRule.Role.KILL, "四王杀副牌拖拉机（可选）")


## ============================= 主牌甩打判定（规则 7.3，2026-11-17 增补） =============================

func test_trump_dump_shape(test) -> void:
	test.check(FollowRule.is_trump_dump([C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.SPADE, Card.RANK_7, 0)], trump), "两张主牌单张可甩")
	test.check(FollowRule.is_trump_dump([
		C(Card.Suit.JOKER, Card.RANK_BIG_JOKER, 0), C(Card.Suit.JOKER, Card.RANK_SMALL_JOKER, 0),
		C(Card.Suit.HEART, Card.RANK_9, 0), C(Card.Suit.HEART, Card.RANK_2, 1)], trump), "全常主可甩（含副R/副2）")
	test.check(not FollowRule.is_trump_dump([C(Card.Suit.SPADE, Card.RANK_5, 0)], trump), "单张走普通领出")
	test.check(not FollowRule.is_trump_dump([C(Card.Suit.SPADE, Card.RANK_5, 0), C(Card.Suit.HEART, Card.RANK_7, 0)], trump), "含副牌不可甩")
	test.check(not FollowRule.is_trump_dump([], trump), "空组不可甩")


func test_dump_follow_validation(test) -> void:
	var hand := [C(Card.Suit.HEART, Card.RANK_7, 0), C(Card.Suit.HEART, Card.RANK_8, 0), C(Card.Suit.DIAMOND, Card.RANK_7, 0)]
	var v: Dictionary = FollowRule.is_legal_dump_follow(hand, [hand[0], hand[1]], 2)
	test.check(v.legal, "张数一致、来自手牌 → 合法垫牌")
	test.eq(v.role, FollowRule.Role.DISCARD, "角色 = 垫牌")
	var wrong: Dictionary = FollowRule.is_legal_dump_follow(hand, [hand[0]], 2)
	test.check(not wrong.legal, "张数不足被拒")
	test.eq(wrong.reason, FollowRule.Reason.WRONG_COUNT, "原因 = 张数不符")
	var foreign: Dictionary = FollowRule.is_legal_dump_follow(hand, [hand[0], C(Card.Suit.CLUB, Card.RANK_7, 0)], 2)
	test.check(not foreign.legal, "不在手牌被拒")
	test.eq(foreign.reason, FollowRule.Reason.NOT_IN_HAND, "原因 = 牌不在手中")
	var dup: Dictionary = FollowRule.is_legal_dump_follow(hand, [hand[0], hand[0]], 2)
	test.check(not dup.legal, "重复出牌被拒")
	test.eq(dup.reason, FollowRule.Reason.DUPLICATE_CARD, "原因 = 重复出牌")
