#!/usr/bin/env bash
# Regression tests for the hook_advise_once dual-harness stop protocol in
# lib.sh. Runnable standalone and in CI.
#
# The protocol is the subtlest piece of the harness: on the first stop the
# warning must be surfaced as a continue-the-turn request (Claude Code/Codex
# `decision:block`, Cursor `followup_message`); on the second stop the loop
# guards (`stop_hook_active` / `loop_count`) must make it emit a structured
# JSON no-op so the run is never hard-blocked — Codex requires JSON on Stop
# stdout at exit 0 (plain text is a protocol error there), and Claude Code
# accepts the same object. A payload with NEITHER loop-guard flag but a
# session/conversation id falls back to hook_advise_once_seen's marker-file
# guard (PAYLOAD-INDEPENDENT of stop_hook_active, which is undocumented in
# current Claude Code docs though still empirically sent — CLI 2.1.207,
# captured payload, 2026-07-12) so advise-exactly-once survives that field
# ever being dropped. Unknown payloads with no session id at all fall back
# to plain text. Any project stop-hook built on hook_advise_once inherits
# exactly this behavior, so pin it here once.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

LIB="$(cd "$(dirname "$0")/../hooks" && pwd)/lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-advise-once.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Keep hook_log out of the repo during tests; the explicit log case opts in.
export HARNESS_LOG=0

# Fixture hook: always warns, so every case exercises the protocol.
cp "$LIB" "$WORK/lib.sh"
cp "$(dirname "$LIB")/../lib/log-lib.sh" "$WORK/log-lib.sh"
cat > "$WORK/fixture-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
hook_read_input
hook_advise_once "TEST WARNING"
EOF
chmod +x "$WORK/fixture-hook.sh"
HOOK="$WORK/fixture-hook.sh"

fails=0

# run <description> <stdin-payload> <must-match-regex> <must-not-match-regex>
# Empty regex = skip that assertion. Hook must always exit 0 (advisory).
run() {
    local desc="$1" payload="$2" want="$3" reject="$4" out rc
    out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null)
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "FAIL: $desc — expected exit 0, got $rc"
        fails=$((fails + 1))
        return
    fi
    if [ -n "$want" ] && ! printf '%s' "$out" | grep -qE "$want"; then
        echo "FAIL: $desc — output missing /$want/: $out"
        fails=$((fails + 1))
        return
    fi
    if [ -n "$reject" ] && printf '%s' "$out" | grep -qE "$reject"; then
        echo "FAIL: $desc — output must not match /$reject/: $out"
        fails=$((fails + 1))
        return
    fi
    echo "ok:   $desc"
}

run "Claude/Codex first stop: decision:block JSON" '{"stop_hook_active": false}' '"decision"[[:space:]]*:[[:space:]]*"block"' ''
run "Claude/Codex first stop: reason carries warning" '{"stop_hook_active": false}' 'TEST WARNING' ''
run "Claude/Codex second stop: JSON no-op, no re-block" '{"stop_hook_active": true}' '"continue"[[:space:]]*:[[:space:]]*true' '"decision"|TEST WARNING'
run "Cursor first stop: followup_message JSON"  '{"loop_count": 0}' '"followup_message"' ''
run "Cursor second stop: JSON no-op, no followup" '{"loop_count": 1}' '\{\}' '"followup_message"|TEST WARNING'
run "unknown payload: plain-text fallback"      '{}' 'TEST WARNING' '"decision"|"followup_message"'
run "empty stdin: plain-text fallback"          '' 'TEST WARNING' '"decision"|"followup_message"'

# Second-pass stdout must PARSE as JSON — the Codex Stop contract ("Stop
# expects JSON on stdout when it exits 0"); a grep alone would miss, say, a
# stray plain-text line after the object.
if printf '%s' '{"stop_hook_active": true}' | "$HOOK" 2>/dev/null | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "ok:   second stop stdout parses as {\"continue\": true}"
else
    echo "FAIL: second stop stdout does not parse as {\"continue\": true}"
    fails=$((fails + 1))
fi
if printf '%s' '{"loop_count": 1}' | "$HOOK" 2>/dev/null | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ok:   Cursor second stop stdout parses as a JSON object"
else
    echo "FAIL: Cursor second stop stdout does not parse as a JSON object"
    fails=$((fails + 1))
fi

# --- payload-independent fallback: session id present, no loop-guard flag ---
# A payload with neither stop_hook_active nor loop_count but a session id —
# e.g. a future Claude Code build that drops stop_hook_active, or any other
# harness shaped like it — must still advise exactly once, not silently
# degrade to "never advised". Point HARNESS_STOP_MARKER_DIR at $WORK so the
# marker file never touches the repo's real .harness/ dir.
MARKER_DIR="$WORK/stop-markers"
sid_first_out=$(printf '%s' '{"session_id": "s1"}' | env HARNESS_STOP_MARKER_DIR="$MARKER_DIR" "$HOOK" 2>/dev/null)
sid_first_rc=$?
sid_second_out=$(printf '%s' '{"session_id": "s1"}' | env HARNESS_STOP_MARKER_DIR="$MARKER_DIR" "$HOOK" 2>/dev/null)
sid_second_rc=$?
if [ "$sid_first_rc" != "0" ] || [ "$sid_second_rc" != "0" ]; then
    echo "FAIL: session-id fallback — expected exit 0 on both stops, got $sid_first_rc then $sid_second_rc"
    fails=$((fails + 1))
