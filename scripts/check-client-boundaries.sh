#!/usr/bin/env bash
# Dependency directions inside the Godot client (apps/client):
#
#   launcher      -> i18n
#                \-> runtime/game_session.gd (this one file)
#   runtime       -> runtime/ and games/shared/
#   games/shared  -> nothing outside games/shared/
#   games/<id>    -> its own directory and games/shared/ (never the launcher, the runtime or another game)
#   i18n          -> nothing outside i18n/
#
# The launcher is local-only: no network classes, no endpoints, no URLs. A game module (games/<id>/, and the test fixtures under testing/games/) also keeps its hands off what the host owns: global input, the window, the audio buses, user:// and global class names. See docs/16-client-architecture.md and docs/20-adding-a-game.md.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="$ROOT/apps/client"
LAUNCHER="$CLIENT/launcher"
RUNTIME="$CLIENT/runtime"
I18N="$CLIENT/i18n"
GAMES="$CLIENT/games"
SHARED="$GAMES/shared"
FIXTURE_GAMES="$CLIENT/testing/games"
FAILED=0

# shellcheck source=lib/scan.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/scan.sh"

# Every scanned tree is required up front: a rule that scans a directory which is not there would pass vacuously.
for required in "$LAUNCHER" "$RUNTIME" "$I18N" "$GAMES" "$SHARED"; do
	if [[ ! -d "$required" ]]; then
		echo "client boundary check: missing $required" >&2
		exit 1
	fi
done

report_matches() {
	local message="$1"
	shift
	local matches
	# No `|| true` here: scan_* already distinguishes "no matches" from "grep failed", and a scan failure must abort the guard rather than read as a clean result.
	matches="$("$@")"
	if [[ -n "$matches" ]]; then
		echo "$message" >&2
		echo "$matches" >&2
		FAILED=1
	fi
}

# report_foreign_paths <message> <dir> <allowed-prefix>...: every res:// path written in <dir> has to start with one of the allowed prefixes. A line passes only when removing the allowed paths leaves no res:// behind, so a forbidden import cannot hide behind an allowed one on the same line.
report_foreign_paths() {
	local message="$1" dir="$2"
	shift 2
	local hits hit rest allowed
	# Captured before the loop instead of streamed from `< <(...)`: an abort inside a process substitution would kill only that subshell and leave the loop looking clean.
	hits="$(scan_lines 'res://' "$dir" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}")"
	while IFS= read -r hit; do
		[[ -z "$hit" ]] && continue
		rest="$hit"
		for allowed in "$@"; do
			rest="${rest//"$allowed"/}"
		done
		if [[ "$rest" == *"res://"* ]]; then
			echo "$message $hit" >&2
			FAILED=1
		fi
	done <<< "$hits"
}

# ---- launcher ----

report_foreign_paths \
	"the launcher may import only res://launcher/, res://i18n/ and res://runtime/game_session.gd:" \
	"$LAUNCHER" 'res://launcher/' 'res://i18n/' 'res://runtime/game_session.gd'

report_matches \
	"the launcher may reach a runtime only through GameSession, never its classes:" \
	scan_lines '\b(RuntimeLoader|DslMigrations|JsonPatch|NetworkMatch[A-Za-z]*|Shooter[A-Z][A-Za-z]*|Survivor[A-Z][A-Za-z]*|TowerDefense[A-Z][A-Za-z]*|WeaponController|BossSkillController|DropItem|ProceduralBGM)\b' "$LAUNCHER" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

report_matches \
	"the launcher may reach a game only through GameSession, never the game library's classes:" \
	scan_lines '\bGame(Module|Registry|Manifest|Input|Audio|Rng|FixedStep)\b' "$LAUNCHER" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

report_matches \
	"the launcher is local-only: no network classes, endpoints or URLs:" \
	scan_lines '\b(HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP|StreamPeerTLS|PacketPeerUDP|TCPServer|UDPServer|ENetConnection|ENetMultiplayerPeer|WebRTCPeerConnection)\b|/api/|(https?|wss?)://' "$LAUNCHER" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# ---- runtime ----

report_foreign_paths \
	"the runtime may import only res://runtime/ and res://games/shared/:" \
	"$RUNTIME" 'res://runtime/' 'res://games/shared/'

report_matches \
	"the runtime must not depend on the launcher:" \
	scan_lines '\bLauncher[A-Z][A-Za-z]*\b' "$RUNTIME" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# A runtime that needs a server (network_match_session.gd) is handed a port object by its host. It never opens a connection or names an address itself.
