#!/usr/bin/env bash
# Game discovery has to work in an exported build, where res:// is a pack and not a directory on disk. This exports the client's resource pack (no export templates needed), runs the manifest check from inside it with no project directory in reach, and requires that every game in the source tree is found there and that the test fixtures are not shipped.
#
# The same goes for a game's media: in a pack the pictures and audio files exist only in their imported form. Every image and audio file of every shipped game is loaded from inside the pack. And because a shipped game may not use every kind of medium, a second pack is exported from a copy of the project in which the fixtures are not excluded, and the fixture module that uses all of them (a sprite atlas with its frame table, a tiled texture, looping music, a stinger and a sound effect from files) is loaded and played from inside that pack.
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
for filter in 'include_filter="*.json"' 'exclude_filter="testing/*,games/*/site_screenshot.*"'; do
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

# count_media <dir> <name pattern>...: media files under a games root, the website screenshots aside (the presets keep those out of the pack).
count_media() {
	local dir="$1"
	shift
	local patterns=()
	local pattern
	for pattern in "$@"; do
		[[ "${#patterns[@]}" -gt 0 ]] && patterns+=(-o)
		patterns+=(-iname "$pattern")
	done
	find "$dir" -mindepth 2 -type f \( "${patterns[@]}" \) ! -name 'site_screenshot.*' | wc -l | tr -d ' '
}

# run_media_check <pack> <roots> <log>: load every medium of the games under <roots> from inside <pack>.
run_media_check() {
	local pack="$1" roots="$2" log="$3" status=0
	(cd "$WORK/empty" && GAME_CHECK_ROOTS="$roots" "$GODOT" --headless --main-pack "$pack" --script res://games/shared/media_check.gd) > "$log" 2>&1 || status=$?
	return "$status"
}

EXPECTED_IMAGES="$(count_media "$CLIENT/games" '*.png' '*.jpg' '*.jpeg' '*.webp')"
EXPECTED_AUDIO="$(count_media "$CLIENT/games" '*.ogg' '*.wav' '*.mp3')"
if ! run_media_check "$WORK/client.pck" "res://games" "$WORK/media.log" || ! grep -Eq "^media_check: ${EXPECTED_IMAGES} images, ${EXPECTED_AUDIO} audio files, [0-9]+ frame tables, 0 problems\$" "$WORK/media.log"; then
	cat "$WORK/media.log" >&2
	echo "export discovery: the exported pack must hold all $EXPECTED_IMAGES images and $EXPECTED_AUDIO audio files of the shipped games, loadable" >&2
	exit 1
fi

# The fixture pack: the same project with the fixtures left in, exported from a copy so that neither the working tree nor its import cache is touched.
FIXTURE_CLIENT="$WORK/fixture-client"
mkdir "$FIXTURE_CLIENT"
(cd "$CLIENT" && tar -cf - --exclude './.godot' .) | (cd "$FIXTURE_CLIENT" && tar -xf -)
sed 's|^exclude_filter="testing/\*,games/\*/site_screenshot\.\*"$|exclude_filter="games/*/site_screenshot.*"|' "$CLIENT/export_presets.cfg" > "$FIXTURE_CLIENT/export_presets.cfg"
"$GODOT" --headless --path "$FIXTURE_CLIENT" --import > "$WORK/fixture-import.log" 2>&1 || { cat "$WORK/fixture-import.log" >&2; echo "export discovery: importing the fixture copy failed" >&2; exit 1; }
if ! "$GODOT" --headless --path "$FIXTURE_CLIENT" --export-pack "$PRESET" "$WORK/fixtures.pck" > "$WORK/fixture-export.log" 2>&1 || [[ ! -s "$WORK/fixtures.pck" ]]; then
	cat "$WORK/fixture-export.log" >&2
	echo "export discovery: exporting the fixture pack failed" >&2
	exit 1
fi
FIXTURE_IMAGES="$(count_media "$CLIENT/testing/games" '*.png' '*.jpg' '*.jpeg' '*.webp')"
FIXTURE_AUDIO="$(count_media "$CLIENT/testing/games" '*.ogg' '*.wav' '*.mp3')"
if [[ "$FIXTURE_IMAGES" -lt 2 || "$FIXTURE_AUDIO" -lt 3 ]]; then
	echo "export discovery: the fixtures under $CLIENT/testing/games must hold an atlas, a texture, music, a stinger and a sound effect, or this check proves nothing" >&2
	exit 1
fi
if ! run_media_check "$WORK/fixtures.pck" "res://testing/games" "$WORK/fixture-media.log" || ! grep -Eq "^media_check: ${FIXTURE_IMAGES} images, ${FIXTURE_AUDIO} audio files, [1-9][0-9]* frame tables, 0 problems\$" "$WORK/fixture-media.log"; then
	cat "$WORK/fixture-media.log" >&2
	echo "export discovery: an exported pack must hold a module's images, audio files and frame tables, loadable" >&2
	exit 1
fi
# And the module that uses them runs there: its own test loads the atlas, the texture and the three kinds of audio file and plays a run to the end.
FIXTURE_TEST_STATUS=0
(cd "$WORK/empty" && "$GODOT" --headless --main-pack "$WORK/fixtures.pck" --script res://testing/games/fixture_gallery/fixture_gallery_test.gd) > "$WORK/fixture-test.log" 2>&1 || FIXTURE_TEST_STATUS=$?
if [[ "$FIXTURE_TEST_STATUS" -ne 0 ]] || ! grep -Eq '^fixture_gallery_test: [0-9]+ passed, 0 failed$' "$WORK/fixture-test.log" || grep -Eq 'ERROR|SCRIPT ERROR' "$WORK/fixture-test.log"; then
	cat "$WORK/fixture-test.log" >&2
	echo "export discovery: the fixture module with recorded audio and high-resolution art does not run from an exported pack" >&2
	exit 1
fi

echo "export discovery: passed ($EXPECTED_GAMES games with $EXPECTED_IMAGES images and $EXPECTED_AUDIO audio files found and loadable in the exported pack, fixtures excluded; a module's atlas, texture, music, stinger and sound effect load and play from a pack)"
