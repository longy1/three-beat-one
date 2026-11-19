#!/usr/bin/env bash
# 受影响测试入口（本地 commit 前跑）：按改动文件映射需要跑的套件，只跑受影响部分。
# 用法：bash test/run_affected.sh [基线ref]   默认 HEAD（工作区+已暂存改动）；提交后可传 HEAD~1。
# 改动面大（触到测试基建/全局配置/未知路径）→ 自动退化为并行全量（run_tests_parallel.sh）。
# 映射表维护：新增套件或目录时同步更新本文件（与 test/suite_registry.gd 对齐）。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe}"
base=${1:-HEAD}

files=$( { git diff --name-only "$base"; git diff --name-only --cached; } | sort -u )
if [ -z "$files" ]; then
  echo "相对 $base 无改动，跳过测试"
  exit 0
fi

suites=()
want_full=0
add() {
  case " ${suites[*]:-} " in
    *" $1 "*) ;;
    *) suites+=("$1") ;;
  esac
}
add_arch() {  # 架构守护便宜且覆盖全仓分层：任何代码改动都带上
  add test_architecture
}
while IFS= read -r f; do
  case "$f" in
    # ── 规则引擎核心：按模块精确映射 ──
    core/card.gd) add test_card; add_arch ;;
    core/trump.gd) add test_trump; add_arch ;;
    core/combo.gd) add test_combo; add_arch ;;
    core/follow_rule.gd) add test_follow; add_arch ;;
    core/trick.gd) add test_trick; add_arch ;;
    core/scoring.gd|core/auction.gd) add test_game; add_arch ;;
    core/game.gd) add test_game test_flow; add_arch ;;
    core/ai_bidding.gd|core/ai_play.gd|core/ai_policy.gd) add test_ai_policy; add_arch ;;
    core/*.gd) add test_card test_trump test_combo test_follow test_trick test_game test_flow; add_arch ;;  # core 新文件兜底
    # ── 表现层 ──
    script/table/*.gd|scene/table/*.tscn|script/ui_style.gd) add test_components test_ui; add_arch ;;
    script/menu/online_menu.gd|scene/menu/online_menu.tscn) add test_online; add_arch ;;
    script/menu/main_menu.gd|scene/menu/main_menu.tscn) add test_ui; add_arch ;;  # 主菜单含「自检」入口
    script/menu/*.gd|scene/menu/*.tscn) add test_ui; add_arch ;;
    net/*.gd) add test_online; add_arch ;;
    server/*.gd) add test_online; add_arch ;;
    # ── 测试自身：改动哪个套件跑哪个 ──
    test/test_*.gd) add "$(basename "${f%.gd}")"; add_arch ;;
    # ── 测试基建 / 全局配置 / 资源：跑全量 ──
    test/test_framework.gd|test/run_tests.gd|test/run_tests_parallel.sh|test/run_affected.sh|test/suite_registry.gd|test/ui_test_base.gd|test/test_base.gd) want_full=1 ;;
    project.godot|export_presets.cfg|theme/*|font/*) want_full=1 ;;
    # ── 纯文档 / 静态设计资产：不影响运行，不触发测试 ──
    doc/*|README.md|AGENTS.md|TODO.md|static/*|.gitignore|.gitattributes) ;;
    *) want_full=1 ;;  # 未知路径兜底
  esac
done <<< "$files"

if [ "$want_full" = "1" ] || [ ${#suites[@]} -ge 8 ]; then
  echo "改动面大（或触到测试基建/全局配置）→ 跑并行全量"
  exec bash test/run_tests_parallel.sh
fi
if [ ${#suites[@]} -eq 0 ]; then
  echo "改动不触发任何套件（纯文档/资产），跳过测试"
  exit 0
fi
selected=$(IFS=,; echo "${suites[*]}")
echo "改动影响套件：$selected"
exec "$GODOT" --headless --path . -s test/run_tests.gd -- --suite="$selected"
