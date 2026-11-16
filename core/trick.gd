class_name Trick
extends RefCounted
## 一轮：领出 + 三人按座位顺序跟牌 + 结算（规则 7.1、8.1、附录 B.2）。
## settle 不信任调用方提供的角色：未提供时按牌面重新推导。


## 结算一轮。plays 按座位顺序、plays[0] 为领出，元素形如：
##   { seat: int, cards: Array[Card], role: int(可选，跟随者由 is_legal 得出) }
## 与 GameEngine.current_plays 同构（键名 seat），调用方可直接传入。
## 支持 1~4 份出牌的部分结算（AI 与 UI 用于判定"当前最大者"）。
## 返回：
##   { ok, error, winner: int(plays 下标), seat: int,
##     points: int, win_main_class: bool, win_type: int }
## - winner/seat：本轮（当前）最大者（并列先出者大，3.1）
## - points：本轮所有已出分牌分值合计（8.1）；是否计入闲家捉分由对局层按赢家阵营决定
## - win_main_class / win_type：末轮抠底判定所需（8.2）
static func settle(plays: Array, trump: TrumpInfo) -> Dictionary:
	if plays.is_empty() or plays.size() > 4:
		return _fail("一轮需要 1~4 份出牌，实得 %d" % plays.size())
	for p in plays:
		if not (p is Dictionary) or not p.has("cards") or p.cards.size() == 0:
			return _fail("出牌记录不完整")

	var lead := Combo.detect(plays[0].cards, trump)
	if lead == null:
		return _fail("领出不构成合法牌型：%s" % Card.cards_to_string(plays[0].cards))

	# 竞争者判定（B.2）：领出牌 + 跟出的同型（副牌轮的杀压过一切跟牌）
	var roles: Array = []
	for i in plays.size():
		roles.append(_derive_role(i, plays[i], lead, trump))

	var winner := 0
	var best_power := Combo.power(lead, trump)
	var kill_winner := -1
	var kill_power := -1
	for i in range(1, plays.size()):
		var combo := Combo.detect(plays[i].cards, trump)
		if combo == null:
			continue  # 垫牌/打尽的凑数牌不参与比较
		var power := Combo.power(combo, trump)
		if roles[i] == FollowRule.Role.KILL:
			if power > kill_power:  # 多个杀比牌力；并列先出者大 → 严格大于
				kill_power = power
				kill_winner = i
		elif roles[i] == FollowRule.Role.FOLLOW_TYPE:
			if power > best_power:  # 并列先出者大 → 严格大于
				best_power = power
				winner = i

	if lead.suit == TrumpInfo.CLASS_TRUMP:
		pass  # 主牌轮：领出牌与跟出的主牌类同型中最大者赢
	elif kill_winner >= 0:
		winner = kill_winner  # 副牌轮有杀：最大杀赢，压过一切跟 S 牌与垫牌
	# else：副牌轮无杀：领出牌与跟 S 同型中最大者赢（已由循环得出）

	var points := 0
	for p in plays:
		for c in p.cards:
			points += c.points()

	var win_combo := Combo.detect(plays[winner].cards, trump)
	return {
		ok = true,
		error = "",
		winner = winner,
		seat = plays[winner].get("seat", winner),
		points = points,
		win_main_class = win_combo.suit == TrumpInfo.CLASS_TRUMP,
		win_type = win_combo.type,
	}


## 无手牌上下文时按牌面推导角色（与 B.2 竞争者定义一致）：
## 跟出完整同型且为领出花色 S → FOLLOW_TYPE；副牌轮跟出主牌类完整同型 → KILL；
## 其余（打尽凑数、垫牌、散主牌）不参与比较 → DISCARD。
## 调用方可用 is_legal 得到的 role 覆盖此推导。
static func _derive_role(index: int, play: Dictionary, lead: Combo, trump: TrumpInfo) -> int:
	if index == 0:
		return FollowRule.Role.LEAD
	if play.has("role"):
		return play.role
	var combo := Combo.detect(play.cards, trump)
	if combo == null or combo.type != lead.type or combo.cards.size() != lead.cards.size():
		return FollowRule.Role.DISCARD
	if lead.suit == TrumpInfo.CLASS_TRUMP:
		return FollowRule.Role.FOLLOW_TYPE if combo.suit == TrumpInfo.CLASS_TRUMP else FollowRule.Role.DISCARD
	if combo.suit == TrumpInfo.CLASS_TRUMP:
		return FollowRule.Role.KILL
	return FollowRule.Role.FOLLOW_TYPE if combo.suit == lead.suit else FollowRule.Role.DISCARD


static func _fail(message: String) -> Dictionary:
	return {ok = false, error = message, winner = -1, seat = -1, points = 0, win_main_class = false, win_type = -1}
