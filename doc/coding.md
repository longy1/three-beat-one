# 三打哈编码规范（doc/coding.md）

> 本文档由 AGENTS.md 原「§4 架构规范 / §5 GDScript 编码规范 / §6 Godot 最佳实践 / §7 UI 布局规范 / §8 测试规范」拆出（2026-11-18），**仅在编码任务时查阅**；总体规范与协作约定（概述/技术栈/目录/Git/文档同步/已知约束）仍在 [AGENTS.md](../AGENTS.md)。
> 章节映射：**§1 架构规范**（原 §4）· **§2 GDScript 编码规范**（原 §5）· **§3 Godot 最佳实践**（原 §6）· **§4 UI 布局规范**（原 §7）· **§5 测试规范**（原 §8）。
> **随实现演进及时更新**——任何行为、结构、流程变更后，须同步修订对应章节（AGENTS.md §5 文档同步表）。

## 1. 架构规范

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
11. **联机路由**：独立 `WebSocketMultiplayerPeer` + JSON 文本包（不挂高层 multiplayer API，避免跨进程节点路径耦合）；**每条客户端消息自带 `pid`（unique_id）**——服务端 `get_packet_peer()` 实测不返回真实来源 id（恒 1），路由信息由协议层携带（`net/protocol.gd` 契约，踩坑记录）。传输可靠有序 = 回放无需额外排序；客户端 5s 心跳，服务端 **60s** 无消息或探测发送失败判离线（阈值取大值容忍 Web 后台标签页暂停主循环——连接由浏览器维持，真断连靠探测发送失败即时判定）。
12. **联机托管与宽限**：人类回合超时（叫分 20s/叫主 30s/扣底 60s/出牌 30s）由 AI 纯模块按其手牌代打并以 `auto=true` 广播（客户端 toast「超时托管」），人类出招即重置计时；**离线座位回合改用 5s 快托管**（他人不必干等）。掉线成员进入**离线宽限期**（180s，`member_offline` 附带宽限秒数供客户端倒计时显示），宽限内回房三条路：**会话令牌 hello 重连**（客户端每实例生成令牌、每条 hello 必带，`hello_ok` 回执签发保存；token 命中存活房间成员即回房——旧连接静默未扫出也在线成员凭 token 立即接管；同昵称但 token 不符 = 其他设备在使用，在线成员一律拒绝并提示「该昵称已在其他设备登录」——在线成员不可被同昵称顶座）/ **旧连接任意消息复活**（服务端 `_try_revive` 按 pid 匹配离线成员）/ **客户端自动重连**（NetClient 等待弹层 + 3s 定时重试，窗口 150s，成功依据 `hello_ok.rejoined`）；离线成员同昵称无令牌可承接（等待扫描判离线 ≤ 探测周期，覆盖应用重启/页面刷新丢令牌的合法回归）。**昵称保留窗口 = 重连窗口**：宽限期内昵称随房间保留（重连分支先于占用拒绝），房间解散/主动退出或未进房连接静默清理后才释放复用。**服务端进程重启不散房（2026-11-20）**：host_room 每次成功变更即全量落盘（成员含会话令牌 + 引擎状态，牌走 `Card.key()` 串），RoomManager 启动经 store 回放恢复——成员离线、令牌保留、宽限计时与待办回合重挂（`_resume_pending_turn` 按阶段重新调度 AI 代打/快托管），客户端凭 token 自动重连即回房续打。回房统一收**公开状态快照**恢复视图，掉线时在走的回合计时重挂满正常时长（回连者获得完整决策窗口）。回前台补发 hello（`NOTIFICATION_APPLICATION_FOCUS_IN`）是 Web 后台标签页恢复的复活入口。**主动 leave 立即关房**并广播累计分（各端弹分数窗→确定→主菜单）。

## 2. GDScript 编码规范（本仓库实践）

- **类型推断陷阱**：`Dictionary`/无类型 `Array` 取值、引擎信号携带的 Variant **不能用 `:=` 推断**，必须显式标注（`var x: int = dict.field`；`var k: String = c.key()`）。历史 bug 多源于此，code review 重点。**联机（2026-11-18）**：game_table 的 `engine` 放宽为非类型化变量（单机 GameEngine / 联机 TableView 鸭子类型）后，所有 `:= engine.xxx` 失去推断来源——已全部显式标注；给持有 Variant 的字段新增读取时同样注意。
- **不覆盖 `Object.to_string()`**（Godot 视为警告级错误）：Card/Combo 用 `label()`。
- 方法调用带括号：`c.points()` 而非 `c.points`（后者得到 Callable，运算时报错）。
- 数组推导式内不要嵌套 `%` 格式化等复杂表达式（解析器不支持），改用显式循环。
- 常量数组/实例：`const` 不能含 `Card.new()` 调用，用实例变量。
- 静态工厂优先：`CardWidget.create()`、`Combo.detect()` 等静态构造；策略函数全部 `static`（AiPolicy 门面共享 `static var rng`，`_static_init` 中 randomize）。
- 注释与文档字符串用中文，函数头 `##` 说明职责与规则依据。
- **代码零更新记录（2026-11-18 起，机器守护）**：任何代码文件（`.gd` 等）内**禁止日期戳与变更记录式注释**（如「20XX-XX-XX 新增/改为/回退」「旧版如何现在如何」「用户定夺 20XX」）——代码注释只描述**当前行为与规则出处**；这类内容一律写进 `doc/update.md`（按日期倒序归档，`test_no_changelog_comments` 全 .gd 扫描违规即红）。不带日期的设计缘由/回归用例来源（§5）不在禁列。
- **文档引用用令牌（机器守护）**：注释指向上游文档一律用短令牌、**禁止写完整路径**——`[规N]` 规则文档 / `[码N]` 本文件 / `[构N]` 重构规范 / `[史]` update.md / `[划N]` 工程计划；解码注册表在 AGENTS.md §5 文档同步要求（`test_doc_tokens_valid` 校验令牌已注册且节号真实存在）。例：`（[码4] 手牌交互）`、`（架构遵循 [构7]）`、`（迁 [史]）`。
- 命名：类名 PascalName；私有成员 `_` 前缀；信号回调 `_on_<signal>`。
- 跨组件共用常量放单一事实源（如 `UiStyle.MAIN_TABLE_CENTER`），禁止两份「应该相等」的数字。

