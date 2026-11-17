# 三打哈（三打一）项目规范

> 本文档是本仓库的开发规范与协作约定。**随实现演进及时更新**——任何行为、结构、流程变更后，须同步修订对应章节。
> 规则依据：[doc/三打哈规则.md](./doc/三打哈规则.md)（唯一规则依据）；里程碑与技术决策：[doc/三打哈-Godot工程计划.md](./doc/三打哈-Godot工程计划.md)；**重构类任务执行 [doc/重构规范.md](./doc/重构规范.md)**（兜底代码根治协议、模块拆分原则、HTML 导出验收工作流、C/S 预留约定）。

## 1. 项目概述

湘西扑克**三打哈（三打一）**的 Godot 单机版：1 名人类玩家（甲，座位 0，牌桌下方）对 3 名电脑玩家（乙/丙/丁）。

- **已完成**：M1 规则引擎（牌/牌型/跟杀垫/一轮结算）、M2 单机完整对局（拍卖→叫主→翻底扣底→逐轮出牌→抠底→分级收益→庄位轮换）+ 贪心 AI + 牌桌 UI；2026-11-16 完成全项目重构（死代码清理、兜底根治、core/UI 模块拆分、Web 导出与浏览器验收工作流）；2026-11-17 Web 验收闭环（根治静态 preload 致导出脚本失效）+ 规则 7.3（无主公示/主牌甩打）+ 交互改进（底牌入手即选中、选牌跨轮保留、主牌副花色分组排序）；2026-11-18 完成 M4 联机对战（C/S 架构：无头 Godot 服务器 + WebSocket + 可见性裁剪同步 + 超时托管 + 断线重连，见 §4.10~12）
- **待启动**：M3 AI 强化与胜率分析（蒙特卡洛）、M5 部署上线（联机服务器公网部署）

## 2. 技术栈与环境

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2** stable（编辑器位于 `S:\Program\Godot\`，用户级环境变量 `GODOT_PATH` 已指向主程序） |
| 语言 | GDScript（无 C#）；渲染 gl_compatibility（兼容桌面/移动/Web） |
| 依赖 | 无第三方插件、无外部美术素材（全部程序化绘制）；**唯一例外：字体**——中文 UI 打包 Noto Sans SC 子集（OFL，Web 无系统字体回退所必需）；**联机存储**：本地 JSON 文件（`user://sanhax_server/store.json`，无第三方依赖，接口形状预留 SQLite 平替） |
| 测试 | 自研轻量框架（`test/test_framework.gd`），headless 运行 |

常用命令（在本仓库根目录执行）：

```bash
# 单元/规则测试（全部通过退出码 0；当前 13 套件 130 用例，含联机回环套件）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s test/run_tests.gd

# UI 冒烟（headless 自动打完一整局，约 1 分钟，退出码 0）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s test/smoke_ui.gd

# 导入校验（改了脚本/场景后先跑）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# 打开游戏窗口
S:/Program/Godot/Godot_v4.7.2-stable_win64.exe --path .

# 启动联机服务器（M4，无头进程；端口默认 9080，可 --port 覆盖；或双击根目录「启动联机服务器.bat」）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://server/server_main.tscn

# 导出 Web 版（视觉验收用；完整流程见 doc/重构规范.md 第 6 章）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web"

# 本地静态服务（导出后浏览器打开 http://127.0.0.1:8765 验收）
cd build/web && python -m http.server 8765
```

**每次改动后的验证顺序**：`--import`（无脚本错误）→ `run_tests.gd`（全绿）→ `smoke_ui.gd`（若动了 UI/引擎流程）→ **Web 导出 + 浏览器截图验收**（若动了视觉/布局/字体）。

## 3. 目录结构

