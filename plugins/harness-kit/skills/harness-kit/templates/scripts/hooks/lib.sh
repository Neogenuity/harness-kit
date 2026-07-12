#!/usr/bin/env bash
# Shared helpers for agent hook scripts. Source from a sibling script:
#
#   . "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
#
# Everything here fails open: missing jq, empty stdin, or an unknown payload
# shape must never break an agent turn. Deny decisions are explicit: exit 2
# (the portable path, always available) or an exit-0 JSON
# permissionDecision:deny on PreToolUse payloads whose JSON was verified
# before being trusted. Either way the caller always sees a deny — the JSON
# form is only ever an ADDITION on top of exit 2, never a replacement that
# could fail open by accident.

# Snapshot the caller's environment now, before any hook sources
# harness.conf — an explicit env override (tests, one-off runs) must always
# win over the conf's HARNESS_LOG default.
HOOK_ENV_HARNESS_LOG="${HARNESS_LOG:-}"
HOOK_ENV_HARNESS_LOG_FILE="${HARNESS_LOG_FILE:-}"
HOOK_ENV_HARNESS_STOP_MARKER_DIR="${HARNESS_STOP_MARKER_DIR:-}"

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
# multiple lines). A real Codex payload carries the BARE patch envelope
# (`*** Begin Patch` … `*** End Patch`) directly in the command — the tool
# identity is in `tool_name`, so the literal "apply_patch" is often absent
# (verified against a real Codex payload, 2026-07); the shell-wrapper form
# (`apply_patch <<'EOF' …`) also occurs. jq -r turns the payload's \n
# escapes into real newlines whatever the shell quoting (<<'EOF', <<EOF, or
# a single-argument string), so the headers always sit at line start.
#
# Callers looping over the result MUST use process substitution
# (`while read … done < <(printf '%s\n' "$files")`), never a pipeline —
# hook_deny's exit 2 inside a pipeline subshell would not end the hook.
hook_affected_files() {
    command -v jq >/dev/null 2>&1 || return 0
    local direct cmd tool
    direct=$(printf '%s' "${HOOK_INPUT:-}" \
        | jq -r '.file_path // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
    if [ -n "$direct" ]; then
        printf '%s\n' "$direct"
        return 0
    fi
    cmd=$(hook_command_string)
    # Decide whether this command IS a patch application, keyed on the tool
    # identity — never on command text alone. Codex's dedicated apply_patch
    # tool sends the BARE envelope with no "apply_patch" literal, so trust its
    # tool_name; and any tool that invokes the apply_patch CLI literally
    # (`apply_patch <<'EOF' …`, including under a Bash/shell tool) is a real
    # application too. A plain shell command that merely CONTAINS patch text
    # (a heredoc writing a .patch file, an echo of a diff) is NOT one —
    # parsing it would fabricate affected-file paths and fail-close a guard,
    # so skip it.
    tool=$(printf '%s' "${HOOK_INPUT:-}" | jq -r '.tool_name // empty' 2>/dev/null)
    if [ "$tool" != "apply_patch" ]; then
        case "$cmd" in *apply_patch*) ;; *) return 0 ;; esac
    fi
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