## 3. Godot 最佳实践（本仓库清单，检查与沉淀自 2026-11-16 重构）

**工程配置**
- `project.godot` 用编辑器/直接编辑均可，但须保持分区有序（application/display/gui/rendering）；新增系统级设置（字体主题等）登记在 AGENTS.md §2/§3。
- `export_presets.cfg` 入库；导出过滤排除非运行时目录（`test/*,doc/*,tool/*,build/*,server/*`，2026-11-18 增 server/——服务端仅桌面源码运行且引用面与客户端隔离）；`net/` 必须进包（Web 客户端联网）；`build/` 忽略。
- `html/head_include` 注入移动端壳层适配（2026-11-17 起；**2026-11-18 Safari 排雷后回退到基线**）：`canvas#canvas{touch-action:none}`、右上角 ⛶ 全屏按钮（DOM 覆盖层，webkit 前缀；iPhone 无该 API 降级提示添加到主屏幕）。**iOS 排雷结论（真机实测）**：①触控输入层无问题（探针页证实事件全达、坐标准）；②曾叠加 rAF 停摆垫片/合成扰动/display 切换/viewport 归一/手势拦截/visualViewport 桥六项，**真机全部无效已回退**——其中 rAF→setTimeout 垫片有反作用：emscripten WebGL 的帧提交绑定真实 rAF 回调（`explicitSwapControl=false`），setTimeout 驱动主循环会让逻辑全速跑而帧永不提交（恰似「点按有效画面冻结」，干扰了排查）；③**流程教训：改 head_include 后必须 `--export-release` 并对产物 grep 验证注入生效**（曾恢复配置未重新导出，用户测到旧包污染判断）；④工程设置 `touch_delay=0.0`/`emulate_mouse_from_touch=true` 保留（移动端正确设定）；⑤**冻结真凶结案（2026-11-21）**：用户升级 iOS 后真机复测冻结不复现——真凶为验证设备 Safari 版本较低（版本相关 bug）；`html,body{position:fixed}` 嫌疑曾于 2026-11-18 实测移除仍冻结、随升级关闭（详见工程计划 Safari 排雷节）。⑥**视口看门狗（2026-11-19 起，用户报告转屏/回前台后画布偏移黑边）**：head_include 追加 iOS UA 门控脚本——`orientationchange`/`visualViewport` resize/回前台时 `scrollTo(0,0)` 复位页面偏移并**合成 window resize**（250/700/1500ms 三拍补发，Safari 视口常分多帧才稳定），让引擎按新视口重算画布尺寸；与②的六个冻结垫片不同，本项只补发引擎自身监听的 resize 事件，无 rAF 垫片反作用风险；产物注入验证照 ③ 流程（grep index.html）；**2026-11-21 真机确认：转屏/回前台自动纠正工作正常**。
- `html/experimental_virtual_keyboard=true`（2026-11-18 联机昵称输入）：触屏 UA 下 LineEdit 聚焦弹系统键盘；桌面浏览器走物理键盘直接输入。
- **Godot Web 对合成输入免疫（2026-11-18 验收实测）**：自动化注入的合成 KeyboardEvent/ClipboardEvent/CDP 文本均不进引擎（仅受信任的真实输入生效）——浏览器验收能覆盖引导/渲染/按钮路径，**文本输入类流程须真实键盘**（桌面双实例人工步骤）。
- `.gitignore` 只忽略生成物（`.godot/`、`build/`）；`.uid` 与源文件成对提交。

**场景结构**
- 组件自带统一尺寸（`custom_minimum_size`），实例只锚定位置不拉伸（SeatPanel 模式）；「组件一处改、实例全部生效」。
- 居中展示组件一律点锚 `UiStyle.MAIN_TABLE_CENTER` + `grow BOTH`（TrumpRankPicker/PileViewer 弹层/ResultPanel 均如此），禁止四角拉伸锚点承载弹层。**锚点按场景取（2026-11-19 起，用户报告退出弹窗歪斜的修正）**：桌面对齐只在牌桌内才有意义——`UiStyle.center_anchor(node)` 统一取值：当前场景为联机牌桌（挂 `_net`）→ 桌面十字中心；主菜单/联机菜单/房间大厅等非牌桌场景 → 屏幕正中 `SCREEN_CENTER`（ScoresDialog/ReconnectOverlay/大厅补电脑确认框均走此规则；这些弹层由 NetClient 或大厅创建、跨场景显示，不能硬编码桌面锚点）。
- 节点语义命名，禁止编辑器自动编号名（如曾经的 MenuButton2）残留。
- 可编辑结构优先落 tscn；纯动态内容程序化构建——两者边界：容器/槽位在场景，内容在脚本。

