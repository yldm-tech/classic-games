#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/scripts/run-godot-test.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_GODOT="$TMP_DIR/godot"
cat >"$FAKE_GODOT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
	if [[ "${FAKE_MODE:?}" == "wrong_version" ]]; then
		echo '4.6.2.stable.fake'
	else
		echo '4.6.3.stable.fake'
	fi
	exit 0
fi

for arg in "$@"; do
	if [[ "$arg" == "--import" ]]; then
		exit 0
	fi
done

case "${FAKE_MODE:?}" in
	parse_error)
		echo 'SCRIPT ERROR: Parse Error: test fixture'
		;;
	false_green)
		;;
	resource_leak)
		echo 'launcher_test: 224 passed, 0 failed'
		echo 'WARNING: ObjectDB instances leaked at exit'
		;;
	success)
		echo 'launcher_test: 224 passed, 0 failed'
		;;
	wrong_version)
		echo 'launcher_test: 224 passed, 0 failed'
		;;
	hang)
		# What a script error inside _initialize looks like from outside: the summary never comes and the process never ends. exec, so the process the runner limits is the one that sleeps.
		exec /bin/sleep 60
		;;
	hang_after_summary)
		echo 'launcher_test: 224 passed, 0 failed'
		exec /bin/sleep 60
		;;
	*)
		echo "unknown fake mode: $FAKE_MODE" >&2
		exit 2
		;;
esac
EOF
chmod +x "$FAKE_GODOT"

failures=0

run_case() {
	local name="$1"
	local expected_status="$2"
	local status=0

	if FAKE_MODE="$name" GODOT="$FAKE_GODOT" GODOT_TEST_TIMEOUT=2 "$RUNNER" \
		res://launcher_test.gd '^launcher_test: [0-9]+ passed, 0 failed$' \
		>"$TMP_DIR/$name.log" 2>&1; then
		status=0
	else
		status=$?
	fi

	if [[ "$status" -ne "$expected_status" ]]; then
		echo "FAIL $name: status=$status expected=$expected_status" >&2
		cat "$TMP_DIR/$name.log" >&2
		failures=$((failures + 1))
	else
		echo "PASS $name"
	fi
}

run_case parse_error 1
run_case false_green 1
run_case resource_leak 1
run_case success 0
run_case wrong_version 1
run_case hang 1
run_case hang_after_summary 1

# The hang has to be reported as what it is, and within the limit rather than after the sleep.
if ! grep -q 'did not finish within 2s' "$TMP_DIR/hang.log"; then
	echo "FAIL hang: the time limit is not named" >&2
	cat "$TMP_DIR/hang.log" >&2
	failures=$((failures + 1))
else
	echo "PASS hang names the time limit"
fi

if [[ "$failures" -ne 0 ]]; then
	echo "run-godot-test contract: $failures failed" >&2
	exit 1
fi

echo 'run-godot-test contract: 8 passed, 0 failed'
