#!/usr/bin/env bash
# Agent hook (after file edit): format the edited file(s) with the project's
# formatter for that file type, then run the fast linter for that type and
# feed any findings straight back to the agent (via hook_feedback) so it
# self-corrects within the turn — the fastest layer of the verification loop.
#
# Provider-agnostic: reads the hook event JSON on stdin and accepts the
# Cursor (`file_path`), Claude Code (`tool_input.file_path`), and Codex
# (`tool_input.command` apply_patch envelope — every file in a multi-file
# patch is processed) layouts via lib.sh:hook_affected_files. Fails open — a
# missing file, missing formatter/linter binary, or formatter error never
# blocks the edit; lint findings are feedback, not a block.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input
files=$(hook_affected_files)
[ -n "$files" ] || exit 0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# apply_patch paths are repo-relative — resolve every file against the root.
cd "$ROOT" || exit 0

# Run a formatter only if its binary exists (project-relative or on PATH);
# swallow failures so the edit is never blocked.
run() {
    local bin="$1"
    if [ -x "$bin" ] || command -v "$bin" >/dev/null 2>&1; then
        "$@" >/dev/null 2>&1 || true
    fi
}

# Run a linter only if its binary exists; a non-zero exit appends its output
# (under a per-file header) as diagnostics to feed back. A passing lint (or
# missing binary) stays silent.
diagnostics=""
lint() {
    local bin="$1" out
    { [ -x "$bin" ] || command -v "$bin" >/dev/null 2>&1; } || return 0
    if ! out=$("$@" 2>&1); then
        diagnostics="${diagnostics:+$diagnostics
}== $file
$out"
    fi
}

process_one() {
    local file="$1"
    [ -f "$file" ] || return 0

    # -- TAILOR: map file extensions to your formatters ---------------------------
    # Uncomment / add lines for the stacks in this repo. Examples:
    case "$file" in
        # *.php)                        run vendor/bin/pint "$file" ;;
        # *.ts|*.tsx|*.js|*.jsx|*.css)  run npx prettier --write "$file" ;;
        # *.py)                         run ruff format "$file" ;;
        # *.go)                         run gofmt -w "$file" ;;
        # *.rs)                         run rustfmt "$file" ;;
        *) : ;;
    esac
    # ------------------------------------------------------------------------------

    # -- TAILOR: map file extensions to a FAST linter (the feedback loop) ---------
    # Millisecond-fast linters only — slow static analysis belongs in verify.sh,
    # not on every edit. Examples:
    case "$file" in
        # *.py)                  lint ruff check "$file" ;;
        # *.ts|*.tsx|*.js|*.jsx) lint npx oxlint "$file" ;;
        # *.php)                 lint php -l "$file" ;;
        *) : ;;
    esac
    # ------------------------------------------------------------------------------
}

while IFS= read -r f; do
    [ -n "$f" ] && process_one "$f"
done < <(printf '%s\n' "$files")

if [ -n "$diagnostics" ]; then
    hook_log lint-findings "$(printf '%s\n' "$files" | head -n 1)" "$diagnostics"
    hook_feedback "Lint findings — fix before finishing:
$diagnostics"
fi

exit 0
