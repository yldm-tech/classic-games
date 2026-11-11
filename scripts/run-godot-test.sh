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
# Seconds one Godot process may run. A test script that hits a script error before it calls quit() leaves the engine running for ever, so without a limit one broken test would hang the whole gate instead of failing it.
TIMEOUT="${GODOT_TEST_TIMEOUT:-600}"
# What a process ended by SIGALRM exits with (128 + 14).
TIMED_OUT=142
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

if ! command -v perl >/dev/null 2>&1; then
	echo "perl is needed to put a time limit on Godot; refusing to run a test that could hang" >&2
	exit 1
fi

# The alarm is set in a process that then becomes Godot itself (an alarm survives exec), so the limit needs no watchdog and leaves nothing behind.
run_godot() {
	local status=0
	set +e
	perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]: $!\n"' "$TIMEOUT" "$GODOT" --headless --path "$ROOT/apps/client" "$@" 2>&1 | tee -a "$LOG_FILE"
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

TEST_STATUS=0
run_godot --script "$TEST_SCRIPT" || TEST_STATUS=$?
if [[ "$TEST_STATUS" -eq "$TIMED_OUT" ]]; then
	echo "Godot test did not finish within ${TIMEOUT}s and was stopped (a script error before quit() leaves the engine running; GODOT_TEST_TIMEOUT changes the limit): $TEST_SCRIPT" >&2
	exit 1
fi
if [[ "$TEST_STATUS" -ne 0 ]]; then
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
