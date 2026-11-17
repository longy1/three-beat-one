# 三打哈 — Godot 工程实现计划

> **状态：M1、M2 已完成（规则引擎 + 单机完整对局，77/77 用例全绿）；M3 待启动。**
> 规则依据与实现细节见 [AGENTS.md](../AGENTS.md) 与《三打哈规则.md》（本目录，含附录 A 推演、附录 B 决策流程）。
> 本文档汇集**已定的技术决策**与**里程碑状态**；本文件与规则文档分离维护：规则变更只改《三打哈规则.md》，工程计划变更只改本文件。

## 1. 已定技术决策

| 决策项 | 结论 |
|---|---|
| 游戏框架 | **Godot 4.7.2**（gl_compatibility 渲染，兼容桌面/移动/Web 导出） |
| 脚本语言 | **GDScript**（2026-11-16 确认；蒙特卡洛性能瓶颈出现时再评估迁移） |
| 架构 | 纯逻辑层（`core/`，不依赖场景节点，联机可复用）/ 表现层（`scene/` + `script/`）严格分离；完整编码/UI/测试/推送规范见 [AGENTS.md](../AGENTS.md) |
| 目录结构 | `core/` `scene/` `script/` `test/` `doc/` `static/`（目录名单数，详见 AGENTS.md 第 3 章） |
| 测试方案 | 自研轻量框架（`test/run_tests.gd` headless 入口，支持 async 用例，失败退出码非 0）；套件 = 规则/剧本/AI 不变量/组件/主流程/UI 回归；主菜单「自检」按钮复用同一套用例 |
| AI 叫分 | **期望收益查表模型**（2026-11-16）：蒙特卡洛校准（1260 局 AI 互搏，`test/calibrate_bidding.gd`）产出「叫分档 × 强度桶」收益表 `AiPolicy.BID_CALIB`；策略或环境变化后重跑校准更新 |
| MVP 范围 | **单机练习优先**：完整一局流程 + AI 对手 + 每张候选出牌打分/胜率分析 |
| 联机对战 | 第二阶段：Godot 高层多人 API（ENet/WebSocket），服务端可用 Godot headless 跑房间逻辑 |
| 托管 | 免费平台（Web 导出可放静态托管；游戏服务器免费层到联机阶段再核实） |
| 目标端 | 桌面 + 移动（含 Web 导出） |
| 接入方式 | ZCode 官方 Godot 插件（godot:cli / godot:setup），编辑器安装于 `S:\Program\Godot\`（用户级环境变量 `GODOT_PATH` 已指向其主程序） |

## 2. 里程碑

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 规则引擎 | 牌与牌型、邻接链、跟/杀/垫判定、一轮结算、并列规则——纯逻辑 + 单元测试 | ✅ 完成 |
| M2 单机对局 | 完整一局：庄位轮换、竞叫、叫主、翻底/扣底、逐轮出牌、末轮抠底、分级与收益 + EV 叫分 AI + 组件化牌桌 UI | ✅ 完成（77/77 用例 + UI 冒烟） |
| 工程重构 | 死代码清理、兜底代码根治、core/UI 模块拆分、架构守护测试、Web 导出与浏览器验收工作流、C/S 预留口子（见 doc/重构规范.md） | ✅ 完成（2026-11-16，82/82 用例 + 冒烟 + Web 浏览器验收） |
| M3 AI 出牌强化 | 蒙特卡洛评估、候选出牌打分；出牌技巧逐步教授后重跑叫分校准 | 待启动 |
| M4 联机对战 | 房间系统、状态同步、断线重连（口子已预留：submit_* 值匹配契约 + 信号复制通道 + AI 纯模块） | 待启动 |
| M5 部署上线 | 免费托管平台部署（静态托管 + 游戏服务端；Web 导出已就绪） | 待启动 |

## 3. 里程碑实施记录

### M1（2026-11-16）

- `core/`：card（84 张、分牌）、trump（3.1 全序、常主脱离花色）、combo（单/对/拖拉机、6.2 邻接链、四王特例）、follow_rule（7.2 跟/杀/垫 + 两处强制项：S 牌打尽与 S 对子优先、主牌打尽与常主对子优先）、trick（B.2 结算、并列先出者大、8.1 捉分）
- **实现中发现《三打哈规则.md》三处牌例笔误**（实现以规则公理为准，待规则维护者裁定是否修订）：
  1. 7.2.2 示例"♣55♣66"：6 已剔除，♣66 不存在（测试以 ♣77/♣1010 等价验证）
  2. A.4 称"本轮无分"：丁跟出的 ♠10 是分牌，按 8.1 轮内分应为 10（连带 A.7 合计）
  3. A.6 称"轮内分 20＋10 = 30"：遗漏丁垫出的 ♠5（5 分），按 8.1 应为 35

### M2（2026-11-16）

- `core/game.gd` 对局引擎（纯逻辑状态机，联机可复用）：竞叫（130 底叫/+5 倍数/封顶 200/放弃永久）、叫主（看底牌前）、翻底/扣底（底牌仅庄家可见）、逐轮出牌（复用 FollowRule 校验）、末轮抠底（单牌 ×1 / 对子·拖拉机 ×2）、分级（compute_outcome 纯函数）与收益（B=1，庄家净收/净付 3 份）、庄位轮换（规则 4）；种子化 RNG + 可注入牌型测试钩子
- `core/ai_policy.gd`：
  - 叫分 = **期望收益查表模型**（`BID_CALIB`，1260 局蒙特卡洛校准）：仅极强牌叫 130/150 为正期望，180/200 一律负期望；校准工具 `test/calibrate_bidding.gd` 可随出牌水平迭代重跑
  - 叫主：花色按张数/大牌/对子加权；R 选持有量最大（成对加成）
  - 扣底：副牌分牌优先入底，不扣常主；出牌：贪心（领最大牌型、能赢用最小、杀看分、垫喂队友）
- **规则修订（2026-11-16，用户裁定）**：R=A 时 A 为常主，**同花色的 A 对与 2 对相邻**——♣AA♣22（喊 ♠A）为合法拖拉机，且在其花色同类拖中排最小（主牌 AA22 < 主牌 7788）；不同花色常主组合仍非法、K~A 禁连不变。已同步规则文档 3.3/6.2/6.3 四处与引擎/用例
- UI：组件化（SeatPanel / InfoSidebar / CardWidget / CrownBadge / DashedRoundedFrame 程序化绘制）、主牌桌区域 + 侧信息板区域双区布局、居中规范（十字中心锚点）、手牌分区（左主右副，区内从大到小）、交互（点选/拖选/右键出牌、悬停牌堆/底牌）、结算面板
- 已知简化：人类固定 0 号位；B 固定 1；无复盘（第 4 节待定事项）；AI 出牌为贪心基线（M3 强化）

### 工程重构（2026-11-16）

全项目重构（执行规则见 **doc/重构规范.md**，四主题五提交 e48b7e9→a651557）：

- **死代码清理**：current_highest_seat / Combo.count / label / CardWidget.set_face_up 等零引用符号删除；测试助手沉淀 TestBase / UiTestBase 共享基类（C() 造牌 8 处重复、_spawn_table 三件套 2 处重复收敛）
- **兜底根治**（根因→修复→用例守护→删兜底）：
  - `_process` 0.5s 全量兜底轮询 → 根因是刷新三重触发无单一入口 → 收敛 `_refresh()` 唯一入口后删除（信号完整性由 test_ui 自动对局不变量守护）
  - submit 内「不得清理」竞态注释 → 根因是按钮生命周期无唯一所有者 → ActionBar 组件化（reset 幂等），按钮界面只由 *_required 处理器重建
  - settle 失败静默 seat=-1 死锁 → `engine_fault` 信号 + faulted 标记显性冻结（回归用例 test_settle_failure_is_loud）
  - 校验器/生成器镜像逻辑（_count_identity_pairs≡_identity_pair_count 等）→ FollowRule 公共口径合并
  - submit_play 引用匹配 vs submit_discard 值匹配的双契约 → 统一按值匹配（Card.key()），联机消息可直接映射
  - last_trick 镜像字段 → get_last_trick() 派生；bottom 双义 → kitty/buried 拆分；首帧兜底宽度 → HandArea 挂起渲染待布局就绪
- **模块拆分**：core 增 auction.gd（规则 5 子状态机）/ scoring.gd（规则 9/10 纯函数）/ ai_bidding.gd + ai_play.gd（纯策略，数据进/决策出），ai_policy.gd 收敛为单机门面；game_table.gd 1002→538 行，拆 HandArea / PileViewer / ActionBar / TrumpRankPicker / CrownAnimator 五组件
- **架构守护**：test_architecture.gd 固化为可执行检查（core 纯度禁依赖清单、AI 模块不引用引擎、submit_* 唯一写入口白名单）；套件注册单一事实源 suite_registry.gd
- **Web 导出与验收工作流**：Noto Sans SC 子集（tool/subset_font.py，8.3MB→227KB）+ theme/default.tres 项目默认字体；export_presets.cfg（Web，导出过滤排除 test/doc/tool）；主菜单 Web 特性守卫（隐藏退出/自检、自检动态加载）；导出→python http.server→内置浏览器截图验收的固定流程
- **信号时序不变式确立**：任何信号发出前状态必须完全就绪（_begin_game 先 auction.begin 再 _set_phase——phase_changed 同步到达 UI 时曾读到未初始化 bids）
- **M4 预留确认**：core 服务端可复用（零依赖机器守护）、submit_* 值匹配契约、信号唯一 UI 复制通道、AI 纯模块可独立调用——后续改动不得破坏（test_architecture.gd 守护）

### Web 验收闭环与规则 7.3（2026-11-17）

- **Web 导出验收闭环**（接续 2026-11-16 阶段 5 收尾）：
  - 根治「导出后主菜单按钮全部失灵」：`main_menu.gd` 顶部遗留 `const TestFramework := preload("res://test/test_framework.gd")`——test/ 已被导出过滤排除，静态 preload 使**整份脚本**在 Web 环境解析失败（_ready 不执行、按钮无处理器、无报错线索）。修复：test/ 一律运行时 `load()`（AGENTS.md §6 已固化为强约束）
  - 导出过滤器补 `build/*`（完整字体源与导出图标曾被误打进包，pck 7.9MB→301KB）
  - 导出模板安装位置（2026-11-17 起）：`S:\Program\Godot\editor_data\export_templates\4.7.2.stable`——编辑器启用 **self-contained 模式**（exe 旁 `._sc_` 标记文件），编辑器数据目录从 `%APPDATA%\Godot` 改为安装目录；模板随目录迁移，editor_settings-4.7.tres 一并复制保持连续（工程内 build/_templates 缓存已删；注意 4.7.x 数据目录是 `editor_data/` 子目录）
  - 验收方法学沉淀：IAB 隐藏页面（document.hidden）会停摆 rAF → Godot 主循环冻结、计时器不走、CDP 输入注入失效；验收 harness 用 setTimeout 垫片驱动 rAF + 引擎启动前固定 canvas 尺寸 + CDP 截图页面内解码，实现隐藏页内的完整对局验收（主菜单守卫/全分区渲染/整局推进均通过）
- **规则 7.3 增补（无主公示与主牌甩打）**：主牌轮垫牌公示【无主】；领出者外三家均无主时可一次甩出任意张主牌单牌（等同连续单张，末轮抠底 ×1）。引擎 trump_void_seats 公示状态 + FollowRule.is_trump_dump/is_legal_dump_follow + Trick.settle 甩打分支 + AiPlay 甩打轮垫牌；AI 不主动甩打（贪心基线），引擎路径由六类迷你剧本确定性覆盖
- **交互改进**：底牌入手即选中（select_cards(engine.kitty)，扣底 8 张拿起态便于观察）；选牌跨轮保留（begin_select 仅模式切换清空 + consume_selected 移除已打出）；主牌区牌力并列的副R/副2 按 ♠→♥→♣→♦ 同花色相邻分组；翻底「底牌（仅你可见）」面板改点锚居中（程序化 PanelContainer + 半字号留空）
- 用例 82→100（+18：甩打/公示引擎 6、FollowRule/Trick 单元 3、AiPlay 甩打垫牌 2、组件 4、UI 集成 2、AI 不变量并入）

## 4. 待定事项清单（联机前需定）

- 每步操作超时时长与托管策略（超时自动跟牌/过）
- 断线重连后能否查看本局历史
- 房间机制：房主建房、加入方式（链接/口令）、是否允许观战
- 复盘功能（含扣底/手牌可见性）
- 多局累计赛制（session 积分榜）
