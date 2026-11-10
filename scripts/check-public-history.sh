#!/usr/bin/env bash
# Publication gate: the history of every ref must be free of the internal strategy and planning notes.
#
# check-architecture.sh only inspects the index, so it sees a forced add but not a file that was committed once and deleted later. Removing a file from the tip does not remove it from history, and publishing a repository publishes its history. Run this before a repository or a branch becomes public, and keep it green afterwards:
#
#   scripts/check-public-history.sh [repository root]
#
# Two rules, both over every ref (`--all`):
#   1. No commit ever touched docs-internal/ or one of the paths the internal notes had before they were moved there.
#   2. No object in history has the content of a file that currently sits in the local, untracked docs-internal/ directory, whatever name it was committed under. This rule only runs where that directory exists.
#
# A repository that fails cannot be fixed by another commit. Publish from a history that never held the files: a new root commit of the final tree pushed to a new repository, or `git filter-repo --invert-paths` over the paths below. A hosted repository that already has the files keeps them in its other branches and pull request refs, so it must not be switched to public as it is.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# docs-internal/ itself, then the locations the same notes had before commit "docs: move internal strategy docs out of the public tree".
INTERNAL_PATHS=(
    docs-internal
    docs/02-market.md
    docs/15-growth-ops.md
    docs/17-business-model.md
    docs/PROGRESS.md
    docs/plans
)

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "public history check: $ROOT is not a git repository, so there is no history to verify" >&2
    exit 1
fi
# A shallow clone holds only part of the history; passing on it would prove nothing.
if [[ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" != "false" ]]; then
    echo "public history check: $ROOT is a shallow clone; fetch the full history first (git fetch --unshallow)" >&2
    exit 1
fi

FAILED=0

commits="$(git -C "$ROOT" log --all --full-history --format='%h %s' -- "${INTERNAL_PATHS[@]}")"
if [[ -n "$commits" ]]; then
    echo "history contains internal documentation paths (${INTERNAL_PATHS[*]}); these commits touch them:" >&2
    echo "$commits" >&2
    FAILED=1
fi

if [[ -d "$ROOT/docs-internal" ]]; then
    objects="$(git -C "$ROOT" rev-list --all --objects)"
    while IFS= read -r -d '' file; do
        # An empty file hashes to the same blob as every other empty file, so it identifies nothing.
        [[ -s "$file" ]] || continue
        blob="$(git -C "$ROOT" hash-object -- "$file")"
        while IFS= read -r object; do
            if [[ "$object" == "$blob" || "$object" == "$blob "* ]]; then
                echo "history contains the content of ${file#"$ROOT"/} as object: $object" >&2
                FAILED=1
            fi
        done <<< "$objects"
    done < <(find "$ROOT/docs-internal" -type f -print0)
fi

if [[ "$FAILED" -ne 0 ]]; then
    echo "public history check: failed; this history must not be published" >&2
    exit 1
fi

echo "public history check: passed"
