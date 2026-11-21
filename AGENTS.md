# 三打哈（三打一）项目规范

> 本文档是本仓库的**总体规范与协作约定**。**随实现演进及时更新**——任何行为、结构、流程变更后，须同步修订对应章节。
> **编码类规范已拆至 [doc/coding.md](./doc/coding.md)（架构 / GDScript / Godot 最佳实践 / UI 布局 / 测试，仅编码任务时查阅）**。
> 规则依据：[doc/三打哈规则.md](./doc/三打哈规则.md)（唯一规则依据）；里程碑与技术决策：[doc/三打哈-Godot工程计划.md](./doc/三打哈-Godot工程计划.md)；**重构类任务执行 [doc/重构规范.md](./doc/重构规范.md)**（兜底代码根治协议、模块拆分原则、HTML 导出验收工作流、C/S 预留约定）；代码变更史归档：[doc/update.md](./doc/update.md)（代码注释禁更新记录，doc/coding.md §2）。
> **代码引用文档一律用短令牌**（[规N]/[码N]/[构N]/[史]/[划N]，禁止写路径）——解码表见 §5 文档同步要求。

## 1. 项目概述

湘西扑克**三打哈（三打一）**的 Godot 单机版：1 名人类玩家（甲，座位 0，牌桌下方）对 3 名电脑玩家（乙/丙/丁）。

- **已完成**：M1 规则引擎（牌/牌型/跟杀垫/一轮结算）、M2 单机完整对局（拍卖→叫主→翻底扣底→逐轮出牌→抠底→分级收益→庄位轮换）+ 贪心 AI + 牌桌 UI；2026-11-16 完成全项目重构（死代码清理、兜底根治、core/UI 模块拆分、Web 导出与浏览器验收工作流）；2026-11-17 Web 验收闭环（根治静态 preload 致导出脚本失效）+ 规则 7.3（无主公示/主牌甩打）+ 交互改进（底牌入手即选中、选牌跨轮保留、主牌副花色分组排序）；2026-11-18 完成 M4 联机对战（C/S 架构：无头 Godot 服务器 + WebSocket + 可见性裁剪同步 + 超时托管 + 断线重连，见 doc/coding.md §1.10~12）+ 同日断线重连闭环（客户端自动重连等待弹层、服务端 180s 宽限 + 旧连接复活 + 离线快托管、底牌浮层层级修正）；2026-11-20 完成 TODO 批次（闲家垫牌守门按庄家剩牌量动态放宽、重连身份令牌化 + 占用文案、
  服务端进程重启不散房、存储升级单文件追加日志库、发牌动画、叫分对话气泡、设置面板、
  双击清选/两指出牌、联机菜单最近成功连接）；2026-11-21 完成牌桌表现层批次二
  （牌背程序化花背重绘、主牌标识守卫自愈、发牌逐张入手 + 排序同长平移 + AI 叫分
  挂起至排序完成、气泡尖角贴面板、手机版 UI 布局与调试入口）
- **待启动**：M3 AI 强化与胜率分析（蒙特卡洛）、M5 部署上线（联机服务器公网部署）

## 2. 技术栈与环境

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2** stable（编辑器位于 `S:\Program\Godot\`，用户级环境变量 `GODOT_PATH` 已指向主程序） |
| 语言 | GDScript（无 C#）；渲染 gl_compatibility（兼容桌面/移动/Web） |
| 依赖 | 无第三方插件、无外部美术素材（全部程序化绘制）；**唯一例外：字体**——中文 UI 打包 Noto Sans SC 子集（OFL，Web 无系统字体回退所必需）；**联机存储**：本地单文件追加日志库 `user://sanhax_server/store.jsonl`（纯 GDScript 无第三方依赖，SQLite 平替定位：变更追加 op 行 + 启动回放 + 快照压实 + 崩溃残行自愈；旧 store.json 首次载入自动迁移） |
| 测试 | 自研轻量框架（`test/test_framework.gd`），headless 运行；支持并行分片与受影响套件选择（见下方命令） |

常用命令（在本仓库根目录执行）：

