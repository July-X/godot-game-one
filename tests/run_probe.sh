#!/usr/bin/env bash
# 双进程 headless 联机回归门禁。
#
#   tests/run_probe.sh [端口] [探针] [已有截图目录]
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
CASE="${2:-}"
case "$CASE" in
  "") SCENE=res://tests/lan_probe.tscn ;;
  wide-host|wide-client|wide-tablet-host|wide-tablet-client) SCENE=res://tests/mixed_viewport_probe.tscn ;;
  pickup-tablet-host|pickup-tablet-client) SCENE=res://tests/pickup_lan_probe.tscn ;;
  resume-guest|resume-host|resume-timeout|resume-exit|resume-quiet) SCENE=res://tests/lan_resume_probe.tscn ;;
  feedback) SCENE=res://tests/feedback_lan_probe.tscn ;;
  draft) SCENE=res://tests/draft_lan_probe.tscn ;;
  draft-touch-wide-host|draft-touch-wide-client) SCENE=res://tests/draft_touch_probe.tscn ;;
  score-safe-wide-host|score-safe-wide-client) SCENE=res://tests/score_safe_area_probe.tscn ;;
  rescue) SCENE=res://tests/rescue_lan_probe.tscn ;;
  boss|boss-kill) SCENE=res://tests/boss_lifecycle_probe.tscn ;;
  boss-coop|boss-coop-wide-host|boss-coop-wide-client) SCENE=res://tests/boss_coop_probe.tscn ;;
  boss-aggro|boss-aggro-mirror) SCENE=res://tests/boss_aggro_probe.tscn ;;
  rift-wide-host|rift-wide-client|rift-timeout-host|rift-timeout-client|rift-review) SCENE=res://tests/rift_route_lan_probe.tscn ;;
  rift-induce-host|rift-induce-client|rift-flank-host|rift-flank-client|rift-duo-host|rift-duo-client|rift-outer-burn|rift-outer-burn-mirror) SCENE=res://tests/rift_inducement_probe.tscn ;;
  hunter-wide-host|hunter-wide-client) SCENE=res://tests/rift_hunter_probe.tscn ;;
  boss-dodge) SCENE=res://tests/boss_dodge_probe.tscn ;;
  *) echo "用法: $0 [端口] [draft|draft-touch-wide-{host,client}|score-safe-wide-{host,client}|rescue|feedback|boss|boss-kill|boss-coop|boss-coop-wide-{host,client}|boss-aggro|boss-aggro-mirror|rift-wide-{host,client}|rift-timeout-{host,client}|rift-review|rift-induce-{host,client}|rift-flank-{host,client}|rift-duo-{host,client}|rift-outer-burn[-mirror]|hunter-wide-{host,client}|boss-dodge|wide-{host,client}|wide-tablet-{host,client}|pickup-tablet-{host,client}|resume-{guest,host,timeout,exit,quiet}]" >&2; exit 2 ;;
