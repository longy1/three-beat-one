# 更新记录（doc/update.md）

> 本文档是全仓库**代码的行为变更史**，原代码注释中的更新记录类内容（日期戳、变更叙述、
> 新旧行为对照）统一迁入此处。2026-11-18 起为强制规范（doc/coding.md §2，test_architecture
> 机器守护）：**代码注释只描述当前行为与规则出处，禁止日期戳与变更记录**；规则笔误与
> 里程碑级决策仍归《三打哈-Godot工程计划.md》，本文档只收代码注释层的历史注记。
> 条目按日期倒序，新条目置顶；每条注明迁出前所在的文件。

## 2026-11-19

- 卡牌移动端触控调整（用户需求：①花色点数同行改竖排以缩短牌间距；②适当加大牌尺寸，
  兼顾画面与主流移动设备触摸目标）：三档尺寸上调——NORMAL 60×86→72×100、MEDIUM
  50×72→60×86、SMALL 44×64→52×76（iPhone 横屏 letterbox 缩放 ≈0.54 下手牌 ≈39×54pt）；
  角标改竖排（点数上、花色下；王无花色仅单字），`Card` 拆出 `rank_label()`/`suit_label()`
  供角标取值；字号随牌放大（中心 30/22/26→34/26/30、背面哈 32/24/28→36/28/32）；
  连锁同步：信息栏 TrumpSlot 场景 min size 44×64→52×76、出牌区/手牌/揭主飞牌均经
  SIZE_* 常量自动跟随；手牌区布局数学复核（HandRow 高 118px 容纳 NORMAL+BASE_Y，
  27 张扣底阶段最小间距仍可行）——原 core/card.gd、script/table/card_widget.gd、
  script/table/info_sidebar.gd 关联场景 info_sidebar.tscn、
  script/table/trick_history_panel.gd 注记、test/test_components.gd（竖排角标断言）
- iOS 视口看门狗（用户报告：iOS Safari 转屏/回前台后画布偏移黑边——Safari 视口在地址栏
  收合/转屏后分多帧才稳定甚至不触发 resize，Godot 画布按旧视口定格）：export_presets.cfg
  的 html/head_include 追加 iOS UA 门控脚本——orientationchange/visualViewport resize/
  visibilitychange(可见) 触发 scrollTo(0,0) 复位页面偏移并合成 window resize（250/700/
  1500ms 三拍补发），让引擎按稳定后的视口重算画布；仅补发引擎自身监听的事件，无此前
  rAF 垫片的反作用风险；桌面/安卓路径被 UA 门控跳过零影响；产物 grep 验证注入生效——
  原 export_presets.cfg、README.md 移动端节、doc/coding.md §3 ⑥、TODO.md iOS 项
- 居中弹层锚点按场景取（用户报告：房间界面退出时累计分数弹窗歪斜——硬编码桌面十字锚点
  在菜单/大厅场景无意义）：新增 `UiStyle.center_anchor(node)` 统一规则——当前场景为联机
  牌桌（挂 `_net`）用桌面十字中心、非牌桌场景（主菜单/联机菜单/房间大厅）用屏幕正中；
  ScoresDialog/ReconnectOverlay/大厅补电脑确认框三处改走该规则；回归用例补进
  test_ui_online_table（牌桌内=桌面锚点、主菜单下=屏幕正中两断言）——原 script/ui_style.gd、
  script/menu/scores_dialog.gd、script/menu/reconnect_overlay.gd、script/menu/room_lobby.gd、
  doc/coding.md §4、test/test_online.gd
- 换行符统一（用户需求：审查中反复出现换行符修改，保持 AI 写盘与仓库一致）：根因是 Windows
  默认 `core.autocrlf=true`（Git 安装器写入系统级配置）在 checkout 时把仓库 LF 注入成 CRLF
  ——仓库 blob 本就全 LF，工作区却 57 个 CRLF 与 AI 写盘的 LF 混杂；新增 `.gitattributes`
  （`* text=auto eol=lf` 强制 LF；`*.bat -text` 保持仓库原样；otf/png 等显式 binary）+
  本仓库 local `core.autocrlf=false`/`core.eol=lf`（不动全局配置）+ 工作区 55 个文本文件
  CRLF→LF 原地归一（内容零变化仅行尾；bat 保持仓库原样不动；git checkout 类命令对内容
  等价文件不写盘，故用 sed 原地转换）+ `git add --renormalize` 重归一 index 消除假 M——
  原 .gitattributes（新增）、.git/config（local）、55 个工作区文件（仅行尾）