```bash
# 单元/规则测试（顺序全量，约 100s；全部通过退出码 0；当前 14 套件 164 用例，含联机回环与存储套件）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s test/run_tests.gd

# 并行全量（push 前必跑；分片并发墙钟 ~25s，分片数默认 = 逻辑核数封顶 8，可 N=6 覆盖）
bash test/run_tests_parallel.sh

# 受影响测试（本地 commit 前跑：按改动文件映射套件，改动面大自动转并行全量；基线可传 HEAD~1 等）
bash test/run_affected.sh

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

# 导出联机服务器 pck（preset "Server"；Linux 无头运行时经 gs/ 分片进部署 stage）
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Server" build/server/server.pck

# 本地静态服务（导出后浏览器打开 http://127.0.0.1:8765 验收）
cd build/web && python -m http.server 8765

# 公网试玩站部署/重部署 + 云端验收：走 .agents/skills/zsite-deploy 技能（SKILL.md 全流程：
# 导出/组包/本地 check/部署/云端探针；部署基建单源在技能 assets/，stage 是生成物；平台限制
# 与导出模板二进制的坑见技能 references/gotchas.md；2026-11-18 上线 https://three-beat-one-v425.zai.site）
.agents/skills/zsite-deploy/scripts/build-stage.sh                          # 导出 Web/Server + 组装 stage
.agents/skills/zsite-deploy/scripts/zsite-cli.sh check .zcode-site/stage    # 本地全栈验证
.agents/skills/zsite-deploy/scripts/zsite-cli.sh deploy .zcode-site/stage   # 部署（首建加 --new --name --prefix）
```

> **部署须用户明确要求才执行**（「部署/上线/重新发布/更新站点」等指令）：本地 `--export-release "Web"` +
> 本地 serve 的浏览器验收只是验证环节，**不等于部署**，验证流程照常做，但绝不自动触发 deploy。

**每次改动后的验证顺序**：`--import`（无脚本错误）→ `bash test/run_affected.sh`（本地 commit 前必跑；改动面大自动转并行全量）→ `smoke_ui.gd`（若动了 UI/引擎流程）→ **push 前跑 `bash test/run_tests_parallel.sh` 并行全量** → **Web 导出 + 浏览器截图验收**（若动了视觉/布局/字体）。本地提交与 push 的约定见第 4 节。

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
                   只持有本人手牌 + 公开回放，隐藏信息不可推导（doc/coding.md §1.10）
script/   表现层脚本（按模块划分子目录；ui_style.gd 为跨模块共享规范工具）
  table/       牌桌模块：game_table.gd 控制器 + hand_area 手牌区 / pile_viewer 牌堆弹层 /
               trick_history_panel 出牌历史 / action_bar 操作按钮条 / trump_rank_picker 叫主面板 /
               crown_animator 皇冠动画 / trump_reveal 揭主双飞 / card_widget 卡牌 / crown_badge 皇冠 /
               void_stamp 无主印章 / dashed_frame 虚线框 / seat_panel 座位面板 / info_sidebar 信息栏 /
               bid_bubbles 叫分对话气泡 / deal_animator 发牌动画
  menu/        界面流程模块：main_menu 主菜单 / online_menu 联机入口 / room_lobby 房间大厅 /
               scores_dialog 累计分数弹层 / reconnect_overlay 断线等待重连弹层 /
               settings_dialog 游戏设置弹层
  app_settings.gd  AppSettings：游戏设置单一事实源（主牌框左右/排序方向/手机版 UI 调试开关，ConfigFile 持久化）
  ui_style.gd  UiStyle：跨模块共享的布局锚点常量（MAIN_TABLE_CENTER）与半字号按钮留空
scene/    场景（与 script/ 子模块一一对应）
  table/       game_table.tscn（内引 seat_panel/info_sidebar 子场景与牌桌组件脚本）
  menu/        main_menu.tscn / online_menu.tscn / room_lobby.tscn
font/     NotoSansSC-Regular.subset.otf（中文子集 ~230KB；重生成走 tool/subset_font.py）
theme/    default.tres（项目默认字体主题，project.godot gui/theme/custom 引用）
tool/     subset_font.py（字体子集化脚本；文案新增字符后重跑）
test/     test_framework.gd + test_base.gd/ui_test_base.gd（共享基类）+ suite_registry.gd（套件注册单一事实源）
          + test_*.gd（14 套件 164 用例，含 test_architecture.gd 架构守护、test_online.gd 联机回环、
          test_store.gd 存储套件）+ run_tests.gd + smoke_ui.gd
          + calibrate_bidding.gd（叫分校准工具，独立 -s 入口）
