#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECKER="$ROOT/scripts/check-public-history.sh"
PASSED=0
FAILED=0
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT

# Fixture commits must not depend on the identity, signing setup or hooks of the machine that runs the test.
fixture_git() {
	local dir="$1"
	shift
	git -C "$dir" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

# fixture: a repository with one public commit on branch main.
fixture() {
	local dir
	dir="$(mktemp -d "$TASK_TMP/fixture.XXXXXX")"
	git -C "$dir" init -q -b main
	mkdir -p "$dir/docs"
	printf '%s\n' '# Architecture' > "$dir/docs/architecture.md"
	fixture_git "$dir" add docs/architecture.md
	fixture_git "$dir" commit -q -m 'docs: add architecture'
	printf '%s\n' "$dir"
}

commit_then_delete() {
	local dir="$1" path="$2"
	mkdir -p "$(dirname "$dir/$path")"
	printf '%s\n' '# Internal' 'Not for publication.' > "$dir/$path"
	fixture_git "$dir" add -f "$path"
	fixture_git "$dir" commit -q -m "add $path"
	fixture_git "$dir" rm -q "$path"
	fixture_git "$dir" commit -q -m "remove $path"
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

# expect_fail_with <label> <target> <text>: the checker must fail and name the reason, so a case cannot pass because of an unrelated error.
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

case_dir="$(fixture)"
expect_pass "history without internal documentation" "$case_dir"

# Removing a file from the tip leaves it in history.
for path in docs/02-market.md docs/15-growth-ops.md docs/17-business-model.md docs/PROGRESS.md docs/plans/roadmap.md docs-internal/plan.md; do
	case_dir="$(fixture)"
	commit_then_delete "$case_dir" "$path"
	expect_fail_with "$path committed and deleted" "$case_dir" "history contains internal documentation paths"
done

# Every ref counts, not only the branch that is checked out.
case_dir="$(fixture)"
fixture_git "$case_dir" checkout -q -b side
commit_then_delete "$case_dir" docs/17-business-model.md
fixture_git "$case_dir" checkout -q main
expect_fail_with "internal path on another branch" "$case_dir" "history contains internal documentation paths"

case_dir="$(fixture)"
commit_then_delete "$case_dir" docs/17-business-model.md
fixture_git "$case_dir" tag old-tip HEAD~1
fixture_git "$case_dir" checkout -q --orphan clean
fixture_git "$case_dir" commit -q -m 'docs: fresh root'
fixture_git "$case_dir" branch -q -D main
expect_fail_with "internal path reachable only from a tag" "$case_dir" "history contains internal documentation paths"
fixture_git "$case_dir" tag -d old-tip >/dev/null
expect_pass "fresh root commit with no other ref" "$case_dir"

# The local, untracked docs-internal/ directory is the reference for content committed under another name.
case_dir="$(fixture)"
mkdir -p "$case_dir/docs-internal"
printf '%s\n' '# Business model' 'Not for publication.' > "$case_dir/docs-internal/17-business-model.md"
: > "$case_dir/docs-internal/empty.md"
: > "$case_dir/docs/empty.md"
fixture_git "$case_dir" add docs/empty.md
fixture_git "$case_dir" commit -q -m 'docs: add an empty page'
expect_pass "untracked docs-internal that was never committed" "$case_dir"
cp "$case_dir/docs-internal/17-business-model.md" "$case_dir/docs/pricing.md"
fixture_git "$case_dir" add docs/pricing.md
fixture_git "$case_dir" commit -q -m 'docs: add pricing'
fixture_git "$case_dir" rm -q docs/pricing.md
fixture_git "$case_dir" commit -q -m 'docs: remove pricing'
expect_fail_with "internal content committed under another name" "$case_dir" "history contains the content of docs-internal/17-business-model.md"

# A check that cannot see the whole history must not report success.
case_dir="$(mktemp -d "$TASK_TMP/fixture.XXXXXX")"
expect_fail_with "directory without git metadata" "$case_dir" "is not a git repository"

case_dir="$(fixture)"
printf '%s\n' '# Runtime' > "$case_dir/docs/runtime.md"
fixture_git "$case_dir" add docs/runtime.md
fixture_git "$case_dir" commit -q -m 'docs: add runtime'
shallow="$(mktemp -d "$TASK_TMP/fixture.XXXXXX")"
git clone -q --depth 1 "file://$case_dir" "$shallow"
expect_fail_with "shallow clone" "$shallow" "is a shallow clone"

echo "check-public-history_test: $PASSED passed, $FAILED failed"
test "$FAILED" -eq 0
