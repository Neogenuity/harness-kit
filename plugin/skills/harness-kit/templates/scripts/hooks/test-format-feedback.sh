#!/usr/bin/env bash
# Regression tests for the post-edit feedback protocol: hook_feedback in
# lib.sh, plus format.sh's fail-open plumbing. Runnable standalone and in CI.
#
# The channel differs per harness: Claude Code and Codex feed a PostToolUse
# hook's stderr to the model on exit 2 (the edit is not undone), while the
# Cursor layout gets plain stdout. Any lint map tailored into format.sh
# inherits exactly this behavior, so pin it here once.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Fixture hook: always has findings, so every case exercises the protocol.
cp "$HOOKS_DIR/lib.sh" "$WORK/lib.sh"
cat > "$WORK/fixture-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
hook_read_input
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

run "Claude/Codex layout: stderr + exit 2"  '{"tool_input":{"file_path":"x.py"}}' 2 err
run "Cursor layout: stdout + exit 0"        '{"file_path":"x.py"}'                0 out
run "unknown payload: stdout fallback"      '{}'                                  0 out
run "empty stdin: stdout fallback"          ''                                    0 out

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

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails format-feedback case(s)"
    exit 1
fi
echo "PASSED: all format-feedback cases"
