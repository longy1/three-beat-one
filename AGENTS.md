# 三打哈（三打一）项目规范

> 本文档是本仓库的开发规范与协作约定。**随实现演进及时更新**——任何行为、结构、流程变更后，须同步修订对应章节。
> 规则依据：《三打哈规则.md》（唯一规则依据）；里程碑与技术决策：《三打哈-Godot工程计划.md》。

## 1. 项目概述

湘西扑克**三打哈（三打一）**的 Godot 单机版：1 名人类玩家（甲，座位 0，牌桌下方）对 3 名电脑玩家（乙/丙/丁）。

- **已完成**：M1 规则引擎（牌/牌型/跟杀垫/一轮结算）、M2 单机完整对局（拍卖→叫主→翻底扣底→逐轮出牌→抠底→分级收益→庄位轮换）+ 贪心 AI + 牌桌 UI
- **待启动**：M3 AI 强化与胜率分析（蒙特卡洛）、M4 联机对战、M5 部署上线

## 2. 技术栈与环境

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2** stable（编辑器位于 `S:\Program\Godot\`，用户级环境变量 `GODOT_PATH` 已指向主程序） |
| 语言 | GDScript（无 C#）；渲染 gl_compatibility（兼容桌面/移动/Web） |
| 依赖 | 无第三方插件、无外部美术素材（全部程序化绘制） |
| 测试 | 自研轻量框架（`tests/test_framework.gd`），headless 运行 |

常用命令（在本仓库根目录执行）：

```bash
# 单元/规则测试（全部通过退出码 0）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd

# UI 冒烟（headless 自动打完一整局，约 1 分钟，退出码 0）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tests/smoke_ui.gd

# 导入校验（改了脚本/场景后先跑）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# 打开游戏窗口
S:/Program/Godot/Godot_v4.7.2-stable_win64.exe --path .
```

**每次改动后的验证顺序**：`--import`（无脚本错误）→ `run_tests.gd`（全绿）→ `smoke_ui.gd`（若动了 UI/引擎流程）。

## 3. 目录结构

```
core/     纯逻辑层（禁止出现任何 Node/场景依赖）
  card.gd          Card：牌表示、84 张牌堆、分牌分值（规则 1、8.1）
  trump.gd         TrumpInfo：主花色+常主 R；3.1 牌力全序；常主脱离花色（3.3）
  combo.gd         Combo：单/对/拖拉机识别、6.2 邻接链、6.3 比较与四王特例
  follow_rule.gd   FollowRule：7.2 跟/杀/垫判定（含两处强制项）；着法枚举
  trick.gd         Trick：一轮结算（支持 1~4 份部分结算，B.2）
  game.gd          GameEngine：对局状态机（拍卖/叫主/扣底/出牌/抠底/结算/庄位轮换）
  ai_policy.gd     AiPolicy：电脑玩家贪心策略（叫分概率衰减分布/叫主/扣底/出牌）
scripts/  表现层脚本
  game_table.gd    牌桌控制器：转发引擎信号 ↔ UI；人类输入；动画（皇冠、Toast）
  card_widget.gd   CardWidget：程序化卡牌控件
  crown_badge.gd   CrownBadge：程序化皇冠（庄家标记动画）
  dashed_frame.gd  DashedRoundedFrame：手牌分区圆角虚线框
  main_menu.gd     主菜单（自检按钮进程内复用 tests/ 用例）