doc/      三打哈规则.md（唯一规则依据）、三打哈-Godot工程计划.md、重构规范.md、coding.md（编码规范，编码时查阅）、update.md（代码变更史归档）
static/   ui-mockup.svg（界面区域图视觉稿，布局变更须同步更新；含 .gdignore 不参与引擎导入）
build/    导出产物（不入库；_font_src/ 为字体源本地缓存；导出模板在编辑器安装目录 S:\Program\Godot\editor_data\export_templates\，self-contained 模式由 exe 旁 ._sc_ 标记启用）
```

`.uid` 文件由 Godot 生成，**必须与对应 `.gd`/`.tscn` 一同提交**；`.godot/`、`.zcode/`、`build/` 已忽略；`export_presets.cfg` **入库**。根目录 `TODO.md` 为迭代想法 backlog（按模块分节、复选框管理，使用约定见文件头；负向结论/失败迭代不走这里，归工程计划与 update.md）。**@TODO.md 的消息默认只是记录**（把想法写入对应分节即完成，不展开实现）；仅当用户明确要求实现/动手时才开工。**换行符约定**：仓库与工作区一律 LF，由 `.gitattributes` 强制（`* text=auto eol=lf`；bat 按 `-text` 保持仓库原样、字体/二进制显式标记），本仓库本地 `core.autocrlf=false`/`core.eol=lf`——Windows 默认 autocrlf=true 会在 checkout 注入 CRLF 与 AI 写盘的 LF 打架，禁止改回。

**命名规范：目录名一律用单数**（core / doc / font / scene / script / static / test / theme / tool），不用复数；新增目录同样遵守。静态设计资产放 static/（含 .gdignore，不参与引擎导入）。

架构 / GDScript / Godot 最佳实践 / UI 布局 / 测试等编码规范见 [doc/coding.md](./doc/coding.md)。

## 4. Git 与推送规范

- 提交信息：`类型: 中文摘要`，类型 ∈ feat/fix/ui/ai/docs/test/chore/refactor；一个主题一个提交。
- **本地提交约定（2026-11-19）**：日常开发改动完成即按主题**本地 commit**（无需用户指示），**默认不 push**；push 仅在用户显式要求（「push/推送/推远端」）时执行。push 前必须先 `bash test/run_tests_parallel.sh` 并行全量确认全绿（本地 commit 前只需 `bash test/run_affected.sh` 受影响测试）。
- **推送流程**（github.com 直连经常被重置，push 可能失败）：失败时改走 gh CLI 的 Git Data API **逐字节复刻提交**（树 → 提交 → PATCH refs/heads/main），保证远端 SHA 与本地一致：
  1. `git ls-tree -r -z HEAD`（**必须 -z**，否则中文文件名被转义成乱码字面量——踩过坑）+ `git cat-file blob` 构造 tree payload；**blob 一律 base64**（树里有字体/图标/GBK bat 等二进制）
  2. `POST /git/trees`、`POST /git/commits`（作者/时间戳取自 `git cat-file commit HEAD`；**时区要 ISO 带冒号 `+08:00`**；**message 必须带尾随 `
