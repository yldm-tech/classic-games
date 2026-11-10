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
		echo 'shell_ui_test: 224 passed, 0 failed'
		echo 'WARNING: ObjectDB instances leaked at exit'
		;;
	success)
		echo 'shell_ui_test: 224 passed, 0 failed'
		;;
	wrong_version)
		echo 'shell_ui_test: 224 passed, 0 failed'
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

	if FAKE_MODE="$name" GODOT="$FAKE_GODOT" "$RUNNER" \
		res://shell_ui_test.gd '^shell_ui_test: [0-9]+ passed, 0 failed$' \
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

if [[ "$failures" -ne 0 ]]; then
	echo "run-godot-test contract: $failures failed" >&2
	exit 1
fi

echo 'run-godot-test contract: 5 passed, 0 failed'
