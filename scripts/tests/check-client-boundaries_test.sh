#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/scripts/check-client-boundaries.sh"
PASSED=0
FAILED=0
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT

fixture() {
	local dir
	dir="$(mktemp -d "$TASK_TMP/fixture.XXXXXX")"
	mkdir -p "$dir/apps/client/launcher" "$dir/apps/client/runtime/shooter" "$dir/apps/client/i18n"
	printf '%s\n' "$dir"
}

expect_pass() {
	local label="$1" target="$2"
	if "$CHECKER" "$target" >/dev/null 2>&1; then
		PASSED=$((PASSED + 1))
	else
		echo "FAIL: $label should pass" >&2
		FAILED=$((FAILED + 1))
	fi
}

# expect_fail <label> <target> <text>: the checker must fail and name the reason, so a case cannot pass because some other rule happened to trip.
expect_fail() {
	local label="$1" target="$2" text="$3" output status=0
	output="$("$CHECKER" "$target" 2>&1)" || status=$?
	if [[ "$status" -ne 0 && "$output" == *"$text"* ]]; then
		PASSED=$((PASSED + 1))
	else
		echo "FAIL: $label should fail with: $text" >&2
		FAILED=$((FAILED + 1))
	fi
}

LAUNCHER_PATHS="the launcher may import only res://launcher/, res://i18n/ and res://runtime/game_session.gd:"
LAUNCHER_CLASSES="the launcher may reach a runtime only through GameSession, never its classes:"
LAUNCHER_LOCAL="the launcher is local-only: no network classes, endpoints or URLs:"
RUNTIME_PATHS="the runtime may import only res://runtime/:"
RUNTIME_LAUNCHER="the runtime must not depend on the launcher:"
RUNTIME_NETWORK="the runtime must not open network connections or own URLs:"
I18N_PATHS="i18n may import only res://i18n/:"
SCREENS="screens live in apps/client/launcher only:"

# ---- the layout as it is ----

case_dir="$(fixture)"
printf '%s\n' 'class_name LauncherHomeScreen' 'extends LauncherScreen' 'const Strings := preload("res://i18n/strings.gd")' 'const ART := "res://launcher/art/shooter.jpg"' > "$case_dir/apps/client/launcher/home_screen.gd"
printf '%s\n' 'extends Control' 'const Session := preload("res://runtime/game_session.gd")' 'var _session: GameSession' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
printf '%s\n' '[ext_resource type="Script" path="res://launcher/launcher_root.gd" id="1"]' > "$case_dir/apps/client/launcher/launcher.tscn"
printf '%s\n' 'class_name GameSession' 'extends Node' 'const Loader := preload("res://runtime/runtime_loader.gd")' > "$case_dir/apps/client/runtime/game_session.gd"
printf '%s\n' 'class_name Strings' 'const LauncherTable := preload("res://i18n/launcher_strings.gd")' > "$case_dir/apps/client/i18n/strings.gd"
expect_pass "launcher screen, i18n and GameSession use" "$case_dir"

for required in launcher runtime i18n; do
	case_dir="$(fixture)"
	rm -rf "${case_dir:?}/apps/client/$required"
	expect_fail "missing $required" "$case_dir" "client boundary check: missing $case_dir/apps/client/$required"
done

# ---- launcher ----

case_dir="$(fixture)"
printf '%s\n' 'const Loader := preload("res://runtime/runtime_loader.gd")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher imports runtime internals by path" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const A := preload("res://runtime/game_session.gd"); const B := preload("res://runtime/shooter/shooter_play.gd")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher hides a runtime import behind the session import" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' '[ext_resource type="Script" path="res://runtime/shooter/shooter_world.gd" id="1"]' > "$case_dir/apps/client/launcher/stage.tscn"
expect_fail "launcher scene embeds a runtime script" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'func baseline() -> String:' '	return FileAccess.get_file_as_string("res://runtime/shooter/baseline.dsl.json")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher reads a runtime data file" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const Sync := preload("res://cloud/profile_sync.gd")' > "$case_dir/apps/client/launcher/launcher_store.gd"
expect_fail "launcher imports a directory outside the allowed three" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'var loader := RuntimeLoader.new()' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher uses a runtime class by name" "$case_dir" "$LAUNCHER_CLASSES"

case_dir="$(fixture)"
printf '%s\n' 'func patch(dsl: Dictionary) -> Dictionary:' '	return JsonPatch.apply(dsl, [])' > "$case_dir/apps/client/launcher/menu_screen.gd"
expect_fail "launcher patches a DSL itself" "$case_dir" "$LAUNCHER_CLASSES"

case_dir="$(fixture)"
printf '%s\n' 'var request := HTTPRequest.new()' > "$case_dir/apps/client/launcher/launcher_store.gd"
expect_fail "launcher makes a network request" "$case_dir" "$LAUNCHER_LOCAL"

case_dir="$(fixture)"
printf '%s\n' 'var socket := WebSocketPeer.new()' > "$case_dir/apps/client/launcher/launcher_store.gd"
expect_fail "launcher opens a socket" "$case_dir" "$LAUNCHER_LOCAL"

case_dir="$(fixture)"
printf '%s\n' 'const FEED := "https://example.test/games.json"' > "$case_dir/apps/client/launcher/launcher_catalog.gd"
expect_fail "launcher owns a URL" "$case_dir" "$LAUNCHER_LOCAL"

case_dir="$(fixture)"
printf '%s\n' 'const SCORES := "/api/v1/scores"' > "$case_dir/apps/client/launcher/launcher_store.gd"
expect_fail "launcher owns an endpoint" "$case_dir" "$LAUNCHER_LOCAL"

# ---- runtime ----

case_dir="$(fixture)"
printf '%s\n' 'const Store := preload("res://launcher/launcher_store.gd")' > "$case_dir/apps/client/runtime/game_session.gd"
expect_fail "runtime imports the launcher by path" "$case_dir" "$RUNTIME_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const Strings := preload("res://i18n/strings.gd")' > "$case_dir/apps/client/runtime/shooter/shooter_world.gd"
expect_fail "runtime imports i18n" "$case_dir" "$RUNTIME_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'func best() -> int:' '	return LauncherStore.new().stats("shooter")["best_score"]' > "$case_dir/apps/client/runtime/shooter/shooter_world.gd"
expect_fail "runtime uses a launcher class by name" "$case_dir" "$RUNTIME_LAUNCHER"

case_dir="$(fixture)"
printf '%s\n' 'var socket := WebSocketPeer.new()' > "$case_dir/apps/client/runtime/network_match_session.gd"
expect_fail "runtime opens a connection itself" "$case_dir" "$RUNTIME_NETWORK"

case_dir="$(fixture)"
printf '%s\n' 'const ROOMS := "wss://example.test/rooms"' > "$case_dir/apps/client/runtime/network_match_session.gd"
expect_fail "runtime owns an address" "$case_dir" "$RUNTIME_NETWORK"

# ---- i18n ----

case_dir="$(fixture)"
printf '%s\n' 'const Catalog := preload("res://launcher/launcher_catalog.gd")' > "$case_dir/apps/client/i18n/strings.gd"
expect_fail "i18n imports the launcher" "$case_dir" "$I18N_PATHS"

# ---- screens ----

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/overlay"
printf '%s\n' 'extends Control' > "$case_dir/apps/client/overlay/login_screen.gd"
expect_fail "screen outside the launcher" "$case_dir" "$SCREENS"

echo "check-client-boundaries_test: $PASSED passed, $FAILED failed"
test "$FAILED" -eq 0
