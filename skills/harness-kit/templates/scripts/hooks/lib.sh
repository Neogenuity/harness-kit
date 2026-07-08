#!/usr/bin/env bash
# Shared helpers for agent hook scripts. Source from a sibling script:
#
#   . "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
#
# Everything here fails open: missing jq, empty stdin, or an unknown payload
# shape must never break an agent turn. Deny decisions are explicit (exit 2).

# Read the hook event JSON from stdin into HOOK_INPUT. Safe on empty stdin.
hook_read_input() {
    HOOK_INPUT=$(cat 2>/dev/null || true)
}

# Extract the target file path from the event across harness layouts:
# Cursor puts it at top level (`file_path`); Claude Code nests it as
# `tool_input.file_path` (Read/Edit/Write) or `tool_input.path` (Grep).
hook_file_path() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "${HOOK_INPUT:-}" | jq -r '.file_path // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null
}

# Deny the pending tool call: human-readable reason on stderr, exit 2 (the
# deny code in both Claude Code and Cursor).
hook_deny() {
    echo "$1" >&2
    exit 2
}

# Advisory stop-hook protocol: surface a warning to the agent exactly once.
#
# Plain stdout from a stop hook is not fed back to the model in either
# harness, so on the FIRST stop this asks the harness to continue the turn —
# Claude Code via `{"decision":"block","reason":...}`, Cursor via
# `{"followup_message":...}`. The loop guards carried on stdin
# (`stop_hook_active` for Claude Code, `loop_count` for Cursor) make the
# SECOND stop print plain text and succeed, so the run is never hard-blocked.
# Unknown harnesses and empty stdin get the plain-text fallback.
#
# Usage: hook_advise_once "$warnings"   (call last; always exits 0)
hook_advise_once() {
    local warnings="$1"
    if command -v jq >/dev/null 2>&1 && [ -n "${HOOK_INPUT:-}" ]; then
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("stop_hook_active")' >/dev/null 2>&1; then
            if printf '%s' "$HOOK_INPUT" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
                printf '%s\n' "$warnings"
            else
                printf '%s' "$warnings" | jq -Rs '{decision: "block", reason: .}'
            fi
            exit 0
        fi
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("loop_count")' >/dev/null 2>&1; then
            if printf '%s' "$HOOK_INPUT" | jq -e '.loop_count > 0' >/dev/null 2>&1; then
                printf '%s\n' "$warnings"
            else
                printf '%s' "$warnings" | jq -Rs '{followup_message: .}'
            fi
            exit 0
        fi
    fi
    printf '%s\n' "$warnings"
    exit 0
}

# List files newly added in the working tree (vs HEAD) matching an ERE —
# including files inside brand-new untracked directories (`-uall`; the default
# porcelain output collapses those to `?? dir/` and would miss them).
hook_new_files() {
    { git diff --name-status HEAD; git status --porcelain -uall | sed -n 's/^?? /A\t/p'; } 2>/dev/null \
        | awk '$1 ~ /^A/ {print $2}' | grep -E "$1" | sort -u || true
}
