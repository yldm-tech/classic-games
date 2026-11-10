#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CLIENT="$ROOT/apps/client"
SERVER="$ROOT/apps/server"
SERVER_INTERNAL="$SERVER/internal"
CLI="$ROOT/apps/cli"
MCP="$ROOT/apps/mcp"
DSL="$ROOT/packages/dsl"
SDK="$ROOT/packages/sdk"
DOCS="$ROOT/docs"
FAILED=0

# shellcheck source=lib/scan.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/scan.sh"

# Every scanned tree is required up front: a rule that scans a directory which is not there would pass vacuously.
for required in "$CLIENT" "$SERVER_INTERNAL" "$CLI" "$MCP" "$DSL" "$SDK" "$DOCS"; do
    if [[ ! -d "$required" ]]; then
        echo "architecture check: missing $required" >&2
        exit 1
    fi
done

report_matches() {
    local message="$1"
    shift
    local matches
    # No `|| true` here: scan_* already distinguishes "no matches" from "grep failed", and a scan failure must abort the
    # guard rather than read as a clean result.
    matches="$("$@")"
    if [[ -n "$matches" ]]; then
        echo "$message" >&2
        echo "$matches" >&2
        FAILED=1
    fi
}

SCREEN_ROLE_PATTERN="class_name[[:space:]]+[A-Za-z0-9_]+Screen\\b|extends[[:space:]]+ScreenBase\\b|extends[[:space:]]+(preload\\()?['\"]res://ui/screen_base\\.gd['\"]"
ARCHITECTURE_ROLE_PATTERN="class_name[[:space:]]+[A-Za-z0-9_]+(Screen|Store|Coordinator)\\b|extends[[:space:]]+ScreenBase\\b|extends[[:space:]]+(preload\\()?['\"]res://ui/screen_base\\.gd['\"]"
SCREEN_BASE_UID=""
if [[ -f "$CLIENT/ui/screen_base.gd.uid" ]]; then
    SCREEN_BASE_UID="$(tr -d '[:space:]' < "$CLIENT/ui/screen_base.gd.uid")"
fi

report_matches \
    "legacy client architecture must remain deleted:" \
    scan_lines 'class_name[[:space:]]+(ShellRoot|ApiClient)\b|\blegacy_api\b|res://shell/shell_root\.gd|res://shell/net/api_client\.gd' \
    "$CLIENT" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"

for legacy_path in "$CLIENT/shell/shell_root.gd" "$CLIENT/shell/net/api_client.gd"; do
    if [[ -e "$legacy_path" ]]; then
        echo "legacy client file must remain deleted: $legacy_path" >&2
        FAILED=1
    fi
done

# Each scan result is captured before the loop instead of streamed from `< <(...)`: an abort inside a process
# substitution would kill only that subshell, leaving the loop with no input and the guard reporting success.
role_sources="$({
    find "$CLIENT" -type f \( -name '*_screen.gd' -o -name '*_store.gd' -o -name '*_coordinator.gd' \) -print
    scan_files "$ARCHITECTURE_ROLE_PATTERN" "$CLIENT" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
    if [[ -n "$SCREEN_BASE_UID" ]]; then
        scan_files_literal "$SCREEN_BASE_UID" "$CLIENT" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
    fi
} | sort -u)"
while IFS= read -r source; do
    [[ -z "$source" ]] && continue
    if scan_hit '(/api/|https?://)' "$source"; then
        echo "screens, stores, and coordinators must not own URL strings: $source" >&2
        FAILED=1
    fi
done <<< "$role_sources"

HTTP_CLIENT_UID=""
if [[ -f "$CLIENT/core/http/http_client.gd.uid" ]]; then
    HTTP_CLIENT_UID="$(tr -d '[:space:]' < "$CLIENT/core/http/http_client.gd.uid")"
fi
http_sources="$({
    scan_files '\bHttpClient\b|res://core/http/http_client\.gd' "$CLIENT" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"
    if [[ -n "$HTTP_CLIENT_UID" ]]; then
        scan_files_literal "$HTTP_CLIENT_UID" "$CLIENT" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}"
    fi
} | sort -u)"
while IFS= read -r source; do
    [[ -z "$source" ]] && continue
    case "$source" in
        "$CLIENT"/core/http/*|"$CLIENT"/features/*/*_api.gd|"$CLIENT"/app/app_root.gd|*_test.gd|*_test.tscn|*_test.tres) continue ;;
    esac
    echo "HttpClient is only allowed in core HTTP, feature APIs, and AppRoot: $source" >&2
    FAILED=1
