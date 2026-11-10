#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/scripts/check-client-boundaries.sh"
PASSED=0
FAILED=0

fixture() {
	local dir
	dir="$(mktemp -d)"
	mkdir -p "$dir/apps/client/features/identity" "$dir/apps/client/features/catalog" "$dir/apps/client/app" "$dir/apps/client/ui/patterns"
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

expect_fail() {
	local label="$1" target="$2"
	if "$CHECKER" "$target" >/dev/null 2>&1; then
		echo "FAIL: $label should fail" >&2
		FAILED=$((FAILED + 1))
	else
		PASSED=$((PASSED + 1))
	fi
}

case_dir="$(fixture)"
printf '%s\n' 'const Http := preload("res://core/http/http_client.gd")' > "$case_dir/apps/client/features/identity/login_screen.gd"
expect_fail "feature screen imports transport" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const Catalog := preload("res://features/catalog/catalog_screen.gd")' > "$case_dir/apps/client/features/identity/login_screen.gd"
expect_fail "feature imports another feature screen" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'var api: ApiClient' > "$case_dir/apps/client/features/identity/identity_coordinator.gd"
expect_fail "feature depends on legacy ApiClient" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'extends Control' 'var api' > "$case_dir/apps/client/app/login_screen.gd"
expect_fail "application screen exposes an api seam" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'extends Control' 'const Transport := preload("res://core/http/http_client.gd")' > "$case_dir/apps/client/app/login_screen.gd"
expect_fail "application screen aliases the HTTP transport" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/shell/screens"
printf '%s\n' 'class_name OfflineScreen' 'extends ScreenBase' > "$case_dir/apps/client/shell/screens/offline_screen.gd"
expect_fail "application screen lives outside app or features" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/shell/screens"
printf '%s\n' 'class_name OfflineScreen' 'extends Control' > "$case_dir/apps/client/shell/screens/offline_screen.gd"
expect_fail "non-ScreenBase application screen lives outside app or features" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const Catalog := preload("res://features/catalog/catalog_store.gd")' > "$case_dir/apps/client/ui/patterns/paged_list.gd"
expect_fail "shared UI imports feature code" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '[ext_resource path="res://features/catalog/catalog_store.gd" type="Script" id="1"]' > "$case_dir/apps/client/ui/patterns/paged_list.tscn"
expect_fail "shared UI resource imports feature code" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const Gateway := preload("res://features/identity/identity_api.gd")' > "$case_dir/apps/client/features/identity/identity_coordinator.gd"
printf '%s\n' 'const Identity := preload("res://features/identity/identity_coordinator.gd")' > "$case_dir/apps/client/app/app_root.gd"
expect_pass "coordinator to gateway and app to feature" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'class_name ShellRoot' > "$case_dir/apps/client/app/app_root.gd"
expect_fail "legacy ShellRoot class is absent" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'class_name ApiClient' > "$case_dir/apps/client/app/app_root.gd"
expect_fail "legacy ApiClient class is absent" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'var legacy_api' > "$case_dir/apps/client/app/app_root.gd"
expect_fail "legacy api compatibility seam is absent" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const Shell := preload("res://shell/shell_root.gd")' > "$case_dir/apps/client/app/app_root.gd"
expect_fail "legacy shell path is absent" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'const API := preload("res://shell/net/api_client.gd")' > "$case_dir/apps/client/app/app_root.gd"
expect_fail "legacy api path is absent" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/shell"
: > "$case_dir/apps/client/shell/shell_root.gd"
expect_fail "empty legacy shell file is absent" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/client/shell/net"
: > "$case_dir/apps/client/shell/net/api_client.gd"
expect_fail "empty legacy api file is absent" "$case_dir"

echo "check-client-boundaries_test: $PASSED passed, $FAILED failed"
test "$FAILED" -eq 0
