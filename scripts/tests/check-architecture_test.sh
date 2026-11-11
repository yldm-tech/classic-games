#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/scripts/check-architecture.sh"
PASSED=0
FAILED=0
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT

fixture() {
	local dir
	dir="$(mktemp -d "$TASK_TMP/fixture.XXXXXX")"
	mkdir -p "$dir/apps/client/launcher" "$dir/apps/client/runtime" \
		"$dir/apps/server/internal/app" "$dir/apps/server/internal/catalog" \
		"$dir/apps/server/cmd/server" "$dir/apps/cli/internal/cli" "$dir/apps/mcp/internal/server" \
		"$dir/packages/dsl" "$dir/packages/sdk" "$dir/docs"
	printf '%s\n' 'package app' 'func migrate() { db.AutoMigrate() }' > "$dir/apps/server/internal/app/migrations.go"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/apps/server' 'require (' '	github.com/yldm-tech/classic-games/packages/dsl v0.0.0' ')' 'replace github.com/yldm-tech/classic-games/packages/dsl => ../../packages/dsl' > "$dir/apps/server/go.mod"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/apps/cli' 'require (' '	github.com/yldm-tech/classic-games/packages/dsl v0.0.0' '	github.com/yldm-tech/classic-games/packages/sdk v0.0.0' ')' > "$dir/apps/cli/go.mod"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/apps/mcp' 'require (' '	github.com/yldm-tech/classic-games/packages/dsl v0.0.0' '	github.com/yldm-tech/classic-games/packages/sdk v0.0.0' ')' > "$dir/apps/mcp/go.mod"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/packages/dsl' > "$dir/packages/dsl/go.mod"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/packages/sdk' > "$dir/packages/sdk/go.mod"
	printf '%s\n' '# Architecture' 'The modular migration is complete.' > "$dir/docs/architecture.md"
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

# expect_fail_with <label> <target> <text>: the checker must fail and name the reason. Used where a weaker checker would still exit non-zero for an unrelated reason (a scan of a missing directory aborts on its own), so the exit status alone would not pin the rule.
expect_fail_with() {
	local label="$1" target="$2" text="$3" output status=0
	output="$("$CHECKER" "$target" 2>&1)" || status=$?
	if [[ "$status" -ne 0 && "$output" == *"$text"* ]]; then
		PASSED=$((PASSED + 1))
	else
		echo "FAIL: $label should fail with: $text" >&2
		FAILED=$((FAILED + 1))
	fi
}

REMOVED_PATH="the removed phone client must stay removed:"
REMOVED_REFERENCE="the client must not reference the removed phone client:"

for removed in app features shell ui; do
	case_dir="$(fixture)"
	mkdir -p "$case_dir/apps/client/$removed"
	expect_fail_with "phone client directory $removed is back" "$case_dir" "$REMOVED_PATH"
done

for removed in main.gd main.tscn; do
	case_dir="$(fixture)"
	: > "$case_dir/apps/client/$removed"
	expect_fail_with "phone client entry $removed is back" "$case_dir" "$REMOVED_PATH"
done

case_dir="$(fixture)"
printf '%s\n' 'const Tokens := preload("res://shell/design_system/theme/tokens.gd")' > "$case_dir/apps/client/launcher/launcher_tokens.gd"
expect_fail_with "import from a removed directory" "$case_dir" "$REMOVED_REFERENCE"

case_dir="$(fixture)"
printf '%s\n' '[ext_resource type="Script" path="res://features/catalog/home_screen.gd" id="1"]' > "$case_dir/apps/client/launcher/launcher.tscn"
expect_fail_with "scene uses a script from a removed directory" "$case_dir" "$REMOVED_REFERENCE"

case_dir="$(fixture)"
printf '%s\n' 'func locale() -> String:' '	return AppState.locale' > "$case_dir/apps/client/launcher/launcher_root.gd"
expect_fail_with "read of the removed AppState autoload" "$case_dir" "$REMOVED_REFERENCE"

case_dir="$(fixture)"
printf '%s\n' '[autoload]' 'AppState="*res://shell/state/app_state.gd"' > "$case_dir/apps/client/project.godot"
expect_fail_with "project registers the removed autoload" "$case_dir" "$REMOVED_REFERENCE"

case_dir="$(fixture)"
printf '%s\n' '[application]' 'run/main_scene="res://main.tscn"' > "$case_dir/apps/client/project.godot"
expect_fail_with "project points at the removed main scene" "$case_dir" "$REMOVED_REFERENCE"

case_dir="$(fixture)"
printf '%s\n' 'package catalog' 'func migrate() { db.AutoMigrate() }' > "$case_dir/apps/server/internal/catalog/repository.go"
expect_fail "production AutoMigrate outside registry" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package catalog' 'func run() { log.Fatal("boom") }' > "$case_dir/apps/server/internal/catalog/service.go"
expect_fail "process lifecycle in business package" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package catalog' 'func run() { signal.NotifyContext(); engine.Run(); srv.ListenAndServe() }' > "$case_dir/apps/server/internal/catalog/service.go"
expect_fail "server lifecycle in business package" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '# Architecture' 'The modular architecture is still migrating.' > "$case_dir/docs/architecture.md"
expect_fail "stale migration documentation" "$case_dir"

for app in cli mcp; do
	case_dir="$(fixture)"
	printf '%s\n' "package $app" 'import "github.com/yldm-tech/classic-games/apps/server/internal/mods"' > "$case_dir/apps/$app/internal/backend.go"
	expect_fail "$app imports the backend module" "$case_dir"

	case_dir="$(fixture)"
	printf '%s\n' "module github.com/yldm-tech/classic-games/apps/$app" 'require github.com/yldm-tech/classic-games/apps/server v0.0.0' > "$case_dir/apps/$app/go.mod"
	expect_fail "$app requires the backend module" "$case_dir"
done

case_dir="$(fixture)"
printf '%s\n' 'package sdk' 'import (' '	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"' ')' > "$case_dir/packages/sdk/client.go"
expect_fail "shared package imports the backend" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package dsl' 'import "github.com/yldm-tech/classic-games/apps/cli/internal/config"' > "$case_dir/packages/dsl/patch.go"
expect_fail "shared package imports an application" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'module github.com/yldm-tech/classic-games/packages/sdk' 'require github.com/yldm-tech/classic-games/apps/mcp v0.0.0' > "$case_dir/packages/sdk/go.mod"
expect_fail "shared package requires an application module" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package sdk' 'import "github.com/yldm-tech/classic-games/apps/mcp/internal/server"' > "$case_dir/packages/sdk/client.go"
expect_fail "shared package imports the MCP server" "$case_dir"

for app in server cli; do
	case_dir="$(fixture)"
	printf '%s\n' 'module github.com/yldm-tech/classic-games/packages/dsl' "require github.com/yldm-tech/classic-games/apps/$app v0.0.0" > "$case_dir/packages/dsl/go.mod"
	expect_fail "packages/dsl requires the $app application module" "$case_dir"
done

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/server/internal/ai/dsl"
printf '%s\n' 'package dsl' > "$case_dir/apps/server/internal/ai/dsl/patch.go"
expect_fail "private DSL package in the backend" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/apps/server/internal/ai"
printf '%s\n' 'package ai' > "$case_dir/apps/server/internal/ai/schema_validator.go"
expect_fail "private schema validator in the backend" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package catalog' 'import "github.com/yldm-tech/classic-games/apps/server/internal/ai/dsl"' > "$case_dir/apps/server/internal/catalog/service.go"
expect_fail "backend imports the removed DSL package" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'module github.com/yldm-tech/classic-games/apps/server' > "$case_dir/apps/server/go.mod"
expect_fail "backend does not require github.com/yldm-tech/classic-games/packages/dsl" "$case_dir"

for required in apps/client apps/server/internal apps/cli apps/mcp packages/dsl packages/sdk docs; do
	case_dir="$(fixture)"
	rm -rf "${case_dir:?}/$required"
	expect_fail_with "missing $required" "$case_dir" "architecture check: missing $case_dir/$required"
done

case_dir="$(fixture)"
mkdir -p "$case_dir/docs-internal"
printf '%s\n' '# Internal plan' > "$case_dir/docs-internal/plan.md"
git -C "$case_dir" init -q
expect_pass "untracked docs-internal" "$case_dir"
git -C "$case_dir" add -f docs-internal/plan.md
expect_fail "tracked docs-internal" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '# Architecture' 'See [the plan](../docs-internal/plan.md).' > "$case_dir/docs/architecture.md"
expect_fail "public docs link into docs-internal" "$case_dir"

# Every public Markdown surface is covered by the reference rule, not only docs/*.md.
for public_doc in README.md README.zh-CN.md CONTRIBUTING.md SECURITY.md apps/cli/README.md packages/sdk/README.md .github/PULL_REQUEST_TEMPLATE.md docs/plans/plan.md docs/guide.mdx; do
	case_dir="$(fixture)"
	mkdir -p "$(dirname "$case_dir/$public_doc")"
	printf '%s\n' '# Notes' 'See [the plan](./docs-internal/plan.md).' > "$case_dir/$public_doc"
	expect_fail_with "$public_doc links into docs-internal" "$case_dir" "public documentation must not reference the untracked docs-internal/ directory:"
done

# apps/web/README.md documents that the site build refuses links into the directory, so it may name it.
case_dir="$(fixture)"
mkdir -p "$case_dir/apps/web"
# shellcheck disable=SC2016 # the backticks are Markdown, not a command substitution
printf '%s\n' '# Website' 'The build stops if a relative link points into `docs-internal/`.' > "$case_dir/apps/web/README.md"
expect_pass "apps/web/README.md names docs-internal on purpose" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '# Classic Games' '架构仍在迁移。' > "$case_dir/README.zh-CN.md"
expect_fail "stale migration claim in the Chinese README" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '# Classic Games' 'The migration is in progress.' > "$case_dir/README.md"
expect_fail "stale migration claim in the English README" "$case_dir"

case_dir="$(fixture)"
mkdir -p "$case_dir/docs/plans"
printf '%s\n' '# Plan' 'The client is still migrating.' > "$case_dir/docs/plans/plan.md"
expect_fail "stale migration claim under docs/plans" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' 'package cli' 'import (' '	"github.com/yldm-tech/classic-games/packages/dsl"' '	"github.com/yldm-tech/classic-games/packages/sdk"' ')' > "$case_dir/apps/cli/internal/cli/app.go"
printf '%s\n' 'package server' 'import "github.com/yldm-tech/classic-games/packages/sdk"' '// The backend module is github.com/yldm-tech/classic-games/apps/server; it is reached over HTTP.' > "$case_dir/apps/mcp/internal/server/server.go"
printf '%s\n' 'package catalog' 'import "github.com/yldm-tech/classic-games/packages/dsl"' > "$case_dir/apps/server/internal/catalog/service.go"
expect_pass "monorepo module boundaries" "$case_dir"

case_dir="$(fixture)"
printf '%s\n' '[application]' 'run/main_scene="res://launcher/launcher.tscn"' > "$case_dir/apps/client/project.godot"
printf '%s\n' 'class_name LauncherRoot' 'const Strings := preload("res://i18n/strings.gd")' > "$case_dir/apps/client/launcher/launcher_root.gd"
printf '%s\n' 'package main' 'func main() { log.Fatal(app.Run()) }' > "$case_dir/apps/server/cmd/server/main.go"
expect_pass "completed architecture boundaries" "$case_dir"

echo "check-architecture_test: $PASSED passed, $FAILED failed"
test "$FAILED" -eq 0
