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
	mkdir -p "$dir/apps/client/launcher" "$dir/apps/client/runtime/shooter" "$dir/apps/client/i18n" "$dir/apps/client/games/shared"
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
RUNTIME_PATHS="the runtime may import only res://runtime/ and res://games/shared/:"
LAUNCHER_GAME_CLASSES="the launcher may reach a game only through GameSession, never the game library's classes:"
SHARED_PATHS="the shared game library may import only res://games/shared/:"
SHARED_HOST="the shared game library must not depend on the launcher or the runtime:"
SHARED_NETWORK="the shared game library must not open network connections or own URLs:"
GAME_PATHS="a game may import only its own directory and res://games/shared/:"
GAME_HOST="a game must not depend on the launcher, the runtime or GameSession:"
GAME_NETWORK="a game must not open network connections or own URLs:"
GAME_APIS="a game reads input, sound and the stage through GameModule only"
GAME_CLASS_NAME="a game must not declare global class names (use preload):"
GAME_UP="a game must name resources by a full res:// path, not through a parent directory:"
GAME_UID="a game must name resources by a full res:// path, not by uid://"
GAME_GLUED="a game must write res:// paths whole, not build them from a bare prefix:"
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

# A game module, the shared library it builds on, the session that hosts it, and a test fixture game.
mkdir -p "$case_dir/apps/client/games/maze/levels" "$case_dir/apps/client/testing/games/fixture"
printf '%s\n' 'class_name GameModule' 'extends Node2D' 'const PlayerInput := preload("res://games/shared/game_input.gd")' > "$case_dir/apps/client/games/shared/game_module.gd"
printf '%s\n' 'class_name GameRegistry' 'const GAMES_ROOT := "res://games"' > "$case_dir/apps/client/games/shared/game_registry.gd"
printf '%s\n' 'class_name GameSession' 'extends Node' 'const Registry := preload("res://games/shared/game_registry.gd")' 'const Loader := preload("res://runtime/runtime_loader.gd")' > "$case_dir/apps/client/runtime/game_session.gd"
printf '%s\n' 'extends GameModule' 'const Level := preload("res://games/maze/levels/level.gd")' 'const Rng := preload("res://games/shared/game_rng.gd")' 'func _game_step(_delta: float) -> void:' '	if input(0).just_pressed(GameInput.A):' '		audio.play("bomb")' '	var player_input := input(1)' > "$case_dir/apps/client/games/maze/main.gd"
printf '%s\n' 'extends RefCounted' 'const DATA := "res://games/maze/levels/one.json"' > "$case_dir/apps/client/games/maze/levels/level.gd"
printf '%s\n' 'extends SceneTree' 'const Main := preload("res://games/maze/main.gd")' > "$case_dir/apps/client/games/maze/maze_test.gd"
printf '%s\n' 'extends GameModule' 'const Part := preload("res://testing/games/fixture/part.gd")' > "$case_dir/apps/client/testing/games/fixture/main.gd"
expect_pass "a game module, the shared library, the hosting session and a fixture game" "$case_dir"

for required in launcher runtime i18n games games/shared; do
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

case_dir="$(fixture)"
printf '%s\n' 'const Maze := preload("res://games/maze/main.gd")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher loads a game's script" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const Registry := preload("res://games/shared/game_registry.gd")' > "$case_dir/apps/client/launcher/launcher_catalog.gd"
expect_fail "launcher imports the game library by path" "$case_dir" "$LAUNCHER_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'func find() -> Dictionary:' '	return GameRegistry.catalog()' > "$case_dir/apps/client/launcher/launcher_catalog.gd"
expect_fail "launcher uses the game registry by name" "$case_dir" "$LAUNCHER_GAME_CLASSES"

case_dir="$(fixture)"
printf '%s\n' 'var _module: GameModule' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher holds a game module" "$case_dir" "$LAUNCHER_GAME_CLASSES"

case_dir="$(fixture)"
printf '%s\n' 'var _guide: LauncherGameGuide' 'var _session: GameSession' > "$case_dir/apps/client/launcher/game_screen.gd"
expect_pass "launcher names of its own that contain Game are not the game library" "$case_dir"

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

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/games/maze"
printf '%s\n' 'const Maze := preload("res://games/maze/main.gd")' > "$case_dir/apps/client/runtime/game_session.gd"
expect_fail "runtime imports a game instead of loading it from its manifest" "$case_dir" "$RUNTIME_PATHS"

# ---- shared game library ----

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/games/maze"
printf '%s\n' 'const Maze := preload("res://games/maze/main.gd")' > "$case_dir/apps/client/games/shared/game_registry.gd"
expect_fail "shared library imports a game" "$case_dir" "$SHARED_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const Session := preload("res://runtime/game_session.gd")' > "$case_dir/apps/client/games/shared/game_module.gd"
expect_fail "shared library imports the runtime" "$case_dir" "$SHARED_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'const GAMES_ROOT := "res://games"; const Maze := preload("res://games/maze/main.gd")' > "$case_dir/apps/client/games/shared/game_registry.gd"
expect_fail "shared library hides a game import behind the games root" "$case_dir" "$SHARED_PATHS"