`**——git 规范，缺了 API 提交 sha 会与本地不一致）
  3. **校验铁律（2026-11-18 踩坑）**：`POST /git/trees` 返回 sha 必须等于本地 `git rev-parse HEAD^{tree}`，`POST /git/commits` 返回 sha 必须等于本地 `git rev-parse HEAD`——任一不等**立即中止并报告**，禁止拿不一致的 sha 改引用（曾因 API 树与本地树不一致 + 盲目 `reset --hard` 把 main 回退一个提交，最终以 cherry-pick 恢复 + 直连重试收场）
  4. 校验通过后 `PATCH /git/refs/heads/main`，本地 `git update-ref refs/remotes/origin/main <sha>` 对齐
- 网络恢复后 `git push` 应显示无差异；若远端落后可随时用上述流程补推。

## 5. 文档同步要求（重要）

**文档引用令牌（代码注释引文档的唯一合法形式）**：代码注释需要指向上游文档时用下列短令牌、**禁止写路径**——路径只存在于本表（文档改名/搬迁只改注册表一处）；代理每次会话自动加载本文档即持有解码表，读代码见令牌即可查此表定位；人类开发者从本文件/README 头部一行进入。`test_doc_tokens_valid` 机器守护：未注册令牌或悬空节号即红。

| 令牌 | 指向 | 说明 |
|---|---|---|
| [规N] | doc/三打哈规则.md 第 N 节 | 规则出处（如 [规7.3]；自然语言「规则 7.3」仍可，令牌为显式形式） |
| [码N] | doc/coding.md §N | 编码规范：1 架构 / 2 GDScript / 3 Godot 最佳实践 / 4 UI 布局 / 5 测试 |
| [构N] | doc/重构规范.md §N | 重构任务规则（裸令牌 [构] = 全文；如 [构7] 联机预留约定） |
| [史] | doc/update.md | 变更史（仅裸令牌，按日期归档；代码注释禁更新记录的唯一出口） |
| [划N] | doc/三打哈-Godot工程计划.md §N | 技术决策 / 里程碑实施记录 |

以下文档**必须随实现保持一致**，改动后逐项检查：

| 文档 | 触发更新的改动 |
|---|---|
| 本文档（AGENTS.md） | 目录结构、命令、推送规范、AI 策略描述、已知简化与约束 |
| doc/coding.md | 架构原则、GDScript/Godot 编码实践、UI 布局、测试规范（编码任务先读，改完核对） |
| doc/三打哈-Godot工程计划.md | 里程碑状态、技术决策、实施记录、规则文档笔误清单 |
| doc/update.md | 任何原本会写进代码注释的日期戳/变更记录内容（新条目置顶；代码注释禁更新记录，doc/coding.md §2） |
| doc/重构规范.md | 兜底白名单/拆分原则/验收工作流的演进（重构任务结束后核对） |
| README.md | 运行方式、玩法说明、目录结构、里程碑状态 |
| TODO.md | 迭代想法随手记录（backlog，无实现同步义务；负向结论/失败迭代不走这里，归工程计划与 update.md） |
| static/ui-mockup.svg | 任何 UI 布局/区域变更（先改稿后施工） |
| .agents/skills/zsite-deploy/ | 部署流程/部署基建（assets 单源）/平台与引擎坑（gotchas）演进 |

## 6. 已知简化与约束

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
    **按庄家剩牌量动态放宽（2026-11-20）**：剩牌 >16 全量避让 / 9~16 只避队友深清（≥4 张）的门 /
    ≤8 守门解除自由垫牌（`_guard_avoid_suits`；banker_cards 经 choose_play 新参传入，
    缺省 -1 未知保持全量口径）；
    垫牌并按花色顶牌牌力分级（`_suit_classes`）：顶 ≤10 无赢张的门尽早清理，顶 J/Q 中性，
    含 K/A 的门更多保留——分级优先于守门避让与逐张牌力（弱门无守门价值），分牌保护仍最优先
  - 闲家无主垫牌（2026-11-18 迭代）：**无主时 5 与无分牌同档尽早甩出**（无赢张价值，
    留 5 意义不大；有主闲家与 feed 喂分档位不变）；**聚焦清一门** `_defender_focus_suit`——
    选队友已垫大牌（≥K）且本家顶 ≤Q（自己握赢张的门保留作捕获门）的副花色整门最先清，
    守门避让对该门失效（无主守门不成立），此后该门领出全是自由垫牌机会
  - 队友无主后的垫牌（2026-11-18 迭代）：闲家有主但队友已公示无主时，主牌集中在我与
    庄家手中——庄家领主逼牌必抽走小分主、拿分主杀也会被更大的主盖掉 → **主牌分降为
    可垫档**（`build_discard` mate_void 通道），无分大牌主（A/2/王等）照旧最后保留；
    feed 喂分档位不变
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
  庄家胜率 40%→37% 基本守恒；2026-11-18 复跑校准验证（4200 局满格）：出牌层自 83cb294
  换表后零改动、24 格差异均在采样噪声内 → 基线无漂移、表维持不动（详见工程计划复跑记录）
- 推送依赖 gh API 复刻流程（见第 4 节）
- Web 导出本地 serve 验收照旧；另有 ZCode Sites 公网试玩站（2026-11-18，命令见第 2 节）：
  平台只暴露一个端口 → 单 Node 进程分流三服务（`/` 游戏；`/files/` 只读文件浏览/下载，
  浏览根限部署包 `/app` 与运行数据 `/data`；WebSocket Upgrade 代理到同实例 Godot 无头联机
  服务器 127.0.0.1:9080 子进程，server.mjs 守护重启）；`index.wasm` 预 gzip 成 `index.wasm.gz`
  与 Linux 模板分片（gs/*.part）规避平台单文件 ≤25MB；客户端 Web 端联机地址自动预填
  `wss://<当前站点>`（online_menu.gd，手动输入 host[:端口]/ws(s):// 照常可用）；
  **链接公开、文件浏览无令牌**，任何人可浏览下载容器文件（容器为临时沙箱、不存机密，用户定夺）；
  长连接实测 400s+ 稳定（应用层 5s 心跳保活；平台文档称请求 300s 超时，实测只作用于空闲连接）；
  房间与累计分随实例 /data 存亡（实例回收即丢）；独立公网服务器部署仍归 M5。联机浏览器验收覆盖
  引导/入口/渲染/字体与客户端校验路径，**文本输入流程需真实键盘**（Godot Web 对合成输入免疫，见
  doc/coding.md §3）——桌面双实例人工验收含完整联机流程
