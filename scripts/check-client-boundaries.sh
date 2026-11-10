#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="$ROOT/apps/client"
FEATURES="$ROOT/apps/client/features"
UI="$ROOT/apps/client/ui"
FAILED=0

# shellcheck source=lib/scan.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/scan.sh"

if [[ ! -d "$FEATURES" ]]; then
	echo "client boundary check: missing $FEATURES" >&2
	exit 1
fi

report_matches() {
	local message="$1"
	shift
	local matches
	# No `|| true` here: scan_* already distinguishes "no matches" from "grep failed", and a scan failure must abort
	# the guard rather than read as a clean result.
	matches="$("$@")"
	if [[ -n "$matches" ]]; then
		echo "$message" >&2
		echo "$matches" >&2
		FAILED=1
	fi
}

report_matches \
	"feature screens must delegate network work to coordinators:" \
	scan_lines 'res://core/http/http_client\.gd|\bHttpClient\b|\bHTTPRequest\b|/api/' "$FEATURES" \
	--include='*_screen.gd' "${SCAN_PRUNE[@]}"

report_matches \
	"screens must not expose a transport or api seam:" \
	scan_lines 'res://core/http|/api/|(^|[^[:alnum:]_])var[[:space:]]+api([[:space:]:=]|$)|\bApiClient\b|\bHttpClient\b|\bHTTPRequest\b' "$CLIENT" \
	--include='*_screen.gd' --include='screen_base.gd' "${SCAN_PRUNE[@]}"

report_matches \
	"features must not depend on the legacy ApiClient:" \
	scan_lines 'res://shell/net/api_client\.gd|\bApiClient\b' "$FEATURES" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"

report_matches \
	"legacy shell architecture must remain deleted:" \
	scan_lines 'class_name[[:space:]]+(ShellRoot|ApiClient)\b|\blegacy_api\b|res://shell/shell_root\.gd|res://shell/net/api_client\.gd' \
	"$CLIENT" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

for legacy_path in "$CLIENT/shell/shell_root.gd" "$CLIENT/shell/net/api_client.gd"; do
	if [[ -e "$legacy_path" ]]; then
		echo "legacy client file must remain deleted: $legacy_path" >&2
		FAILED=1
	fi
done

if [[ -d "$UI" ]]; then
	report_matches \
		"shared UI patterns must remain presentation-only:" \
		scan_lines 'res://features/|res://core/http|\bHttpClient\b|\bHTTPRequest\b|/api/' "$UI" \
		"${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"
fi

while IFS= read -r -d '' source; do
	case "$source" in
		"$CLIENT"/app/*|"$CLIENT"/features/*|"$CLIENT"/runtime/*) ;;
		*)
			echo "application screen lives outside apps/client/app or apps/client/features: $source" >&2
			FAILED=1
			;;
	esac
done < <(find "$CLIENT" -type f -name '*_screen.gd' -print0)

while IFS= read -r -d '' source; do
	relative="${source#"$FEATURES"/}"
	source_feature="${relative%%/*}"
	# Captured up front rather than piped from a process substitution: a scan failure inside `< <(...)` would only kill
	# the subshell and leave the loop looking clean, which is precisely the vacuous-pass mode this guard must not have.
	imports="$(scan_only 'res://features/[^/]+/[^"]*_screen\.gd' "$source")"
	while IFS= read -r import; do
		[[ -z "$import" ]] && continue
		target="${import#res://features/}"
		target_feature="${target%%/*}"
		if [[ "$target_feature" != "$source_feature" ]]; then
			echo "feature $source_feature imports screen from feature $target_feature: $source" >&2
			FAILED=1
		fi
	done <<< "$imports"
done < <(find "$FEATURES" -type f -name '*.gd' -print0)

if [[ "$FAILED" -ne 0 ]]; then
	exit 1
fi

echo "client boundary check: passed"
