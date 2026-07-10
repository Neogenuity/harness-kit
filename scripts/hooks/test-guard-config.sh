#!/usr/bin/env bash
# Regression tests for guard-config.sh. Runnable standalone and in CI.
# Each case feeds a hook payload on stdin and asserts the exit code:
#   0 = allowed, 2 = denied.
#
# The guard protects the harness mechanism from agent edits; if you tailor
# PROTECTED_PATHS, extend these cases so the boundary stays pinned.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Run from a fake repo root so ROOT resolution and rel-path stripping are
# exercised exactly as installed.
mkdir -p "$WORK/scripts/hooks" "$WORK/src"
cp "$HOOKS_DIR/lib.sh" "$WORK/scripts/hooks/lib.sh"
cp "$HOOKS_DIR/guard-config.sh" "$WORK/scripts/hooks/guard-config.sh"
HOOK="$WORK/scripts/hooks/guard-config.sh"

fails=0

payload() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
cursor_payload() { printf '{"file_path":"%s"}' "$1"; }

# run <expected-exit> <description> <json-payload> [env]
run() {
    local expected="$1" desc="$2" payload="$3" actual
    printf '%s' "$payload" | env HARNESS_LOG=0 ${4:-HARNESS_ALLOW_MECHANISM_EDITS=0} "$HOOK" >/dev/null 2>&1
    actual=$?
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $desc — expected exit $expected, got $actual"
        fails=$((fails + 1))
    else
        echo "ok:   $desc"
    fi
}

# --- deny: mechanism files, absolute and relative, both layouts ---
run 2 "hook script edit denied"          "$(payload "$WORK/scripts/hooks/lib.sh")"
run 2 "check-harness.sh edit denied"     "$(payload "$WORK/scripts/check-harness.sh")"
run 2 "manifest edit denied"             "$(payload "$WORK/scripts/.harness-manifest")"
run 2 "regression test edit denied"      "$(payload "$WORK/scripts/test-check-harness.sh")"
run 2 "hook wiring edit denied"          "$(payload "$WORK/.claude/settings.json")"
run 2 "opencode.json edit denied"        "$(payload "$WORK/opencode.json")"
run 2 "relative path denied"             "$(payload "scripts/hooks/guard-secrets.sh")"
run 2 "Cursor layout denied"             "$(cursor_payload "$WORK/scripts/sync-agent-skills.sh")"

# --- allow: ordinary files, escape hatch, fail-open ---
run 0 "ordinary source file allowed"     "$(payload "$WORK/src/app.php")"
run 0 "sibling name not protected"       "$(payload "$WORK/src/check-harness.sh.md")"
run 0 "escape hatch allows mechanism edit" "$(payload "$WORK/scripts/hooks/lib.sh")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "empty payload fails open"         '{}'

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails guard-config case(s)"
    exit 1
fi
echo "PASSED: all guard-config cases"
