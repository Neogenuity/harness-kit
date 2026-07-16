#!/usr/bin/env bash
# Regression tests for the post-edit feedback protocol: hook_feedback in
# lib.sh, plus format.sh's fail-open plumbing. Runnable standalone and in CI.
#
# The channel differs per harness: Claude Code and Codex feed a PostToolUse
# hook's stderr to the model on exit 2 (the edit is not undone). Cursor's
# `afterFileEdit` documents no output field for arbitrary feedback text
# ("No output fields currently supported", verified 2026-07-12) and its
# exit-0 stdout is parsed as JSON, so that layout gets the documented no-op
# (`{}`) instead of dead plain text — the finding still reaches
# .harness/log.jsonl via hook_log (format.sh calls it before hook_feedback).
# Any lint map tailored into format.sh inherits exactly this behavior, so
# pin it here once.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-format-feedback.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Fixture hook: always has findings, so every case exercises the protocol.
cp "$HOOKS_DIR/lib.sh" "$WORK/lib.sh"
cp "$HOOKS_DIR/../log-lib.sh" "$WORK/log-lib.sh"
export HARNESS_LOG=1
export HARNESS_LOG_FILE="$WORK/log.jsonl"
cat > "$WORK/fixture-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
hook_read_input
hook_log lint-findings x.py "TEST DIAGNOSTIC SENTINEL-RAW-MUST-NOT-PERSIST"
hook_feedback "TEST DIAGNOSTIC"
EOF
chmod +x "$WORK/fixture-hook.sh"

fails=0

# run <description> <stdin-payload> <expected-exit> <expected-stream: out|err>
run() {
    local desc="$1" payload="$2" want_rc="$3" want_stream="$4" out err rc
    out=$(printf '%s' "$payload" | "$WORK/fixture-hook.sh" 2>"$WORK/stderr")
    rc=$?
    err=$(cat "$WORK/stderr")
    if [ "$rc" != "$want_rc" ]; then
        echo "FAIL: $desc — expected exit $want_rc, got $rc"
        fails=$((fails + 1))
        return
    fi
    if [ "$want_stream" = "err" ]; then
        if ! printf '%s' "$err" | grep -q 'TEST DIAGNOSTIC'; then
            echo "FAIL: $desc — diagnostic missing from stderr"
            fails=$((fails + 1)); return
        fi
        if printf '%s' "$out" | grep -q 'TEST DIAGNOSTIC'; then
            echo "FAIL: $desc — diagnostic must not also hit stdout"
            fails=$((fails + 1)); return
        fi
    else
        if ! printf '%s' "$out" | grep -q 'TEST DIAGNOSTIC'; then
            echo "FAIL: $desc — diagnostic missing from stdout"
            fails=$((fails + 1)); return
        fi
    fi
    echo "ok:   $desc"
}

run "Claude nested layout: stderr + exit 2" '{"session_id":7,"conversation_id":"conversation-fallback","tool_input":{"file_path":"x.py"}}' 2 err
run "Codex command layout: stderr + exit 2" "$(jq -cn --arg c "apply_patch <<'EOF'
*** Begin Patch
*** Update File: x.py
*** End Patch
EOF" '{turn_id: "t1", tool_name: "apply_patch", tool_use_id: "c1", tool_input: {command: $c}}')" 2 err
run "unknown payload: stdout fallback"      '{}'                                  0 out
run "empty stdin: stdout fallback"          ''                                    0 out

# Cursor layout: afterFileEdit documents no output field for arbitrary
# feedback text and exit-0 stdout there is parsed as JSON, so the diagnostic
# must NOT leak as plain text — it degrades to the documented no-op object.
# Assert both halves: stdout parses as JSON, and the diagnostic is absent.
cursor_out=$(printf '%s' '{"file_path":"x.py"}' | "$WORK/fixture-hook.sh" 2>"$WORK/stderr")
cursor_rc=$?
if [ "$cursor_rc" != "0" ]; then
    echo "FAIL: Cursor layout — expected exit 0, got $cursor_rc"
    fails=$((fails + 1))
elif ! printf '%s' "$cursor_out" | jq -e . >/dev/null 2>&1; then
    echo "FAIL: Cursor layout — stdout does not parse as JSON: $cursor_out"
    fails=$((fails + 1))
elif printf '%s' "$cursor_out" | grep -q 'TEST DIAGNOSTIC'; then
    echo "FAIL: Cursor layout — diagnostic leaked as plain text (afterFileEdit has no such field; must degrade to the log, not dead stdout text)"
    fails=$((fails + 1))
else
    echo "ok:   Cursor layout — degrades to documented no-op JSON ({}), finding stays in the log only"
fi

if [ -f "$HARNESS_LOG_FILE" ] && jq -e -s '
    length >= 1 and all(.[]; .version == 2 and .event == "lint-findings"
      and keys == ["context","data","detail","event","file","hook","ts","version"]
      and (.detail | fromjson) == {category:"lint-findings",count:1})
      and (tostring | contains("SENTINEL-RAW-MUST-NOT-PERSIST") | not)
      and any(.[]; .context.session_id == "conversation-fallback"
        and .context.provenance.session_id == "payload")' \
      "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    echo "ok:   lint findings use the exact v2 envelope"
else
    echo "FAIL: lint findings did not use the exact v2 envelope"
    fails=$((fails + 1))
fi

# format.sh itself must stay silent and fail open when no lint arm matches.
fmt_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$WORK/nothing.xyz" \
    | "$HOOKS_DIR/format.sh" 2>&1)
fmt_rc=$?
if [ "$fmt_rc" != "0" ] || [ -n "$fmt_out" ]; then
    echo "FAIL: format.sh with no matching arm — expected silent exit 0, got exit $fmt_rc: $fmt_out"
    fails=$((fails + 1))
else
    echo "ok:   format.sh with no matching arm stays silent"
fi

# ... and when a Codex patch names a file that doesn't exist (fail open).
fmt_out=$(jq -cn --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n*** Update File: %s\n*** End Patch\nEOF" "$WORK/nothing.xyz")" \
    '{tool_input: {command: $c}}' | "$HOOKS_DIR/format.sh" 2>&1)
fmt_rc=$?
if [ "$fmt_rc" != "0" ] || [ -n "$fmt_out" ]; then
    echo "FAIL: format.sh with a Codex patch on a missing file — expected silent exit 0, got exit $fmt_rc: $fmt_out"
    fails=$((fails + 1))
else
    echo "ok:   format.sh with a Codex patch on a missing file stays silent"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails format-feedback case(s)"
    exit 1
fi
echo "PASSED: all format-feedback cases"
