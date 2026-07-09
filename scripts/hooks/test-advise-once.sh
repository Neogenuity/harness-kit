#!/usr/bin/env bash
# Regression tests for the hook_advise_once dual-harness stop protocol in
# lib.sh. Runnable standalone and in CI.
#
# The protocol is the subtlest piece of the harness: on the first stop the
# warning must be surfaced as a continue-the-turn request (Claude Code
# `decision:block`, Cursor `followup_message`); on the second stop the loop
# guards (`stop_hook_active` / `loop_count`) must make it degrade to plain
# text so the run is never hard-blocked. Unknown payloads fall back to plain
# text. Any project stop-hook built on hook_advise_once inherits exactly this
# behavior, so pin it here once.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

LIB="$(cd "$(dirname "$0")" && pwd)/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Keep hook_log out of the repo during tests; the explicit log case opts in.
export HARNESS_LOG=0

# Fixture hook: always warns, so every case exercises the protocol.
cp "$LIB" "$WORK/lib.sh"
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

run "Claude first stop: decision:block JSON"    '{"stop_hook_active": false}' '"decision"[[:space:]]*:[[:space:]]*"block"' ''
run "Claude first stop: reason carries warning" '{"stop_hook_active": false}' 'TEST WARNING' ''
run "Claude second stop: plain text, no re-block" '{"stop_hook_active": true}' 'TEST WARNING' '"decision"'
run "Cursor first stop: followup_message JSON"  '{"loop_count": 0}' '"followup_message"' ''
run "Cursor second stop: plain text, no followup" '{"loop_count": 1}' 'TEST WARNING' '"followup_message"'
run "unknown payload: plain-text fallback"      '{}' 'TEST WARNING' '"decision"|"followup_message"'
run "empty stdin: plain-text fallback"          '' 'TEST WARNING' '"decision"|"followup_message"'

# --- observability: an advisory appends one valid JSON line ---
LOG="$WORK/log.jsonl"
printf '%s' '{"stop_hook_active": false}' | env HARNESS_LOG=1 HARNESS_LOG_FILE="$LOG" "$HOOK" >/dev/null 2>&1
if [ -f "$LOG" ] && jq -e 'select(.event == "advise")' "$LOG" >/dev/null 2>&1; then
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