- 大厅选座（用户需求：座位旁加落座按钮，点击挪到那个位置）：协议新增 `sit { seat }`（大厅
  内落座——空位挪入、他人占座互换，成员字典整体对调、昵称/离线态随人走，对局中拒绝）；
  房主座位跟人不跟座（owner_seat 按房主昵称推导，开局/下一局权限校验本就按昵称不受影响）；
  大厅成员行右侧加【落座】按钮（自己所在行不显示、对局中不显示，room_state 广播驱动刷新；
  视觉稿大厅区域同步）——原 net/protocol.gd、server/room_manager.gd（_on_sit）、
  server/host_room.gd（sit/owner_seat）、net/net_client.gd（request_sit）、
  script/menu/room_lobby.gd（_member_row 行改造）、static/ui-mockup.svg、
  test/test_online.gd（test_seat_sit）
- 同昵称快速接管与昵称保留口径（用户需求：断连后凭昵称重建连接，昵称为其保留重连窗口）：
  服务端 `_on_hello` 增加「静默在线成员接管」分支——同昵称 hello 命中在线成员且其 peer
  静默超阈（TAKEOVER_STALE=15s，客户端 5s 心跳 ×3）时释放旧 peer 映射并立即回房，覆盖
  「断连未被扫描判出（半开 TCP 发送不报错）」窗口期内重连首试被「昵称已被占用」阻塞约
  60s 的问题；昵称保留口径明确为「保留窗口 = 重连窗口」（宽限期内随房间保留，重连分支
  先于占用拒绝；房间解散/主动退出或未进房连接静默清理后才释放复用）——原
  server/room_manager.gd（_on_hello/_peer_stale/_release_peer）、net/protocol.gd 注释、
  test/test_online.gd（test_nick_takeover_on_stale）、doc/coding.md §1.12/§5、
  AGENTS.md §6、README.md 联机段

## 2026-11-18

- 联机断线重连闭环（用户需求三项）：①服务端心跳判定阈值 15s→60s（Web 后台标签页暂停
  主循环、心跳停发但连接由浏览器维持，真断连靠探测发送失败即时判定）；掉线成员经旧连接
  发来的任意消息按 pid 匹配离线成员直接复活回房（room_manager._try_revive，无需重新
  hello）；②客户端自动重连：NetClient 掉线（在房间/对局中）不再直接弹窗回菜单，改进
  等待重连弹层（script/menu/reconnect_overlay.gd 新增）+ 3s 定时重试（窗口 150s 与服务端
  宽限对齐），成功依据 hello_ok 新增 rejoined 字段；回前台补发 hello（FOCUS_IN）为 Web
  后台恢复的复活入口；期间 ERR 视为「服务端尚未扫出掉线」留待下轮重试（昵称占用未释放
  的竞态窗口自愈）；服务端离线宽限 120s→180s（用户定夺 3 分钟）、member_offline 附带
  grace 秒数、离线座位回合 5s 快托管（他人不必干等）、回连时在走的回合计时重挂满正常
  时长；牌桌/大厅新增掉线等待与重连提示（member_presence 信号）；③底牌浮层遮挡修复：
  扣底阶段底牌展示 z_index 50→1（只比桌面高一层），出牌历史面板/牌堆弹层显式 z=10
  ——原 server/room_manager.gd、server/host_room.gd、net/protocol.gd、net/net_client.gd、
  script/menu/reconnect_overlay.gd（新增）、script/menu/room_lobby.gd、
  script/table/game_table.gd、script/table/trick_history_panel.gd、script/table/pile_viewer.gd、
  test/test_online.gd（自动重连/复活/快托管三用例；既有 drop 用例经 auto_reconnect=false
  保持旧路径）、test/test_ui.gd（底牌层级回归用例）
