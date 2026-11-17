# 三打哈（三打一）

湘西扑克游戏**三打哈（三打一）**的 Godot 工程：单机（1 人对 3 电脑）+ 联机对战（C/S 架构，4 人房间可电脑补位）。

- **项目规范**：[AGENTS.md](./AGENTS.md)（架构/编码/UI/测试/推送/Godot 最佳实践约定，随实现同步更新）
- **重构规范**：[doc/重构规范.md](./doc/重构规范.md)（兜底代码根治协议、模块拆分原则、HTML 导出验收工作流、C/S 预留约定）
- 规则唯一依据：[doc/三打哈规则.md](./doc/三打哈规则.md)（含附录 A 完整推演、附录 B 单轮决策流程）
- 技术决策与里程碑：[doc/三打哈-Godot工程计划.md](./doc/三打哈-Godot工程计划.md)

## 技术栈

| 项目 | 设定 |
|---|---|
| 引擎 | Godot 4.7.2（gl_compatibility 渲染，兼容桌面/移动/Web） |
| 语言 | GDScript |
| 字体 | Noto Sans SC 子集（OFL，`font/`；文案变更后 `tool/subset_font.py` 重生成） |
| 规则引擎 | `core/` 纯逻辑类（零 Node/场景/时序/IO 依赖，test_architecture.gd 机器守护），单机与联机服务端共用 |

## 目录结构

```
core/     规则引擎与 AI：card / trump / combo / follow_rule / trick /
          auction（叫分拍卖）/ scoring（分级收益）/ game（对局状态机编排）/
          ai_bidding（EV 叫分）/ ai_play（贪心出牌）/ ai_policy（单机门面）
net/      联机客户端：protocol（消息契约/座位旋转）/ net_client（连接/心跳/重连/场景路由）/
          table_view（可见性裁剪的对局视图状态，信号面与引擎同构）
server/   联机服务端（桌面源码运行，Web 包排除）：server_main 入口 / room_manager 连接中枢 /
          host_room 权威房间（AI 直调纯模块 + 超时托管 + 离线宽限重连）/ store 持久存储（JSON）
script/   表现层脚本（按模块划分子目录）
  table/       牌桌模块：game_table 控制器 + hand_area / pile_viewer / action_bar /
               trump_rank_picker / crown_animator / trump_reveal / card_widget / seat_panel /
               info_sidebar / crown_badge / void_stamp / dashed_frame / trick_history_panel
  menu/        界面流程模块：main_menu / online_menu 联机入口 / room_lobby 房间大厅 /
               scores_dialog 累计分数弹层
  ui_style.gd  跨模块共享的 UI 规范常量与按钮留空
scene/    场景（与 script/ 子模块对应）：table/ 牌桌场景；menu/ 主菜单与联机流程场景
font/     中文字体子集（Web 导出必需：浏览器无系统字体回退）
theme/    default.tres 默认字体主题
tool/     subset_font.py 字体子集化脚本
test/     测试框架 + 共享基类（test_base / ui_test_base）+ 套件注册（suite_registry）+
          13 套件 136 用例（规则/剧本/AI 不变量/架构守护/组件/主流程/UI 回归/联机回环）
          + smoke_ui.gd 冒烟 + calibrate_bidding.gd 叫分校准工具
doc/      三打哈规则（唯一规则依据）、三打哈-Godot工程计划、重构规范
static/   ui-mockup.svg 界面区域图（含联机屏）
AGENTS.md 项目规范
启动联机服务器.bat  一键启动无头联机服务器（用 %GODOT_PATH%，端口 9080）
```

## 运行