done <<< "$http_sources"

FEATURES="$CLIENT/features"
if [[ -d "$FEATURES" ]]; then
    while IFS= read -r -d '' source; do
        relative="${source#"$FEATURES"/}"
        source_feature="${relative%%/*}"
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
    done < <(find "$FEATURES" -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' \) -print0)

    feature_screens="$({
        find "$FEATURES" -type f -name '*_screen.gd' -print
        scan_files "$SCREEN_ROLE_PATTERN" "$FEATURES" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
        if [[ -n "$SCREEN_BASE_UID" ]]; then
            scan_files_literal "$SCREEN_BASE_UID" "$FEATURES" "${SCAN_GD[@]}" "${SCAN_PRUNE[@]}"
        fi
    } | sort -u)"
    while IFS= read -r target_screen; do
        [[ -z "$target_screen" ]] && continue
        uid_file="$target_screen.uid"
        [[ -f "$uid_file" ]] || continue
        target_uid="$(tr -d '[:space:]' < "$uid_file")"
        [[ -n "$target_uid" ]] || continue
        target_relative="${target_screen#"$FEATURES"/}"
        target_feature="${target_relative%%/*}"
        consumers="$(scan_files_literal "$target_uid" "$FEATURES" "${SCAN_GD_SCENES[@]}" "${SCAN_PRUNE[@]}")"
        while IFS= read -r consumer; do
            [[ -z "$consumer" ]] && continue
            consumer_relative="${consumer#"$FEATURES"/}"
            consumer_feature="${consumer_relative%%/*}"
            if [[ "$consumer_feature" != "$target_feature" ]]; then
                echo "feature $consumer_feature imports screen UID from feature $target_feature: $consumer" >&2
                FAILED=1
            fi
        done <<< "$consumers"
    done <<< "$feature_screens"
fi

while IFS= read -r -d '' source; do
    if scan_hit '\.AutoMigrate\(' "$source" && [[ "$source" != "$SERVER_INTERNAL/app/migrations.go" ]]; then
        echo "production AutoMigrate is only allowed in internal/app/migrations.go: $source" >&2
        FAILED=1
    fi
done < <(find "$SERVER_INTERNAL" -type f -name '*.go' ! -name '*_test.go' -print0)

