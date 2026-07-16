#!/usr/bin/env bash
# Regression tests for session-context.sh — the session-start banner. Pins the
# BANNER_RECENT_COMMITS toggle (default OFF, the context-efficiency trim) read
# from env and from harness.conf, and fail-safe on a bad value. Runnable
# standalone and in CI.
set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-session-context.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0

# session-context.sh derives ROOT from its own location, so place it under
# $WORK/scripts/hooks and make $WORK a git repo with a couple of commits.
mkdir -p "$WORK/scripts/hooks" "$WORK/docs/plans/active"
cp "$HOOKS_DIR/session-context.sh" "$WORK/scripts/hooks/session-context.sh"
HOOK="$WORK/scripts/hooks/session-context.sh"
(
    cd "$WORK" || exit 1
    git init -q .
    git config user.email "t@example.invalid"; git config user.name "t"
    echo one > a.txt; git add -A; git commit -qm "first commit" >/dev/null
    echo two > b.txt; git add -A; git commit -qm "second commit" >/dev/null
)

# (1) default (unset) — Branch line present, Recent-commits block omitted.
out=$(env -u BANNER_RECENT_COMMITS "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q '^Branch:' && ! printf '%s' "$out" | grep -q 'Recent commits:'; then
    echo "ok:   default omits the recent-commits block"
else
    echo "FAIL: default should show Branch but omit Recent commits"; fails=$((fails+1))
fi

# (2) BANNER_RECENT_COMMITS=2 (env) — block present.
out=$(env BANNER_RECENT_COMMITS=2 "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'Recent commits:' && [ "$(printf '%s\n' "$out" | grep -c 'commit$')" -ge 1 ]; then
    echo "ok:   BANNER_RECENT_COMMITS=2 (env) includes the recent-commits block"
else
    echo "FAIL: BANNER_RECENT_COMMITS=2 should include recent commits"; fails=$((fails+1))
fi

# (3) value honored from harness.conf (the production source).
printf 'BANNER_RECENT_COMMITS=1\n' > "$WORK/scripts/harness.conf"
out=$(env -u BANNER_RECENT_COMMITS "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'Recent commits:'; then
    echo "ok:   BANNER_RECENT_COMMITS honored from harness.conf"
else
    echo "FAIL: harness.conf BANNER_RECENT_COMMITS not honored"; fails=$((fails+1))
fi
rm -f "$WORK/scripts/harness.conf"

# (4) fail-safe: a non-numeric value must not crash (exit 0, no block).
out=$(env BANNER_RECENT_COMMITS=abc "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'Recent commits:'; then
    echo "ok:   non-numeric BANNER_RECENT_COMMITS fails safe (no block, exit 0)"
else
    echo "FAIL: non-numeric value should fail safe (rc=$rc)"; fails=$((fails+1))
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails session-context case(s)"; exit 1; fi
echo "PASSED: all session-context cases"