```
core/     纯逻辑层（禁止任何 Node/场景/时序/IO 依赖；test_architecture.gd 机器守护）
  card.gd          Card：牌表示、84 张牌堆、分牌分值、值身份键 key()（规则 1、8.1）
  trump.gd         TrumpInfo：主花色+常主 R；3.1 牌力全序；常主脱离花色（3.3）
  combo.gd         Combo：单/对/拖拉机识别、6.2 邻接链、6.3 比较与四王特例
  follow_rule.gd   FollowRule：7.2 跟/杀/垫判定（含两处强制项）；着法枚举；对子公共口径
  trick.gd         Trick：一轮结算（出入参键名 seat，与 current_plays 同构；支持部分结算 B.2）
  auction.gd       Auction：叫分拍卖子状态机（规则 5：校验/轮转/结标，bids/turn 归其所有）
  scoring.gd       Scoring：分级与收益纯函数（规则 9/10：compute_outcome/compute_payments）
  game.gd          GameEngine：对局状态机编排（委托 Auction/Scoring；submit_* 唯一变更入口）
  ai_bidding.gd    AiBidding：叫分纯策略（强度评分 + EV 校准表；数据进/决策出）
  ai_play.gd       AiPlay：叫主/扣底/出牌纯策略（贪心启发式；数据进/决策出）
  ai_policy.gd     AiPolicy：AI 门面（共享 rng + 引擎状态解包；单机适配层，M4 服务端绕过）
net/      联机客户端层（进 Web 导出包；协议/连接/视图，全部与具体 UI 解耦）
  protocol.gd      NetProto：消息契约（种类常量、牌键编解码、座位旋转 rot/unrot、昵称校验）
  net_client.gd    NetClient：WebSocket 连接/心跳/重连、房间状态缓存、场景路由、
                   挂 tree.root（名 "NetClient"）跨场景存活；测试钩子 standalone/debug_record
  table_view.gd    TableView：可见性裁剪的对局视图状态——信号/查询面与 GameEngine 同构，
                   竞叫用真实 Auction、结算用真实 Trick.settle（公开数据同源）；
                   只持有本人手牌 + 公开回放，隐藏信息不可推导（§4.10）
script/   表现层脚本
  game_table.gd    牌桌控制器（编排：引擎接线/信号处理/刷新/提交门面，~540 行）
  hand_area.gd     HandArea：手牌区（分区渲染/排序/点选拖选右键/精准刷新）
  pile_viewer.gd   PileViewer：牌堆查看器（历史/牌堆按钮 + 底牌悬停弹层 + 延迟隐藏）
  trick_history_panel.gd  TrickHistoryPanel：出牌历史面板（十字摆位一轮四家 + 翻轮次 + 遮罩关闭）
  action_bar.gd    ActionBar：操作按钮条（按钮生命周期唯一所有者）
  trump_rank_picker.gd  TrumpRankPicker：叫主点数居中面板（rank_picked 信号）
  crown_animator.gd     CrownAnimator：皇冠庄家标记动画
  trump_reveal.gd  TrumpReveal：揭主双飞动画（主 R 牌中央出现并飞入信息栏主牌位）
  card_widget.gd   CardWidget：程序化卡牌控件
  crown_badge.gd   CrownBadge：程序化皇冠
  void_stamp.gd   VoidStamp：【无主】圆形红印章（规则 7.3 公示，程序化绘制）
  dashed_frame.gd  DashedRoundedFrame：手牌分区圆角虚线框
  seat_panel.gd    SeatPanel：座位面板组件（crown_anchor 落点测量封装）
  info_sidebar.gd  InfoSidebar：右侧信息栏组件
  ui_style.gd      UiStyle：UI 规范工具（MAIN_TABLE_CENTER 常量、半字号留空）
  main_menu.gd     主菜单（自检动态加载套件；Web 下隐藏退出/自检）
  online_menu.gd   联机入口（昵称/地址/建房/凭码加入；昵称 ConfigFile 记忆）
  room_lobby.gd    房间大厅（房间码/成员列表/开局/退出；人数不满补电脑确认弹层）
  scores_dialog.gd ScoresDialog：房间累计分数弹层（退出/掉线/关房时展示，确定→主菜单）
scene/    main_menu.tscn / online_menu.tscn / room_lobby.tscn / game_table.tscn / seat_panel.tscn / info_sidebar.tscn
server/   联机服务端（仅桌面源码运行，**已从 Web 导出排除**；不设 class_name，动态 load 装配）
  server_main.tscn/.gd  入口场景（无头进程：监听端口/装配 manager+store/--port 用户参数）
  room_manager.gd  连接中枢：peer↔昵称、房间表、消息分发、掉线扫描（探测 ping + 心跳超时）
  host_room.gd     单房间权威 GameEngine + AI 定时驱动（绕门面直调纯模块）+ 超时托管 +
                   离线宽限/重连快照 + 动作广播（可见性裁剪）+ 结算入库
  store.gd         持久存储：本地 JSON（players 昵称注册表 / rooms 留档 / room_scores 房间累计分），
                   变更即原子落盘；接口形状对齐后续 SQLite 平替
font/     NotoSansSC-Regular.subset.otf（中文子集 ~230KB；重生成走 tool/subset_font.py）
theme/    default.tres（项目默认字体主题，project.godot gui/theme/custom 引用）
tool/     subset_font.py（字体子集化脚本；文案新增字符后重跑）
test/     test_framework.gd + test_base.gd/ui_test_base.gd（共享基类）+ suite_registry.gd（套件注册单一事实源）
          + test_*.gd（13 套件 130 用例，含 test_architecture.gd 架构守护、test_online.gd 联机回环）+ run_tests.gd + smoke_ui.gd
          + calibrate_bidding.gd（叫分校准工具，独立 -s 入口）
doc/      三打哈规则.md（唯一规则依据）、三打哈-Godot工程计划.md、重构规范.md
static/   ui-mockup.svg（界面区域图视觉稿，布局变更须同步更新；含 .gdignore 不参与引擎导入）
build/    导出产物（不入库；_font_src/ 为字体源本地缓存；导出模板在编辑器安装目录 S:\Program\Godot\editor_data\export_templates\，self-contained 模式由 exe 旁 ._sc_ 标记启用）
```

`.uid` 文件由 Godot 生成，**必须与对应 `.gd`/`.tscn` 一同提交**；`.godot/`、`.zcode/`、`build/` 已忽略；`export_presets.cfg` **入库**。

**命名规范：目录名一律用单数**（core / doc / font / scene / script / static / test / theme / tool），不用复数；新增目录同样遵守。静态设计资产放 static/（含 .gdignore，不参与引擎导入）。

## 4. 架构规范

