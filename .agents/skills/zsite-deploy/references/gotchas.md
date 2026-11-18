# gotchas：平台限制与踩坑记录（部署/排障前必读）

## 平台侧（ZCode Sites）

- **只暴露 3000 一个公网端口**：第二个端口无法对公网开放。三服务（游戏/文件浏览/wss 联机）
  全部在 3000 由 Node 分流；HTTPS 在边缘终结，应用收到普通 HTTP（`X-Forwarded-*` 头）。
- **HTTP Upgrade 会转发**（wss 可用），但**请求 300s 超时只作用于空闲连接**：应用层 5s 心跳
  （NetClient PING）实测 400s+ 稳定。别按 300s 给用户制造焦虑文案。
- **包内单文件 ≤25MB**（整个包 ≤200MB/解压 400MB）：Godot Web 的 `index.wasm`（~39.5MB）必须
  预 gzip（约 10MB）由 server.mjs 按 `Accept-Encoding` 透传 `Content-Encoding: gzip`；Linux
  无头模板（73.5MB→gzip ~28MB）必须 split 成 20MB 分片，云内 `cat | gunzip` 拼回。
- **实例 = 1 vCPU/1GB/512MB 盘**；`$DATA_DIR`(/data) 可写但实例回收即丢（房间与累计分随实例
  消亡是已知简化）。Node 内存上限 start.sh 已设 768MB，给 Godot 子进程留余量。
- **运行时 stdout 拿不到**（`logs` 只有部署阶段事件）→ server.mjs 把 Godot 子进程输出落
  `/data/godot.log` 并提供 `/debug`；引擎自身日志走 `--log-file`（绕开 libc 管道全缓冲——
  长跑子进程的 stdout 会滞留在缓冲区，永远看不到，这是排障时「静默」假象的根源）。
- 部署失败码：`PACKAGE_CHECK_FAILED` 看 error.data.problems 逐项修；quota（exit 3）等下期；
  exit 2 重新登录 ZCode。详细官方口径见 site-deploy skill 的 troubleshooting。

## 引擎侧（Godot 导出模板二进制）

- **`disable_path_overrides` 编译项**：导出模板二进制**不支持** `--main-pack`、位置场景参数
  （报 "compiled without support for path overrides" 并退出）。标准装载 = **二进制旁放同名
  .pck**（`godot-server` + `godot-server.pck` 同目录），启动即自动加载。
- **`--` 用户参数在模板二进制上不可靠**：带 `-- --port N` 长跑会静默挂死（无输出、不监听、
  不退出），Windows 非模板 exe 无此问题。→ 端口走环境变量：`server/server_main.gd
  _parse_port` 优先读 `GODOT_PORT`，node spawn 天然传递。别改回用户参数方案。
- **按 feature 覆盖主场景**：Server 预设 `custom_features="server"` +
  project.godot `run/main_scene.server="res://server/server_main.tscn"`——否则邻接 pck 起的是
  主菜单而非服务器。Web/桌面预设无此 feature，行为不变。
- Linux 无头模板在 Debian 12（glibc 2.36）可直接跑（`--version` 秒回验证二进制可用性）。
- **--version 自检**是二进制层的最小验证：能输出版本号 = 执行层 OK；再卡就是引擎初始化之后
  的事，用 `--headless --quit-after 1`（一帧即退）与真实参数对拍定位。

## 本机侧（Windows 开发机）

- **无独立 node**：一切 node 调用走 `ELECTRON_RUN_AS_NODE=1 S:/Program/ZCode/ZCode.exe`。
  `scripts/zsite-cli.sh` 已封装（自动 glob 插件最新版本号路径——插件升级后路径会变）。
- **check 的 PATH 坑**：check 会 spawn `bash start.sh`（内部 `exec node server.mjs`）——给
  check 注入的 PATH 项**必须绝对路径**（相对路径经 MSYS→Windows→MSYS 两次转换后丢失，
  曾致 `node: not found`）。zsite-cli.sh 已用绝对路径前置 assets/（node shim）。
- `grep -c` 计数为 0 时退出码 1，会截断 `&&` 链——脚本里不要拿它当链中环节。
- `-s` 脚本路径按 `res://` 解析：`--path` 指向别的目录时用**绝对路径**传探针脚本。
- 探针要在服务器就绪后跑：全栈起服后 `sleep 6~8` 再发探针，否则吃「连接被拒」竞态。
- 首次 `--import` 在全新目录会冒 ~7 条一次性 ERROR（冷缓存），第二次干净；test_components
  的 seat_panel 错误路径与 test_online 的 instantiate 报错是**已提交代码里的既有瑕疵**
  （见 update.md 2026-11-18 昵称条目同期的排查记录），不影响 140/140 口径。

## 站点运维

- 重部署必须重建 stage（生成物），不要手补文件——`build-stage.sh` 全自动。
- 改部署基建（server.mjs/start.sh/package.json/探针）→ 改 **skill assets**，再 build-stage。
- `prefix` 改名 = 旧地址立即失效（无跳转）；`delete --site` 永久删除。两者都要用户明确确认。
- 站点内容上线后过平台内容审核；被拒会自动下架（offlineReason: review_rejected），改内容
  重新部署即可恢复。