elif ! printf '%s' "$sid_first_out" | grep -q 'TEST WARNING'; then
    echo "FAIL: session-id fallback — first stop did not surface the warning: $sid_first_out"
    fails=$((fails + 1))
elif printf '%s' "$sid_second_out" | grep -q 'TEST WARNING'; then
    echo "FAIL: session-id fallback — second stop re-surfaced the warning instead of a silent no-op: $sid_second_out"
    fails=$((fails + 1))
elif ! printf '%s' "$sid_second_out" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "FAIL: session-id fallback — second stop stdout does not parse as a JSON object: $sid_second_out"
    fails=$((fails + 1))
else
    echo "ok:   session-id fallback (no loop-guard flag) — first stop advises, second is a silent structured no-op"
fi

# --- F6 (2026-07-12 review): the marker prune must spare unrelated files ---
# HARNESS_STOP_MARKER_DIR can point at a user-owned dir, so the opportunistic
# stale-marker prune must delete ONLY this guard's own markers (stopadv-*),
# never arbitrary files. Plant an old non-marker file and confirm it survives.
PRUNE_DIR="$WORK/prune-dir"
mkdir -p "$PRUNE_DIR"
: > "$PRUNE_DIR/user-file.txt"
touch -t 202601010000 "$PRUNE_DIR/user-file.txt"   # older than the 3-day window
printf '%s' '{"session_id": "prune-s"}' | env HARNESS_STOP_MARKER_DIR="$PRUNE_DIR" "$HOOK" >/dev/null 2>&1
if [ -e "$PRUNE_DIR/user-file.txt" ]; then
    echo "ok:   marker prune spares unrelated files in an override dir (scoped to stopadv-*)"
else
    echo "FAIL: marker prune DELETED an unrelated user file in the override dir"
    fails=$((fails + 1))
fi

# --- F7 (2026-07-12 review): a null/absent id can't dedupe -> surface always ---
# jq's // is blind to null, so {"session_id": null} must NOT collapse into a
# shared bucket that cross-suppresses distinct sessions; with no real id there
# is nothing to key on, so the advisory surfaces on every stop.
NULL_DIR="$WORK/null-dir"
n1=$(printf '%s' '{"session_id": null}' | env HARNESS_STOP_MARKER_DIR="$NULL_DIR" "$HOOK" 2>/dev/null)
n2=$(printf '%s' '{"session_id": null}' | env HARNESS_STOP_MARKER_DIR="$NULL_DIR" "$HOOK" 2>/dev/null)
if printf '%s' "$n1" | grep -q 'TEST WARNING' && printf '%s' "$n2" | grep -q 'TEST WARNING'; then
    echo "ok:   null session id surfaces every stop (never silently cross-suppressed)"
else
    echo "FAIL: null session id did not surface on both stops (n1='$n1' n2='$n2')"
    fails=$((fails + 1))
fi

# --- F7: distinct ids differing only in stripped characters must not collide ---
# "a/b" and "a?b" both sanitize to "a_b"; a digest of the raw id keeps their
# keys distinct so one session's advisory can't suppress the other's.
COLLIDE_DIR="$WORK/collide-dir"
c1=$(printf '%s' '{"session_id": "a/b"}' | env HARNESS_STOP_MARKER_DIR="$COLLIDE_DIR" "$HOOK" 2>/dev/null)
c2=$(printf '%s' '{"session_id": "a?b"}' | env HARNESS_STOP_MARKER_DIR="$COLLIDE_DIR" "$HOOK" 2>/dev/null)
if printf '%s' "$c1" | grep -q 'TEST WARNING' && printf '%s' "$c2" | grep -q 'TEST WARNING'; then
    echo "ok:   ids differing only in stripped chars (a/b vs a?b) don't cross-suppress"
else
    echo "FAIL: a/b vs a?b collided — second advisory suppressed (c1='$c1' c2='$c2')"
    fails=$((fails + 1))
fi

# --- observability: an advisory appends one valid JSON line ---
LOG="$WORK/log.jsonl"
printf '%s' '{"stop_hook_active": false}' | env HARNESS_LOG=1 HARNESS_LOG_FILE="$LOG" "$HOOK" >/dev/null 2>&1
if [ -f "$LOG" ] && jq -e 'select(.version == 2 and .event == "advise"
        and keys == ["context","data","detail","event","file","hook","ts","version"])' "$LOG" >/dev/null 2>&1; then
    echo "ok:   advisory appends a valid JSON log line"
else
    echo "FAIL: advisory did not append a valid JSON log line"
    fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails advise-once case(s)"
    exit 1
fi
echo "PASSED: all advise-once cases"