case_dir="$(fixture)"
printf '%s\n' 'func best() -> int:' '	return LauncherStore.new().stats("maze")["best_score"]' > "$case_dir/apps/client/games/shared/game_module.gd"
expect_fail "shared library uses a launcher class" "$case_dir" "$SHARED_HOST"

case_dir="$(fixture)"
printf '%s\n' 'var session := GameSession.new()' > "$case_dir/apps/client/games/shared/game_module.gd"
expect_fail "shared library uses the session that hosts it" "$case_dir" "$SHARED_HOST"

case_dir="$(fixture)"
printf '%s\n' 'var request := HTTPRequest.new()' > "$case_dir/apps/client/games/shared/game_audio.gd"
expect_fail "shared library makes a network request" "$case_dir" "$SHARED_NETWORK"

# ---- games ----

# game_case <file content lines...>: a fixture with one game, games/maze/main.gd, holding those lines.
game_case() {
	case_dir="$(fixture)"
	mkdir -p "$case_dir/apps/client/games/maze" "$case_dir/apps/client/games/tank"
	printf '%s\n' "$@" > "$case_dir/apps/client/games/maze/main.gd"
}

game_case 'const Tank := preload("res://games/tank/main.gd")'
expect_fail "game imports another game" "$case_dir" "$GAME_PATHS"

game_case 'const Own := preload("res://games/maze/level.gd"); const Tank := preload("res://games/tank/main.gd")'
expect_fail "game hides another game behind its own import" "$case_dir" "$GAME_PATHS"

game_case 'const Tokens := preload("res://launcher/launcher_tokens.gd")'
expect_fail "game imports launcher code" "$case_dir" "$GAME_PATHS"

game_case 'const Session := preload("res://runtime/game_session.gd")'
expect_fail "game imports the runtime" "$case_dir" "$GAME_PATHS"

game_case 'const Strings := preload("res://i18n/strings.gd")'
expect_fail "game imports the launcher strings" "$case_dir" "$GAME_PATHS"

game_case 'const DATA := "res://games/mazes/level.json"'
expect_fail "game reads a directory whose name merely starts like its own" "$case_dir" "$GAME_PATHS"

game_case 'func best() -> int:' '	return LauncherStore.new().stats("maze")["best_score"]'
expect_fail "game uses a launcher class by name" "$case_dir" "$GAME_HOST"

game_case 'var session := GameSession.new()'
expect_fail "game uses GameSession" "$case_dir" "$GAME_HOST"

game_case 'var socket := WebSocketPeer.new()'
expect_fail "game opens a socket" "$case_dir" "$GAME_NETWORK"

game_case 'const SCORES := "https://example.test/scores"'
expect_fail "game owns a URL" "$case_dir" "$GAME_NETWORK"

game_case 'func _game_step(_delta: float) -> void:' '	if Input.is_action_pressed("launcher_accept"):' '		pass'
expect_fail "game polls global input" "$case_dir" "$GAME_APIS"

game_case 'func _unhandled_input(event) -> void:' '	pass'
expect_fail "game handles raw input events" "$case_dir" "$GAME_APIS"

game_case 'func _input(event) -> void:' '	pass'
expect_fail "game handles raw input events early" "$case_dir" "$GAME_APIS"

game_case 'func keys() -> Array:' '	return InputMap.get_actions()'
expect_fail "game reads the input map" "$case_dir" "$GAME_APIS"

game_case 'const SAVE := "user://maze.save"'
expect_fail "game writes its own save file" "$case_dir" "$GAME_APIS"

game_case 'func mute() -> void:' '	AudioServer.set_bus_mute(0, true)'
expect_fail "game touches the audio buses" "$case_dir" "$GAME_APIS"

game_case 'func grow() -> void:' '	DisplayServer.window_set_size(Vector2i(100, 100))'
expect_fail "game touches the window" "$case_dir" "$GAME_APIS"

game_case 'func stop() -> void:' '	get_tree().paused = true'
expect_fail "game pauses the whole tree" "$case_dir" "$GAME_APIS"

game_case 'func home() -> String:' '	return OS.get_environment("HOME")'
expect_fail "game reads the operating system" "$case_dir" "$GAME_APIS"

game_case 'class_name MazePlayer' 'extends Node2D'
expect_fail "game declares a global class name" "$case_dir" "$GAME_CLASS_NAME"

# Ways around the res:// rules: a path that is not written as a whole res:// path.
game_case 'const Tank := preload("../tank/main.gd")'
expect_fail "game imports another game through a parent directory" "$case_dir" "$GAME_UP"

game_case 'const Store := preload("../../launcher/launcher_store.gd")'
expect_fail "game imports launcher code through a parent directory" "$case_dir" "$GAME_UP"

game_case 'func tank() -> Resource:' '	return load("levels/../../tank/main.gd")'
expect_fail "game climbs out of its directory in the middle of a path" "$case_dir" "$GAME_UP"

