#!/usr/bin/env bash
# Render one console-launcher screen to a 1920x1080 PNG. Needs a real renderer (a desktop session), so it is not part of `make ci`.
#
#   scripts/run-launcher-shot.sh [screen] [state]
#
# screen defaults to "home", state to "played" ("fresh" renders an empty profile). The remaining knobs are environment variables read by apps/client/launcher/launcher_shot.gd: LAUNCHER_SHOT_ACTIONS, LAUNCHER_SHOT_LOCALE, LAUNCHER_SHOT_NAME and the rest listed at the top of that file. The PNG goes to LAUNCHER_SHOT_DIR (default ~/screenshots/classic-games/console-launcher).
#
# A game in play, with scripted input for each player (a game module; see docs/20-adding-a-game.md):
#
#   LAUNCHER_SHOT_GAME=<id> LAUNCHER_SHOT_PLAYERS=2 LAUNCHER_SHOT_INPUT="2:right+a/left;1:/a" scripts/run-launcher-shot.sh game
#
# LAUNCHER_SHOT_GAMES_ROOT=res://testing/games does the same for the test fixture module (LAUNCHER_SHOT_GAME=fixture_duo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
EXPECTED_VERSION="$(<"$ROOT/apps/client/.godot-version")"
ACTUAL_VERSION="$("$GODOT" --version)"

if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION".* ]]; then
	echo "Godot version mismatch: expected $EXPECTED_VERSION, got $ACTUAL_VERSION" >&2
	exit 1
fi

export LAUNCHER_SHOT_SCREEN="${1:-${LAUNCHER_SHOT_SCREEN:-home}}"
export LAUNCHER_SHOT_STATE="${2:-${LAUNCHER_SHOT_STATE:-played}}"
export LAUNCHER_SHOT_DIR="${LAUNCHER_SHOT_DIR:-$HOME/screenshots/classic-games/console-launcher}"
mkdir -p "$LAUNCHER_SHOT_DIR"

"$GODOT" --headless --path "$ROOT/apps/client" --import >/dev/null 2>&1

# A small window is enough: the launcher is rendered into its own 1920x1080 viewport. The script quits by itself after writing the file.
"$GODOT" --path "$ROOT/apps/client" --resolution 640x360 --script res://launcher/launcher_shot.gd
