#!/usr/bin/env bash
# Regression tests for the model-visible deny protocol: hook_deny in
# lib.sh. Runnable standalone and in CI.
#
# hook_deny is shared by guard-config.sh and guard-secrets.sh. The portable
# path is exit 2 + stderr, always available. On a PreToolUse payload —
# gated strictly on `.hook_event_name == "PreToolUse"`, since that's the
# only field that reliably distinguishes it from the Cursor top-level
# file_path layout — Claude Code and Codex both parse
# `hookSpecificOutput.permissionDecision` (verified against the Claude Code
# hooks doc, 2026-07-12), so it additionally emits an exit-0 JSON deny with
# the reason in `permissionDecisionReason`, model-visible instead of routed
# to internal logs. Every other shape (Cursor's layout, a non-PreToolUse
# event, no hook_event_name at all, jq unavailable, or JSON construction
# failing) MUST stay on the portable exit-2 path: a malformed exit-0 "deny"
# would fail OPEN (allow), the one direction this protocol must never take.
# Existing guard-config.sh / guard-secrets.sh regression payloads
# deliberately omit hook_event_name and must keep exiting 2 — any guard
# built on hook_deny inherits exactly this behavior, so pin it here once.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")/../hooks" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-deny-reasons.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Keep hook_log out of the repo during tests.
export HARNESS_LOG=0

skips=0

# Fixture hook: always denies with a fixed reason, so every case exercises
# the protocol.
cp "$HOOKS_DIR/lib.sh" "$WORK/lib.sh"
cat > "$WORK/fixture-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
hook_read_input
hook_deny "REASON TEXT"
EOF
chmod +x "$WORK/fixture-hook.sh"
HOOK="$WORK/fixture-hook.sh"

fails=0

# --- 1: PreToolUse tool_input layout -> exit 0, JSON deny, model-visible reason ---
out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"x.py"}}' | "$HOOK" 2>"$WORK/stderr1")
rc=$?
if [ "$rc" != "0" ]; then
    echo "FAIL: PreToolUse layout — expected exit 0, got $rc"
    fails=$((fails + 1))
elif ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    echo "FAIL: PreToolUse layout — stdout does not parse as JSON: $out"
    fails=$((fails + 1))
elif ! printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "FAIL: PreToolUse layout — hookSpecificOutput.permissionDecision:deny missing: $out"
    fails=$((fails + 1))
elif ! printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1; then
    echo "FAIL: PreToolUse layout — hookSpecificOutput.hookEventName:PreToolUse missing: $out"
    fails=$((fails + 1))
elif ! printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | grep -q 'REASON TEXT'; then
    echo "FAIL: PreToolUse layout — reason text missing from permissionDecisionReason: $out"
    fails=$((fails + 1))
else
    echo "ok:   PreToolUse layout — exit 0, JSON permissionDecision:deny carries the model-visible reason"
fi

# --- 2: Cursor top-level file_path layout (no hook_event_name) -> exit 2, stderr ---
out=$(printf '%s' '{"file_path":"x.py"}' | "$HOOK" 2>"$WORK/stderr2")
rc=$?
err=$(cat "$WORK/stderr2")
if [ "$rc" != "2" ]; then
    echo "FAIL: Cursor layout — expected exit 2, got $rc"
    fails=$((fails + 1))
elif ! printf '%s' "$err" | grep -q 'REASON TEXT'; then
    echo "FAIL: Cursor layout — reason missing from stderr: $err"
    fails=$((fails + 1))
elif [ -n "$out" ]; then
    echo "FAIL: Cursor layout — expected no stdout, got: $out"
    fails=$((fails + 1))
else
    echo "ok:   Cursor layout (no hook_event_name) — portable exit 2 + stderr reason"
fi

# --- 3: jq unavailable on a PreToolUse payload -> exit 2, fail-closed ---
# Build a PATH containing everything hook_deny's call path needs EXCEPT jq,
# by resolving each tool once and writing an exec wrapper for it. Note that
# printf, true and false are bash BUILTINS, which is why the resolver below
# cannot use `command -v` — see _shim.
# This proves the JSON deny path degrades to the portable exit-2 fallback
# rather than crashing or — the one unacceptable outcome — failing open when
# jq truly isn't there to build or verify the JSON.
# _shim <bindir> <tool> — put a runnable <tool> onto a synthetic PATH without
# needing symlink privilege, and without trusting `command -v` for a name that
# is ALSO a shell builtin. Two independent traps this avoids:
#   1. MSYS/Git Bash without Developer Mode cannot create real symlinks: `ln -s`
#      either copies or fails outright, leaving the directory short of tools.
#      The synthetic PATH then means "nothing is available", not "jq is
#      missing" — the assertion below stops testing what it claims to.
#   2. `command -v printf` answers `printf` in bash, not /usr/bin/printf,
#      because printf is a builtin. `ln -s printf <dir>/printf` therefore has no
#      resolvable source. This one bites on ANY bash, privilege or not.
# An exec wrapper is a plain file, so it needs no privilege anywhere.
_shim() {
    local dir="$1" tool="$2" target
    # `type -P` is the correct resolver: it searches PATH for an executable FILE
    # and deliberately skips builtins and functions, so it answers
    # /usr/bin/printf where `command -v printf` answers `printf`. No hardcoded
    # /bin:/usr/bin guess, which would mis-resolve on Nix or a minimal image.
    target=$(type -P -- "$tool" 2>/dev/null)
    # Retry on the standard utility PATH for a host whose login PATH omits
    # coreutils' home.
    [ -n "$target" ] || target=$( PATH=$(getconf PATH 2>/dev/null); type -P -- "$tool" 2>/dev/null )
    [ -n "$target" ] || return 1
    # Quote the target: an unquoted path containing whitespace yields a wrapper
    # that builds and chmods cleanly, then fails at run time with 126 — a
    # mis-built fixture presenting as the assertion failing, which is the exact
    # class this helper exists to remove.
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$target" > "$dir/$tool" || return 1
    # 755 explicitly: `chmod +x` is masked by the caller's umask.
    chmod 755 "$dir/$tool"
}