**脚本**
- 节点引用统一 `@onready var x := $Path`（禁止散落的 `get_node`/`$` 长路径重复出现在方法体内）。
- **组件封装不穿透**：外部不 `get_node` 进组件内部结构，为用途补公开 API（如 `SeatPanel.crown_anchor()`）；组件内部路径仅测试断言可用。
- 单一事实源：套件注册 `test/suite_registry.gd`（run_tests 与主菜单自检共用）；布局锚点 `UiStyle`。
- 开发期专属功能（自检）用运行时 `load()` 而非静态 `preload`，避免拖进导出包。**更强约束（2026-11-17 Web 实测踩坑）**：任何对被导出过滤排除文件（如 `test/*`）的静态 `preload`会让**整份脚本**在导出环境解析失败——`_ready` 不执行、按钮全部失去处理器且无任何运行报错线索；此类引用必须全部走运行时 `load()`，并在 `--export-release` 后用浏览器验收确认。
- **Web 特性守卫**：`OS.has_feature("web")` 分支处理平台差异（quit 无效、test 未打包）；新增平台敏感 API 前先查该守卫。
- `_ready` 只做接线与轻构建；重构建走组件 `_ready` 分摊；首帧依赖布局的渲染挂起到尺寸有效（HandArea 模式），禁止兜底默认尺寸。
- 信号连接用 `.connect()` 方法引用/lambda，风格保持统一；信号发出前状态就绪（§1.5）。**陷阱（2026-11-17 实测）**：lambda 内 `func(): x.start` 是求值出 Callable 后丢弃（仅 STANDALONE_EXPRESSION 警告，不报错），方法从未被调用——连接回调方法直接用裸 Callable（`connect(x.start)`），lambda 内必须带括号调用。
- **ScrollContainer 最小尺寸为 0**：放入自适应容器（VBox/PanelContainer）会整层塌缩，内容全部裁剪不可见——弹层滚动区必须按内容行数设置 `custom_minimum_size`（PileViewer 历史弹层 2026-11-17 回归）。
- **复用 Timer 的回调单槽化（2026-11-18 联机踩坑）**：one_shot Timer 复用做调度器时，`timeout.connect(action)` 每次调度都会叠加连接——改为单槽「待执行 Callable + 固定回调」（`_pending_ai` 模式）；同理，测试里对**多发信号**（如 remote_action）挂 `CONNECT_ONE_SHOT` 会被首个无关发射消费掉。
- **跨场景存活组件**：需要跨 `change_scene_to_file` 存活的状态挂 `tree.root` 直属节点（联机 `NetClient`，名字固定便于 `get_node_or_null` 定位），自毁走 `queue_free.call_deferred()`；本项目维持零 autoload。

**资源与字体**
- 中文显示依赖打包字体（浏览器无系统回退）：文案新增字符后**必须重跑 `python -I tool/subset_font.py`** 再导出，否则豆腐块。
- **第二字体：王牌 JOKER 字母用 Roboto Mono 子集**（2026-11-19）：`font/RobotoMono-Regular.subset.ttf` 仅含
  J/O/K/E/R 五字形（1.2KB）——Noto 的比例拉丁字形墨迹中心互有偏差，竖排会错位，等宽同 advance 才能成列
  （♠♥♣♦ 花色符号等宽拉丁字体没有，故角标花色仍走 Noto + 居中对齐）；源字体缓存 `build/_font_src/RobotoMono-Regular.ttf`
  （Apache-2.0，jsdelivr 镜像可下，GitHub 直连常被重置），重切命令：
  `python -I -m fontTools.subset build/_font_src/RobotoMono-Regular.ttf --output-file=font/RobotoMono-Regular.subset.ttf --unicodes=U+004A,U+004F,U+004B,U+0045,U+0052 --no-hinting --layout-features= --no-glyph-names --name-IDs=1,2`——字母集变化须重切。
- 字体走主题资源（`theme/default.tres` + `gui/theme/custom`），不在各控件逐个 override 字体。
- 新增控件一律程序化绘制（参照 CardWidget/CrownBadge/DashedRoundedFrame），不引入图片素材。

## 4. UI 布局规范

