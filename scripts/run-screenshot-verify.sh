#!/usr/bin/env bash
# Capture polished-shell screenshots. Not part of `make ci`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
OUT_DIR="${CLASSIC_GAMES_SHOT_DIR:-/tmp/fp-shots}"
EXPECTED_VERSION="$(<"$ROOT/apps/client/.godot-version")"
ACTUAL_VERSION="$("$GODOT" --version)"

if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" && "$ACTUAL_VERSION" != "$EXPECTED_VERSION".* ]]; then
	echo "Godot version mismatch: expected $EXPECTED_VERSION, got $ACTUAL_VERSION" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
export CLASSIC_GAMES_SHOT_DIR="$OUT_DIR"

# Prefer the on-screen X11 path so viewport pixels are real. Fall back to
# whatever display the caller already exported.
export DISPLAY="${DISPLAY:-:1}"

"$GODOT" --headless --path "$ROOT/apps/client" --import >/tmp/fp-shot-import.log 2>&1 || true

"$GODOT" --path "$ROOT/apps/client" \
	--display-driver x11 \
	--rendering-method gl_compatibility \
	--resolution 430x932 \
	--script res://screenshot_verify.gd
