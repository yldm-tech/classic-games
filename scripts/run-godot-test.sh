#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
	echo "usage: $0 <res://test-script.gd> <success-summary-regex>" >&2
	exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
EXPECTED_VERSION="$(<"$ROOT/apps/client/.godot-version")"
TEST_SCRIPT="$1"
SUCCESS_PATTERN="$2"
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

run_godot() {
	local status=0
	set +e
	"$GODOT" --headless --path "$ROOT/apps/client" "$@" 2>&1 | tee -a "$LOG_FILE"
	status=${PIPESTATUS[0]}
	set -e
	return "$status"
}

ACTUAL_VERSION="$("$GODOT" --version)"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION".* ]]; then
	echo "Godot version mismatch: expected $EXPECTED_VERSION, got $ACTUAL_VERSION" >&2
	exit 1
fi

if ! run_godot --import; then
	echo "Godot resource import failed" >&2
	exit 1
fi

if ! run_godot --script "$TEST_SCRIPT"; then
	echo "Godot test process failed: $TEST_SCRIPT" >&2
	exit 1
fi

if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$LOG_FILE"; then
	echo "Godot reported a script parse/load error: $TEST_SCRIPT" >&2
	exit 1
fi

if grep -Eq 'ObjectDB instances leaked|RIDs? .* leaked|resources still in use at exit' "$LOG_FILE"; then
	echo "Godot reported leaked runtime resources: $TEST_SCRIPT" >&2
	exit 1
fi

if ! grep -Eq "$SUCCESS_PATTERN" "$LOG_FILE"; then
	echo "Godot test did not emit the required success summary: $TEST_SCRIPT" >&2
	exit 1
fi