1. **纯逻辑与表现严格分离**：`core/` 内的类只依赖彼此与 `RefCounted`，不引用 Node/SceneTree/IO/时间。由 `test/test_architecture.gd` 机器守护（禁用依赖清单扫描）；联机阶段服务端可直接复用 `core/`。
2. **引擎不信任调用方**：`GameEngine` 所有 `submit_*` 方法自行校验（阶段、座位轮次、合法性、底牌可见性），非法操作返回判定字典且不改变状态。UI/AI 永远不绕过校验。**submit_\* 是唯一状态变更入口**，公开查询方法走白名单（`test_engine_public_api_is_submit_only` 守护）。
3. **提交按值匹配**：`Card.key()`（花色+点数+副号）在两副牌内唯一，UI/AI/联机消息可传等值副本，无须持有引擎内对象引用——这是网络消息可直接映射为 submit 调用的契约基础（M4）。
4. **信号驱动 UI，单一刷新入口**：引擎信号（`*_required/trick_settled/game_over/phase_changed/engine_fault`）→ `game_table.gd` 处理器 → `_refresh()`（唯一刷新入口）。**禁止**新增定时轮询式「兜底同步」；信号完整性由 test_ui 自动对局「UI==引擎」不变量守护。按钮界面只由 `*_required` 处理器重建（`ActionBar.reset()` 幂等清理），submit 方法原则上不做清理；**唯一例外（2026-11-17）**：`_submit_human_play` 成功后立即 reset——出牌后常伴结算停留，期间下一个 `*_required` 处理器在 await 挂起、不会同步重建，旧「出牌」按钮会挂满停留期且可再点；安全性依据：人类出牌的下一手必为 AI 或进结算，重建都发生在挂起恢复之后，清理不会误删新按钮（其余 submit 的下一个处理器为同步重建，那里清理仍会竞态误删——禁止效仿）。
5. **状态归一所有**：bids/turn 归 `Auction`；选中态归 `HandArea`；按钮归 `ActionBar`；皇冠归 `CrownAnimator`。派生状态用访问器（`get_last_trick()` 由 trick_history 末元素派生），不存镜像字段。**信号发出前状态必须完全就绪**（`_begin_game` 先 `auction.begin` 再 `_set_phase` 的教训）。
6. **规则出处可追溯**：`core/` 注释标注规则文档章节号；改动规则实现必须先核对规则文档，笔误登记到《三打哈-Godot工程计划.md》"M1 实施记录"。
7. **AI 数据进/决策出**：`AiBidding/AiPlay` 只收数据参数（随机源注入），不持有引擎引用；`AiPolicy` 是单机门面（解包引擎状态）。M4 服务端绕过门面直调纯模块。
8. **显性报障**：引擎内部一致性破坏走 `engine_fault` 信号 + `faulted` 标记 + `push_error`（如 settle 失败），禁止静默哨兵值（seat=-1）死锁。
9. **多局会话**：`start_session(seed)` 种子化发牌；`start_session_with_deal()` 为测试钩子（注入手牌+底牌，按值匹配可传副本）；庄位轮换规则 4 在 `start_next_game()` 内实现。
10. **联机 C/S（M4 落地，2026-11-18）**：服务端（`server/`，无头 Godot 进程）权威运行 GameEngine 并直调 AiBidding/AiPlay 纯模块（数据进/决策出）；客户端**不跑引擎**——`net/table_view.gd` 以可见性裁剪的视图状态 + 与引擎同构的信号/查询面驱动 game_table（重构规范 §7.3 预留形态的落地）。服务器只下发本人手牌（庄家另加翻底底牌）与公开回放（叫分/亮牌/轮次/捉分/无主公示/终局结算）；**他人手牌、所扣牌面永不出现在广播里**（扣底广播只发座位与新张数），动作回放附带权威 `counts` 张数。座位旋转 `rot(s)=(s-my+4)%4` 在 NetClient 摄取层对 game_start/snapshot 统一完成——本地玩家恒为 0 号位，game_table 的 HUMAN_SEAT=0 语义零改动。
11. **联机路由**：独立 `WebSocketMultiplayerPeer` + JSON 文本包（不挂高层 multiplayer API，避免跨进程节点路径耦合）；**每条客户端消息自带 `pid`（unique_id）**——服务端 `get_packet_peer()` 实测不返回真实来源 id（恒 1），路由信息由协议层携带（`net/protocol.gd` 契约，踩坑记录）。传输可靠有序 = 回放无需额外排序；客户端 5s 心跳，服务端 15s 无消息或探测发送失败判离线。
12. **联机托管与宽限**：人类回合超时（叫分 20s/叫主 30s/扣底 60s/出牌 30s）由 AI 纯模块按其手牌代打并以 `auto=true` 广播（客户端 toast「超时托管」），人类出招即重置计时；掉线成员进入**离线宽限期**（120s，回合由托管代打、对局继续），宽限内同昵称 hello 重连并收**公开状态快照**恢复视图，逾期按退出关房；**主动 leave 立即关房**并广播累计分（各端弹分数窗→确定→主菜单）。

## 5. GDScript 编码规范（本仓库实践）

- **类型推断陷阱**：`Dictionary`/无类型 `Array` 取值、引擎信号携带的 Variant **不能用 `:=` 推断**，必须显式标注（`var x: int = dict.field`；`var k: String = c.key()`）。历史 bug 多源于此，code review 重点。**联机（2026-11-18）**：game_table 的 `engine` 放宽为非类型化变量（单机 GameEngine / 联机 TableView 鸭子类型）后，所有 `:= engine.xxx` 失去推断来源——已全部显式标注；给持有 Variant 的字段新增读取时同样注意。
- **不覆盖 `Object.to_string()`**（Godot 视为警告级错误）：Card/Combo 用 `label()`。
- 方法调用带括号：`c.points()` 而非 `c.points`（后者得到 Callable，运算时报错）。
- 数组推导式内不要嵌套 `%` 格式化等复杂表达式（解析器不支持），改用显式循环。
- 常量数组/实例：`const` 不能含 `Card.new()` 调用，用实例变量。
- 静态工厂优先：`CardWidget.create()`、`Combo.detect()` 等静态构造；策略函数全部 `static`（AiPolicy 门面共享 `static var rng`，`_static_init` 中 randomize）。
- 注释与文档字符串用中文，函数头 `##` 说明职责与规则依据。
- 命名：类名 PascalName；私有成员 `_` 前缀；信号回调 `_on_<signal>`。
- 跨组件共用常量放单一事实源（如 `UiStyle.MAIN_TABLE_CENTER`），禁止两份「应该相等」的数字。