- **固定优先原则（2026-11-16 确立）**：桌面区域、手牌区先固定；操作按钮/提示等临时 UI 在**各自的固定槽位**内显隐（悬浮式），**禁止用可变高度容器（VBox 堆叠）承载会增减的行**——历史上按钮出现曾推挤手牌跳动。
- **相对长度原则**：节点定位用 0~1 比例 anchors（勿写死像素）；动态出牌/动画位置用相对常量（`TRICK_ANCHORS`/`CrownAnimator.CROWN_HUMAN_TARGET` 为 0~1 Vector2，渲染时 ×层尺寸）。卡牌等控件以 720p 设计分辨率定义基准尺寸，`canvas_items` 拉伸模式保证任意窗口整体等比缩放。
- **两大区域（2026-11-16 确立）**：画面分为**主牌桌区域**（x 0~82.8%）与**侧信息板区域**（82.8%~100%，InfoSidebar）。区域名称标注于视觉稿。
- **居中规范（2026-11-16 确立）**：所有居中展示组件（弹层/面板/皇冠出现点）统一锚定**主牌桌十字中心** `UiStyle.MAIN_TABLE_CENTER`=(0.419, 0.408)——左右对齐丙面板中轴、上下对齐乙/丁面板中轴；实现为点锚 + grow BOTH（尺寸随内容向四周自适应），禁止固定 offsets 尺寸（内容不满时视觉偏置）。翻底阶段的中央「底牌（仅你可见）」面板（2026-11-17 起程序化 PanelContainer）同属此列。
- **半字号留空原则（2026-11-16 确立）**：所有文字与其最近的边框（面板边、按钮边）四向留空 **≥ 字号的一半**。落实方式：按钮统一走 `UiStyle.pad_button()`（content margin = 字号/2）；面板在 tscn 中用 StyleBoxFlat `content_margin_*` 落实（InfoSidebar 8 / SeatPanel 9 / ResultPanel 15，≈ 各自最大字号的一半）。豁免：无边框裸文字（Toast/提示行/顶栏标签）、卡牌角标（扑克角标贴角为惯例设计）。
- **卡牌尺寸与角标（2026-11-19 移动端触控调整）**：三档尺寸单一事实源在 `CardWidget`——NORMAL 72×100（手牌/出牌区≤2 张/揭主飞牌）、MEDIUM 60×86（出牌区 3+ 张）、SMALL 52×76（历史面板/牌堆弹层/信息栏/底牌展示；信息栏 `TrumpSlot` 场景 min size 与之同步）。**角标**（2026-11-19 重做）：点数、花色两行各自在半区**水平居中**，共用同一条竖直中轴——Noto 里花色字形是全角、点数是半角，左对齐必错位，居中才是对齐手段（等宽拉丁字体不含 ♠♥♣♦ 字形，解决不了）；每行一个 Label（勿用单 Label `\n` 换行，主题行距实测 ≈1.8× 字号不可控）；**卡牌旋转对称**：右下角同款角标 180° 镜像（`pivot_offset=size/2` + `rotation_degrees=180`）。**中央花色**字号三档 26/18/22，牌面**横竖正中**（调小让位上下角标，2026-11-19 由 34/26/30 改；勿加下沉偏移——会读成不居中）。**王牌面**：经典小丑牌版式（2026-11-19 定稿）——**无「大/王」角标**，左右两列竖排 JOKER 字样（右列整列 180° 倒置，逐字母 Label 落位；字号 11/8/9 小于点数、字距紧凑、整列纵向居中——实牌参照，勿摊满全列高；大王红/小王黑沿用着色区分），中央 `PixelJester` 像素小丑（Balatro 像素风参考，帽色同步红/黑）。移动端触摸目标依据：iPhone 横屏（844×390pt）下逻辑 1280×720 letterbox 缩放 ≈0.54，手牌 ≈39×54pt。改尺寸后须核对：手牌区高度（HandRow 118px，NORMAL 高 +BASE_Y 16 ≤118）、27 张扣底阶段最小间距、信息栏槽位、历史面板十字区宽度。
- **组件复用**：三家电庄信息框复用 `SeatPanel`；右侧信息栏 `InfoSidebar`；手牌区 `HandArea`；牌堆弹层 `PileViewer`；操作按钮 `ActionBar`——实例只锚定/挂载，不各自拉伸改尺寸。
- **对称十字出牌位**：四家出牌围绕牌桌中心对称——你=下方（0.419,0.55）、丙=信息板正下方（0.419,0.28）、丁=面板右侧（0.234,0.408）、乙=面板左侧（0.604,0.408）。每家出牌为**重叠横排**：步距 = `HandArea.SPACING_MAX`（与手牌同款紧凑口径，后牌盖前牌各露左缘角标条，2026-11-19 起不再摊开全宽），出牌行整体不接收鼠标（`MOUSE_FILTER_IGNORE`，重叠区不挡点击）。
- **游戏设置弹层（SettingsDialog，2026-11-20）**：程序化构建（遮罩 + `UiStyle.center_anchor` 居中 + 面板 z=60 + content_margin 15，与 ScoresDialog 同口径）；三个循环切换按钮（手牌区主牌：在左/在右；牌点数排序：从大到小/从小到大；手机版 UI 调试：关/开）+【完成】；变更即保存（AppSettings.save_settings）并回调 on_changed（牌桌据此重应用布局与重渲手牌）；主菜单与牌桌信息栏两处入口共用。
- 设计分辨率 1280×720（stretch canvas_items / keep），统一 12px 边距；桌面窗口默认 1920×1080（`window/size/window_*_override`，内容仍按 720p 基准等比放大 1.5×，控件像素常量不随窗口变大——2026-11-17 用户设定）。
- 区域划分见 [static/ui-mockup.svg](../static/ui-mockup.svg)（布局改动先改视觉稿再施工）：
  - 顶栏（局数/出牌庄/叫分）；**抓牌庄家不展示**
  - 叫主点数选择：居中多排面板（2 排 × 6，TrumpRankPicker），10 个点数按钮完整展示（R ∈ 5~2，不可为王）
  - 叫分提示显示在主牌桌正中央（BidCenterLabel，「叫分中（最高 X）」）；**不用「拍卖」一词**（非本土打牌用语）
  - **叫分对话气泡（BidBubbles，2026-11-20）**：各家叫分/放弃以带尾巴的气泡呈现于座位旁（你=手牌上方尾朝下、乙=面板左侧尾朝右、丙=面板下方尾朝上、丁=面板右侧尾朝左；锚点即尾巴尖角，**贴近玩家面板**——甲手牌区顶上方 8px、乙/丙/丁面板缘 6~12px，2026-11-21 调整），姓名版状态行腾空；只有当前最高叫分的气泡在展示（低分被更高分取代即消失）、放弃气泡保留到拍卖结束、无表态座位隐藏（新局不留残影）；字号随分值 130→200 线性（17→44px），气泡封顶约中央空白牌桌 1/3 面积；状态驱动全量幂等 apply（_refresh_seats 每刷调用，重连快照恢复同路径生效；发牌/排序动画期间挂起不显示，排序完成后随拍卖呈现），程序化绘制（圆角矩形 + 一体化尾巴三角：填充与框连续、描边只走斜边与框缘自然相接，接缝无描边横线；Label 居中）
  - 丙上带居中牌桌区；丁面板贴左缘；乙面板贴牌桌右缘（与丁关于牌桌中心对称）
  - 右侧信息栏（InfoSidebar）：**主牌提示 = 一张「正 R」牌面**（守卫自愈渲染：`_refresh_top_bar` 以 `engine.trump != _last_trump_shown and not _trump_reveal.active` 放行——揭主飞行中跳过、落位回调渲染，**飞行被打断时 active 复位由守卫自愈重渲**，杜绝「回调丢失 + 引用比较永久跳过」的标识消失）；**未叫主态**：牌背微透明 + 居中问号 + 下方注明「未叫主」；另有手牌统计 + 局面（捉分/累计）+ 设置与主菜单按钮（设置入口与主菜单共用 SettingsDialog）；下半为 M3 预留；**手机版默认收起**（见下「手机版布局」）
  - 底部固定槽位：按钮 / 提示 / 手牌（双虚线框：左主牌右副牌，区内从大到小；叫主前王与 2 进左框；主牌区内牌力并列的副R/副2 按 ♠→♥→♣→♦ 同花色相邻分组，2026-11-17）。**手牌紧凑摆法（2026-11-19）**：相邻牌步距 ≤ `HandArea.SPACING_MAX`（24，2026-11-19 由 40 收紧）——重叠摆法、每张露左缘角标条（步距 = 露出条宽），宽度不足时向 `SPACING_MIN`（8）继续收紧
  - 牌堆按钮左下（悬停查看出牌历史，旧→新）
