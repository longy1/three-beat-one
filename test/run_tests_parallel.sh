#!/usr/bin/env bash
# 全量测试并行入口（push 前跑）：4 个 Godot 分片进程并发，按「文件名::用例名」稳定哈希分片，
# TEST_PORT_OFFSET 隔离各分片的在线回环端口与存储文件；合并退出码与失败清单。
# 用法：bash test/run_tests_parallel.sh    （分片数可用 N=6 覆盖；单分片等价顺序全量）
# 本地 commit 只想跑受影响套件 → 用 test/run_affected.sh。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-S:/Program/Godot/Godot_v4.7.2-stable_win64_console.exe}"
# 默认分片数 = 逻辑核数（封顶 8；实测 7700X 上 6 分片墙钟 ~24s，顺序全量 ~100s）
N=${N:-$(nproc 2>/dev/null || echo 6)}
[ "$N" -gt 8 ] && N=8
[ "$N" -lt 1 ] && N=1
out=.godot/test_shards
rm -rf "$out"
mkdir -p "$out"

for k in $(seq 0 $((N - 1))); do
  (
    TEST_PORT_OFFSET=$k "$GODOT" --headless --path . -s test/run_tests.gd -- \
      --shard="$k/$N" --result-file="$out/shard$k.txt" >"$out/shard$k.out" 2>&1
    echo $? >"$out/shard$k.code"
  ) &
done
wait

fail=0
total_pass=0
total_count=0
for k in $(seq 0 $((N - 1))); do
  code=$(cat "$out/shard$k.code" 2>/dev/null || echo 1)
  summary=$(cat "$out/shard$k.txt" 2>/dev/null || echo "（分片 $k 未产出结果）")
  echo "== 分片 $k（exit $code）: $summary"
  grep -E "^\[slow\]" "$out/shard$k.out" 2>/dev/null
  [ "$code" != "0" ] && fail=1
  p=$(sed -n 's/.*：\([0-9]*\)\/\([0-9]*\) 个用例.*/\1 \2/p' "$out/shard$k.txt" 2>/dev/null | head -1)
  total_pass=$((total_pass + ${p%% *}))
  total_count=$((total_count + ${p##* }))
done
if [ "$fail" = "0" ]; then
  echo "== ✓ 并行全量通过：$total_pass/$total_count 个用例（$N 分片）=="
else
  echo "== ✗ 并行全量存在失败（详见各分片输出：$out/）=="
  grep -h "^  · " "$out"/shard*.txt 2>/dev/null
fi
exit $fail
