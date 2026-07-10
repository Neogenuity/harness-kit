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

# The shell command a tool call will run, if any. Claude Code's Bash tool
# and Codex's shell/apply_patch tools carry it as `tool_input.command`;
# tolerate an argv-array form by joining on newlines so the apply_patch
# envelope headers keep their line anchors.
hook_command_string() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "${HOOK_INPUT:-}" | jq -r '
        .tool_input.command // empty
        | if type == "array" then map(tostring) | join("\n") else tostring end
    ' 2>/dev/null
}

# Every file path a tool call touches, newline-separated, across harness
# layouts: Cursor puts one at top level (`file_path`); Claude Code nests one
# as `tool_input.file_path` (Read/Edit/Write) or `tool_input.path` (Grep).
# Codex sends NO file-path field — file edits arrive as an apply_patch
# invocation inside `tool_input.command` — so parse the patch envelope's
# file headers (Update/Add/Delete File, Move to; a multi-file patch yields
# multiple lines). jq -r turns the payload's \n escapes into real newlines
# whatever the shell quoting (<<'EOF', <<EOF, or a single-argument string),
# so the headers always sit at line start.
#
# Callers looping over the result MUST use process substitution
# (`while read … done < <(printf '%s\n' "$files")`), never a pipeline —
# hook_deny's exit 2 inside a pipeline subshell would not end the hook.
hook_affected_files() {
    command -v jq >/dev/null 2>&1 || return 0
    local direct cmd
    direct=$(printf '%s' "${HOOK_INPUT:-}" \
        | jq -r '.file_path // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
    if [ -n "$direct" ]; then
        printf '%s\n' "$direct"
        return 0
    fi
    cmd=$(hook_command_string)
    case "$cmd" in *apply_patch*) ;; *) return 0 ;; esac
    printf '%s\n' "$cmd" | awk '
        /^\*\*\* (Update|Add|Delete) File: / { sub(/^\*\*\* (Update|Add|Delete) File: /, ""); print; next }
        /^\*\*\* Move to: /                  { sub(/^\*\*\* Move to: /, ""); print }
    ' | awk '!seen[$0]++'
}

# First affected file — the common single-file case and the deny-log label.
hook_file_path() {
    hook_affected_files | head -n 1
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
# Plain stdout from a stop hook is not fed back to the model in any harness,
# so on the FIRST stop this asks the harness to continue the turn — Claude
# Code and Codex via `{"decision":"block","reason":...}`, Cursor via
# `{"followup_message":...}`. The loop guards carried on stdin
# (`stop_hook_active` for Claude Code/Codex, `loop_count` for Cursor) make
# the SECOND stop emit a structured no-op instead, so the run is never
# hard-blocked: `{"continue": true}` on the stop_hook_active layout — Codex
# requires JSON on stdout when a Stop hook exits 0 (plain text is a protocol
# error there) and the same object is valid Claude Code hook output; the two
# are indistinguishable on stdin — and `{}` on the Cursor layout (recent
# Cursor builds reject plain-text hook stdout). Unknown harnesses and empty
# stdin get the plain-text fallback.
#
# Usage: hook_advise_once "$warnings"   (call last; always exits 0)
hook_advise_once() {
    local warnings="$1"
    hook_log advise "" "$warnings"
    if command -v jq >/dev/null 2>&1 && [ -n "${HOOK_INPUT:-}" ]; then
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("stop_hook_active")' >/dev/null 2>&1; then
            if printf '%s' "$HOOK_INPUT" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
                printf '{"continue": true}\n'
            else
                printf '%s' "$warnings" | jq -Rs '{decision: "block", reason: .}'
            fi
            exit 0
        fi
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("loop_count")' >/dev/null 2>&1; then
            if printf '%s' "$HOOK_INPUT" | jq -e '.loop_count > 0' >/dev/null 2>&1; then
                printf '{}\n'
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