- **手牌交互**：选中的牌**上浮牌高的 20%**（`HandArea.SELECT_LIFT_RATIO`）；左键按住滑动可**批量选择相邻牌**（以首张的新态对齐滑过的牌）；出牌模式下**右键直接提交出牌**（`play_requested` 信号，引擎校验非法 toast）。**命中范围 = 露出条带**（2026-11-19）：卡牌控件 `mouse_filter IGNORE`，点击/拖动统一走 `HandArea._hit_card_at` 条带命中——每张牌只有到下一张牌左缘为止的露出部分可命中（各框末张整张），卡牌自身整张矩形在重叠区会误命中被压住的牌（拖动旧实现取「最左包含」的牌，正好隔一张）。选中态刷新走 `HandArea._widgets` 精准更新单张，禁止整排重建（闪烁/抖动）。**选牌跨轮保留（2026-11-17）**：同模式连续轮次不清空选择（`begin_select` 仅模式切换时清），且 `render` 以当前权威手牌为准自动剪除 selected 中已不在手牌的陈旧引用（快速连打的渲染竞争曾留下已打出牌的引用致整局「牌不在手中」卡死）——陈旧选中不允许跨渲染存活；提交成功后 `consume_selected` 只移除已打出的牌；**底牌入手即选中**：人类庄家翻底后 `select_cards(engine.kitty)` 预选 8 张（拿起态，便于观察与直接扣回）。**双击空白清空选择（2026-11-20）**：双击手牌区空白（条带未命中任何牌）或牌桌空白（Background 层）清空选择（把选中的牌全部放回）；**触屏两指单击出牌（2026-11-20）**：首指按下即快照当前选择（先于触摸模拟的鼠标点选副作用），第二指按下（至少一指在手牌区内）确认手势，两指全抬恢复快照、出牌模式提交 `play_requested`——与右键出牌等效的触屏入口。**手牌呈现偏好（2026-11-20）**：主牌框在左/右（框序对调）与牌点数从大到小/从小到大（花色分组从左到右不变）由 AppSettings 驱动（`script/app_settings.gd` 单一事实源，ConfigFile user://settings.cfg 即时保存生效），变更后控制器重渲整排。
- 庄家标记 = 皇冠动画（`CrownAnimator`）：拍卖结束从主牌桌区域正中央 ×4 出现，`TRANS_CUBIC EASE_OUT` 1s 飞至庄家名字旁停驻——落点动态测量（`SeatPanel.crown_anchor()`：名字首字左缘前 4px、冠高 = NameLabel 字号）；人类 0 号位落**手牌上方按钮行**（历史/牌堆按钮右侧 (0.108,0.749)，2026-11-17 起，不再遮挡手牌）。新局拍卖开始时清除（皇冠与揭主牌面均 clear）。面板不用「·抓牌/·庄」文字。**揭主双飞（2026-11-17）**：叫主完成的同一时刻，主 R 牌面（`TrumpReveal`，中央 ×2.2）与皇冠同现于主牌桌中央并同步减速飞行——牌面落点为信息栏主牌展示位（`InfoSidebar.trump_slot_center()`），落位回调把主牌放进信息栏并记 `_last_trump_shown`（`TrumpReveal.active` 期间 `_refresh_top_bar` 跳过即时刷新；飞行被 clear() 打断时 active 复位、守卫自愈重渲，见信息栏条目）。
- **【无主】印章（规则 7.3，2026-11-17）**：主牌轮垫牌公示——`VoidStamp` 圆形红章（斜置半透明红、程序化绘制）：乙/丙/丁盖在 SeatPanel 右下角（`set_void_trump`；印章 `top_level=true` 脱离容器布局树用全局坐标定位——PanelContainer 会对直接子件整面填充布局，曾把印章拽到左上角压住姓名）；人类 0 号位盖在**手牌区右上方固定槽位**（HumanVoidStamp，tscn 锚点 (958,488)，2026-11-17 调整）。
- **左下按钮区（不随牌变动）**：【历史】= 点击打开**出牌历史面板**（`TrickHistoryPanel`，2026-11-17 重做）：居中弹层以**十字形**展示一轮四家出牌（与牌桌出牌摆位座位方位同构、窗口更小，赢家 ✓ 金标），默认**最后一轮**；中央下方 【<<】【<】【>】【>>】 四按钮翻第一页/上一页/下一页/最后一轮（边界禁用）；右上角 ✕ 或**点击窗口外**（全屏微暗遮罩，`MOUSE_FILTER_STOP` 透明拦截）关闭；打开期间新轮结算由 `trick_settled → _refresh → refresh` 状态驱动就地收敛页码；【牌堆】= 仅庄家是自己且进入出牌阶段后显示（「历史」右侧同一行），悬停弹出**底牌堆 2 行 × 4 张**（`engine.buried`，仅自己可见；弹层归 `PileViewer`）。**悬停弹层机制（2026-11-17 历史面板重做后仅剩【牌堆】按钮悬停路径；座位面板悬停路径已移除）**：事件驱动 + 粘滞——显示随 `mouse_entered` 一次调用，隐藏靠 0.1s 延迟计时器（粘滞时长 2026-11-17 用户定夺为 0.1s；弹层悬停仍保持打开，重悬停即可再次查看），**不用周期轮询**（`mouse_entered/exited` 本就是引擎逐帧悬停判定的结果，自建轮询属 §1 禁止的定时兜底）。
- 一轮结算后牌面（含 ✓赢家）停留 **1.5 秒后主动清空出牌桌**（TRICK_PAUSE 由 `_trick_timer.timeout` 统一触发清空，不依赖下一手替换）；末轮停留后才弹结算面板。
- **发牌动画（DealAnimator，2026-11-21 重做节奏）**：开局（单机开局/下一局、联机 game_start；重连快照不播）中央背面牌叠 → **逐拍一张一张发（TICK 0.2s/张，无飞行牌）**：每拍自己手牌在**汇聚槽**现身一张（提前算好：发牌顺序紧凑行，间距复用 SPACING_MIN/MAX clamp，行基线与真实手牌行同 y），各家座位面板张数经 on_tick 逐拍 +1（0 张起步，动画结束回归引擎权威值）→ 到齐后停顿 → 两边往中间收拢到一张 → 展开到真实牌序布局：展开前按目标位 x 升序重排容器子节点（**途中遮盖关系与排序后一致**——右牌盖左牌，与 HandArea 渲染 z 序相同），每张以**相同时长**（EXPAND_DUR）平移至测量位，结束后重渲替换无跳变。目标位取自控制器先做的一次**测量渲染**（HandArea.card_positions，随后 set_widgets_visible 隐藏真实牌面、set_frames_visible(false) 隐藏虚线框——牌未分区排序前框位与牌不对齐，动画结束放行真实渲染（排序完成）后再展现），动画结束回调重渲放行——不复制布局数学（单一事实源仍是 HandArea._do_render）；播放期间 `_render_hand` 经 `_deal_active` 统一挂起，且**拍卖表态一并挂起**（`_on_auction_required` 在 `_deal_active` 时仅做状态刷新即返回——AI 不叫分、人类不出拍卖条、叫分气泡同样挂起至排序完成（含庄家底叫 130）；`_on_deal_done` 按引擎当前轮转补跑；下一局/联机 game_start 须在引擎信号前置位 `_deal_active`）——排序完成前 AI 不开始叫分（用户需求），**表现层不阻塞对局逻辑**（引擎仍可被测试直驱）；speed 缩放供测试与冒烟。
- **手机版 UI 独立分支（2026-11-21，用户定夺：与桌面版仅共享规则与流程，布局/尺寸/组件解耦各自迭代）**：判定 = `AppSettings.effective_mobile_ui()`——移动端设备特性（android/ios/web_android/web_ios）自动启用，或设置面板「手机版 UI（调试）」强制开启（PC 调试入口，ConfigFile 持久化）。分支应用器 = 控制器 `_apply_layout_mode`（桌面还原值在 `_ready` 捕获、tscn 即桌面事实源；布局常量组 = `script/table/mobile/layout.gd` MobileLayout）：
  - **顶栏**（MobileTopBar，高 56，程序化）：**只放当局信息**——局况（庄/叫分）+ 主牌小牌面（揭主飞牌落点，CardWidget 第四档 SIZE_BAR 36×50）+ 捉分 + **手牌统计（图标+数字 ×4：花色字符着色，主花色金色突出、王计入主牌数，未叫主=四门；恒 4 组，set_suit_stats）** + 「更多」按钮；桌面版顶栏/中央叫分提示在手机分支隐藏
  - **「更多」面板**（MobileMorePanel，居中弹层、ScoresDialog 口径）：局数、四家累计、手牌统计（点数行灰显）、设置/主菜单入口；点窗外/✕ 关闭（closed 信号清控制器引用）；打开期间由 _refresh 状态驱动实时更新
  - **手牌**：卡 96×134（HandArea 覆写 hand_card_size）、贴底（hand_base_y 分支值）、步距 40·12（桌面 24·8）、宽 ≈90% 屏宽（BottomArea 左右 64）；出牌十字居中、乙/丁面板对称贴两缘、操作按钮 150×52；发牌逐拍/虚线框显隐/气泡/选中上浮 20% 口径全部沿用（DealAnimator 尺寸与步距随 HandArea 取值）
  - 桌面版布局完全不变；布局改动先改视觉稿（ui-mockup.svg 手机版画板）