scenes/   main_menu.tscn / game_table.tscn
tests/    test_framework.gd + test_*.gd（8 套件 58 用例）+ run_tests.gd + smoke_ui.gd
docs/     ui-mockup.svg（界面区域图视觉稿，布局变更须同步更新）
```

`.uid` 文件由 Godot 生成，**必须与对应 `.gd`/`.tscn` 一同提交**；`.godot/`、`.zcode/` 已忽略。

## 4. 架构规范

1. **纯逻辑与表现严格分离**：`core/` 内的类只依赖彼此与 `RefCounted`，不引用 Node/SceneTree/UI。联机阶段服务端可直接复用 `core/`。
2. **引擎不信任调用方**：`GameEngine` 所有 `submit_*` 方法自行校验（阶段、座位轮次、合法性、底牌可见性），非法操作返回判定字典且不改变状态。UI/AI 永远不绕过校验。
3. **信号驱动 UI**：引擎通过信号（`auction_required/trump_required/discard_required/play_required/trick_settled/game_over/phase_changed`）通知 UI，`game_table.gd` 只做呈现与输入转发；AI 行动统一走 `_run_ai()`（0.7s 节奏 Timer）。
4. **规则出处可追溯**：`core/` 注释标注规则文档章节号（如「规则 7.2.2」「8.2」）；改动规则实现必须先核对规则文档，若发现文档笔误，以公理为准实现，并把笔误登记到《三打哈-Godot工程计划.md》的"M1 实施记录"（已有 3 处：♣66 不存在、A.4 漏计 ♠10、A.6 漏计 ♠5）。
5. **结算快照**：引擎保留 `last_trick`（上轮出牌快照，供结算后 UI 停留 1 秒展示）与 `trick_history`（全部轮次，供座位牌堆悬停查看）；新一轮领出时清除 `last_trick`。
6. **多局会话**：`start_session(seed)` 种子化发牌；`start_session_with_deal()` 为测试钩子（注入手牌+底牌）；庄位轮换规则 4 在 `start_next_game()` 内实现。

## 5. GDScript 编码规范（本仓库实践）

- **类型推断陷阱**：`Dictionary`/无类型 `Array` 取值、引擎信号携带的 Variant **不能用 `:=` 推断**，必须显式标注（`var x: int = dict.field`）。历史 bug 多源于此，code review 重点。
- **不覆盖 `Object.to_string()`**（Godot 视为警告级错误）：Card/Combo 用 `label()`。
- 方法调用带括号：`c.points()` 而非 `c.points`（后者得到 Callable，运算时报错）。
- 数组推导式内不要嵌套 `%` 格式化等复杂表达式（解析器不支持），改用显式循环。
- 常量数组/实例：`const` 不能含 `Card.new()` 调用，用实例变量。
- 静态工厂优先：`CardWidget.create()`、`Combo.detect()` 等静态构造；策略函数全部 `static`（AiPolicy 共享 `static var rng`，`_static_init` 中 randomize）。
- 注释与文档字符串用中文，函数头 `##` 说明职责与规则依据。
- 命名：类名 PascalName；私有成员 `_` 前缀；信号回调 `_on_<signal>`。

## 6. UI 布局规范

- **固定优先原则（2026-11-16 确立）**：桌面区域、手牌区先固定；操作按钮/提示等临时 UI 在**各自的固定槽位**内显隐（悬浮式），**禁止用可变高度容器（VBox 堆叠）承载会增减的行**——历史上按钮出现曾推挤手牌跳动。
- **相对长度原则**：节点定位用 0~1 比例 anchors（勿写死像素）；动态出牌/动画位置用相对常量（`TRICK_ANCHORS`/`CROWN_TARGETS` 为 0~1 Vector2，渲染时 ×层尺寸）。卡牌等控件以 720p 设计分辨率定义基准尺寸，`canvas_items` 拉伸模式保证任意窗口整体等比缩放。
- **两大区域（2026-11-16 确立）**：画面分为**主牌桌区域**（x 0~82.8%，`MAIN_TABLE_CENTER` 为其几何中心）与**侧信息板区域**（82.8%~100%，InfoSidebar）；皇冠动画必须在主牌桌区域正中央出现。区域名称标注于视觉稿。
- **半字号留空原则（2026-11-16 确立）**：所有文字与其最近的边框（面板边、按钮边）四向留空 **≥ 字号的一半**。落实方式：按钮统一走 `UiStyle.pad_button()`（content margin = 字号/2）；面板在 tscn 中用 StyleBoxFlat `content_margin_*` 落实（InfoSidebar 8 / SeatPanel 9 / ResultPanel 15，≈ 各自最大字号的一半）。豁免：无边框裸文字（Toast/提示行/顶栏标签）、卡牌角标（扑克角标贴角为惯例设计）。
- **组件复用**：三家电庄信息框复用 `SeatPanel` 组件（scenes/seat_panel.tscn，悬停牌堆信号内置）；右侧信息栏为独立组件 `InfoSidebar`（scenes/info_sidebar.tscn，与牌桌场景解耦，菜单/统计/局面走其 API）。**组件应自带统一尺寸**（`custom_minimum_size`，如 SeatPanel 180×100），实例只锚定位置、不各自拉伸——改尺寸只改组件一处。
- **对称十字出牌位**：四家出牌围绕牌桌中心对称——你=下方（0.419,0.55）、丙=信息板正下方（0.419,0.267）、丁=面板右侧（0.234,0.408）、乙=面板左侧（0.604,0.408）。
- 设计分辨率 1280×720（stretch canvas_items / keep），统一 12px 边距。
- 区域划分见 [docs/ui-mockup.svg](./docs/ui-mockup.svg)（布局改动先改视觉稿再施工）：
  - 顶栏（局数/出牌庄/叫分）；**抓牌庄家不展示**
  - 叫分提示显示在主牌桌正中央（BidCenterLabel，「叫分中（最高 X）」）；**不用「拍卖」一词**（非本土打牌用语）
  - 丙上带居中牌桌区；丁面板贴左缘；乙面板贴牌桌右缘（与丁关于牌桌中心对称）
  - 右侧信息栏（InfoSidebar）：**主牌提示 = 一张「正 R」牌面**（主花色+R，如 ♠ 主 R=2 → ♠2）；**未叫主态**：牌背微透明 + 居中问号 + 下方注明「未叫主」（顶栏不展示任何未叫主信息）；另有手牌统计 + 局面（捉分/累计）+ 主菜单按钮；下半为 M3 预留
  - 底部固定槽位：按钮 / 提示 / 手牌（双虚线框：左主牌右副牌，区内从大到小；叫主前王与 2 进左框）
  - 牌堆按钮左下（悬停查看出牌历史，旧→新）
