---
name: zsite-deploy
description: 把三打哈 Godot 工程发布/重部署到 ZCode Sites 公网站点（游戏 + /files/ 文件浏览 + wss 联机代理三合一）并完成本地与云端验证。凡提到 部署/上线/重新发布/更新站点/公网试玩站/zsite/ZCode Sites/联机服务器部署，或完成导出后要发布，一律走本流程——不要现场重新发明步骤，平台限制与模板二进制的坑都已在流程与 gotchas 里。
---

# zsite-deploy：三打哈 ZCode Sites 部署流程

## 常量速查

| 项 | 值 |
|---|---|
| 线上站点 | https://three-beat-one-v425.zai.site（siteId 2123036108123566080） |
| stage | `<repo>/.zcode-site/stage/`（gitignored 生成物；布局见 `scripts/build-stage.sh`） |
| 部署 CLI | `scripts/zsite-cli.sh <子命令> ...`（自动定位插件最新版 + Electron Node 运行时 + node shim） |
| 导出预设 | `Web`（build/web/index.html）、`Server`（build/server/server.pck，custom_features="server"） |
| 云内布局 | /app=stage；/data=运行数据；Godot 无头服务器 127.0.0.1:9080；诊断路由 `/debug` |
| 单文件上限 | 平台包内单文件 ≤25MB → `index.wasm.gz` 预 gzip + `gs/godot-server.gz.part-*` 分片 |

## 流程总览

代码改动 → 项目验证顺序（AGENTS.md：`--import` → `run_tests.gd` → 涉 UI 加 `smoke_ui.gd`）→
**导出+组包** → **本地全栈验证** → **部署** → **云端验收**。文档/文案有新增字符先重跑字体子集
（`python -I tool/subset_font.py`）。

## 1. 导出 + 组包

```bash
.agents/skills/zsite-deploy/scripts/build-stage.sh            # 从仓库根构建
```

脚本做四件事：Godot 双导出（Web/Server 预设）→ web 产物进 stage（`index.wasm` 压成
`index.wasm.gz`）→ 联机服务器（`server.pck` + Linux 无头模板 gzip 分片 20MB）→ 根部基建
从 **skill assets 单源复制**（`assets/` 里的 server.mjs/start.sh/package.json 是唯一事实源，
改部署基建要改 assets，不要直接改 stage——stage 是生成物，下次组包会被覆盖）。

## 2. 本地全栈验证（不花云端配额）

```bash
GODOT_BIN="S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe" \
GODOT_ARGS="--headless --path <src_root> res://server/server_main.tscn -- --port 9080" \
scripts/zsite-cli.sh check .zcode-site/stage
```

期望 `{"status":"live","httpStatus":200}`。注入的 GODOT_BIN/GODOT_ARGS 用本机 Windows Godot
替代云内 Linux 二进制（start.sh 检测到 GODOT_BIN 已设即跳过组装），把「Node 三服务 + ws
代理 + Godot 子进程」整条链在本机跑通。

协议回环探针（NetClient → 代理 → 无头服务器，建房成功 = 链路通）：

```bash
S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path <src_root> \
  -s <repo绝对路径>/.agents/skills/zsite-deploy/assets/probe_online.gd -- 13003 探针
# 先在另一终端起新鲜 stage：cd .zcode-site/stage && PORT=13003 GAME_DIR=web FILES_ROOTS=web \
#   GODOT_BIN=... GODOT_ARGS=... node server.mjs（node 用 assets/node shim）
# 期望输出 PROBE_OK <房间码>；探针等 6~8s 再跑（Godot 子进程启动需要时间）
```

## 3. 部署

```bash
scripts/zsite-cli.sh deploy .zcode-site/stage                # 重部署（同站点）
scripts/zsite-cli.sh deploy .zcode-site/stage --new --name "三打哈·三打一" --prefix three-beat-one  # 首建
```

进度流几分钟跑完；失败码与处置见 `references/gotchas.md`。部署完成会写 `.zcode-site.json`
（gitignored，勿入 stage）。

## 4. 云端验收清单

依次过一遍（任何一步红 → `references/gotchas.md` 排障）：

1. **健康**：`curl -s -o /dev/null -w "%{http_code}" https://three-beat-one-v425.zai.site/` → 200
2. **联机服务器进程**：`curl -s https://three-beat-one-v425.zai.site/debug` → `listening` 两栈皆 true
3. **wss 穿边缘**：
   `curl -si -N -m 8 -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" https://<站点>/` → `HTTP/1.1 101`
4. **协议全链路**（真客户端语义，无需浏览器键盘）：
   `Godot --headless --path <src_root> -s <repo>/.agents/skills/zsite-deploy/assets/probe_online.gd -- wss://<站点> 探针昵称` → `PROBE_OK <房间码>`
5. **昵称在线占用制**：`-- hello` 模式 A/B（同昵称同时在线被拒；掉线 7s 后复用成功）；
   建过房的昵称宽限期内回来走重连回原房间（见 update.md 2026-11-18 在线占用制条目）
6. **长连接**：`-- stay` 模式跑 400s → `PROBE_STABLE`（平台 300s 超时只作用于空闲连接）
7. **浏览器**：打开站点截图主菜单 → 开始对局；联机菜单确认地址已预填 `wss://<站点>`。
   注意 Godot Web 文本输入对合成事件免疫（doc/coding.md §3），自动化打不了昵称，双人
   人工验收开两个浏览器窗口。

## 5. 诊断与数据

- `/debug`：godotExit/listening/日志尾（node 侧 + 引擎 `--log-file`）
- `/files/`：浏览 `/app`（部署包）与 `/data`（运行数据，store.json 在
  `/data/xdg/godot/app_userdata/三打哈（三打一）/sanhax_server/`）
- 运行日志：`scripts/zsite-cli.sh logs <deploymentId>`（仅部署阶段事件；运行时 stdout 用 /debug）

## 6. 干净树出包（工作区被无关在途改动污染时的兜底）

工作区里若有他人未完成的改动（会随导出被打进 pck 且可能编译失败），不要动共享工作区，
用 `git archive` 出干净树再叠放**本仓库的部署相关文件**后对其构建：

```bash
git archive HEAD | tar -x -C .zcode-site/wt
# 叠放清单（工作树版本 = 想发布的版本；随演进增删）：
#   server/room_manager.gd server/store.gd server/server_main.gd server/host_room.gd
#   test/test_online.gd scene/menu/online_menu.tscn scene/menu/main_menu.tscn
#   script/menu/online_menu.gd export_presets.cfg project.godot
#   font/NotoSansSC-Regular.subset.otf
#   （早期轮次还包括 .gitignore/AGENTS/README——纯文档不入构建，可省）
scripts/build-stage.sh .zcode-site/wt      # 对干净树导出组包
```

## 7. 已知平台/引擎坑

全部细节在 `references/gotchas.md`——**部署或排障前先读它**：平台单端口与 Upgrade、单文件
25MB、导出模板二进制 `disable_path_overrides`（禁 `--main-pack`/位置场景；`--` 用户参数长跑
静默挂 → 端口走 `GODOT_PORT` 环境变量）、feature 主场景覆盖、node 不在 PATH、探针竞态等。