- **联机界面（2026-11-18，M4）**：主菜单新增【联机对战】→ `scene/menu/online_menu.tscn`（昵称/服务器地址默认 ws://127.0.0.1:9080/新建房间/房间码+加入/返回；状态行报错；昵称 ConfigFile 记忆；**「最近成功连接」列表（2026-11-20）**：连接成功即记录地址（去重置顶、封顶 5 条），点按条目填入地址框）→ `scene/menu/room_lobby.tscn`（房间码大字、四座位成员列表——房主/你/电脑/离线标注、开始游戏仅房主可见、退出房间）。**人数不满开局流程**：房主点开始 → 居中确认弹层「人数不满（X/4），是否自动补充电脑玩家？」——是 → `start{fill_ai:true}` 补满即开；否 → 仅关闭弹层留在房间页；满 4 人直接开。**累计分数弹层** `script/menu/scores_dialog.gd`（居中锚点按场景取 `UiStyle.center_anchor` + 全屏遮罩）：主动退出（本地立即弹）、他人退出/离线超时/服务器失联（`room_closed`/`connection_lost` 数据弹出），确定 → 主菜单。牌桌联机态复用单机布局：座位名 = 成员昵称（本地座位序，0 号位带（你）），AI 补位名「电脑·乙/丙/丁」；结算面板【下一局】仅房主可见（其余等待）。布局注记见 static/ui-mockup.svg 联机屏。
- 新增控件一律程序化绘制（参照 CardWidget/CrownBadge/DashedRoundedFrame），不引入图片素材。

