#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
MODE="${1:---release}"

case "$MODE" in
  --release|--debug) ;;
  *) echo "usage: $0 [--release|--debug]" >&2; exit 2 ;;
esac

mkdir -p "$ROOT/apps/client/build/web" "$ROOT/apps/client/build/windows" "$ROOT/apps/client/build/macos" "$ROOT/apps/client/build/android" "$ROOT/apps/client/build/ios"

export_one() {
  local preset="$1" output="$2"
  "$GODOT" --headless --path "$ROOT/apps/client" "--export${MODE}" "$preset" "$output"
}

export_one "Web" "$ROOT/apps/client/build/web/index.html"
export_one "Windows Desktop" "$ROOT/apps/client/build/windows/ClassicGames.exe"
export_one "macOS" "$ROOT/apps/client/build/macos/ClassicGames.app"
export_one "Android" "$ROOT/apps/client/build/android/ClassicGames.apk"
export_one "iOS" "$ROOT/apps/client/build/ios/ClassicGames.ipa"
