#!/usr/bin/env bash
# Agent hook (after file edit): format the edited file with the project's
# formatter for that file type.
#
# Provider-agnostic: reads the hook event JSON on stdin and accepts either the
# Cursor (`file_path`) or Claude Code (`tool_input.file_path`) field layout.
# Fails open — a missing file, missing formatter binary, or formatter error
# never blocks the edit.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input
file=$(hook_file_path)
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 0

# Run a formatter only if its binary exists (project-relative or on PATH);
# swallow failures so the edit is never blocked.
run() {
    local bin="$1"
    if [ -x "$bin" ] || command -v "$bin" >/dev/null 2>&1; then
        "$@" >/dev/null 2>&1 || true
    fi
}

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

exit 0
