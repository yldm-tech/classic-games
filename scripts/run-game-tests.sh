#!/usr/bin/env bash
# Run every game's headless tests with the fail-closed Godot runner.
#
# A test is any apps/client/games/<dir>/*_test.gd (a game's own tests, and the shared library's), apps/client/testing/*_test.gd (the module contract tests that use the fixture module) or apps/client/testing/games/<dir>/*_test.gd (the fixture module's own). Nothing lists them: adding a game with a test file adds its tests here, in `make ci` and in the GitHub workflow.
#
# Each test script must end by printing "<file name without .gd>: <n> passed, 0 failed". Finding no test at all is a failure, not a pass.
#
#   scripts/run-game-tests.sh [client-dir]
#
# GAME_TEST_RUNNER replaces scripts/run-godot-test.sh (the self-test uses it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="${1:-$ROOT/apps/client}"
RUNNER="${GAME_TEST_RUNNER:-$ROOT/scripts/run-godot-test.sh}"

if [[ ! -d "$CLIENT/games" ]]; then
	echo "game tests: missing $CLIENT/games" >&2
	exit 1
fi

TESTS=()
while IFS= read -r file; do
	[[ -n "$file" ]] && TESTS+=("$file")
done < <(
	{
		find "$CLIENT/games" -mindepth 2 -maxdepth 2 -type f -name '*_test.gd'
		if [[ -d "$CLIENT/testing" ]]; then
			find "$CLIENT/testing" -mindepth 1 -maxdepth 1 -type f -name '*_test.gd'
		fi
		if [[ -d "$CLIENT/testing/games" ]]; then
			find "$CLIENT/testing/games" -mindepth 2 -maxdepth 2 -type f -name '*_test.gd'
		fi
	} | LC_ALL=C sort
)

if [[ "${#TESTS[@]}" -eq 0 ]]; then
	echo "game tests: no *_test.gd found under $CLIENT/games or $CLIENT/testing" >&2
	exit 1
fi

FAILED=()
for file in "${TESTS[@]}"; do
	name="$(basename "$file" .gd)"
	resource="res://${file#"$CLIENT"/}"
	echo "== $resource"
	if ! "$RUNNER" "$resource" "^${name}: [0-9]+ passed, 0 failed\$"; then
		FAILED+=("$resource")
	fi
done

if [[ "${#FAILED[@]}" -ne 0 ]]; then
	echo "game tests: ${#FAILED[@]} of ${#TESTS[@]} failed:" >&2
	printf '  %s\n' "${FAILED[@]}" >&2
	exit 1
fi

echo "game tests: ${#TESTS[@]} test files passed"
