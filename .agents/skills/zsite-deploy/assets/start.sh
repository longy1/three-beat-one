#!/usr/bin/env bash
# ZCode Sites start.sh：前台运行 server.mjs，绑 0.0.0.0:3000。
# / 游戏页面；/files/ 部署容器只读文件浏览；WebSocket 升级代理到 Godot 无头联机服务器
# （server.mjs 拉起子进程，见其头注）。
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export NODE_ENV=production
export PORT="${PORT:-3000}"
export HOST=0.0.0.0 HOSTNAME=0.0.0.0
# 实例只有 1 GB 内存，给非堆内存留余量。
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=768}"
# 可写但临时（实例回收即丢）。
export DATA_DIR="${DATA_DIR:-$PWD/data}"
mkdir -p "$DATA_DIR"

# 文件浏览根（只读）：部署包内容 + 运行数据目录，不暴露系统目录。
export FILES_ROOTS="${FILES_ROOTS:-/app:/data}"

# 组装 Linux 无头 Godot（gs/ 内分片 ≤25MB 打包限制；每次启动重新拼装，几秒）。
# 导出模板二进制不支持 --main-pack/--path 覆盖（disable_path_overrides 编译项），
# 标准加载方式 = 二进制旁放同名 .pck 自动装载。
# 联机数据经 XDG_DATA_HOME 落 /data（user:// = $XDG_DATA_HOME/godot/app_userdata/三打哈（三打一））。
# 本地 Windows 全栈验证可外部注入 GODOT_BIN/GODOT_ARGS（指向本机 Godot 与项目路径），跳过组装。
export GODOT_PORT="${GODOT_PORT:-9080}"
if [ -z "${GODOT_BIN:-}" ]; then
	cat gs/godot-server.gz.part-* | gunzip > "$DATA_DIR/godot-server.tmp"
	chmod +x "$DATA_DIR/godot-server.tmp"
	mv -f "$DATA_DIR/godot-server.tmp" "$DATA_DIR/godot-server"
	cp gs/server.pck "$DATA_DIR/godot-server.pck"
	export GODOT_BIN="$DATA_DIR/godot-server"
	# 端口经环境变量 GODOT_PORT 传给 server_main（模板二进制的 `--` 用户参数路径不可靠，
	# 见 server_main.gd _parse_port）；--log-file 绕过 libc 管道全缓冲拿引擎日志
	export GODOT_ENGINE_LOG="$DATA_DIR/gd-engine.log"
	export GODOT_ARGS="--headless --log-file $GODOT_ENGINE_LOG"
fi
export XDG_DATA_HOME="${XDG_DATA_HOME:-$DATA_DIR/xdg}"

exec node server.mjs