## 6. Godot 最佳实践（本仓库清单，检查与沉淀自 2026-11-16 重构）

**工程配置**
- `project.godot` 用编辑器/直接编辑均可，但须保持分区有序（application/display/gui/rendering）；新增系统级设置（字体主题等）登记在本文件 §2/§3。
- `export_presets.cfg` 入库；导出过滤排除非运行时目录（`test/*,doc/*,tool/*,build/*,server/*`，2026-11-18 增 server/——服务端仅桌面源码运行且引用面与客户端隔离）；`net/` 必须进包（Web 客户端联网）；`build/` 忽略。
- `html/head_include` 注入移动端壳层适配（2026-11-17）：`canvas#canvas{touch-action:none}` 与 `html,body{position:fixed}`（iOS 忽略 overflow:hidden，页面微滚动会吞点按）；右上角 ⛶ 全屏按钮（DOM 覆盖层，非 Godot 控件）——iPhone Safari 无 Element Fullscreen API，点击时降级提示「添加到主屏幕」全屏方案。改此项后须 `--export-release` 并浏览器验证按钮与画布注入。
- `html/experimental_virtual_keyboard=true`（2026-11-18 联机昵称输入）：触屏 UA 下 LineEdit 聚焦弹系统键盘；桌面浏览器走物理键盘直接输入。
- **Godot Web 对合成输入免疫（2026-11-18 验收实测）**：自动化注入的合成 KeyboardEvent/ClipboardEvent/CDP 文本均不进引擎（仅受信任的真实输入生效）——浏览器验收能覆盖引导/渲染/按钮路径，**文本输入类流程须真实键盘**（桌面双实例人工步骤）。
- `.gitignore` 只忽略生成物（`.godot/`、`build/`）；`.uid` 与源文件成对提交。

**场景结构**
- 组件自带统一尺寸（`custom_minimum_size`），实例只锚定位置不拉伸（SeatPanel 模式）；「组件一处改、实例全部生效」。
- 居中展示组件一律点锚 `UiStyle.MAIN_TABLE_CENTER` + `grow BOTH`（TrumpRankPicker/PileViewer 弹层/ResultPanel 均如此），禁止四角拉伸锚点承载弹层。
- 节点语义命名，禁止编辑器自动编号名（如曾经的 MenuButton2）残留。
- 可编辑结构优先落 tscn；纯动态内容程序化构建——两者边界：容器/槽位在场景，内容在脚本。

**脚本**
- 节点引用统一 `@onready var x := $Path`（禁止散落的 `get_node`/`$` 长路径重复出现在方法体内）。
- **组件封装不穿透**：外部不 `get_node` 进组件内部结构，为用途补公开 API（如 `SeatPanel.crown_anchor()`）；组件内部路径仅测试断言可用。
- 单一事实源：套件注册 `test/suite_registry.gd`（run_tests 与主菜单自检共用）；布局锚点 `UiStyle`。
- 开发期专属功能（自检）用运行时 `load()` 而非静态 `preload`，避免拖进导出包。**更强约束（2026-11-17 Web 实测踩坑）**：任何对被导出过滤排除文件（如 `test/*`）的静态 `preload`会让**整份脚本**在导出环境解析失败——`_ready` 不执行、按钮全部失去处理器且无任何运行报错线索；此类引用必须全部走运行时 `load()`，并在 `--export-release` 后用浏览器验收确认。
- **Web 特性守卫**：`OS.has_feature("web")` 分支处理平台差异（quit 无效、test 未打包）；新增平台敏感 API 前先查该守卫。
- `_ready` 只做接线与轻构建；重构建走组件 `_ready` 分摊；首帧依赖布局的渲染挂起到尺寸有效（HandArea 模式），禁止兜底默认尺寸。
- 信号连接用 `.connect()` 方法引用/lambda，风格保持统一；信号发出前状态就绪（§4.5）。**陷阱（2026-11-17 实测）**：lambda 内 `func(): x.start` 是求值出 Callable 后丢弃（仅 STANDALONE_EXPRESSION 警告，不报错），方法从未被调用——连接回调方法直接用裸 Callable（`connect(x.start)`），lambda 内必须带括号调用。
- **ScrollContainer 最小尺寸为 0**：放入自适应容器（VBox/PanelContainer）会整层塌缩，内容全部裁剪不可见——弹层滚动区必须按内容行数设置 `custom_minimum_size`（PileViewer 历史弹层 2026-11-17 回归）。
- **复用 Timer 的回调单槽化（2026-11-18 联机踩坑）**：one_shot Timer 复用做调度器时，`timeout.connect(action)` 每次调度都会叠加连接——改为单槽「待执行 Callable + 固定回调」（`_pending_ai` 模式）；同理，测试里对**多发信号**（如 remote_action）挂 `CONNECT_ONE_SHOT` 会被首个无关发射消费掉。
- **跨场景存活组件**：需要跨 `change_scene_to_file` 存活的状态挂 `tree.root` 直属节点（联机 `NetClient`，名字固定便于 `get_node_or_null` 定位），自毁走 `queue_free.call_deferred()`；本项目维持零 autoload。

**资源与字体**
- 中文显示依赖打包字体（浏览器无系统回退）：文案新增字符后**必须重跑 `python -I tool/subset_font.py`** 再导出，否则豆腐块。
- 字体走主题资源（`theme/default.tres` + `gui/theme/custom`），不在各控件逐个 override 字体。
- 新增控件一律程序化绘制（参照 CardWidget/CrownBadge/DashedRoundedFrame），不引入图片素材。