- Web 壳清理与主菜单文案：移除导出壳注入的左上角诊断角标 #sbd-diag（墙钟/rAF/分辨率
  统计，CSS 规则、DOM 创建与计数循环整体删除，一并清掉历史遗留的残串行；全屏按钮与
  iOS 提示保留）；主菜单标题「三打一单机版」改「三打一」——原 export_presets.cfg
  （html/head_include）、scene/menu/main_menu.tscn
- 昵称改在线占用制：只与同时在线的玩家互斥（活跃 peer；存活房间成员含离线宽限期经
  重连分支承接），掉线经扫描清理即释放、可随时复用；废除全局永久注册表（store.gd 删
  players 表与 has_player/register_player，载入旧文件即丢弃遗留 players 键；房间留档
  与累计分持久化不变）——原 server/room_manager.gd（_on_hello 拒绝条件）、
  server/store.gd、server/server_main.gd 与 server/host_room.gd 注记、
  scene/menu/online_menu.tscn（标签文案）、test/test_online.gd（存储用例去注册断言、
  昵称用例改在线占用语义并新增掉线释放复用断言）
- 队友无主后垫牌迭代：闲家有主但队友已公示无主时，主牌分（带分主牌）降为可垫档、
  无分大牌主照旧保留（主牌集中在我与庄家手中，小分主守不住）——原 core/ai_play.gd
  垫牌排序新增 mate_void 通道
- 闲家无主垫牌迭代：无主时 5 与无分牌同档尽早甩出（留 5 无赢张价值）；聚焦清一门
  「队友已垫大牌（≥K）且本家无赢张（顶 ≤Q）」的副花色（守门对该门失效）——原
  core/ai_play.gd 两处垫牌断言与甩打轮断言按新基准更新（♥5 不再受无分牌保护）
- 叫分扫荡概率模型（`AiBidding.sweep_prob`）落地：假想定主估「以对/拖抽干闲家主牌」
  概率，上探档 P≥0.30/0.60/0.85 → 165/180/200；特批参与 P≥0.5 且 EV>−2.0；极端
  P≥0.85 无视 EV 放手（探 200 与放宽参与均为用户定夺）。原注记散于
  core/ai_bidding.gd、test/test_ai_policy.gd
- 行为翻转：165/180 档旧版「全负 EV 一律放弃」→ 扫荡概率高的手逐级跟叫（满编四王手
  跟至封顶 200；对手加叫按 Δ=(叫分−130)×0.04 折算常主证据即时压回）。原注记于
  test/test_ai_policy.gd
- 校准复跑验证：出牌层自 83cb294 换表后零改动，4200 局满格复测 24 格差异均在采样噪声
  内 → 基线无漂移，BID_CALIB 维持不动；校准工具样本量 60→200 局/格（详见工程计划
  「校准复跑验证」节）
- 规范建立：代码文件禁更新记录式注释，历史注记迁入本文档（本条即迁出动作本身）
- 文档引用令牌制落地：代码注释引用文档一律用短令牌（[规N]/[码N]/[构N]/[史]/[划N]），
  不再写完整路径——注册表单一事实源在 AGENTS.md §5（代理每次会话自动加载 = 天然解码表），
  `test_doc_tokens_valid` 校验令牌已注册且节号真实存在于目标文档「## N.」标题；原 12 处
  路径式引用迁为令牌（ui_style / trump_rank_picker / hand_area / table_view / store /
  host_room / test_components / test_architecture / ui_test_base / test_ui）

## 2026-11-17

