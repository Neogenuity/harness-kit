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

# The format/lint policy lives in harness.conf as data (FORMAT_RULES /
# LINT_RULES, one `<glob[|glob...]>=<command>` per line — the edited file is
# appended as the command's last argument). This script is pure mechanism:
# absent conf or empty rules mean no-op, never an error.
# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness.conf" ] && . "$ROOT/scripts/harness.conf" 2>/dev/null
FORMAT_RULES="${FORMAT_RULES:-}"
LINT_RULES="${LINT_RULES:-}"

# match_pat <file> <glob[|glob...]> — case-glob match with '|' alternation
# (a '|' inside an expanded case pattern is literal, so split and loop).
match_pat() {
    local file="$1" alts="$2" p
    local IFS='|'
    set -f
    for p in $alts; do
        # shellcheck disable=SC2254
        case "$file" in $p) set +f; return 0 ;; esac
    done
    set +f
    return 1
}

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

apply_rules() {
    # apply_rules <runner: run|lint> <rules> <file> — first matching rule wins
    # per list. The command template is word-split by design (no quoting
    # support: a formatter needing space-containing arguments gets a small
    # repo-owned wrapper script instead).
    local runner="$1" rules="$2" file="$3" rule pat cmd
    [ -n "$rules" ] || return 0
    while IFS= read -r rule; do
        case "$rule" in ''|\#*) continue ;; esac
        pat=${rule%%=*}
        cmd=${rule#*=}
        [ -n "$pat" ] && [ -n "$cmd" ] && [ "$pat" != "$rule" ] || continue
        if match_pat "$file" "$pat"; then
            # shellcheck disable=SC2086
            "$runner" $cmd "$file"
            return 0
        fi
    done <<EOF
$rules
EOF
    return 0
}

process_one() {
    local file="$1"
    [ -f "$file" ] || return 0
    apply_rules run  "$FORMAT_RULES" "$file"
    apply_rules lint "$LINT_RULES" "$file"
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