## 7. UI 布局规范

- **固定优先原则（2026-11-16 确立）**：桌面区域、手牌区先固定；操作按钮/提示等临时 UI 在**各自的固定槽位**内显隐（悬浮式），**禁止用可变高度容器（VBox 堆叠）承载会增减的行**——历史上按钮出现曾推挤手牌跳动。
- **相对长度原则**：节点定位用 0~1 比例 anchors（勿写死像素）；动态出牌/动画位置用相对常量（`TRICK_ANCHORS`/`CrownAnimator.CROWN_HUMAN_TARGET` 为 0~1 Vector2，渲染时 ×层尺寸）。卡牌等控件以 720p 设计分辨率定义基准尺寸，`canvas_items` 拉伸模式保证任意窗口整体等比缩放。
- **两大区域（2026-11-16 确立）**：画面分为**主牌桌区域**（x 0~82.8%）与**侧信息板区域**（82.8%~100%，InfoSidebar）。区域名称标注于视觉稿。
- **居中规范（2026-11-16 确立）**：所有居中展示组件（弹层/面板/皇冠出现点）统一锚定**主牌桌十字中心** `UiStyle.MAIN_TABLE_CENTER`=(0.419, 0.408)——左右对齐丙面板中轴、上下对齐乙/丁面板中轴；实现为点锚 + grow BOTH（尺寸随内容向四周自适应），禁止固定 offsets 尺寸（内容不满时视觉偏置）。翻底阶段的中央「底牌（仅你可见）」面板（2026-11-17 起程序化 PanelContainer）同属此列。
- **半字号留空原则（2026-11-16 确立）**：所有文字与其最近的边框（面板边、按钮边）四向留空 **≥ 字号的一半**。落实方式：按钮统一走 `UiStyle.pad_button()`（content margin = 字号/2）；面板在 tscn 中用 StyleBoxFlat `content_margin_*` 落实（InfoSidebar 8 / SeatPanel 9 / ResultPanel 15，≈ 各自最大字号的一半）。豁免：无边框裸文字（Toast/提示行/顶栏标签）、卡牌角标（扑克角标贴角为惯例设计）。
- **组件复用**：三家电庄信息框复用 `SeatPanel`；右侧信息栏 `InfoSidebar`；手牌区 `HandArea`；牌堆弹层 `PileViewer`；操作按钮 `ActionBar`——实例只锚定/挂载，不各自拉伸改尺寸。
- **对称十字出牌位**：四家出牌围绕牌桌中心对称——你=下方（0.419,0.55）、丙=信息板正下方（0.419,0.28）、丁=面板右侧（0.234,0.408）、乙=面板左侧（0.604,0.408）。
- 设计分辨率 1280×720（stretch canvas_items / keep），统一 12px 边距；桌面窗口默认 1920×1080（`window/size/window_*_override`，内容仍按 720p 基准等比放大 1.5×，控件像素常量不随窗口变大——2026-11-17 用户设定）。
- 区域划分见 [static/ui-mockup.svg](./static/ui-mockup.svg)（布局改动先改视觉稿再施工）：
  - 顶栏（局数/出牌庄/叫分）；**抓牌庄家不展示**
  - 叫主点数选择：居中多排面板（2 排 × 6，TrumpRankPicker），10 个点数按钮完整展示（R ∈ 5~2，不可为王）
  - 叫分提示显示在主牌桌正中央（BidCenterLabel，「叫分中（最高 X）」）；**不用「拍卖」一词**（非本土打牌用语）
  - 丙上带居中牌桌区；丁面板贴左缘；乙面板贴牌桌右缘（与丁关于牌桌中心对称）
  - 右侧信息栏（InfoSidebar）：**主牌提示 = 一张「正 R」牌面**；**未叫主态**：牌背微透明 + 居中问号 + 下方注明「未叫主」；另有手牌统计 + 局面（捉分/累计）+ 主菜单按钮；下半为 M3 预留
  - 底部固定槽位：按钮 / 提示 / 手牌（双虚线框：左主牌右副牌，区内从大到小；叫主前王与 2 进左框；主牌区内牌力并列的副R/副2 按 ♠→♥→♣→♦ 同花色相邻分组，2026-11-17）
  - 牌堆按钮左下（悬停查看出牌历史，旧→新）