esac
HOST_DISPLAY=(--headless)
CLIENT_DISPLAY=(--headless)
PROBE_ARGS=("$CASE")
if [[ "$CASE" == resume-* ]]; then
  if [[ $# -lt 3 || ! -d "$3" || -n "$(ls -A "$3")" ]]; then
    echo "恢复探针需要一个空的协调目录" >&2; exit 2
  fi
  PROBE_ARGS+=("$(cd "$3" && pwd)")
elif [[ $# -ge 3 ]]; then
  if [[ ( "$CASE" != wide-* && "$CASE" != pickup-tablet-* && "$CASE" != hunter-wide-* && "$CASE" != rift-induce-* && "$CASE" != rift-flank-* && "$CASE" != rift-duo-* && "$CASE" != rift-review && "$CASE" != rescue && "$CASE" != boss-coop* ) || ! -d "$3" ]]; then
    echo "截图需要 rescue、boss-coop、wide-*、hunter-wide-*、rift-induce-*、rift-flank-*、rift-duo-*、rift-review 或 pickup-tablet-* 模式，以及一个已有目录" >&2
    exit 2
  fi
  PROBE_ARGS+=("$(cd "$3" && pwd)")
  host_size=1280x720
  client_size=1600x720
  if [[ "$CASE" == wide-host ]]; then
    host_size=1600x720
    client_size=1280x720
  elif [[ "$CASE" == rift-review || "$CASE" == boss-coop-wide-host ]]; then
    host_size=1600x720
    client_size=960x720
  elif [[ "$CASE" == boss-coop-wide-client || "$CASE" == wide-tablet-host || "$CASE" == pickup-tablet-host || "$CASE" == hunter-wide-client || "$CASE" == rift-induce-client || "$CASE" == rift-flank-client || "$CASE" == rift-duo-client ]]; then
    host_size=960x720
  elif [[ "$CASE" == wide-tablet-client || "$CASE" == pickup-tablet-client || "$CASE" == hunter-wide-host || "$CASE" == rift-induce-host || "$CASE" == rift-flank-host || "$CASE" == rift-duo-host ]]; then
    host_size=1600x720
    client_size=960x720
  fi
  HOST_DISPLAY=(--windowed --resolution "$host_size" --position 5,35 --audio-driver Dummy)
  CLIENT_DISPLAY=(--windowed --resolution "$client_size" --position 240,110 --audio-driver Dummy)
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$(mktemp -d)"
HOST_LOG="$LOG_DIR/host.log"
CLIENT_LOG="$LOG_DIR/client.log"
# 只有通过时才清日志；失败要留下现场，否则那句"日志保留"是假的
KEEP_LOGS="${PROBE_KEEP_LOGS:-0}"
cleanup() { [ "$KEEP_LOGS" = "0" ] && rm -rf "$LOG_DIR"; }
trap cleanup EXIT

GODOT="${GODOT:-godot}"

echo "[probe] port=$PORT log_dir=$LOG_DIR"
cd "$ROOT" || exit 2

HOST_ARGS=("${PROBE_ARGS[@]}")
CLIENT_ARGS=("${PROBE_ARGS[@]}")
case "$CASE" in
  draft-touch-wide-host|score-safe-wide-host) HOST_ARGS+=(wide) ;;
  draft-touch-wide-client|score-safe-wide-client) CLIENT_ARGS+=(wide) ;;
  rift-duo-*) HOST_ARGS+=(--rift-log); CLIENT_ARGS+=(--rift-log) ;;
esac

"$GODOT" "${HOST_DISPLAY[@]}" --path . "$SCENE" -- host "$PORT" "${HOST_ARGS[@]}" \
	> "$HOST_LOG" 2>&1 &
HOST_PID=$!
sleep 1
"$GODOT" "${CLIENT_DISPLAY[@]}" --path . "$SCENE" -- client "$PORT" "${CLIENT_ARGS[@]}" \
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
# 注意用 printf '%s'（不加换行）：空字符串配 '%s\n' 会产生一个空行，
# 被 grep -c 误计成 1 次错误，导致日志完全干净时反而报 FAIL。
ENGINE_REAL=$(printf '%s' "$ENGINE_ERRORS" | grep -vcE "$KNOWN" || true)
ENGINE_KNOWN=$(printf '%s' "$ENGINE_ERRORS" | grep -cE "$KNOWN" || true)

echo "--- GATE ---"
echo "host_rc=$HOST_RC client_rc=$CLIENT_RC failed_assert=$FAILED_ASSERT script_errors=$SCRIPT_ERRORS engine_errors=$ENGINE_REAL known_join_noise=$ENGINE_KNOWN"

if [ "$HOST_RC" -ne 0 ] || [ "$CLIENT_RC" -ne 0 ] \
	|| [ "$FAILED_ASSERT" -ne 0 ] || [ "$SCRIPT_ERRORS" -ne 0 ] || [ "$ENGINE_REAL" -ne 0 ]; then
	if [ "$SCRIPT_ERRORS" -ne 0 ] || [ "$ENGINE_REAL" -ne 0 ]; then
		echo "[probe] 运行期报错上下文："
		printf '%s\n' "$ENGINE_ERRORS" | grep -vE "$KNOWN" | head -20
		cat "$HOST_LOG" "$CLIENT_LOG" | grep -A 2 "SCRIPT ERROR" | head -20
	fi
	KEEP_LOGS=1
	echo "[probe] FAIL（日志保留在 ${LOG_DIR}）"
	exit 1
fi

echo "[probe] PASS"
exit 0
