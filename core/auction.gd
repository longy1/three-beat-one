class_name Auction
extends RefCounted
## 叫分拍卖（规则 5）：出价校验、轮转与结标。
## 纯逻辑状态模块：GameEngine 持有并委托调用，不依赖引擎与其他模块，
## 联机服务端可直接复用（M4）。


const BID_PASS := -1         ## 放弃标识（永久退出）
const DEALER_BASE_BID := 130 ## 抓牌庄家底叫（规则 5.1）
const BID_CAP := 200         ## 封顶（规则 5.2）


var bids: Array = []  ## 每座位 { value: int, passed: bool }
var turn := -1        ## 当前表态座位


## 开局：抓牌庄家固定 130 底叫（规则 5.1），从其下一位开始表态。返回首个表态座位。
func begin(dealer_seat: int, player_count: int) -> int:
	bids = []
	for s in player_count:
		bids.append({value = 0, passed = false})
	bids[dealer_seat].value = DEALER_BASE_BID
	turn = (dealer_seat + 1) % player_count
	return turn


func has_passed(seat: int) -> bool:
	return bids[seat].passed


func bid_value(seat: int) -> int:
	return bids[seat].value


func highest_bid() -> int:
	var highest := 0
	for b in bids:
		highest = maxi(highest, b.value)
	return highest


## value = BID_PASS 表示放弃（永久退出，规则 5.3）；否则须为高于当前最高、
## 5 的倍数、≤ 封顶。非法表态返回判定字典且不改变状态。
func submit(seat: int, value: int) -> Dictionary:
	if seat != turn:
		return _err("未轮到座位 %d" % seat)
	if value == BID_PASS:
		bids[seat].passed = true
	else:
		var highest := highest_bid()
		if bids[seat].passed:
			return _err("已放弃，不能再叫")
		if highest >= BID_CAP:
			return _err("当前叫分已封顶，只能放弃")
		if value <= highest:
			return _err("叫分须高于当前最高 %d" % highest)
		if value % 5 != 0:
			return _err("叫分须为 5 的倍数")
		if value > BID_CAP:
			return _err("叫分封顶 %d" % BID_CAP)
		bids[seat].value = value
	return {ok = true, error = ""}


## 推进到下一位未放弃者。返回其座位号。
func advance(player_count: int) -> int:
	for i in player_count:
		turn = (turn + 1) % player_count
		if not bids[turn].passed:
			return turn
	return turn


## 拍卖结束（规则 5.4）：至多一名未放弃者
func is_complete() -> bool:
	var active := 0
	for b in bids:
		if not b.passed:
			active += 1
	return active <= 1


## 结标：唯一未放弃者为出牌庄家（规则 5.4/5.5）
func winner_seat() -> int:
	for s in bids.size():
		if not bids[s].passed:
			return s
	return -1


func _err(message: String) -> Dictionary:
	return {ok = false, error = message}
