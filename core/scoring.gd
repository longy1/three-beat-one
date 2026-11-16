class_name Scoring
extends RefCounted
## 分级与收益结算（规则 9、10）。纯静态函数：引擎结算与测试互检共用，
## 不持有任何状态，联机服务端可直接复用。


const WIN_LINE := 205  ## 闲家胜线（规则 9）


## 胜负与级数（规则 9）：总分 = 叫分 + 闲家捉分（含抠底）。
## - 总分 ≥ 205：闲家胜，1 + ⌊(总分−205)/40⌋ 级，封顶 3
## - 捉分 0：庄胜 3 级；5~20：庄胜 2 级；≥25：庄胜 1 级
static func compute_outcome(contract_value: int, captured_total: int) -> Dictionary:
	var total := contract_value + captured_total
	if total >= WIN_LINE:
		return {banker_won = false, level = mini(3, 1 + (total - WIN_LINE) / 40), total = total}
	if captured_total == 0:
		return {banker_won = true, level = 3, total = total}
	if captured_total <= 20:
		return {banker_won = true, level = 2, total = total}
	return {banker_won = true, level = 1, total = total}


## 本局四家收益（规则 10）：庄家胜收 3 份 B×级数；负则付每位闲家 B×级数。收支守恒。
static func compute_payments(outcome: Dictionary, banker_seat: int, base_stake: int, player_count: int) -> Array:
	var payments: Array = []
	for s in player_count:
		payments.append(0)
	var delta: int = base_stake * outcome.level
	if outcome.banker_won:
		# 每位闲家支付庄家 B×级数：庄家净收 3 份
		for s in player_count:
			payments[s] = 3 * delta if s == banker_seat else -delta
	else:
		for s in player_count:
			payments[s] = -3 * delta if s == banker_seat else delta
	return payments
