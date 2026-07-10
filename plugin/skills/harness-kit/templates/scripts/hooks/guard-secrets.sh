#!/usr/bin/env bash
# Agent hook (before file read/edit): block agent access to secret-bearing
# files.
#
# Provider-agnostic: reads the hook event JSON on stdin and accepts the
# Cursor (`file_path`), Claude Code (`tool_input.file_path` for Read,
# `tool_input.path` for Grep), and Codex (`tool_input.command` — apply_patch
# envelopes and shell commands) layouts via lib.sh:hook_affected_files. On
# Codex this also denies apply_patch WRITES to secret files (an agent
# shouldn't touch them at all), and adds a best-effort token scan of shell
# command strings — Codex reads files through the shell, so that scan is the
# only live secret layer there. Exit code 2 denies; anything else fails open.
#
# Scope: defense-in-depth, not a complete boundary. Codex's own docs call
# PreToolUse "a guardrail rather than a complete enforcement boundary", and
# the token scan is bypassable (indirection, xargs, globs, encodings). Pair
# it with the harness's native permission deny list (see
# providers/claude/settings.json) as a second layer; denies are logged to
# .harness/log.jsonl so a noisy or bypassed pattern surfaces in the audit
# loop.
#
# Matching is case-insensitive because dev filesystems are case-insensitive on
# macOS/Windows (`.ENV` reads the same bytes as `.env`), and it follows
# symlinks so a link named `notes.md` pointing at `.env` is still blocked. The
# symlink *target* is authoritative — a link named `.env.example` pointing at
# `.env` does not get the example allow-list pass.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The patterns live in scripts/harness.conf (SECRET_PATTERNS /
# SECRET_ALLOW_PATTERNS) so the hook, its tests, and the native provider deny
# lists share one source — tailor them THERE, not here. The fallbacks below
# only cover a missing conf.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness.conf" ] && . "$ROOT/scripts/harness.conf"
SECRET_ALLOW_PATTERNS="${SECRET_ALLOW_PATTERNS:-.env.example .env.sample .env.dist .env.testing *.example}"
SECRET_PATTERNS="${SECRET_PATTERNS:-.env .env.* auth.json credentials.json *.pem id_rsa id_ed25519}"

# Globs in the pattern lists must reach `case` verbatim — without noglob the
# unquoted `for pat in $SECRET_PATTERNS` would expand `*.pem` against the CWD.
set -f

hook_read_input
files=$(hook_affected_files)
cmd=$(hook_command_string)
{ [ -n "$files" ] || [ -n "$cmd" ]; } || exit 0

# Classify a basename as `allow` (safe example/testing file), `secret`, or
# `other`. Case-folded. Allow patterns are checked first so `.env.mcp.example`
# (which also matches `.env.*`) resolves to `allow`.
classify() {
    local name pat
    name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    # $pat is deliberately unquoted: conf entries are globs, and case-glob
    # matching is the point (noglob above keeps the shell from expanding
    # them first).
    for pat in $SECRET_ALLOW_PATTERNS; do
        # shellcheck disable=SC2254
        case "$name" in $pat) echo allow; return ;; esac
    done
    for pat in $SECRET_PATTERNS; do
        # shellcheck disable=SC2254
        case "$name" in $pat) echo secret; return ;; esac
    done
    echo other
}

# Deny when a path names (or symlinks to) a secret file. The bytes actually
# read come from the symlink's target, so classify that; fall back to the
# literal path when it isn't a symlink or can't be resolved. An allow-listed
# *target* opts out; the literal check still catches a dangling link named
# `.env` whose target can't be resolved.
check_path() {
    local file="$1" resolved target_verdict literal_verdict
    resolved=$(readlink -f "$file" 2>/dev/null || true)
    [ -n "$resolved" ] || resolved="$file"
    target_verdict=$(classify "$(basename "$resolved")")
    literal_verdict=$(classify "$(basename "$file")")
    [ "$target_verdict" = allow ] && return 0
    if [ "$target_verdict" = secret ] || [ "$literal_verdict" = secret ]; then
        hook_deny "Blocked by scripts/hooks/guard-secrets.sh: '$(basename "$file")' may contain real secrets. Use an .example/.testing variant instead."
    fi
    return 0
}

# Process substitution, not a pipeline — hook_deny must exit the hook, and
# `exit 2` inside a pipeline subshell would be swallowed (see lib.sh).
while IFS= read -r f; do
    [ -n "$f" ] && check_path "$f"
done < <(printf '%s\n' "$files")

# Best-effort token scan of the shell command itself (see Scope above).
# apply_patch envelopes are stripped first: their file headers were already
# checked by the loop above, and patch *content* merely mentioning `.env`
# (docs, comments, this very hook's source) is not a read.
if [ -n "$cmd" ]; then
    stripped=$(printf '%s\n' "$cmd" \
        | awk '/^\*\*\* Begin Patch/{skip=1} !skip{print} /^\*\*\* End Patch/{skip=0}')
    while IFS= read -r tok; do
        [ -n "$tok" ] && check_path "$tok"
    done < <(printf '%s\n' "$stripped" | tr -s "[:space:];|&<>()=\"'\`" '\n')
fi

exit 0
