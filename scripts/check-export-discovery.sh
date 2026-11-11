#!/usr/bin/env bash
# Game discovery has to work in an exported build, where res:// is a pack and not a directory on disk. This exports the client's resource pack (no export templates needed), runs the manifest check from inside it with no project directory in reach, and requires that every game in the source tree is found there and that the test fixtures are not shipped.
#
#   scripts/check-export-discovery.sh
#
# GODOT picks the binary; EXPORT_PRESET the preset (default "Windows Desktop": every preset has the same resource filters, and this one exports without any platform setup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/apps/client"
GODOT="${GODOT:-godot}"
PRESET="${EXPORT_PRESET:-Windows Desktop}"
EXPECTED_VERSION="$(<"$CLIENT/.godot-version")"
ACTUAL_VERSION="$("$GODOT" --version)"

if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION".* ]]; then
	echo "Godot version mismatch: expected $EXPECTED_VERSION, got $ACTUAL_VERSION" >&2
	exit 1
fi

# Every preset must carry the filters, or a build for that platform could ship the fixtures.
PRESETS="$(grep -c '^\[preset\.[0-9]*\]$' "$CLIENT/export_presets.cfg")"
for filter in 'include_filter="*.json"' 'exclude_filter="testing/*"'; do
	if [[ "$(grep -cFx "$filter" "$CLIENT/export_presets.cfg")" -ne "$PRESETS" ]]; then
		echo "export discovery: every preset in export_presets.cfg needs $filter" >&2
		exit 1
	fi
done

EXPECTED_GAMES="$(find "$CLIENT/games" -mindepth 2 -maxdepth 2 -type f -name game.json | wc -l | tr -d ' ')"
if [[ "$EXPECTED_GAMES" -eq 0 ]]; then
	echo "export discovery: no game.json under $CLIENT/games" >&2
	exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/empty"

"$GODOT" --headless --path "$CLIENT" --import > "$WORK/import.log" 2>&1 || { cat "$WORK/import.log" >&2; echo "export discovery: import failed" >&2; exit 1; }
if ! "$GODOT" --headless --path "$CLIENT" --export-pack "$PRESET" "$WORK/client.pck" > "$WORK/export.log" 2>&1 || [[ ! -s "$WORK/client.pck" ]]; then
	cat "$WORK/export.log" >&2
	echo "export discovery: exporting the pack failed" >&2
	exit 1
fi

# Run from an empty directory so nothing but the pack can answer for res://.
run_in_pack() {
	local roots="$1" log="$2" status=0
	(cd "$WORK/empty" && GAME_CHECK_ROOTS="$roots" GAME_CHECK_MANIFESTS_ONLY=1 "$GODOT" --headless --main-pack "$WORK/client.pck" --script res://games/shared/manifest_check.gd) > "$log" 2>&1 || status=$?
	return "$status"
}

if ! run_in_pack "res://games" "$WORK/games.log" || ! grep -Eq "^manifest_check: ${EXPECTED_GAMES} games, 0 problems\$" "$WORK/games.log"; then
	cat "$WORK/games.log" >&2
	echo "export discovery: the exported pack does not hold all $EXPECTED_GAMES games with valid manifests" >&2
	exit 1
fi

if run_in_pack "res://testing/games" "$WORK/fixtures.log" || ! grep -Fq "res://testing/games: no game found there" "$WORK/fixtures.log"; then
	cat "$WORK/fixtures.log" >&2
	echo "export discovery: the test fixtures must not be in the exported pack" >&2
	exit 1
fi

echo "export discovery: passed ($EXPECTED_GAMES games found in the exported pack, fixtures excluded)"
