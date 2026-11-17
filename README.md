# 三打哈（三打一）

湘西扑克游戏**三打哈（三打一）**的 Godot 单机版工程（1 人对 3 电脑）。

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
script/   game_table 控制器（编排）+ 组件：hand_area 手牌区 / pile_viewer 牌堆弹层 /
          action_bar 操作按钮条 / trump_rank_picker 叫主面板 / crown_animator 皇冠动画 /
          card_widget 卡牌 / seat_panel / info_sidebar / crown_badge / void_stamp 无主印章 /
          dashed_frame / ui_style
scene/    main_menu、game_table 牌桌、seat_panel 座位组件、info_sidebar 信息栏组件
font/     中文字体子集（Web 导出必需：浏览器无系统字体回退）
theme/    default.tres 默认字体主题
tool/     subset_font.py 字体子集化脚本
test/     测试框架 + 共享基类（test_base / ui_test_base）+ 套件注册（suite_registry）+
          12 套件 100+ 用例（规则/剧本/AI 不变量/架构守护/组件/主流程/UI 回归）
          + smoke_ui.gd 冒烟 + calibrate_bidding.gd 叫分校准工具
doc/      三打哈规则（唯一规则依据）、三打哈-Godot工程计划、重构规范
static/   ui-mockup.svg 界面区域图
AGENTS.md 项目规范
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

# Web 版导出 + 本地浏览器试玩（视觉验收工作流，详见 doc/重构规范.md 第 6 章）
Godot --headless --path . --export-release "Web"
cd build/web && python -m http.server 8765   # 浏览器打开 http://127.0.0.1:8765

# 移动端：手机浏览器直接访问同一地址即可玩（无线程构建兼容 iOS Safari；
# 自适应画布 + 触控点按等价鼠标；横屏体验最佳，竖屏 letterbox 居中可玩）
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

## 里程碑

- **M1 规则引擎 ✅**：牌与牌型、邻接链、跟牌/杀/垫判定、一轮结算、并列规则
- **M2 单机对局 ✅**：完整一局（拍卖/叫主/翻底扣底/逐轮出牌/抠底/分级收益/庄位轮换）
  + EV 叫分 AI + 组件化牌桌 UI + R=A 拖拉机规则修订
- **工程重构 ✅（2026-11-16）**：死代码清理与兜底根治、core/UI 模块拆分（Auction/Scoring/
  AiBidding/AiPlay + HandArea 等五组件）、架构守护测试、Web 导出与浏览器验收工作流、C/S 预留口子
- **Web 验收闭环 + 规则 7.3 ✅（2026-11-17）**：根治静态 preload 致导出脚本失效；
  新增无主公示印章与主牌甩打规则；底牌入手即选中、选牌跨轮保留、主牌副花色分组排序
- M3 AI 出牌强化（蒙特卡洛评估、候选打分，出牌技巧逐步教授）；M4 联机对战；M5 部署上线
