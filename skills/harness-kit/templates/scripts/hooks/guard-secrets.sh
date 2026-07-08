#!/usr/bin/env bash
# Agent hook (before file read): block agent reads of secret-bearing files.
#
# Provider-agnostic: reads the hook event JSON on stdin and accepts the Cursor
# (`file_path`) and Claude Code (`tool_input.file_path` for Read,
# `tool_input.path` for Grep) field layouts. Exit code 2 denies the read in
# both harnesses; anything else fails open.
#
# Scope: defense-in-depth, not a complete boundary — shell commands
# (`cat .env` via Bash) and directory-wide searches are not intercepted.
# Pair it with the harness's native permission deny list (see
# providers/claude/settings.json) as a second layer.
#
# Matching is case-insensitive because dev filesystems are case-insensitive on
# macOS/Windows (`.ENV` reads the same bytes as `.env`), and it follows
# symlinks so a link named `notes.md` pointing at `.env` is still blocked. The
# symlink *target* is authoritative — a link named `.env.example` pointing at
# `.env` does not get the example allow-list pass.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input
file=$(hook_file_path)
[ -n "$file" ] || exit 0

# Classify a basename as `allow` (safe example/testing file), `secret`, or
# `other`. Case-folded. Allow patterns are checked first so `.env.mcp.example`
# (which also matches `.env.*`) resolves to `allow`.
classify() {
    local name
    name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$name" in
        # -- TAILOR: allow-listed safe files (no real credentials) ------------
        .env.example|.env.sample|.env.dist|.env.testing|*.example) echo allow ;;
        # -- TAILOR: secret-bearing files --------------------------------------
        .env|.env.*|auth.json|credentials.json|*.pem|id_rsa|id_ed25519) echo secret ;;
        # ----------------------------------------------------------------------
        *) echo other ;;
    esac
}

# The bytes actually read come from the symlink's target, so classify that.
# Fall back to the literal path when it isn't a symlink or can't be resolved.
resolved=$(readlink -f "$file" 2>/dev/null || true)
[ -n "$resolved" ] || resolved="$file"

target_verdict=$(classify "$(basename "$resolved")")
literal_verdict=$(classify "$(basename "$file")")

# An allow-listed *target* opts out. Otherwise deny if either the target or
# the literal name looks like a secret (the literal check catches a dangling
# link named `.env` whose target can't be resolved).
if [ "$target_verdict" = allow ]; then
    exit 0
fi

if [ "$target_verdict" = secret ] || [ "$literal_verdict" = secret ]; then
    hook_deny "Blocked by scripts/hooks/guard-secrets.sh: '$(basename "$file")' may contain real secrets. Use an .example/.testing variant instead."
fi

exit 0
