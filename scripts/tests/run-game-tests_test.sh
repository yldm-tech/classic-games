#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/run-game-tests.sh"
PASSED=0
FAILED=0
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT

# A stand-in for run-godot-test.sh: records what it was asked to run and fails for any test whose path contains "broken".
RUNNER="$TASK_TMP/runner.sh"
CALLS="$TASK_TMP/calls.log"
cat > "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$2" >> "$CALLS_LOG"
[[ "$1" != *broken* ]]
RUNNER_EOF
chmod +x "$RUNNER"

client() {
	local dir
	dir="$(mktemp -d "$TASK_TMP/client.XXXXXX")"
	mkdir -p "$dir/games/shared"
	printf '%s\n' "$dir"
}

run() {
	: > "$CALLS"
	CALLS_LOG="$CALLS" GAME_TEST_RUNNER="$RUNNER" "$SCRIPT" "$1"
}

check() {
	local label="$1"
	shift
	if "$@"; then
		PASSED=$((PASSED + 1))
	else
		echo "FAIL: $label" >&2
		FAILED=$((FAILED + 1))
	fi
}

# ---- no tests at all is a failure ----

case_dir="$(client)"
status=0
output="$(run "$case_dir" 2>&1)" || status=$?
check "no test file fails" test "$status" -ne 0
check "and says why" grep -q 'no \*_test.gd found' <<< "$output"

status=0
output="$(run "$TASK_TMP/nowhere" 2>&1)" || status=$?
check "a missing games directory fails" test "$status" -ne 0

# ---- discovery ----

case_dir="$(client)"
mkdir -p "$case_dir/games/maze" "$case_dir/games/tank/levels" "$case_dir/testing/games/fixture"
touch "$case_dir/games/shared/shared_test.gd" "$case_dir/games/maze/maze_test.gd" "$case_dir/games/maze/maze_rules_test.gd" "$case_dir/games/tank/tank_test.gd"
touch "$case_dir/games/tank/levels/level_test.gd" "$case_dir/games/maze/main.gd" "$case_dir/games/stray_test.gd"
touch "$case_dir/testing/module_contract_test.gd" "$case_dir/testing/games/fixture/main.gd" "$case_dir/testing/games/fixture/fixture_test.gd"
status=0
output="$(run "$case_dir" 2>&1)" || status=$?
check "a tree of passing tests passes" test "$status" -eq 0
check "every game's test files and the contract tests run, and nothing else" test "$(cut -d' ' -f1 "$CALLS" | tr '\n' ' ')" = "res://games/maze/maze_rules_test.gd res://games/maze/maze_test.gd res://games/shared/shared_test.gd res://games/tank/tank_test.gd res://testing/games/fixture/fixture_test.gd res://testing/module_contract_test.gd "
check "each is held to its own summary line" grep -qF 'res://games/maze/maze_test.gd ^maze_test: [0-9]+ passed, 0 failed$' "$CALLS"
check "the count is reported" grep -q 'game tests: 6 test files passed' <<< "$output"

# ---- one failure fails the run, after the others still ran ----

case_dir="$(client)"
mkdir -p "$case_dir/games/alpha" "$case_dir/games/broken" "$case_dir/games/zeta"
touch "$case_dir/games/alpha/alpha_test.gd" "$case_dir/games/broken/broken_test.gd" "$case_dir/games/zeta/zeta_test.gd"
status=0
output="$(run "$case_dir" 2>&1)" || status=$?
check "a failing test fails the run" test "$status" -ne 0
check "and is named" grep -q 'res://games/broken/broken_test.gd' <<< "$output"
check "the tests after it still ran" grep -q 'res://games/zeta/zeta_test.gd' "$CALLS"

echo "run-game-tests_test: $PASSED passed, $FAILED failed"
test "$FAILED" -eq 0