## 5. 测试规范

- 新增/修改规则行为**必须带用例**；规则类改动对照规则文档章节写正反例。
- 套件注册**只改 `test/suite_registry.gd` 一处**（run_tests 与主菜单自检共用；主菜单运行时动态加载）。
- 共享基类：`test/test_base.gd`（C() 造牌 / trump 基准 / Phase 别名）、`test/ui_test_base.gd`（_spawn_table 三件套 / tree_pause）——新套件 `extends TestBase` 或 `extends UiTestBase`，勿再复制助手。
- **计时敏感断言用单帧等待**：断言「某延迟计时器尚未触发」时用 `await tree.process_frame`（1 帧后即查），不要用 `create_timer` 定时等待与被测计时器赛跑——后台负载的慢帧会把两把计时器挤进同一帧造成假失败（2026-11-19 牌堆弹层延迟隐藏用例假失败）。`tree_pause()`（0.05s）只用于「等引擎信号链走完」，不做竞态断言。
- **分级测试入口（2026-11-19）**：本地 commit 前 `bash test/run_affected.sh`（改动文件→套件映射在本脚本，新增套件/目录须同步维护）；push 前 `bash test/run_tests_parallel.sh` 并行全量（分片按「文件名::用例名」稳定哈希，**新用例自动纳入分片无需登记**；test_online 的端口/存储按 TEST_PORT_OFFSET 偏移，分片进程不冲突）。框架逐套件打 `[suite]` 耗时、≥2s 用例打 `[slow]` 行——新增慢用例会自己暴露。
- **架构守护（test_architecture.gd）**：core 纯度（禁 Node/场景/时序/IO 依赖清单扫描）、AI 模块不引用引擎类型、submit_* 唯一写入口白名单、代码零日期戳/史志类注记（`test_no_changelog_comments` 全 .gd 扫描）——规范固化为可执行检查，违规即红。
- AI 改动用两类测试守护：单项策略断言 + **30 局种子化自动对局不变量**（零非法着法、每局完整结束、捉分 ≤200+底牌分、收支守恒、Scoring.compute_outcome 互检）。
- 特定规则路径优先用**注入迷你局剧本**（`start_session_with_deal`，如抠底 ×1/×2/庄赢不抠三剧本），不要写脆弱的整局剧本。规则 7.3（无主公示/主牌甩打）同样由迷你剧本确定性覆盖（甩打结算/条件拒绝/跟牌张数/末轮甩打抠底 ×1/公示触发与不触发六类）。
- 叫分等概率策略的断言用固定 `AiPolicy.rng.seed` 的确定性断言（EV 档位断言）。
- **平衡校准工具**：`test/calibrate_bidding.gd`（独立 -s 入口，不注册套件）——蒙特卡洛模拟「固定叫分 × 强度桶」统计胜率/期望收益，用于重训 `AiBidding.BID_CALIB` 查表；AI 策略或对手水平变化后建议重跑校准。样本量 200 局/格（2026-11-18 起，24 格满配 4200 局；此前 60 局/格噪声 SE≈0.5、罕见格跑不满，曾致换表误判）。
- **校准的边界**：校准表测的是「当前出牌策略水平」的条件期望，不是牌力理论上限——出牌策略迭代后必须重跑校准。