```bash
# 编辑器安装位置：S:\Program\Godot\（环境变量 GODOT_PATH 已指向主程序）
# 用 Godot 4.7+ 打开本目录即可运行（主场景：主菜单 → 开始对局）

# 全量测试（规则 + 对局 + 组件 + 主流程 + UI 回归 + 架构守护，退出码 0 = 全绿）
Godot --headless --path . -s test/run_tests.gd

# UI 冒烟测试（headless 自动打完一局，约 1 分钟）
Godot --headless --path . -s test/smoke_ui.gd

# 叫分平衡校准（蒙特卡洛，重训 AiBidding.BID_CALIB 查表用）
Godot --headless --path . -s test/calibrate_bidding.gd

# 联机对战（M4）：先启动服务器（无头进程，端口 9080；或双击根目录「启动联机服务器.bat」）
Godot --headless --path . res://server/server_main.tscn
# 再开 1~4 个游戏窗口（双击 exe 或上条命令去掉 --headless），主菜单 → 联机对战：
#   输入昵称（全局唯一，注册后永久占用）→ 新建房间 / 凭房间码加入
#   房主「开始游戏」：人数不满会询问是否电脑补位（是→补满开局，否→留在房间页）
#   同房间跨局累计分数；任意成员退出/掉线超时 → 全员弹累计分窗 → 确定 → 回主菜单
# 数据存 user://sanhax_server/store.json（昵称注册表/房间留档/房间累计分，重启不丢）
# 人工验收建议（完整流程）：两个实例 A/B → A 建房记下房间码 → B 加入 → A 开局选补电脑
#   → 打完一局看结算与累计 → B 退出 → 两端弹累计分窗 → 确定 → 回主菜单；
#   进阶：对局中直接关掉 B 的窗口（掉线宽限 120s 内重连同昵称可回房续打）；
#   A 挂机 30s 体验超时托管。

# Web 版导出 + 本地浏览器试玩（视觉验收工作流，详见 doc/重构规范.md 第 6 章）
Godot --headless --path . --export-release "Web"
cd build/web && python -m http.server 8765   # 浏览器打开 http://127.0.0.1:8765

# 移动端：手机访问需要 HTTPS（Godot 要求安全上下文，普通 HTTP 局域网地址会被拒绝，
# 报「Secure Context ... use HTTPS」）。用自签名证书的 HTTPS 服务器：
python tool/serve_https.py            # 自动生成证书并打印手机访问地址
# 手机浏览器打开打印的 https://<局域网IP>:8765，首次会警告自签名证书——
# 选「高级 → 继续访问」（iOS：显示详细信息 → 访问此网站）即可正常进入。
# 无线程构建兼容 iOS Safari；触控点按等价鼠标；横屏体验最佳，竖屏 letterbox 居中可玩。
# 页面右上角有 ⛶ 全屏按钮（安卓/桌面/ iPad 直接全屏；iPhone Safari 无网页全屏 API，
# 点按钮会提示：用「分享 → 添加到主屏幕」，从主屏图标启动即为无浏览器框全屏）。
```

## 玩法

1 人（甲，下方）对 3 电脑（乙/丙/丁，逆时针出牌）。流程：叫分竞拍（抓牌庄家底叫 130，
加叫 +5 倍数封顶 200）→ 出牌庄家叫主（主花色 + 常主 R，看底牌之前）→ 翻底扣底 8 张 →
逐轮出牌（跟/杀/垫由引擎校验，非法出牌提示原因；主牌轮垫牌盖【无主】印章公示，
三家均无主时可多张主牌单牌一起甩打，等同连续单张）→ 末轮抠底（单牌/甩打 ×1、对子/拖拉机 ×2）→
按 205 分线分级结算（基底分 B=1）。多局连续进行，庄位按规则 4 轮换。

界面：右侧信息栏（主牌牌面、手牌统计、局面/累计收益）；各座位悬停查看出牌历史；
庄家自己可在左下【牌堆】悬停查看底牌；翻底后底牌 8 张自动呈选中拿起态便于观察；
手牌选牌跨轮保留；主菜单「规则引擎自检」进程内运行全部测试（Web 版隐藏）。

**联机对战**：主菜单 →「联机对战」→ 输入昵称与服务器地址 → 新建房间（得 4 位房间码）或凭码
加入（全局最多 4 人）。房主开始游戏：人数不满时询问是否电脑补位（AI 补位名「电脑·乙/丙/丁」）。
对局中你的座位固定在下方（服务端做座位旋转映射）；他人手牌/底牌永不下发到你的客户端
（可见性裁剪）。操作超时（叫分 20s/叫主 30s/扣底 60s/出牌 30s）由电脑代打并提示「超时托管」；
掉线 120 秒内用同一昵称重连可回到对局（自动收公开快照恢复），超时按退出处理。任意成员
退出/掉线超时 → 房间解散，所有人弹出房间累计分数窗 → 确定 → 回主菜单；分数与昵称注册表
由服务器持久化（重启不丢）。

## 里程碑

- **M1 规则引擎 ✅**：牌与牌型、邻接链、跟牌/杀/垫判定、一轮结算、并列规则
- **M2 单机对局 ✅**：完整一局（拍卖/叫主/翻底扣底/逐轮出牌/抠底/分级收益/庄位轮换）
  + EV 叫分 AI + 组件化牌桌 UI + R=A 拖拉机规则修订
- **工程重构 ✅（2026-11-16）**：死代码清理与兜底根治、core/UI 模块拆分（Auction/Scoring/
  AiBidding/AiPlay + HandArea 等五组件）、架构守护测试、Web 导出与浏览器验收工作流、C/S 预留口子
- **Web 验收闭环 + 规则 7.3 ✅（2026-11-17）**：根治静态 preload 致导出脚本失效；
  新增无主公示印章与主牌甩打规则；底牌入手即选中、选牌跨轮保留、主牌副花色分组排序
- **M4 联机对战 ✅（2026-11-18）**：C/S 架构（无头 Godot 服务器 + WebSocket）、建房/凭码加入/
  补 AI 开局、可见性裁剪同步、超时托管、断线重连与离线宽限、房间累计分持久化（136/136 用例，联机 11 用例回环覆盖）
- M3 AI 出牌强化（蒙特卡洛评估、候选打分，出牌技巧逐步教授）；M5 部署上线（联机服务器公网部署）