- **手牌交互**：选中的牌**上浮牌高的 20%**（`SELECT_LIFT_RATIO`）；左键按住滑动可**批量选择相邻牌**（以首张的新态对齐滑过的牌）；出牌模式下**右键直接提交出牌**（引擎校验，非法 toast 提示原因）。选中态刷新走 `_card_widgets` 精准更新单张，禁止整排重建（闪烁/抖动）。
- 庄家标记 = 皇冠动画：拍卖结束从主牌桌区域正中央 ×4 出现，`TRANS_CUBIC EASE_OUT`（减速缩小）1s 飞至庄家名字旁停驻——**落点动态计算**：名字首字文字左缘前 4px、皇冠高度 = NameLabel 字号（`_crown_target()` 测量文字宽度）；人类 0 号位无面板用 `CROWN_TARGETS[0]` 常量。新局拍卖开始时清除。面板不用「·抓牌/·庄」文字。
- 一轮结算后牌面（含 ✓赢家）停留 1 秒再进入下一轮；末轮停留后才弹结算面板。
- 新增控件一律程序化绘制（参照 CardWidget/CrownBadge/DashedRoundedFrame），不引入图片素材。

## 7. 测试规范

- 新增/修改规则行为**必须带用例**；规则类改动对照规则文档章节写正反例。
- 套件清单需同步登记到 `tests/run_tests.gd` 与 `scripts/main_menu.gd`（自检按钮复用同一套用例）。
- AI 改动用两类测试守护：单项策略断言 + **30 局种子化自动对局不变量**（零非法着法、每局完整结束、捉分 ≤200+底牌分、收支守恒、compute_outcome 互检）。
- 特定规则路径优先用**注入迷你局剧本**（`start_session_with_deal`，如抠底 ×1/×2/庄赢不抠三剧本），不要写脆弱的整局剧本。
- 叫分等概率策略的断言用分布断言（400 次采样、固定 `AiPolicy.rng.seed`），断言相对关系而非精确值。

## 8. Git 与推送规范

- 提交信息：`类型: 中文摘要`，类型 ∈ feat/fix/ui/ai/docs/test/chore；一个主题一个提交。
- **推送流程**（github.com 直连经常被重置，push 可能失败）：失败时改走 gh CLI 的 Git Data API **逐字节复刻提交**（树 → 提交 → PATCH refs/heads/main），保证远端 SHA 与本地一致：
  1. `git ls-tree -r -z HEAD`（**必须 -z**，否则中文文件名被转义成乱码字面量——踩过坑）+ `git cat-file blob` 构造 tree payload
  2. `POST /git/trees`、`POST /git/commits`（作者/时间戳取自 `git cat-file commit HEAD`）
  3. `PATCH /git/refs/heads/main`，本地 `git update-ref refs/remotes/origin/main <sha>` 对齐
- 网络恢复后 `git push` 应显示无差异；若远端落后可随时用上述流程补推。

## 9. 文档同步要求（重要）

以下文档**必须随实现保持一致**，改动后逐项检查：

| 文档 | 触发更新的改动 |
|---|---|
| 本文档（AGENTS.md） | 目录结构、命令、编码/布局/测试/推送规范、AI 策略描述、UI 区域变化 |
| 三打哈-Godot工程计划.md | 里程碑状态、技术决策、实施记录、规则文档笔误清单 |
| README.md | 运行方式、玩法说明、目录结构、里程碑状态 |
| docs/ui-mockup.svg | 任何 UI 布局/区域变更（先改稿后施工） |

## 10. 已知简化与约束

- 人类固定 0 号位（甲）；基底分 B 固定 1；无悔棋/复盘/历史记录（规则文档第 3 节待定项）
- AI 无推理：叫分=概率衰减分布，出牌=贪心启发式（见 `ai_policy.gd` 头部策略概要）；M3 计划引入蒙特卡洛评估与候选打分
- 30 局自动对局中抠底极少出现（贪心庄家扣底常留主牌），8.2 路径由迷你剧本确定性覆盖
- 推送依赖 gh API 复刻流程（见第 8 节）
