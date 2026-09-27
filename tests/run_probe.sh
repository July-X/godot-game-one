#!/usr/bin/env bash
# 双进程 headless 联机回归门禁。
#
#   tests/run_probe.sh [端口]
#
# 做三件人工流程做不到的事：
#   1. 自动收口两个进程的退出码（探针断言失败 → 非零退出）
#   2. 扫描日志里的 SCRIPT ERROR / 引擎 ERROR —— 探针只断言行为，
#      像 "Node not found" 这类引擎报错不会变成任何一条 VERDICT
#   3. 打印 VERDICT 汇总，CI / Agent 可直接判成败
#
# 注意：探针 host 端会在场景跑完后主动退出，client 端靠"观察到 P1 死亡"
# 做同步点，两端总耗时约 40~60 秒。

set -uo pipefail

PORT="${1:-7788}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$(mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"
CLIENT_LOG="$LOG_DIR/client.log"
trap 'rm -rf "$LOG_DIR"' EXIT

GODOT="${GODOT:-godot}"

echo "[probe] port=$PORT log_dir=$LOG_DIR"
cd "$ROOT" || exit 2

"$GODOT" --headless --path . res://tests/lan_probe.tscn -- host "$PORT" \
	> "$HOST_LOG" 2>&1 &
HOST_PID=$!
sleep 1
"$GODOT" --headless --path . res://tests/lan_probe.tscn -- client "$PORT" \
	> "$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

wait "$HOST_PID"; HOST_RC=$?
wait "$CLIENT_PID"; CLIENT_RC=$?

echo "--- VERDICT ---"
grep -h "VERDICT" "$HOST_LOG" "$CLIENT_LOG"
echo "--- SUMMARY ---"
grep -h "VERDICT SUMMARY" "$HOST_LOG" "$CLIENT_LOG"

FAILED_ASSERT=$(cat "$HOST_LOG" "$CLIENT_LOG" | grep -c "pass=false" || true)
SCRIPT_ERRORS=$(cat "$HOST_LOG" "$CLIENT_LOG" | grep -c "SCRIPT ERROR" || true)

# 引擎 / 脚本错误：探针断言覆盖不到，但同样是回归。
# 只统计 ERROR: 行，忽略 "   at:" 续行（它们总是跟在被过滤掉的 at-exit 泄漏噪音后面）。
# headless 强制退出固有的 at-exit 泄漏噪音每次都会出现，不算回归。
NOISE='were leaked at exit|RIDs of type|ObjectDB instances leaked|resources still in use'
# 已知的入局期噪音：@rpc 以「节点所在场景路径」寻址，本项目是 Main。
# 客户端还停在大厅/探针场景时 /root/Main 不存在，Host 已经开始广播，
# 引擎就会报找不到路径并丢包。这是既有设计（见 docs/architecture.md 的
# 「RPC 寻址与入局期噪音」），丢的包由实体快照自愈机制补齐。
# 放行它们，但计数打出来，数量暴涨说明同步链路真的退化了。
KNOWN='Node not found: "Main"|Failed to get path from RPC: Main|Invalid packet received|Parameter "node" is null'
ENGINE_ERRORS=$(cat "$HOST_LOG" "$CLIENT_LOG" | grep "^ERROR: " | grep -vE "$NOISE" || true)
ENGINE_REAL=$(printf '%s\n' "$ENGINE_ERRORS" | grep -vcE "$KNOWN" || true)
ENGINE_KNOWN=$(printf '%s\n' "$ENGINE_ERRORS" | grep -cE "$KNOWN" || true)

echo "--- GATE ---"
echo "host_rc=$HOST_RC client_rc=$CLIENT_RC failed_assert=$FAILED_ASSERT script_errors=$SCRIPT_ERRORS engine_errors=$ENGINE_REAL known_join_noise=$ENGINE_KNOWN"

if [ "$HOST_RC" -ne 0 ] || [ "$CLIENT_RC" -ne 0 ] \
	|| [ "$FAILED_ASSERT" -ne 0 ] || [ "$SCRIPT_ERRORS" -ne 0 ] || [ "$ENGINE_REAL" -ne 0 ]; then
	if [ "$SCRIPT_ERRORS" -ne 0 ] || [ "$ENGINE_REAL" -ne 0 ]; then
		echo "[probe] 运行期报错上下文："
		printf '%s\n' "$ENGINE_ERRORS" | grep -vE "$KNOWN" | head -20
		cat "$HOST_LOG" "$CLIENT_LOG" | grep -A 2 "SCRIPT ERROR" | head -20
	fi
	echo "[probe] FAIL（日志保留在 $LOG_DIR）"
	exit 1
fi

echo "[probe] PASS"
rm -rf "$LOG_DIR"
exit 0
