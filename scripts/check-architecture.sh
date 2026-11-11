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

# ---- removed phone client ----
#
# The client is the console launcher plus the game runtimes (docs/16-client-architecture.md). The portrait phone app it replaced was removed as a whole; neither its directories nor references to them may come back. Dependency directions between the directories that exist are checked by check-client-boundaries.sh.
for removed_path in app features shell ui main.gd main.tscn; do
    if [[ -e "$CLIENT/$removed_path" ]]; then
        echo "the removed phone client must stay removed: $CLIENT/$removed_path" >&2
        FAILED=1
    fi
done

SCAN_CLIENT=("${SCAN_GD_SCENES[@]}" --include='project.godot')
report_matches \
    "the client must not reference the removed phone client:" \
    scan_lines 'res://(app|features|shell|ui)/|res://main\.(gd|tscn)|\b(AppState|AppRoot|ScreenBase)\b' \
    "$CLIENT" "${SCAN_CLIENT[@]}" "${SCAN_PRUNE[@]}"

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
