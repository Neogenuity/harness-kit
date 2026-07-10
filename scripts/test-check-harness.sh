#!/usr/bin/env bash
# Regression tests for check-harness.sh. Runnable standalone and in CI.
# Builds a throwaway fixture repo, runs the real check-harness.sh against it,
# and asserts the outcome. Every other check is skipped by its existence
# guard in a bare fixture, so a run isolates check #4 (markdown link
# resolution) unless the fixture opts a file in.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPTS_DIR/check-harness.sh"

fails=0

# new_fixture -> prints a fresh $WORK with an executable copy of check-harness.
# (cp does not preserve the exec bit, and check #5 flags a non-executable
# harness script — so chmod it, exactly as an install would.)
new_fixture() {
    local work
    work=$(mktemp -d)
    mkdir -p "$work/scripts" "$work/docs"
    cp "$CHECK" "$work/scripts/check-harness.sh"
    chmod +x "$work/scripts/check-harness.sh"
    printf '%s' "$work"
}

# assert_ok <description> <work>   — check-harness must pass (exit 0)
assert_ok() {
    local desc="$1" work="$2" out rc
    out=$(bash "$work/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "0" ]; then
        echo "ok:   $desc"
    else
        echo "FAIL: $desc — expected exit 0, got $rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$work"
}

# assert_flags <description> <work> <needle>  — check-harness must fail (exit 1)
# and its output must mention <needle> (proves it flagged the real breakage,
# not something incidental).
assert_flags() {
    local desc="$1" work="$2" needle="$3" out rc
    out=$(bash "$work/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] && printf '%s' "$out" | grep -qF "$needle"; then
        echo "ok:   $desc"
    else
        echo "FAIL: $desc — expected exit 1 mentioning '$needle', got exit $rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$work"
}

# --- the regression: a titled link to a file that EXISTS must not error ---
# Before the fix, "${link%%#*}" left the title on the target
# (guide.md "The Guide") so the path never resolved and check #4 errored.
W=$(new_fixture)
: > "$W/docs/guide.md"
cat > "$W/docs/index.md" <<'EOF'
# Index
- [Guide](guide.md "The Guide")
- [Ticked](guide.md 'single-quoted title')
- [Parened](guide.md (parenthetical title))
- [Anchored](guide.md#section "with anchor and title")
- [Bare](guide.md)
EOF
assert_ok "titled links to an existing file do not error" "$W"

# --- angle-bracketed destination (may contain spaces) resolves ---
W=$(new_fixture)
: > "$W/docs/my guide.md"
cat > "$W/docs/index.md" <<'EOF'
# Index
- [Spaced](<my guide.md>)
- [SpacedTitled](<my guide.md> "a title")
EOF
assert_ok "angle-bracketed destination with a space resolves" "$W"

# --- positive control: a genuinely missing target is still flagged ---
# Guards against "fixing" false positives by neutering the check entirely.
W=$(new_fixture)
cat > "$W/docs/index.md" <<'EOF'
# Index
- [Missing](does-not-exist.md "Even with a title")
EOF
assert_flags "a missing target is still reported" "$W" "does-not-exist.md"

# --- links inside a fenced code block are ignored ---
W=$(new_fixture)
cat > "$W/docs/index.md" <<'EOF'
# Index
```
- [Example](totally-made-up.md)
```
EOF
assert_ok "links in fenced code blocks are ignored" "$W"

# --- check #8b: opencode.json deny list must mirror SECRET_PATTERNS ---
# jq-gated: the check itself is skipped without jq, so the assertion would
# be meaningless there.
if command -v jq >/dev/null 2>&1; then
    W=$(new_fixture)
    printf 'SECRET_PATTERNS=".env auth.json"\n' > "$W/scripts/harness.conf"
    cat > "$W/opencode.json" <<'EOF'
{ "permission": { "read": { "**/.env": "deny" } } }
EOF
    assert_flags "opencode.json missing a secret pattern is flagged" "$W" "auth.json"

    W=$(new_fixture)
    printf 'SECRET_PATTERNS=".env auth.json"\n' > "$W/scripts/harness.conf"
    cat > "$W/opencode.json" <<'EOF'
{ "permission": { "read": { "**/.env": "deny", "**/auth.json": "deny" } } }
EOF
    assert_ok "opencode.json mirroring every pattern passes" "$W"

    # --- deleting a wired provider's native deny file is an error, not a skip ---
    W=$(new_fixture)
    printf 'SECRET_PATTERNS=".env"\n' > "$W/scripts/harness.conf"
    mkdir -p "$W/.opencode/skills"
    assert_flags "wired .opencode/ without opencode.json is flagged" "$W" "opencode.json is missing"

    W=$(new_fixture)
    printf 'SECRET_PATTERNS=".env"\n' > "$W/scripts/harness.conf"
    mkdir -p "$W/.claude/skills"
    assert_flags "wired .claude/ without settings.json is flagged" "$W" ".claude/settings.json is missing"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails check-harness case(s)"
    exit 1
fi
echo "PASSED: all check-harness cases"