- **手牌交互**：选中的牌**上浮牌高的 20%**（`HandArea.SELECT_LIFT_RATIO`）；左键按住滑动可**批量选择相邻牌**（以首张的新态对齐滑过的牌）；出牌模式下**右键直接提交出牌**（`play_requested` 信号，引擎校验非法 toast）。选中态刷新走 `HandArea._widgets` 精准更新单张，禁止整排重建（闪烁/抖动）。**选牌跨轮保留（2026-11-17）**：同模式连续轮次不清空选择（`begin_select` 仅模式切换时清），且 `render` 以当前权威手牌为准自动剪除 selected 中已不在手牌的陈旧引用（快速连打的渲染竞争曾留下已打出牌的引用致整局「牌不在手中」卡死）——陈旧选中不允许跨渲染存活；提交成功后 `consume_selected` 只移除已打出的牌；**底牌入手即选中**：人类庄家翻底后 `select_cards(engine.kitty)` 预选 8 张（拿起态，便于观察与直接扣回）。
- 庄家标记 = 皇冠动画（`CrownAnimator`）：拍卖结束从主牌桌区域正中央 ×4 出现，`TRANS_CUBIC EASE_OUT` 1s 飞至庄家名字旁停驻——落点动态测量（`SeatPanel.crown_anchor()`：名字首字左缘前 4px、冠高 = NameLabel 字号）；人类 0 号位落**手牌上方按钮行**（历史/牌堆按钮右侧 (0.108,0.749)，2026-11-17 起，不再遮挡手牌）。新局拍卖开始时清除（皇冠与揭主牌面均 clear）。面板不用「·抓牌/·庄」文字。**揭主双飞（2026-11-17）**：叫主完成的同一时刻，主 R 牌面（`TrumpReveal`，中央 ×2.2）与皇冠同现于主牌桌中央并同步减速飞行——牌面落点为信息栏主牌展示位（`InfoSidebar.trump_slot_center()`），落位回调才把主牌放进信息栏（期间 `_refresh` 经 `_last_trump_shown` 先行标记跳过即时刷新）。
- **【无主】印章（规则 7.3，2026-11-17）**：主牌轮垫牌公示——`VoidStamp` 圆形红章（斜置半透明红、程序化绘制）：乙/丙/丁盖在 SeatPanel 右下角（`set_void_trump`；印章 `top_level=true` 脱离容器布局树用全局坐标定位——PanelContainer 会对直接子件整面填充布局，曾把印章拽到左上角压住姓名）；人类 0 号位盖在**手牌区右上方固定槽位**（HumanVoidStamp，tscn 锚点 (958,488)，2026-11-17 调整）。
- **左下按钮区（不随牌变动）**：【历史】= 点击打开**出牌历史面板**（`TrickHistoryPanel`，2026-11-17 重做）：居中弹层以**十字形**展示一轮四家出牌（与牌桌出牌摆位座位方位同构、窗口更小，赢家 ✓ 金标），默认**最后一轮**；中央下方 【<<】【<】【>】【>>】 四按钮翻第一页/上一页/下一页/最后一轮（边界禁用）；右上角 ✕ 或**点击窗口外**（全屏微暗遮罩，`MOUSE_FILTER_STOP` 透明拦截）关闭；打开期间新轮结算由 `trick_settled → _refresh → refresh` 状态驱动就地收敛页码；【牌堆】= 仅庄家是自己且进入出牌阶段后显示（「历史」右侧同一行），悬停弹出**底牌堆 2 行 × 4 张**（`engine.buried`，仅自己可见；弹层归 `PileViewer`）。**悬停弹层机制（2026-11-17 历史面板重做后仅剩【牌堆】按钮悬停路径；座位面板悬停路径已移除）**：事件驱动 + 粘滞——显示随 `mouse_entered` 一次调用，隐藏靠 0.1s 延迟计时器（粘滞时长 2026-11-17 用户定夺为 0.1s；弹层悬停仍保持打开，重悬停即可再次查看），**不用周期轮询**（`mouse_entered/exited` 本就是引擎逐帧悬停判定的结果，自建轮询属 §4 禁止的定时兜底）。
- 一轮结算后牌面（含 ✓赢家）停留 **1.5 秒后主动清空出牌桌**（TRICK_PAUSE 由 `_trick_timer.timeout` 统一触发清空，不依赖下一手替换）；末轮停留后才弹结算面板。
- **联机界面（2026-11-18，M4）**：主菜单新增【联机对战】→ `scene/online_menu.tscn`（昵称/服务器地址默认 ws://127.0.0.1:9080/新建房间/房间码+加入/返回；状态行报错；昵称 ConfigFile 记忆）→ `scene/room_lobby.tscn`（房间码大字、四座位成员列表——房主/你/电脑/离线标注、开始游戏仅房主可见、退出房间）。**人数不满开局流程**：房主点开始 → 居中确认弹层「人数不满（X/4），是否自动补充电脑玩家？」——是 → `start{fill_ai:true}` 补满即开；否 → 仅关闭弹层留在房间页；满 4 人直接开。**累计分数弹层** `script/scores_dialog.gd`（MAIN_TABLE_CENTER 居中 + 全屏遮罩）：主动退出（本地立即弹）、他人退出/离线超时/服务器失联（`room_closed`/`connection_lost` 数据弹出），确定 → 主菜单。牌桌联机态复用单机布局：座位名 = 成员昵称（本地座位序，0 号位带（你）），AI 补位名「电脑·乙/丙/丁」；结算面板【下一局】仅房主可见（其余等待）。布局注记见 static/ui-mockup.svg 联机屏。
- 新增控件一律程序化绘制（参照 CardWidget/CrownBadge/DashedRoundedFrame），不引入图片素材。

## 8. 测试规范

- 新增/修改规则行为**必须带用例**；规则类改动对照规则文档章节写正反例。
- 套件注册**只改 `test/suite_registry.gd` 一处**（run_tests 与主菜单自检共用；主菜单运行时动态加载）。
- 共享基类：`test/test_base.gd`（C() 造牌 / trump 基准 / Phase 别名）、`test/ui_test_base.gd`（_spawn_table 三件套 / tree_pause）——新套件 `extends TestBase` 或 `extends UiTestBase`，勿再复制助手。
- **架构守护（test_architecture.gd）**：core 纯度（禁 Node/场景/时序/IO 依赖清单扫描）、AI 模块不引用引擎类型、submit_* 唯一写入口白名单——规范固化为可执行检查，违规即红。
- AI 改动用两类测试守护：单项策略断言 + **30 局种子化自动对局不变量**（零非法着法、每局完整结束、捉分 ≤200+底牌分、收支守恒、Scoring.compute_outcome 互检）。
- 特定规则路径优先用**注入迷你局剧本**（`start_session_with_deal`，如抠底 ×1/×2/庄赢不抠三剧本），不要写脆弱的整局剧本。规则 7.3（无主公示/主牌甩打）同样由迷你剧本确定性覆盖（甩打结算/条件拒绝/跟牌张数/末轮甩打抠底 ×1/公示触发与不触发六类）。
- 叫分等概率策略的断言用固定 `AiPolicy.rng.seed` 的确定性断言（EV 档位断言）。
- **平衡校准工具**：`test/calibrate_bidding.gd`（独立 -s 入口，不注册套件）——蒙特卡洛模拟「固定叫分 × 强度桶」统计胜率/期望收益，用于重训 `AiBidding.BID_CALIB` 查表；AI 策略或对手水平变化后建议重跑校准。
- **校准的边界**：校准表测的是「当前出牌策略水平」的条件期望，不是牌力理论上限——出牌策略迭代后必须重跑校准。