### UI 用例维护（test/test_ui.gd）

UI 层曾因无用例而集中出 bug（信号时序竞态、引用遗漏、渲染丢弃）。UI 用例模式已固化：

1. **headless 实例化场景**：`_spawn_table()` 加载 game_table 场景、等两帧布局、把 `_ai_timer/_trick_timer` 调快（免等待真实节奏）。
2. **方法级驱动**：不模拟鼠标——直接调用控制器方法（如 `_submit_human_trump()`）或引擎 API，触发与真实点击相同的信号链。控制器门面触点：`hand_area.selected/select_mode`、`_piles.*`、`_trump_picker`。
3. **节点状态断言**：断言按钮存在/可见、Label 文本、popup 标题等真实 UI 状态；计数类断言须跳过 `is_queued_for_deletion()` 节点（queue_free 帧末才删）。
4. **一致性不变量**：自动对局每步断言「UI 显示 == 引擎数据」（如捉分 label vs `captured_points`），步间 `await 0.05s` 让信号处理器走完。
5. **纪律：每个用户报告的 UI bug，修复提交必须同时在本套件补一个回归用例**（命名体现回归来源）。框架支持 async 用例（`run_suites` 可 await）。

### 联机用例（test/test_online.gd，2026-11-18）

- **真实 WebSocket 回环**：同进程跑 server 栈（store/room_manager/host_room）+ 真 NetClient 客户端，服务端计时全部按 `time_scale=0.02` 缩放（AI 节拍 ~14ms、人类托管 ~0.4s、离线快托管 ~0.1s、离线宽限 180s→~3.6s）。夹具 `heartbeat_timeout=60` 与服务端默认一致（远大于客户端心跳间隔 5s，空闲客户端不会误判离线）；复用例的掉线检测靠 `drop_connection` 后的定向发送失败即时生效。
- **覆盖（18 用例）**：会话令牌重连（同 token 接管回房、在线成员不可被同昵称顶座、离线成员同昵称承接）、服务端重启不散房（同端口同存储重建→房间恢复→token 重连打完）、联机菜单最近成功连接、昵称在线占用制（重开实例不丢、占用拒绝、trim 归一、AI 前缀拒绝）；房间操作守卫（在房重复建房/加入、满员、对局中加入、非房主开局、重复开局、未开局 next）；房间全生命周期（建房→凭码加入→人数不满拒绝开局→补 AI 开局→完整对局→分数落盘与广播一致→退出关房广播）；可见性断言（`debug_record` 录制回放：扣底无牌面、开局无底牌、game_start 仅本人 19 张、非庄家无 kitty）；超时托管（auto 标记 + 服务端状态推进核对）；断线重连与宽限超时；客户端自动重连（等待弹层→重试回房→快照恢复→打完）；后台标签页复活（旧连接消息 `_try_revive` 回房、宽限取消）；离线快托管与重连重挂计时；同昵称快速接管（静默在线成员被同昵称 hello 立即回房、旧映射释放、扫描不误判）；大厅选座（空位挪入/占座互换/房主身份跟人走/新成员填首个空位/对局中拒绝）；多局累计（下一局重灌/庄位轮换/跨局累计分/非房主 next 被拒）；注入强牌局的确定性旋转校验与人类操作路径（叫分值/叫主/扣底/非法出牌拒绝+重试）；四阶段重连快照矩阵（叫主/扣底/出牌/终局）；UI 级联机牌桌（真实场景接管、人类走 UI 提交方法、退出弹层回主菜单）。
- **客户端代打驱动 `_drive_until`**：读本地视图状态 + 状态指纹防重发 + `send_act` 提交（人类决策复用 AiPlay 纯模块）；服务端引擎与客户端视图的公开字段（捉分/轮数）逐局互检。
- **测试钩子**：`NetClient.standalone`（game_start/snapshot 直接灌视图、不切场景）、`NetClient.debug_record`（录全部入站消息）、`NetClient.auto_reconnect`（默认 false：既有 drop 用例保持旧的断线即弹窗路径，自动重连用例显式开启）、`host_room.time_scale`、`manager.sweep_interval/heartbeat_timeout/takeover_stale`。

### 存储用例（test/test_store.gd，2026-11-20）

- server/store.gd 单文件追加日志库的独立快套件：分数/留档跨实例持久、进行中房间快照落盘与摘除、日志压实、崩溃残行自愈（尾部半行截断 + 自愈重写）、旧版 store.json 自动迁移。

### 组件用例（test/test_components.gd）与主流程用例（test/test_flow.gd）

- **组件用例**：每个可复用组件独立断言功能——CardWidget（角标/花色着色/牌背）、SeatPanel（统一尺寸/set_info/悬停信号）、InfoSidebar（统计行灰显/局面/主牌牌面/菜单信号）、UiStyle（半字号内边距）、CrownBadge+DashedRoundedFrame（绘制不崩/早退分支）；以及**关联用例**（组件↔控制器接线）。
- **组件规范联动**：组件行为/尺寸变更必须同步断言——防止"组件一处改、实例各自坏"。
- **主流程用例**：两条端到端主线，人类动作一律走真实 UI 提交方法（与点击同一信号链）、AI 走引擎直驱：自己叫主主线 / 其它叫主主线（含庄位轮换）。
- 新增组件/主流程时同步补对应用例。
