#!/usr/bin/env bash
# ZCode Sites CLI 包装：自动定位最新版插件脚本，经 ZCode 自带 Node 运行时执行。
# 用法：zsite-cli.sh <check|deploy|logs|status|list|...> [参数...]
#   例：zsite-cli.sh check .zcode-site/stage
#       zsite-cli.sh deploy .zcode-site/stage          （重部署）
#       zsite-cli.sh deploy .zcode-site/stage --new --name "站点名" --prefix <prefix>  （首建）
#       zsite-cli.sh logs <deploymentId>
# check 子命令会 spawn `bash start.sh`（内部要找 node），本脚本自动把 assets/（node shim）前置到 PATH。
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZCODE_EXE="${ZCODE_EXE:-S:/Program/ZCode/ZCode.exe}"
PLUGIN="$(ls -d "$HOME/.zcode/cli/plugins/cache/zcode-plugins-official/zcode-site/"*/scripts/zcode-site.mjs 2>/dev/null | sort -V | tail -1)"
if [ -z "$PLUGIN" ]; then
	echo "未找到 zcode-site 插件脚本（~/.zcode/cli/plugins/cache/zcode-plugins-official/zcode-site/）" >&2
	exit 1
fi
export PATH="$SKILL_DIR/assets:$PATH"
exec env ELECTRON_RUN_AS_NODE=1 "$ZCODE_EXE" "$PLUGIN" "$@"