### UI 用例维护（test/test_ui.gd）

UI 层曾因无用例而集中出 bug（信号时序竞态、引用遗漏、渲染丢弃）。UI 用例模式已固化：

1. **headless 实例化场景**：`_spawn_table()` 加载 game_table 场景、等两帧布局、把 `_ai_timer/_trick_timer` 调快（免等待真实节奏）。
2. **方法级驱动**：不模拟鼠标——直接调用控制器方法（如 `_submit_human_trump()`）或引擎 API，触发与真实点击相同的信号链。控制器门面触点：`hand_area.selected/select_mode`、`_piles.*`、`_trump_picker`。
3. **节点状态断言**：断言按钮存在/可见、Label 文本、popup 标题等真实 UI 状态；计数类断言须跳过 `is_queued_for_deletion()` 节点（queue_free 帧末才删）。
4. **一致性不变量**：自动对局每步断言「UI 显示 == 引擎数据」（如捉分 label vs `captured_points`），步间 `await 0.05s` 让信号处理器走完。
5. **纪律：每个用户报告的 UI bug，修复提交必须同时在本套件补一个回归用例**（命名体现回归来源）。框架支持 async 用例（`run_suites` 可 await）。

### 联机用例（test/test_online.gd，2026-11-18）

- **真实 WebSocket 回环**：同进程跑 server 栈（store/room_manager/host_room）+ 真 NetClient 客户端，服务端计时全部按 `time_scale=0.02` 缩放（AI 节拍 ~14ms、人类托管 ~0.4s、离线宽限 ~2.4s）。测试夹具注意：`heartbeat_timeout` 须放大到远大于客户端心跳间隔（5s），否则空闲客户端被误判离线触发关房。
- **覆盖**：store 持久化与昵称全局唯一（重开实例不丢、占用拒绝、AI 前缀拒绝）；房间全生命周期（建房→凭码加入→人数不满拒绝开局→补 AI 开局→完整对局→分数落盘与广播一致→退出关房广播）；可见性断言（`debug_record` 录制回放：扣底无牌面、开局无底牌、game_start 仅本人 19 张）；超时托管（auto 标记 + 服务端状态推进核对）；断线重连（drop→member_offline→宽限内存活→同昵称回房收快照→打完→宽限超时关房）。
- **客户端代打驱动 `_drive_until`**：读本地视图状态 + 状态指纹防重发 + `send_act` 提交（人类决策复用 AiPlay 纯模块）；服务端引擎与客户端视图的公开字段（捉分/轮数）逐局互检。
- **测试钩子**：`NetClient.standalone`（game_start/snapshot 直接灌视图、不切场景）、`NetClient.debug_record`（录全部入站消息）、`host_room.time_scale`、`manager.sweep_interval/heartbeat_timeout`。

### 组件用例（test/test_components.gd）与主流程用例（test/test_flow.gd）

- **组件用例**：每个可复用组件独立断言功能——CardWidget（角标/花色着色/牌背）、SeatPanel（统一尺寸/set_info/悬停信号）、InfoSidebar（统计行灰显/局面/主牌牌面/菜单信号）、UiStyle（半字号内边距）、CrownBadge+DashedRoundedFrame（绘制不崩/早退分支）；以及**关联用例**（组件↔控制器接线）。
- **组件规范联动**：组件行为/尺寸变更必须同步断言——防止"组件一处改、实例各自坏"。
- **主流程用例**：两条端到端主线，人类动作一律走真实 UI 提交方法（与点击同一信号链）、AI 走引擎直驱：自己叫主主线 / 其它叫主主线（含庄位轮换）。
- 新增组件/主流程时同步补对应用例。

## 9. Git 与推送规范

- 提交信息：`类型: 中文摘要`，类型 ∈ feat/fix/ui/ai/docs/test/chore/refactor；一个主题一个提交。
- **推送流程**（github.com 直连经常被重置，push 可能失败）：失败时改走 gh CLI 的 Git Data API **逐字节复刻提交**（树 → 提交 → PATCH refs/heads/main），保证远端 SHA 与本地一致：
  1. `git ls-tree -r -z HEAD`（**必须 -z**，否则中文文件名被转义成乱码字面量——踩过坑）+ `git cat-file blob` 构造 tree payload
  2. `POST /git/trees`、`POST /git/commits`（作者/时间戳取自 `git cat-file commit HEAD`）
  3. `PATCH /git/refs/heads/main`，本地 `git update-ref refs/remotes/origin/main <sha>` 对齐
- 网络恢复后 `git push` 应显示无差异；若远端落后可随时用上述流程补推。

## 10. 文档同步要求（重要）

以下文档**必须随实现保持一致**，改动后逐项检查：

