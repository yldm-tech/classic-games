#!/usr/bin/env bash
# Backend smoke test over real HTTP: build and start the Go backend with a fresh database, then drive the endpoints that serve and transform runtime content, and compare what comes back with the files the Godot client ships (apps/client/runtime).
#
#   scripts/spike-integration.sh      (PORT=8099 by default; needs go, curl and jq)
#
# The Godot client is not involved: the launcher is local-only and never calls the backend. Not part of `make ci`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8099}"
RUNTIME_DIR="$ROOT/apps/client/runtime"
API="http://127.0.0.1:$PORT/api/v1"
PASSED=0
FAILED=0

for tool in go curl jq; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "spike-integration: $tool is required" >&2
		exit 1
	fi
done

WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() {
	if [[ -n "$SERVER_PID" ]]; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

(cd "$ROOT/apps/server" && go build -o "$WORK/server" ./cmd/server)

# The backend runs in the scratch directory, so its SQLite file is created there and removed with it; every content path is therefore absolute. CLASSIC_GAMES_DEV_ADMIN is not set: nothing below needs a moderator.
(
	cd "$WORK"
	PORT="$PORT" \
		CLASSIC_GAMES_SCHEMA_DIR="$ROOT/packages/schemas" \
		CLASSIC_GAMES_RUNTIME_DIR="$RUNTIME_DIR" \
		CLASSIC_GAMES_BASELINE="$RUNTIME_DIR/shooter/baseline.dsl.json" \
		CLASSIC_GAMES_SURVIVOR_BASELINE="$RUNTIME_DIR/survivor/baseline.dsl.json" \
		CLASSIC_GAMES_TOWER_DEFENSE_BASELINE="$RUNTIME_DIR/tower_defense/baseline.dsl.json" \
		exec "$WORK/server" >"$WORK/server.log" 2>&1
) &
SERVER_PID=$!

# curl's own retry waits for the port, so no sleep is needed.
if ! curl -s --retry-connrefused --retry 40 --retry-delay 1 -o /dev/null "http://127.0.0.1:$PORT/healthz"; then
	echo "spike-integration: the backend did not become ready" >&2
	cat "$WORK/server.log" >&2
	exit 1
fi
# Something else may already listen on the port and answer /healthz in the backend's place; the backend started here then fails to bind and exits.
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
	echo "spike-integration: the backend exited during startup (is port $PORT in use?)" >&2
	cat "$WORK/server.log" >&2
	exit 1
fi

check() {
	local label="$1"
	shift
	if "$@"; then
		PASSED=$((PASSED + 1))
		echo "  PASS  $label"
	else
		FAILED=$((FAILED + 1))
		echo "  FAIL  $label"
	fi
}

# call <METHOD> <path> [json-body]: the response body goes to $WORK/body, the HTTP status to $STATUS.
STATUS=""
TOKEN=""
call() {
	local method="$1" path="$2" args=(-s -o "$WORK/body" -w '%{http_code}' -X "$1" -H 'Content-Type: application/json')
	if [[ -n "$TOKEN" ]]; then
		args+=(-H "Authorization: Bearer $TOKEN")
	fi
	if [[ "$#" -ge 3 ]]; then
		args+=(--data-binary "$3")
	fi
	STATUS="$(curl "${args[@]}" "$API$path")"
}

status_is() { [[ "$STATUS" == "$1" ]]; }
# body_is [jq-option]... <jq-filter>: the filter must evaluate to true on the response body.
body_is() { jq -e "$@" "$WORK/body" >/dev/null 2>&1; }
# same_json <file-a> <file-b>: equal as JSON values, whatever the key order, the whitespace and the spelling of numbers (1 and 1.0).
same_json() { jq -e -n --slurpfile a "$1" --slurpfile b "$2" '$a == $b' >/dev/null 2>&1; }

# ---- authentication ----

call POST /mods '{}'
check "a write without a session is rejected with 401 AUTH_REQUIRED" body_is '.error.code == "AUTH_REQUIRED"'
check "and the status is 401" status_is 401

call POST /auth/guest '{}'
check "guest login returns 200" status_is 200
TOKEN="$(jq -r '.token // ""' "$WORK/body")"
check "guest login returns a token" test -n "$TOKEN"

# ---- runtime content served by the backend is the client's ----

for runtime in shooter survivor tower_defense; do
	call GET "/runtimes/$runtime/1.0.0/baseline"
	check "$runtime baseline is served" status_is 200
	check "$runtime baseline equals apps/client/runtime/$runtime/baseline.dsl.json" same_json "$WORK/body" "$RUNTIME_DIR/$runtime/baseline.dsl.json"
	call GET "/runtimes/$runtime/1.0.0/schema"
	check "$runtime schema is served" status_is 200

	call POST /ai/validate "$(jq -n --slurpfile dsl "$RUNTIME_DIR/$runtime/baseline.dsl.json" --arg runtime "$runtime@1.0.0" '{runtime: $runtime, dsl: $dsl[0]}')"
	check "$runtime baseline passes /ai/validate" body_is '.valid == true'
done

SHOOTER="$RUNTIME_DIR/shooter/baseline.dsl.json"

call POST /ai/validate "$(jq -n --slurpfile dsl "$SHOOTER" '{runtime: "shooter@1.0.0", dsl: ($dsl[0] | .player.hp = 9999)}')"
check "an out-of-range value is rejected with 422" status_is 422
check "and the error envelope says DSL_INVALID" body_is '.error.code == "DSL_INVALID"'

# Without ANTHROPIC_API_KEY the backend answers /ai/mod with its built-in stub provider, which is what makes this deterministic.
call POST /ai/mod "$(jq -n --slurpfile dsl "$SHOOTER" '{runtime: "shooter@1.0.0", current_dsl: $dsl[0], prompt: "把飞机换成猫"}')"
check "/ai/mod returns 200" status_is 200
check "/ai/mod returns a patch and the patched DSL" body_is '(.dsl_patch | length) > 0 and .new_dsl.player.sprite == "cat"'

# ---- fork chain: the same patches and the same golden as packages/dsl and the client's runtime/json_patch.gd ----

call POST /mods '{"runtime": "shooter@1.0.0", "parent_id": "", "patch": [{"op": "replace", "path": "/player/sprite", "value": "cat"}]}'
check "creating a root mod returns 201" status_is 201
ROOT_MOD="$(jq -r '.id // ""' "$WORK/body")"

call GET "/mods/$ROOT_MOD/dsl"
check "the root mod's effective DSL carries its patch" body_is '.player.sprite == "cat" and (.enemies | has("turret_1"))'

call POST "/mods/$ROOT_MOD/fork" '{}'
check "forking returns 201 with the parent set" body_is --arg parent "$ROOT_MOD" '.parent_id == $parent'
FORK_MOD="$(jq -r '.id // ""' "$WORK/body")"

call POST /mods "$(jq -n --arg parent "$FORK_MOD" '{runtime: "shooter@1.0.0", parent_id: $parent, patch: [
	{op: "add", path: "/enemies/bird_1", value: {type: "bird", behavior: "sine", count: 10, hp: 15, speed: 12}},
	{op: "replace", path: "/enemies/dog_1/count", value: 30},
	{op: "remove", path: "/enemies/turret_1"}]}')"
check "creating a child of the fork returns 201" status_is 201
CHILD_MOD="$(jq -r '.id // ""' "$WORK/body")"

call GET "/mods/$CHILD_MOD/dsl"
check "the child's effective DSL equals the shared golden fork_expected.dsl.json" same_json "$WORK/body" "$RUNTIME_DIR/shooter/testdata/fork_expected.dsl.json"

# The backend stores a patch without applying it; a patch that does not apply shows when the effective DSL is asked for.
call POST /mods '{"runtime": "shooter@1.0.0", "parent_id": "", "patch": [{"op": "replace", "path": "/player/nope", "value": 1}]}'
BROKEN_MOD="$(jq -r '.id // ""' "$WORK/body")"
call GET "/mods/$BROKEN_MOD/dsl"
check "a mod whose patch does not apply has no effective DSL (422)" status_is 422
check "and the error envelope says DSL_INVALID" body_is '.error.code == "DSL_INVALID"'

echo
echo "=== spike-integration: $PASSED passed, $FAILED failed ==="
test "$FAILED" -eq 0