report_matches \
	"the runtime must not open network connections or own URLs:" \
	scan_lines '\b(HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP|StreamPeerTLS|PacketPeerUDP|TCPServer|UDPServer|ENetConnection|ENetMultiplayerPeer|WebRTCPeerConnection)\b|/api/|(https?|wss?)://' "$RUNTIME" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# ---- games ----

NETWORK='\b(HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP|StreamPeerTLS|PacketPeerUDP|TCPServer|UDPServer|ENetConnection|ENetMultiplayerPeer|WebRTCPeerConnection)\b|/api/|(https?|wss?)://'
HOST_CLASSES='\b(Launcher[A-Z][A-Za-z]*|GameSession|RuntimeLoader|DslMigrations|JsonPatch|NetworkMatch[A-Za-z]*|Shooter[A-Z][A-Za-z]*|Survivor[A-Z][A-Za-z]*|TowerDefense[A-Z][A-Za-z]*|WeaponController|BossSkillController|DropItem|ProceduralBGM)\b'
# What belongs to the host. A game reads its players through GameModule.input(), draws on its own stage and plays sound through GameModule.audio; it never polls or handles input itself, never touches the window, the buses, the tree or the player's files.
HOST_APIS='\bInput\.|\bInputMap\b|\bInputEvent[A-Za-z]*\b|\b_(unhandled_)?(key_)?input\(|user://|\bOS\.|\bProjectSettings\b|\bAudioServer\b|\bDisplayServer\b|\bEngine\.time_scale\b|\bget_tree\(\)\.(root|paused|quit|change_scene|reload_current_scene)|\bget_window\(|\bDirAccess\b'

# The shared library names the games root itself ("res://games", closing quote included) to discover what is under it; it imports nothing from there.
report_foreign_paths \
	"the shared game library may import only res://games/shared/:" \
	"$SHARED" 'res://games/shared/' '"res://games"'

report_matches \
	"the shared game library must not depend on the launcher or the runtime:" \
	scan_lines "$HOST_CLASSES" "$SHARED" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

report_matches \
	"the shared game library must not open network connections or own URLs:" \
	scan_lines "$NETWORK" "$SHARED" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# check_game_dir <dir> <res-prefix>: one game module's directory. <res-prefix> is where it lives (res://games/<id>/ or res://testing/games/<id>/).
check_game_dir() {
	local dir="$1" prefix="$2"
	report_foreign_paths \
		"a game may import only its own directory and res://games/shared/:" \
		"$dir" "$prefix" 'res://games/shared/'
	report_matches \
		"a game must not depend on the launcher, the runtime or GameSession:" \
		scan_lines "$HOST_CLASSES" "$dir" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"
	report_matches \
		"a game must not open network connections or own URLs:" \
		scan_lines "$NETWORK" "$dir" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"
	report_matches \
		"a game reads input, sound and the stage through GameModule only (no Input, InputMap, _input, user://, OS, AudioServer, DisplayServer, window or tree access):" \
		scan_lines "$HOST_APIS" "$dir" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
	# A class_name is global: two games declaring the same one would break each other, and any game could then reach another by name.
	report_matches \
		"a game must not declare global class names (use preload):" \
		scan_lines '^[[:space:]]*class_name[[:space:]]' "$dir" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
}

while IFS= read -r -d '' game_dir; do
	[[ "$game_dir" == "$SHARED" ]] && continue
	check_game_dir "$game_dir" "res://games/$(basename "$game_dir")/"
done < <(find "$GAMES" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ -d "$FIXTURE_GAMES" ]]; then
	while IFS= read -r -d '' game_dir; do
		check_game_dir "$game_dir" "res://testing/games/$(basename "$game_dir")/"
	done < <(find "$FIXTURE_GAMES" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# ---- i18n ----

report_foreign_paths \
	"i18n may import only res://i18n/:" \
	"$I18N" 'res://i18n/'

# ---- screens ----

while IFS= read -r -d '' source; do
	case "$source" in
		"$LAUNCHER"/*) ;;
		*)
			echo "screens live in apps/client/launcher only: $source" >&2
			FAILED=1
			;;
	esac
done < <(find "$CLIENT" -type f -name '*_screen.gd' -not -path '*/.godot/*' -print0)

if [[ "$FAILED" -ne 0 ]]; then
	exit 1
fi

echo "client boundary check: passed"