| 文档 | 触发更新的改动 |
|---|---|
| 本文档（AGENTS.md） | 目录结构、命令、编码/布局/测试/推送规范、AI 策略描述、UI 区域变化、最佳实践 |
| doc/三打哈-Godot工程计划.md | 里程碑状态、技术决策、实施记录、规则文档笔误清单 |
| doc/重构规范.md | 兜底白名单/拆分原则/验收工作流的演进（重构任务结束后核对） |
| README.md | 运行方式、玩法说明、目录结构、里程碑状态 |
| static/ui-mockup.svg | 任何 UI 布局/区域变更（先改稿后施工） |

## 11. 已知简化与约束

- 人类固定 0 号位（甲）；基底分 B 固定 1；无悔棋/复盘/历史记录（规则文档第 3 节待定项）
- AI 无深度推理但含角色化启发（2026-11-17 迭代，2026-11-18 扫荡叫分增补）：叫分 = 强度评分 +
  EV 校准表定「愿叫上限档」+ 扫荡概率上探（`AiBidding.sweep_prob`：假想定主复用
  `AiPlay.choose_trump`，按 7.2 跟牌强制估「以对/拖抽干闲家主牌」概率——底牌期望主 +
  对手最大持主估计 + 常主/对/拖控制系数；对手加叫按 Δ=(叫分−130)×0.04 折算常主证据即时压低，
  每次表态以最新 bids 重算即「及时更新」；P≥0.30/0.60/0.85 → 上探 165/180/200，探 200 与
  P≥0.5 且 EV>−2.0 特批参与、P≥0.85 无视 EV 放手均为用户定夺），
  实际叫分一律当前最高 +5 平滑递进（不再一手跳档）；出牌 = AiPlay 角色策略
  （数据进/决策出，choose_play 额外收 history 轮次与 trump_void 公示）：
  - 闲家：不主动领主牌对/拖（例外：无副牌、庄家已公示无主）；副牌领出优先队友缺门花色
    （历史推断 S 领出轮未出 S 牌 → 缺门），避开庄家缺门花色（防小杀）
  - 闲家下分（2026-11-17 迭代）：庄家当前领先且未现身牌中仍存在能压过其当前牌的同型牌
    （未见 = 全副牌 − 已出 − 我手牌，底牌不可知按仍在计；副牌轮的未现身主牌同型视作可杀，
    `_unseen_can_beat`）→ 提前垫分；确定无人能压（如双大王已现身、庄家出小王）→ 保留分牌，
    跟牌优先无分牌、垫牌保留分牌
  - 闲家垫牌守门协调（2026-11-17）：历史中队友（含人类 0 号位）以垫牌角色累计 ≥2 张的副花色
    视为「在清该门」（`_teammate_shed_suits`），本家自由垫牌避开同门（分值打平时生效，
    feed 喂分不受影响）——每门副牌至少留一家闲家守门，末局庄家剩余副牌有人能压；
    垫牌并按花色顶牌牌力分级（`_suit_classes`）：顶 ≤10 无赢张的门尽早清理，顶 J/Q 中性，
    含 K/A 的门更多保留——分级优先于守门避让与逐张牌力（弱门无守门价值），分牌保护仍最优先
  - 庄家扣底（2026-11-17 平衡细化）：保留顶牌最强（平手取更长）且 ≥2 张的副花色整门作赢张引擎，
    其分牌随门保留在手；其余副牌分牌优先入底（8.2 策略注记）；保留门仅在凑不满 8 张时
    才从最弱处扣起；常主不扣
  - 庄家：**三家公示无主 → 7.3 甩主牌，每次最多 4 张**（2026-11-17 用户定夺，太多看不清；
    甩 n 张逼三家各垫 n 张，闲家分牌被强制垫出而作废；主牌更多时下一轮继续甩）；握顶张（大王对/四王）先出最高常主对勾引（藏强牌）；弱主（无王 ≤5 张）先出
    最小主单逼闲家放主；≥2 闲家公示无主后改闯最大副牌组合；开局（手牌 ≥12）提前闯 Q 以上副对
  - 闲家破坏庄家副牌（领出试探）：副牌组合加成「庄家还持有」的花色（历史跟/领过且未缺门，
    `_banker_held_suits`）；无组合时单张试探——确定庄家剩某副花色 → 领该门最大牌
    （带分即出分试探）；不确定 → 领 A/Q 级大牌（庄家跟牌减薄或被迫杀主）
  - 甩打（7.3）：AI **不主动甩打**（贪心基线逐轮出牌），仅在他人甩打轮按垫牌策略跟牌（`build_discard`，队友甩打时喂分）；引擎甩打路径由迷你剧本测试覆盖
  - M3 计划引入蒙特卡洛评估与候选打分。
- 30 局自动对局中抠底极少出现（贪心庄家扣底常留主牌），8.2 路径由迷你剧本确定性覆盖
- 扫荡概率为启发式模型（`AiBidding` 扫荡常量组可调）；上探与特批是刻意的策略加注，
  BID_CALIB 口径未变（测「强制叫分 × 出牌策略」条件期望，出牌策略未动）——精调极端档
  阈值/斜率后建议重跑校准验证收益；60 局观察：200 出现率 2%~20% 随边界手翻转波动，
  庄家胜率 40%→37% 基本守恒
- 推送依赖 gh API 复刻流程（见第 9 节）
- Web 导出为验收工具（本地 serve），尚未部署公网（M5）；联机浏览器验收覆盖引导/入口/渲染/字体与客户端校验路径，**文本输入流程需真实键盘**（Godot Web 对合成输入免疫，见 §6）——桌面双实例人工验收含完整联机流程
- **联机（M4）已知简化**：反作弊止步于可见性裁剪（不下发隐藏信息；服务端逻辑仍可被逆向，定位为本地/可信小服）；服务端进程重启会解散进行中的房间（昵称注册表与房间累计分已持久化不丢）；无复盘、无观战、无操作时长配置化
