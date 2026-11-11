#!/usr/bin/env bash
# Dependency directions inside the Godot client (apps/client):
#
#   launcher -> i18n
#           \-> runtime/game_session.gd (this one file)
#   runtime  -> nothing outside runtime/
#   i18n     -> nothing outside i18n/
#
# The launcher is local-only: no network classes, no endpoints, no URLs. See docs/16-client-architecture.md.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="$ROOT/apps/client"
LAUNCHER="$CLIENT/launcher"
RUNTIME="$CLIENT/runtime"
I18N="$CLIENT/i18n"
FAILED=0

# shellcheck source=lib/scan.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/scan.sh"

# Every scanned tree is required up front: a rule that scans a directory which is not there would pass vacuously.
for required in "$LAUNCHER" "$RUNTIME" "$I18N"; do
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
	"the launcher is local-only: no network classes, endpoints or URLs:" \
	scan_lines '\b(HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP|StreamPeerTLS|PacketPeerUDP|TCPServer|UDPServer|ENetConnection|ENetMultiplayerPeer|WebRTCPeerConnection)\b|/api/|(https?|wss?)://' "$LAUNCHER" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# ---- runtime ----

report_foreign_paths \
	"the runtime may import only res://runtime/:" \
	"$RUNTIME" 'res://runtime/'

report_matches \
	"the runtime must not depend on the launcher:" \
	scan_lines '\bLauncher[A-Z][A-Za-z]*\b' "$RUNTIME" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

# A runtime that needs a server (network_match_session.gd) is handed a port object by its host. It never opens a connection or names an address itself.
report_matches \
	"the runtime must not open network connections or own URLs:" \
	scan_lines '\b(HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP|StreamPeerTLS|PacketPeerUDP|TCPServer|UDPServer|ENetConnection|ENetMultiplayerPeer|WebRTCPeerConnection)\b|/api/|(https?|wss?)://' "$RUNTIME" \
	"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

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