- AI 角色化策略迭代（core/ai_play.gd、test/test_ai_policy.gd）：
  - 闲家提前下分门槛 `_unseen_can_beat`：未现身牌中仍有同型能压过庄家当前牌才下分
    （单张比牌力 / 对子同身份两张更高 / 拖拉机相邻两对更高；副牌轮未现身主牌同型可杀）
  - 庄家扣底平衡细化：保留顶牌最强（平手取更长）且 ≥2 张的副花色整门作赢张引擎，
    分牌随门保留；常主不扣
  - 闲家垫牌守门协调 `_teammate_shed_suits`：队友以垫牌角色累计 ≥2 张的副花色视为
    「在清该门」，本家自由垫牌避开同门
  - 垫牌花色牌力三档分级：顶 ≤10 尽早清理 / 顶 J~Q 中性 / 含 K~A 更多保留；
    分级优先于守门避让与逐张牌力
  - 领出角色化重写 + 增补：7.3 甩牌（三家公示无主甩主牌）、庄家持有花色加成（持续消耗
    其副牌）、无组合时单张试探（确定剩牌领该门最大带分试探 / 不确定领 A/Q 大牌）
  - 甩牌上限（用户定夺：太多看不清）：一次最多 4 张，主牌更多时下一轮继续甩
- 叫分平滑化：EV 校准表只定「愿叫上限档」，实际叫分一律当前最高 +5 逐轮递进（弃跳档）
  （core/ai_bidding.gd）
- 叫分重校准：守门协调 + 牌力分级 + 下分门槛细化出牌策略下 ×2 轮加权定稿 BID_CALIB
  （强牌 130/135/150 = +0.17/+0.15/+0.33，150 档最优；165+ 明确负，愿叫上限档 150）
- 规则 7.3 无主公示/主牌甩打增补（core/follow_rule.gd、core/game.gd、core/trick.gd、
  test/test_follow.gd、test/test_game.gd）：领出者之外三家均无主牌时可一次甩出多张
  主牌单牌，等同连续单张；甩打轮其余三家垫相同张数
- UI（script/table/）：
  - 揭主双飞 `TrumpReveal`：叫主完成瞬间主 R 牌面与皇冠同现中央，牌面飞至信息栏
    主牌位，落位回调才把主牌放进信息栏（此前即时出现无过程）
  - AI 庄家扣底节奏 `AI_DISCARD_DELAY=1.0`：关键决策点多停约 1 秒，太快看不清翻底
  - 皇冠人类落点 `CROWN_HUMAN_TARGET=(0.108,0.749)`：手牌上方按钮行、牌堆按钮右侧，
    不遮挡手牌（原落点遮手牌）
  - 「牌堆」入口移至「历史」右侧同一行（原皇冠下方会遮挡手牌）；`PileViewer` 重做：
    原按座位悬停/钉住的自身历史弹层移除，悬停粘滞 `HIDE_DELAY=0.1s`（用户定夺 0.1s）
  - `SeatPanel` 悬停查看历史路径移除，出牌历史改走 `TrickHistoryPanel`（重做：十字
    摆位一轮四家出牌、翻轮次四按钮、✕/点击窗口外遮罩关闭、状态驱动就地收敛页码）
- 修复/回归（test/test_ui.gd、test/test_components.gd）：
  - `HandArea.render` 剪除陈旧选中引用：「牌不在手中」整局卡死（快速连打/暂停期出牌
    的渲染竞争留下已打出牌的引用，后续提交全被 NOT_IN_HAND 拒绝）
  - `VoidStamp` 用 `top_level` 脱离布局树：曾是 PanelContainer 直接子件被整面填充布局
    拽到左上角压住姓名
  - 底牌入手即选中（人类庄家翻底后 `select_cards(engine.kitty)` 预选）
  - 选牌跨轮保留：`begin_select` 仅模式切换时清空，同模式续轮不清
  - 出牌提交成功后按钮立即隐藏：结算停留期内下一个 `*_required` 处理器 await 挂起，
    旧「出牌」按钮曾挂满整个停留期且可再点

## 2026-11-16

- 规则修订（R=A 特例）：R 为 A 时 A 即常主，同花色的 A 对与 2 对相邻（A~2 连，含副
  花色 AA22 与主花色 AA22 同判合法）；AA22 在其花色的同类拖拉机中排最小（如主牌
  AA22 < 主牌 7788）。原注记于 core/combo.gd、test/test_combo.gd