# Deny the pending tool call. Portable path: human-readable reason on
# stderr, exit 2 (the deny code in Claude Code, Cursor, and Codex). On a
# PreToolUse payload — verified via `.hook_event_name`, since that's the
# only field that reliably distinguishes it from the Cursor top-level
# `file_path` layout and from other event types — Claude Code and Codex both
# parse `hookSpecificOutput.permissionDecision` (verified against the Claude
# Code and Codex hooks docs, 2026-07-12), so emit the exit-0 JSON deny
# instead: the reason becomes model-visible, where the plain PreToolUse
# exit-2 stderr may not be (Claude Code's exit-2 table, unlike its PostToolUse
# row, doesn't document PreToolUse stderr reaching the model). The JSON is
# round-tripped through jq before being trusted — if construction fails for
# ANY reason (jq absent, jq error, empty output), the event isn't PreToolUse,
# or the write to stdout fails, this falls through to the portable exit 2.
# That fallback is load-bearing: a malformed or unwritten exit-0 "deny" would
# fail OPEN (allow), the one direction this protocol must never take.
hook_deny() {
    local reason="$1" event="" json=""
    hook_log deny "$(hook_file_path)" "$reason"
    if command -v jq >/dev/null 2>&1 && [ -n "${HOOK_INPUT:-}" ]; then
        event=$(printf '%s' "$HOOK_INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
        if [ "$event" = "PreToolUse" ]; then
            json=$(printf '%s' "$reason" | jq -Rs \
                '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}' 2>/dev/null)
            # Take the exit-0 JSON deny only if the object verifies AND the write
            # to stdout actually succeeds. A failed write (closed/broken stdout)
            # must fall through to the portable exit-2 deny — never exit 0 with
            # no deny bytes, which a harness reads as ALLOW (the one fail-open
            # direction this protocol must never take).
            if [ -n "$json" ] && printf '%s' "$json" | jq -e 'has("hookSpecificOutput")' >/dev/null 2>&1 \
                && printf '%s\n' "$json"; then
                exit 0
            fi
        fi
    fi
    echo "$reason" >&2
    exit 2
}

# Post-tool feedback: surface diagnostics to the agent AFTER a tool already
# ran (the post-edit lint loop). Claude Code and Codex feed a PostToolUse
# hook's stderr to the model when it exits 2 — the edit is not undone, the
# agent just sees the findings and self-corrects within the turn. Cursor's
# `afterFileEdit` response schema documents NO output field that surfaces
# arbitrary text to the agent ("No output fields currently supported",
# verified 2026-07-12), and exit-0 stdout there is parsed as JSON ("use the
# JSON output"), so plain text on that layout is dead — no recognized
# layout may emit it. The Cursor top-level `file_path` layout therefore gets
# the documented no-op JSON (`{}`) instead: every hook_feedback caller in
# this kit calls hook_log first (see format.sh), so the finding still lands
# in .harness/log.jsonl even where it can't reach the model. An unrecognized
# payload (no jq, empty stdin, neither `tool_input` nor `file_path`) keeps
# the plain stdout + exit 0 fallback — it isn't a known layout to degrade.
#
# Usage: hook_feedback "$diagnostics"   (call last; never blocks the edit)
hook_feedback() {
    local diagnostics="$1"
    if command -v jq >/dev/null 2>&1 && [ -n "${HOOK_INPUT:-}" ]; then
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("tool_input")' >/dev/null 2>&1; then
            printf '%s\n' "$diagnostics" >&2
            exit 2
        fi
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("file_path")' >/dev/null 2>&1; then
            printf '{}\n'
            exit 0
        fi
    fi
    printf '%s\n' "$diagnostics"
    exit 0
}

# Short, filesystem-safe digest of arbitrary text (POSIX `cksum`, on both
# macOS and Linux by default; falls back to a byte count if it's somehow
# missing — coarser, but still separates most distinct warning strings
# rather than refusing to key a marker at all).
hook_text_digest() {
    if command -v cksum >/dev/null 2>&1; then
        printf '%s' "$1" | cksum | awk '{print $1}'
    else
        printf '%s' "$1" | wc -c | tr -d '[:space:]'
    fi
}

# Payload-independent Stop loop guard — the FALLBACK path hook_advise_once
# takes only when a payload carries NEITHER `stop_hook_active` NOR
# `loop_count` but does carry a session/conversation id (see below for why
# this is a fallback, not the primary mechanism). Keys a marker file under
# .harness/stop-markers/ (dir overridable via HARNESS_STOP_MARKER_DIR,
# mirroring HARNESS_LOG_FILE, so tests can redirect it away from the repo)
# on the payload's `.session_id` (Claude Code; falls back to
# `.conversation_id`) plus a digest of the warning text — so the SAME warning
# in the SAME session advises exactly once even if a harness drops both
# loop-guard flags, while a genuinely NEW warning in that session still
# surfaces. A real id is REQUIRED: a present-but-null or absent id (jq's // is
# blind to null) resolves to empty and returns 1 (surface every time) rather
# than collapsing distinct sessions into one shared bucket that would
# cross-suppress them. Opportunistically prunes ONLY this guard's own markers
# (the `stopadv-` prefix) older than 3 days on the way in — cheap, bounded by
# session count, and never touches unrelated files in a user-pointed
# HARNESS_STOP_MARKER_DIR.
#
# Returns 0 = already advised this (session, warning) pair -> caller emits a
# structured no-op. Returns 1 = first time, OR the marker dir couldn't be
# used for ANY reason (unwritable, mkdir failure, etc.) -> caller must
# surface the advisory. That fallback direction is load-bearing: this guard
# must fail toward SHOWING the advisory, never toward silently swallowing
# it — an agent stuck in a real loop with no advisory is worse than an
# occasional duplicate one.
hook_advise_once_seen() {
    local warnings="$1" root marker_dir sid sid_safe digest sid_digest key marker_file
    root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)" || return 1
    marker_dir="${HOOK_ENV_HARNESS_STOP_MARKER_DIR:-${HARNESS_STOP_MARKER_DIR:-$root/.harness/stop-markers}}"
    mkdir -p "$marker_dir" 2>/dev/null || return 1
    [ -w "$marker_dir" ] || return 1
    # A real id is required to dedupe. jq's // treats a present-but-null id as
    # absent, so {"session_id":null} resolves to empty -> return 1 (surface),
    # never a shared bucket that cross-suppresses distinct sessions.
    sid=$(printf '%s' "${HOOK_INPUT:-}" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null)
    [ -n "$sid" ] || return 1
    digest=$(hook_text_digest "$warnings")
    # Collision-safe key: a filesystem-safe rendering of the id PLUS a digest of
    # the raw id, so ids differing only in stripped characters ("a/b" vs "a?b")
    # still map to distinct keys. The `stopadv-` prefix marks markers this guard
    # owns, so the prune below can scope to them and spare unrelated files.
    sid_safe=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')
    sid_digest=$(hook_text_digest "$sid")
    key="stopadv-${sid_safe}-${sid_digest}-${digest}"
    marker_file="$marker_dir/$key"
    find "$marker_dir" -maxdepth 1 -type f -name 'stopadv-*' -mtime +3 -delete 2>/dev/null || true
    [ -e "$marker_file" ] && return 0
    : > "$marker_file" 2>/dev/null || return 1
    return 1
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
# Cursor builds reject plain-text hook stdout).
#
# `stop_hook_active` is undocumented in current Claude Code docs though
# still empirically sent (captured payload, Claude Code CLI 2.1.207,
# 2026-07-12) — PRIMARY path here because it's stateless and proven; see the
# plan's Decisions for why the payload-independent marker guard
# (hook_advise_once_seen) stays a FALLBACK rather than replacing it. That
# fallback engages only when a payload has neither loop-guard flag but does
# carry a session/conversation id, so a future Claude Code build that drops
# `stop_hook_active` still advises exactly once instead of silently
# degrading to "never advised" or "always re-advised". A payload with no
# loop-guard flag AND no session id at all (or empty stdin, or no jq) has no
# key to guard on and falls through to the unknown-harness plain-text
# fallback below.
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
        if printf '%s' "$HOOK_INPUT" | jq -e 'has("session_id") or has("conversation_id")' >/dev/null 2>&1; then
            if hook_advise_once_seen "$warnings"; then
                printf '{"continue": true}\n'
            else
                printf '%s' "$warnings" | jq -Rs '{decision: "block", reason: .}'
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
