class_name NetProto
extends RefCounted
## 联机消息契约（M4）：C/S 消息种类、牌键编解码、座位旋转。
## 消息一律为 JSON 兼容字典（JSON.stringify 往返，不含对象引用）；牌以 Card.key()
## 串数组传输，落地用 Card.from_key 还原等值副本（submit_* 按值匹配契约）。
## 路由约定：客户端→服务器的每条消息携带 pid（发送方 unique_id）——独立
## WebSocketPeer 在服务端不返回真实来源 id，路由信息由协议层携带。
## 可见性纪律（服务端遵守）：他人的手牌、底牌、所扣之牌的牌面永不出现在消息里；
## 扣底广播只发座位与新张数。
##
## 客户端 → 服务器：
##   hello   { nick }                          连接后首条；重连同昵称且房间存活时自动重连回房
##   create  { }                               新建房间（建者为房主，0 号位）
##   join    { code }                          凭房间码加入
##   leave   { }                               主动退出（房间立即结算关闭）
##   start   { fill_ai }                       房主开始对局；人数不满时 fill_ai=true 电脑补位
##   next    { }                               房主开下一局
##   act     { kind, ... }                     人类操作：bid{value} / trump{suit,rank} /
##                                             discard{cards} / play{cards}（仅本人可见的牌）
##   ping    { }                               心跳（服务器回 pong）
##
## 服务器 → 客户端：
##   hello_ok      { nick }
##   room_state    { code, members[{seat,name,is_ai,offline}], owner_seat, status, rejoined }
##   game_start    { round, dealer, my_hand, counts, members, cumulative }   真座位空间，客户端旋转
##   snapshot      { ...game_start 全量公开状态（重连恢复） }                 真座位空间
##   act           { kind, seat, ...载荷, counts, auto? }                    动作回放广播
##                 bid{value} trump{suit,rank} discard{} play{cards,role,dump?} void{}
##                 （discard 不含牌面；void 表示该座位已公示无主，7.3）
##   kitty         { cards }                                                 仅发给出牌庄家（翻底，规则 2）
##   game_over     { result }                                                引擎结算全量（终局底牌公开）
##   scores        { rows[{name,score,games}] }                              房间累计分（按座位序）
##   member_offline { seat, name }                                           成员掉线（宽限期开始）
##   err           { msg }
##   room_closed   { reason, rows }                                          房间解散（附带累计分）
##   pong          { }


const SERVER_ID := 1  ## MultiplayerPeer.TARGET_PEER_SERVER

const HELLO := "hello"
const HELLO_OK := "hello_ok"
const CREATE := "create"
const JOIN := "join"
const LEAVE := "leave"
const START := "start"
const NEXT := "next"
const ACT := "act"
const PING := "ping"
const PONG := "pong"
const ROOM_STATE := "room_state"
const GAME_START := "game_start"
const SNAPSHOT := "snapshot"
const KITTY := "kitty"
const GAME_OVER := "game_over"
const SCORES := "scores"
const MEMBER_OFFLINE := "member_offline"
const ERR := "err"
const ROOM_CLOSED := "room_closed"

## 动作种类（act.kind）
const KIND_BID := "bid"
const KIND_TRUMP := "trump"
const KIND_DISCARD := "discard"
const KIND_PLAY := "play"
const KIND_VOID := "void"

const NICK_MAX_LEN := 12
const AI_NAME_PREFIX := "电脑·"


## 座位旋转：真座位 → 本地座位（本地玩家恒为 0 号位）
static func rot_seat(seat: int, my_seat: int) -> int:
	return (seat - my_seat + 4) % 4


## 座位旋转：本地座位 → 真座位
static func unrot_seat(seat: int, my_seat: int) -> int:
	return (seat + my_seat) % 4


## 按真座位下标的数组 → 按本地座位下标：local[i] = arr[(i + my_seat) % 4]
static func rot_array(arr: Array, my_seat: int) -> Array:
	var out: Array = []
	for i in arr.size():
		out.append(arr[(i + my_seat) % 4])
	return out


## 牌组 → 键串数组（JSON 传输格式）
static func keys_of(cards: Array) -> Array:
	var keys: Array = []
	for c in cards:
		keys.append(c.key())
	return keys


## 键串数组 → 等值副本牌组
static func cards_of(keys: Array) -> Array:
	var cards: Array = []
	for k in keys:
		cards.append(Card.from_key(k))
	return cards


## 昵称合法性（服务器与客户端共用口径）：非空、去首尾空白后 ≤ 12 字、不得用电脑前缀
static func check_nick(nick: String) -> String:
	## 返回错误信息，"" 表示合法
	var trimmed := nick.strip_edges()
	if trimmed.is_empty():
		return "昵称不能为空"
	if trimmed.length() > NICK_MAX_LEN:
		return "昵称最多 %d 个字" % NICK_MAX_LEN
	if trimmed.begins_with(AI_NAME_PREFIX):
		return "昵称不能以「%s」开头" % AI_NAME_PREFIX
	return ""
