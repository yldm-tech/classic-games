#!/usr/bin/env bash
# 双端集成冒烟:起 Go 后端 → Godot 客户端经 feature gateway 调真实 /ai/mod、/ai/validate → 关后端。
# 用法:scripts/spike-integration.sh   (可用 GODOT=/path/to/godot、PORT=8099 覆盖)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PORT="${PORT:-8099}"

cleanup() {
  [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null
  lsof -ti:"$PORT" 2>/dev/null | xargs kill 2>/dev/null
}
trap cleanup EXIT

# 起后端(StubProvider + 真 SchemaValidator)
# FORGEPLAY_DEV_ADMIN=1:让登录用户可做审核裁决(仅集成测试;生产严禁)。
( cd "$ROOT/apps/server" && PORT="$PORT" FORGEPLAY_SCHEMA_DIR="$ROOT/packages/schemas" \
  FORGEPLAY_DEV_ADMIN=1 go run ./cmd/server ) &
SRV=$!

# 等 healthz(curl 自带重试,避免显式 sleep)
if ! curl -s --retry-connrefused --retry 40 --retry-delay 1 -o /dev/null "http://127.0.0.1:$PORT/healthz"; then
  echo "后端未就绪" >&2
  exit 1
fi

LOG="$(mktemp)"
FORGEPLAY_API="http://127.0.0.1:$PORT" "$GODOT" --headless --path "$ROOT/apps/client" \
  --script res://net_integration_test.gd 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ] || ! grep -Eq '^=== 集成结果: [0-9]+ passed, 0 failed ===$' "$LOG"; then
  echo "集成测试未完整通过（缺少成功结果标记或 Godot 返回失败）" >&2
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"
