#!/usr/bin/env bash
# 组装 ZCode Sites 部署 stage：Godot 双导出 + 产物布局（wasm 预 gzip / Linux 模板分片）。
# 用法：build-stage.sh [src_root]
#   src_root 默认仓库根；工作区被无关在途改动污染时传干净树目录（SKILL.md §干净树出包）。
# 产物：<repo>/.zcode-site/stage/（web/ 游戏静态 + gs/ 联机服务器 + 根部基建 [来自 skill assets 单源]）。
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$SKILL_DIR/../../.." && pwd)"
SRC="${1:-$REPO}"
STAGE="$REPO/.zcode-site/stage"
GODOT_BIN="${GODOT_PATH:-S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe}"
TPL_DIR="${GODOT_TPL_DIR:-S:/Program/Godot/editor_data/export_templates/4.7.2.stable}"

echo "== 1/4 Godot 双导出（src=$SRC）=="
mkdir -p "$SRC/build/web" "$SRC/build/server"
# 先导入：全新干净树没有 .godot 缓存，不先导入会在导出启动时因主题字体未导入而刷错误
(cd "$SRC" && "$GODOT_BIN" --headless --path . --import) > /dev/null 2>&1 || true
(cd "$SRC" && "$GODOT_BIN" --headless --path . --export-release "Web" build/web/index.html) > /dev/null
(cd "$SRC" && "$GODOT_BIN" --headless --path . --export-release "Server" build/server/server.pck) > /dev/null

echo "== 2/4 web 产物（index.wasm 预 gzip，过平台单文件 25MB 限制）=="
rm -rf "$STAGE/web"
mkdir -p "$STAGE/web"
for f in index.html index.js index.pck index.png index.icon.png index.apple-touch-icon.png index.audio.worklet.js index.audio.position.worklet.js; do
	cp "$SRC/build/web/$f" "$STAGE/web/"
done
gzip -9 -c "$SRC/build/web/index.wasm" > "$STAGE/web/index.wasm.gz"

echo "== 3/4 联机服务器（server.pck + Linux 无头模板分片 20MB）=="
rm -rf "$STAGE/gs"
mkdir -p "$STAGE/gs"
cp "$SRC/build/server/server.pck" "$STAGE/gs/"
gzip -9 -c "$TPL_DIR/linux_release.x86_64" | split -b 20m -d - "$STAGE/gs/godot-server.gz.part-"

echo "== 4/4 根部基建（assets 单源复制）+ LF 规范 =="
cp "$SKILL_DIR/assets/server.mjs" "$SKILL_DIR/assets/start.sh" "$SKILL_DIR/assets/package.json" "$STAGE/"
sed -i 's/\r$//' "$STAGE/start.sh" "$STAGE/server.mjs"

echo "== stage 概览 =="
du -sh "$STAGE"
echo 完成。后续：scripts/zsite-cli.sh check .zcode-site/stage → zsite-cli.sh deploy .zcode-site/stage
