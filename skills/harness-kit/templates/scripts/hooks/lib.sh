#!/usr/bin/env bash
# Shared helpers for agent hook scripts. Source from a sibling script:
#
#   . "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
#
# Everything here fails open: missing jq, empty stdin, or an unknown payload
# shape must never break an agent turn. Deny decisions are explicit (exit 2).

# Snapshot the caller's environment now, before any hook sources
# harness.conf — an explicit env override (tests, one-off runs) must always
# win over the conf's HARNESS_LOG default.
HOOK_ENV_HARNESS_LOG="${HARNESS_LOG:-}"
HOOK_ENV_HARNESS_LOG_FILE="${HARNESS_LOG_FILE:-}"

# Read the hook event JSON from stdin into HOOK_INPUT. Safe on empty stdin.
hook_read_input() {
    HOOK_INPUT=$(cat 2>/dev/null || true)
}

# Extract the target file path from the event across harness layouts:
# Cursor puts it at top level (`file_path`); Claude Code and Codex nest it
# as `tool_input.file_path` (Read/Edit/Write) or `tool_input.path` (Grep).
hook_file_path() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "${HOOK_INPUT:-}" | jq -r '.file_path // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null
}

# Append one JSON line describing a guard event to the harness log
# (.harness/log.jsonl under the repo root, git-ignored) so repeated agent
# mistakes become visible data — the audit workflow summarizes it. Controlled
# by HARNESS_LOG (default on; env wins, then scripts/harness.conf) and
# HARNESS_LOG_FILE. Requires jq; never fails the calling hook.
hook_log() {
    local event="$1" file="${2:-}" detail="${3:-}" root logfile enabled
    command -v jq >/dev/null 2>&1 || return 0
    root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || return 0
    if [ -n "$HOOK_ENV_HARNESS_LOG" ]; then
        enabled="$HOOK_ENV_HARNESS_LOG"
    else
        if [ -z "${HARNESS_LOG:-}" ] && [ -f "$root/scripts/harness.conf" ]; then
            # shellcheck source=/dev/null
            . "$root/scripts/harness.conf" 2>/dev/null || true
        fi
        enabled="${HARNESS_LOG:-1}"
    fi
    [ "$enabled" = "0" ] && return 0
    logfile="${HOOK_ENV_HARNESS_LOG_FILE:-${HARNESS_LOG_FILE:-$root/.harness/log.jsonl}}"
    mkdir -p "$(dirname "$logfile")" 2>/dev/null || return 0
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg hook "$(basename "$0")" \
        --arg event "$event" --arg file "$file" --arg detail "$detail" \
        '{ts: $ts, hook: $hook, event: $event, file: $file, detail: $detail}' \
        >> "$logfile" 2>/dev/null || true
    return 0
}

# Deny the pending tool call: human-readable reason on stderr, exit 2 (the
# deny code in Claude Code, Cursor, and Codex).
hook_deny() {
    hook_log deny "$(hook_file_path)" "$1"
    echo "$1" >&2
    exit 2
}

# Post-tool feedback: surface diagnostics to the agent AFTER a tool already
# ran (the post-edit lint loop). Claude Code and Codex feed a PostToolUse
# hook's stderr to the model when it exits 2 — the edit is not undone, the
# agent just sees the findings and self-corrects within the turn. Cursor's
# layout (top-level file_path) gets plain stdout instead. No jq, empty
# stdin, or an unknown layout falls back to stdout + exit 0 (fail open).
#
# Usage: hook_feedback "$diagnostics"   (call last; never blocks the edit)
hook_feedback() {
    local diagnostics="$1"
    if command -v jq >/dev/null 2>&1 && [ -n "${HOOK_INPUT:-}" ] \
        && printf '%s' "$HOOK_INPUT" | jq -e 'has("tool_input")' >/dev/null 2>&1; then
        printf '%s\n' "$diagnostics" >&2
        exit 2
    fi
    printf '%s\n' "$diagnostics"
    exit 0
}

# Advisory stop-hook protocol: surface a warning to the agent exactly once.
#
# Plain stdout from a stop hook is not fed back to the model in either
# harness, so on the FIRST stop this asks the harness to continue the turn —
# Claude Code and Codex via `{"decision":"block","reason":...}`, Cursor via
# `{"followup_message":...}`. The loop guards carried on stdin
# (`stop_hook_active` for Claude Code/Codex, `loop_count` for Cursor) make the
# SECOND stop print plain text and succeed, so the run is never hard-blocked.
# Unknown harnesses and empty stdin get the plain-text fallback.
#
# Usage: hook_advise_once "$warnings"   (call last; always exits 0)
hook_advise_once() {
    local warnings="$1"
    hook_log advise "" "$warnings"
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