NOJQ_BIN="$WORK/nojq-bin"
mkdir -p "$NOJQ_BIN"
shim_missing=""
for tool in bash sh cat dirname basename head mkdir date printf grep sed awk tr readlink env true false git; do
    _shim "$NOJQ_BIN" "$tool" || shim_missing="$shim_missing $tool"
done
if [ -n "$shim_missing" ]; then
    # Report the unbuildable fixture as itself. Asserting on a half-populated
    # PATH is how "the harness could not be built" got reported as "the guard
    # failed to fail closed (got 127)".
    echo "SKIP: jq-unavailable PreToolUse — could not build the stripped PATH (unresolvable:$shim_missing)"
    skips=$((skips + 1))
elif PATH="$NOJQ_BIN" bash -c 'command -v jq' >/dev/null 2>&1; then
    echo "FAIL: jq-unavailable harness — jq is still resolvable on the stripped PATH; test setup is broken"
    fails=$((fails + 1))
else
    out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"x.py"}}' \
        | env HARNESS_LOG=0 PATH="$NOJQ_BIN" "$HOOK" 2>"$WORK/stderr3")
    rc=$?
    err=$(cat "$WORK/stderr3")
    if [ "$rc" != "2" ]; then
        echo "FAIL: jq-unavailable PreToolUse — expected exit 2 (fail-closed), got $rc"
        fails=$((fails + 1))
    elif ! printf '%s' "$err" | grep -q 'REASON TEXT'; then
        echo "FAIL: jq-unavailable PreToolUse — reason missing from stderr: $err"
        fails=$((fails + 1))
    elif [ -n "$out" ]; then
        echo "FAIL: jq-unavailable PreToolUse — expected no stdout, got: $out"
        fails=$((fails + 1))
    else
        echo "ok:   jq unavailable on a PreToolUse payload — fails closed to the portable exit 2"
    fi
fi

# --- extra: non-PreToolUse event stays on the portable path ---
out=$(printf '%s' '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"x.py"}}' | "$HOOK" 2>"$WORK/stderr4")
rc=$?
if [ "$rc" != "2" ]; then
    echo "FAIL: non-PreToolUse event — expected exit 2, got $rc"
    fails=$((fails + 1))
elif ! grep -q 'REASON TEXT' "$WORK/stderr4"; then
    echo "FAIL: non-PreToolUse event — reason missing from stderr"
    fails=$((fails + 1))
else
    echo "ok:   non-PreToolUse hook_event_name — stays on the portable exit 2 path"
fi

# --- extra: tool_input present but no hook_event_name (existing regression
#     payloads in test-guard-config.sh / test-guard-secrets.sh are shaped
#     exactly like this) must keep exiting 2 ---
out=$(printf '%s' '{"tool_input":{"file_path":"x.py"}}' | "$HOOK" 2>"$WORK/stderr5")
rc=$?
if [ "$rc" != "2" ]; then
    echo "FAIL: tool_input without hook_event_name — expected exit 2, got $rc"
    fails=$((fails + 1))
elif ! grep -q 'REASON TEXT' "$WORK/stderr5"; then
    echo "FAIL: tool_input without hook_event_name — reason missing from stderr"
    fails=$((fails + 1))
else
    echo "ok:   tool_input layout without hook_event_name — stays on the portable exit 2 path (backward-compat with existing guard regression payloads)"
fi

# --- extra: empty payload fails closed too (a deny is always a deny) ---
out=$(printf '%s' '{}' | "$HOOK" 2>"$WORK/stderr6")
rc=$?
if [ "$rc" != "2" ]; then
    echo "FAIL: empty payload — expected exit 2, got $rc"
    fails=$((fails + 1))
else
    echo "ok:   empty payload — still a portable exit 2 deny"
fi

# --- extra: fail-closed when the exit-0 JSON write itself fails ---
# A PreToolUse deny whose JSON can't reach stdout (here: stdout closed with
# >&-, standing in for any broken/closed pipe) MUST fall through to the
# portable exit-2 deny — never exit 0 with no deny bytes, which a harness
# reads as ALLOW. This pins the write-failure arm of the fail-closed invariant
# that the plain jq-present happy path can't exercise.
printf '%s' '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"x.py"}}' \
    | "$HOOK" >&- 2>"$WORK/stderr7"
rc=$?
if [ "$rc" != "2" ]; then
    echo "FAIL: closed-stdout PreToolUse deny — expected exit 2 (fail-closed), got $rc"
    fails=$((fails + 1))
elif ! grep -q 'REASON TEXT' "$WORK/stderr7"; then
    echo "FAIL: closed-stdout PreToolUse deny — reason missing from stderr"
    fails=$((fails + 1))
else
    echo "ok:   closed-stdout PreToolUse deny — falls through to the portable exit 2 (never fails open)"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails deny-reasons case(s)"
    exit 1
fi
if [ "$skips" -gt 0 ]; then
    echo "PASSED: all deny-reasons cases that ran ($skips skipped)"
else
    echo "PASSED: all deny-reasons cases"
fi