game_case 'const Tank := preload("uid://b8x2k4tank01")'
expect_fail "game imports by uid" "$case_dir" "$GAME_UID"

game_case 'func tank() -> Resource:' '	return load("res://" + "games/tank/main.gd")'
expect_fail "game glues a path onto a bare res:// prefix" "$case_dir" "$GAME_PATHS"

game_case 'func store() -> Resource:' '	return load("res:" + "//launcher/launcher_store.gd")'
expect_fail "game splits the res:// prefix itself" "$case_dir" "$GAME_GLUED"

game_case 'const Level := preload("levels/one.gd")' 'const DATA := "res://games/maze/levels/%d.json"' '# see ../README.md'
expect_pass "a path below the game's own directory, a formatted own path and a comment are fine" "$case_dir"

game_case 'var peer := ENetMultiplayerPeer.new()'
expect_fail "game hosts a multiplayer peer" "$case_dir" "$GAME_NETWORK"

game_case 'var peer := WebRTCMultiplayerPeer.new()'
expect_fail "game opens a WebRTC peer" "$case_dir" "$GAME_NETWORK"

game_case 'var stream := StreamPeerTCP.new()'
expect_fail "game opens a TCP stream" "$case_dir" "$GAME_NETWORK"

game_case 'func where() -> String:' '	return IP.resolve_hostname("example.org")'
expect_fail "game resolves a host name" "$case_dir" "$GAME_NETWORK"

game_case 'func fetch() -> void:' '	JavaScriptBridge.eval("fetch(1)")'
expect_fail "game runs script in the browser" "$case_dir" "$GAME_NETWORK"

game_case 'func size() -> Vector2:' '	return get_viewport().get_visible_rect().size'
expect_fail "game reads the viewport" "$case_dir" "$GAME_APIS"

game_case 'func save() -> void:' '	FileAccess.open("/tmp/maze.save", FileAccess.WRITE)'
expect_fail "game writes a file" "$case_dir" "$GAME_APIS"

game_case 'func save(level: Resource) -> void:' '	ResourceSaver.save(level, "res://games/maze/level.tres")'
expect_fail "game saves a resource" "$case_dir" "$GAME_APIS"

game_case 'func peer() -> Object:' '	return ClassDB.instantiate("HTTP" + "Request")'
expect_fail "game instantiates a class by a built name" "$case_dir" "$GAME_APIS"

game_case 'func shell() -> Node:' '	return get_node("/root/LauncherRoot")'
expect_fail "game reaches for the root of the tree by path" "$case_dir" "$GAME_APIS"

game_case 'func loop() -> MainLoop:' '	return Engine.get_main_loop()'
expect_fail "game reaches for the main loop" "$case_dir" "$GAME_APIS"

game_case 'func _gui_input(event: Variant) -> void:' '	pass'
expect_fail "game handles pointer input on a control" "$case_dir" "$GAME_APIS"

game_case 'func load_level(index: int) -> String:' '	return FileAccess.get_file_as_string("res://games/maze/levels/%d.json" % index)' 'func tiles() -> PackedByteArray:' '	return FileAccess.open("res://games/maze/tiles.bin", FileAccess.READ).get_buffer(64)'
expect_pass "a game may read its own data files" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const Maze := preload("../games/maze/main.gd")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher reaches into a game through a parent directory" "$case_dir" "the launcher must name resources by a full res:// path, not through a parent directory:"

case_dir="$(fixture)"
printf '%s\n' 'const Maze := preload("uid://c1maze")' > "$case_dir/apps/client/launcher/launcher_game_host.gd"
expect_fail "launcher reaches into a game by uid" "$case_dir" "the launcher must name resources by a full res:// path, not by uid://"

case_dir="$(fixture)"
printf '%s\n' '[ext_resource type="Script" path="../games/maze/main.gd" id="1"]' > "$case_dir/apps/client/launcher/launcher.tscn"
expect_fail "launcher scene reaches into a game through a parent directory" "$case_dir" "the launcher must name resources by a full res:// path, not through a parent directory:"

case_dir="$(fixture)"
printf '%s\n' 'const Store := preload("../launcher/launcher_store.gd")' > "$case_dir/apps/client/games/shared/game_module.gd"
expect_fail "shared library reaches the launcher through a parent directory" "$case_dir" "the shared game library must name resources by a full res:// path, not through a parent directory:"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/testing/games/fixture"
printf '%s\n' 'const Shooter := preload("res://runtime/shooter/shooter_play.gd")' > "$case_dir/apps/client/testing/games/fixture/main.gd"
expect_fail "a fixture game is held to the same import rule" "$case_dir" "$GAME_PATHS"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/testing/games/fixture"
printf '%s\n' 'func _game_step(_delta: float) -> void:' '	Input.get_vector("a", "b", "c", "d")' > "$case_dir/apps/client/testing/games/fixture/main.gd"
expect_fail "and to the same input rule" "$case_dir" "$GAME_APIS"

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