while IFS= read -r -d '' source; do
    case "$source" in
        "$SERVER_INTERNAL"/app/*) continue ;;
    esac
    if scan_hit '\blog\.(Fatal|Fatalf|Fatalln)\b|\bos\.Exit\b|\bsignal\.(Notify|NotifyContext)\b|\.(Run|RunTLS|RunUnix|ListenAndServe|ListenAndServeTLS|Serve)\(' "$source"; then
        echo "server business packages must not own process lifecycle: $source" >&2
        FAILED=1
    fi
done < <(find "$SERVER_INTERNAL" -type f -name '*.go' ! -name '*_test.go' -print0)

# ---- monorepo module boundaries ----
#
# Dependencies point one way: apps -> packages. The backend is an application, not a library: the CLI and the MCP server reach it over HTTP through github.com/yldm-tech/classic-games/packages/sdk and share DSL logic through github.com/yldm-tech/classic-games/packages/dsl, never by importing github.com/yldm-tech/classic-games/apps/server. Both the Go sources and the go.mod files are checked, so a `require` cannot slip in ahead of its first import.
SCAN_GO=(--include='*.go')
SCAN_GOMOD=(--include='go.mod')

report_matches \
    "the CLI and the MCP server must not depend on the backend module (use github.com/yldm-tech/classic-games/packages/sdk and github.com/yldm-tech/classic-games/packages/dsl):" \
    scan_lines '"github.com/yldm-tech/classic-games/apps/server["/]' "$CLI" "$MCP" "${SCAN_GO[@]}" "${SCAN_PRUNE[@]}"
report_matches \
    "the CLI and the MCP server must not require the backend module in go.mod:" \
    scan_lines '\bgithub\.com/yldm-tech/classic-games/apps/server\b' "$CLI" "$MCP" "${SCAN_GOMOD[@]}" "${SCAN_PRUNE[@]}"

report_matches \
    "shared packages must not import an application module:" \
    scan_lines '"github\.com/yldm-tech/classic-games/apps/(server|cli|mcp)["/]' "$DSL" "$SDK" "${SCAN_GO[@]}" "${SCAN_PRUNE[@]}"
report_matches \
    "shared packages must not require an application module in go.mod:" \
    scan_lines '\bgithub\.com/yldm-tech/classic-games/apps/(server|cli|mcp)\b' "$DSL" "$SDK" "${SCAN_GOMOD[@]}" "${SCAN_PRUNE[@]}"

# RFC 6902 patching, DSL migration and schema validation have exactly one Go implementation, packages/dsl, pinned to the GDScript one by shared golden files. The backend must consume it instead of growing a private copy again.
for private_copy in "$SERVER_INTERNAL/ai/dsl" "$SERVER_INTERNAL/ai/schema_validator.go"; do
    if [[ -e "$private_copy" ]]; then
        echo "the backend must use github.com/yldm-tech/classic-games/packages/dsl, not a private copy of the DSL code: $private_copy" >&2
        FAILED=1
    fi
done
report_matches \
    "the backend must import github.com/yldm-tech/classic-games/packages/dsl, not the removed internal/ai/dsl package:" \
    scan_lines '"github.com/yldm-tech/classic-games/apps/server/internal/ai/dsl["/]' "$SERVER" "${SCAN_GO[@]}" "${SCAN_PRUNE[@]}"
if [[ ! -f "$SERVER/go.mod" ]]; then
    echo "architecture check: missing $SERVER/go.mod" >&2
    exit 1
fi
if ! scan_hit '^[[:space:]]*(require[[:space:]]+)?github.com/yldm-tech/classic-games/packages/dsl[[:space:]]+v' "$SERVER/go.mod"; then
    echo "the backend must require the shared github.com/yldm-tech/classic-games/packages/dsl module: $SERVER/go.mod" >&2
    FAILED=1
fi

# docs-internal/ holds strategy and planning notes that are not part of the public tree. It is git-ignored; this rule catches a forced add. A tree without git metadata (a source archive) tracks nothing, so there is nothing to check there; inside a work tree a failing git aborts the guard instead of reading as "nothing tracked".
if [[ -e "$ROOT/.git" ]]; then
    tracked_internal="$(git -C "$ROOT" ls-files -- docs-internal)"
    if [[ -n "$tracked_internal" ]]; then
        echo "docs-internal/ must stay untracked:" >&2
        echo "$tracked_internal" >&2
        FAILED=1
    fi
fi

# README.md and README.zh-CN.md are optional: a repository without one has no claim to contradict, and skipping it is not the same as swallowing a scan failure, which still aborts.
SCAN_DOCS=("${SCAN_MD[@]}" --include='*.mdx')
doc_targets=("$DOCS")
for readme in "$ROOT/README.zh-CN.md" "$ROOT/README.md"; do
    if [[ -f "$readme" ]]; then
        doc_targets=("$readme" "${doc_targets[@]}")
    fi
done

# The reference rule covers every public Markdown surface, not only docs/: the top-level project files, each app and package README and the GitHub templates. An unmatched glob stays a literal string and is dropped by the -e test, so a missing optional file is skipped while a scan failure still aborts. apps/web/README.md is the one file that names the directory on purpose, to document that the site build refuses links into it.
public_doc_targets=("$DOCS")
for candidate in "$ROOT"/*.md "$ROOT"/apps/*/README.md "$ROOT"/packages/*/README.md "$ROOT/.github"; do
    if [[ -e "$candidate" && "$candidate" != "$ROOT/apps/web/README.md" ]]; then
        public_doc_targets=("$candidate" "${public_doc_targets[@]}")
    fi
done
report_matches \
    "public documentation must not reference the untracked docs-internal/ directory:" \
    scan_lines 'docs-internal/' "${public_doc_targets[@]}" "${SCAN_DOCS[@]}" "${SCAN_PRUNE[@]}"
report_matches \
    "architecture documentation still claims the migration is incomplete:" \
    scan_lines -i '迁移中|仍在迁移|尚未删除|migration is in progress|still migrating|migration remains incomplete' \
    "${doc_targets[@]}" "${SCAN_DOCS[@]}" "${SCAN_PRUNE[@]}"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi

echo "architecture check: passed"