- **联机（M4）已知简化**：反作弊止步于可见性裁剪（不下发隐藏信息；服务端逻辑仍可被逆向，定位为本地/可信小服）；**服务端进程重启不散房（2026-11-20）**：进行中房间全量落盘（成员含会话令牌 + 引擎状态），启动恢复——成员离线、令牌保留、宽限计时与待办回合重挂，客户端自动重连凭令牌回房续打；**重连身份 = 会话令牌（2026-11-20）**：客户端每实例生成、hello 必带，token 命中存活房间成员即回房（在线成员不可被同昵称顶座——同昵称无令牌提示「该昵称已在其他设备登录」）；**掉线不立即释放**：宽限期内随房间保留（同令牌回房；离线成员同昵称可承接——覆盖应用重启/页面刷新丢令牌的合法回归；旧连接任意消息复活覆盖断连未被扫出的窗口期），房间解散/主动退出或未进房连接静默清理后才释放复用，不持久化（旧版全局注册制已废）；断线重连闭环参数：心跳判定 60s / 离线宽限 180s / 离线座位回合 5s 快托管 / 客户端重试 3s × 150s 窗口；无复盘、无观战、无操作时长配置化
- **牌桌表现层批次（2026-11-20）**：发牌动画为纯表现层（开局/下一局播放、重连快照不播；期间
  `_render_hand` 挂起、动画结束统一放行，不阻塞对局逻辑）；叫分气泡只展示当前最高叫分
  （低分被更高分取代即消失、放弃气泡保留到拍卖结束；状态驱动幂等 apply，重连恢复同路径生效）；
  设置两项仅影响呈现（主牌框在左/右、牌序从大到小/从小到大，花色分组从左到右不变；
  AppSettings 即时保存 user://settings.cfg）；双击空白清空选择、触屏两指单击出牌
  （首指按下即快照选择，恢复快照撤销触摸模拟点选副作用）；联机菜单「最近成功连接」
  连接成功即记录（去重置顶、封顶 5 条）
- **牌桌表现层批次二（2026-11-21）**：牌背去「哈」字改程序化经典花背纹样（CardBackPattern：
  内框 + 45° 菱形格纹 + 中央徽章，`CardWidget` 移除 back_mark，零素材约束维持）；信息栏主牌
  标识守卫自愈（`_refresh_top_bar` 以 `engine.trump != _last_trump_shown and not
  _trump_reveal.active` 放行——揭主落位回调渲染，飞行被 clear() 打断时 active 复位自愈重渲，
  根治标识消失）；发牌动画逐拍一张（TICK 0.2s/张：3 背面飞闲家 + 1 背面飞入我方汇聚槽，
  落位翻正现身），展开前按目标位 x 升序重排 z、各牌同长平移（途中遮盖与排序后一致）；
  拍卖表态挂起至排序完成（`_on_auction_required` 动画期仅状态刷新，`_on_deal_done` 按引擎
  当前轮转补跑；下一局/game_start 先置 `_deal_active` 再触发引擎信号）；叫分气泡尖角贴近
  玩家面板（面板缘 6~12px）；手机版 UI（移动端特性 android/ios/web_android/web_ios 自动
  启用 + 设置「手机版 UI（调试）」PC 入口）：手牌区 ≈90% 屏宽（BottomArea 右缘 -128）、
  信息栏默认收起右上角按钮展开浮层，桌面版不变
