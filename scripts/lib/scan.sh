#!/usr/bin/env bash
# Portable source scanning for the architecture guards.
#
# The guards used to shell out to ripgrep and swallow its exit status with `2>/dev/null || true`. That made a missing
# `rg` indistinguishable from "no violations found": on any machine without ripgrep — including the stripped self-hosted
# CI runner images — every check silently degraded into a no-op while still reporting success. A guard that cannot run
# must fail loudly, never pass vacuously.
#
# So these helpers are built on grep(1), which is present everywhere the guards run, and they treat grep's three outcomes
# distinctly: exit 0 = matches found, exit 1 = no matches, exit >= 2 = grep itself failed (missing binary, unreadable
# path, unsupported flag, bad expression) which aborts the caller instead of being reported as a clean scan.
#
# Callers that capture a helper's output in a command substitution still fail closed: the abort ends the substitution
# subshell with a non-zero status, which `set -e` (and `set -o pipefail` for piped groups) propagates to the caller.

# Directories that never hold reviewable sources. grep -r descends into dot-directories that ripgrep skipped by default,
# so these have to be named explicitly to keep Godot's import cache out of the results.
SCAN_PRUNE=(--exclude-dir=.git --exclude-dir=.godot --exclude-dir=.import)

# File-type filters, spelled out because grep has no brace-glob support.
SCAN_GD=(--include='*.gd')
SCAN_GD_SCENES=(--include='*.gd' --include='*.tscn' --include='*.tres')
SCAN_MD=(--include='*.md')

scan_abort() {
	local status="$1"
	shift
	echo "scan: grep failed (exit $status) — the architecture guard cannot verify this rule and refuses to report success" >&2
	echo "scan: failing command: grep $*" >&2
	exit "$status"
}

# scan_exec <grep-arg>... — print matches, print nothing when there are none, abort when grep itself fails.
scan_exec() {
	local status=0 output
	output="$(grep "$@")" || status=$?
	if ((status >= 2)); then
		scan_abort "$status" "$@"
	fi
	if ((status == 0)); then
		printf '%s\n' "$output"
	fi
}

# scan_lines <pattern> <target>... — matches as path:line:text (extended regex, recursive).
scan_lines() { scan_exec -rEn "$@"; }

# scan_files <pattern> <target>... — paths of files containing a match (extended regex, recursive).
scan_files() { scan_exec -rEl "$@"; }

# scan_files_literal <literal> <target>... — paths of files containing a literal string (recursive).
scan_files_literal() { scan_exec -rlF "$@"; }

# scan_only <pattern> <file> — each matched substring on its own line, for a single file.
scan_only() { scan_exec -oE "$@"; }

# scan_hit <pattern> <file> — true when the file matches; aborts when grep itself fails.
scan_hit() {
	local status=0
	grep -Eq "$@" || status=$?
	if ((status >= 2)); then
		scan_abort "$status" "-Eq" "$@"
	fi
	return "$status"
}
