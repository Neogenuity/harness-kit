#!/usr/bin/env bash
# Regression tests for check-harness.sh. Runnable standalone and in CI.
# Builds a throwaway fixture repo, runs the real check-harness.sh against it,
# and asserts the outcome. Every other check is skipped by its existence
# guard in a bare fixture, so a run isolates check #4 (markdown link
# resolution) unless the fixture opts a file in.
set -uo pipefail

# Force check-harness.sh's dependency-free skill validation instead of an
# external `skills-ref` (which may or may not be installed) so the skill cases
# below are deterministic across machines.
export SKILLS_REF_BIN=__no_skills_ref_binary__

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

# assert_warns <description> <work> <needle>  — check-harness must PASS (exit 0)
# but its output must contain <needle>. Doctor WARNINGs never fail the build,
# so this is how we pin one without conflating it with an ERROR (assert_flags)
# or a silent pass (assert_ok).
assert_warns() {
    local desc="$1" work="$2" needle="$3" out rc
    out=$(bash "$work/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qF "$needle"; then
        echo "ok:   $desc"
    else
        echo "FAIL: $desc — expected exit 0 with '$needle', got exit $rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$work"
}

# assert_ok_without <description> <work> <needle> — check-harness must PASS
# (exit 0) AND its output must NOT contain <needle>. Pins a "does not warn"
# behavior that assert_ok alone can't (warnings don't change the exit code).
assert_ok_without() {
    local desc="$1" work="$2" needle="$3" out rc
    out=$(bash "$work/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "0" ] && ! printf '%s' "$out" | grep -qF "$needle"; then
        echo "ok:   $desc"
    else
        echo "FAIL: $desc — expected exit 0 without '$needle', got exit $rc"
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

# --- check #9: manifest checksum verification, including tailored lines ---
# Gated like the check itself: skipped when no sha tool exists. The fixture
# mechanism file is executable (check #5) and not named test-* (check #6).
if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
    sha() {
        if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
        else sha256sum "$1" | awk '{print $1}'; fi
    }
    ZEROS=$(printf '0%.0s' $(seq 1 64))

    W=$(new_fixture)
    printf 'echo ok\n' > "$W/scripts/mech.sh"; chmod +x "$W/scripts/mech.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/mech.sh\n' "$(sha "$W/scripts/mech.sh")" > "$W/scripts/.harness-manifest"
    assert_ok "manifest: matching checksum passes" "$W"

    W=$(new_fixture)
    printf 'echo ok\n' > "$W/scripts/mech.sh"; chmod +x "$W/scripts/mech.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/mech.sh\n' "$ZEROS" > "$W/scripts/.harness-manifest"
    assert_flags "manifest: checksum mismatch is flagged" "$W" "does not match"

    # The integrity/ownership split: '# tailored' exempts a file from
    # template replacement, NOT from checksum verification.
    W=$(new_fixture)
    printf 'echo ok\n' > "$W/scripts/mech.sh"; chmod +x "$W/scripts/mech.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/mech.sh # tailored\n' "$ZEROS" > "$W/scripts/.harness-manifest"
    assert_flags "manifest: tailored mismatch is still flagged" "$W" "tailored files are still checksum-verified"

    W=$(new_fixture)
    printf 'echo ok\n' > "$W/scripts/mech.sh"; chmod +x "$W/scripts/mech.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/mech.sh # tailored\n' "$(sha "$W/scripts/mech.sh")" > "$W/scripts/.harness-manifest"
    assert_ok "manifest: tailored line with current checksum passes" "$W"

    W=$(new_fixture)
    printf '# harness-kit 9.9.9\n%s  scripts/gone.sh\n' "$ZEROS" > "$W/scripts/.harness-manifest"
    assert_flags "manifest: missing pinned file is flagged" "$W" "does not exist"

    W=$(new_fixture)
    printf '# harness-kit 9.9.9\n%s  scripts/gone.sh # tailored\n' "$ZEROS" > "$W/scripts/.harness-manifest"
    assert_flags "manifest: missing tailored file is flagged too" "$W" "does not exist"
fi

# --- check #9: a missing manifest is an ERROR once the harness is adopted ---
# (scripts/hooks/ present), but still a skip for a pre-adoption repo. Needs no
# sha tool — detecting an absent manifest hashes nothing — so it sits outside
# the sha gate above.
W=$(new_fixture)
mkdir -p "$W/scripts/hooks"          # adoption signal, but no .harness-manifest
assert_flags "adopted repo (scripts/hooks/) missing its manifest is flagged" "$W" ".harness-manifest is missing"

# Truncating the manifest to a header (or 0 bytes) must be caught too: sha256_of
# hashes an empty file to a real digest, so without the pin-count guard the
# verify branch would accept a manifest that pins nothing.
W=$(new_fixture)
mkdir -p "$W/scripts/hooks"
printf '# harness-kit 9.9.9\n' > "$W/scripts/.harness-manifest"   # header only, no pins
assert_flags "adopted repo with an emptied manifest is flagged" "$W" "no pinned entries"

W=$(new_fixture)                     # pre-adoption: no hooks dir, no manifest
assert_ok "a pre-adoption repo with no manifest still passes" "$W"

# --- check #1: strict Agent Skills spec validation (ERRORs) ---
# One fixture per failure class the spec makes a hard requirement.
W=$(new_fixture)
mkdir -p "$W/docs/skills/good-skill"
cat > "$W/docs/skills/good-skill/SKILL.md" <<'EOF'
---
name: good-skill
description: Does a thing. Use when the user asks to do the thing.
---

# Good Skill

Body.
EOF
assert_ok "a spec-conformant skill passes" "$W"

W=$(new_fixture)
mkdir -p "$W/docs/skills/good-skill"
cat > "$W/docs/skills/good-skill/SKILL.md" <<'EOF'
---
name: wrong-name
description: Does a thing.
---
# X
EOF
assert_flags "skill name not matching its directory is flagged" "$W" "must equal its parent directory"

W=$(new_fixture)
mkdir -p "$W/docs/skills/bad--name"
cat > "$W/docs/skills/bad--name/SKILL.md" <<'EOF'
---
name: bad--name
description: Does a thing.
---
# X
EOF
assert_flags "consecutive hyphens in a skill name are flagged" "$W" "consecutive hyphens"

W=$(new_fixture)
mkdir -p "$W/docs/skills/empty-desc"
cat > "$W/docs/skills/empty-desc/SKILL.md" <<'EOF'
---
name: empty-desc
description:
---
# X
EOF
assert_flags "an empty description is flagged" "$W" "description:' is empty"

W=$(new_fixture)
mkdir -p "$W/docs/skills/no-close"
cat > "$W/docs/skills/no-close/SKILL.md" <<'EOF'
---
name: no-close
description: Does a thing.

# X
no closing delimiter
EOF
assert_flags "missing closing frontmatter delimiter is flagged" "$W" "no closing '---' delimiter"

# --- check #10b: active-plan staleness (doctor WARNs) ---
# No 'Next action' section; the fixture is not a git repo, so the git-age arm
# skips gracefully (proves the no-history path doesn't crash or false-warn).
W=$(new_fixture)
mkdir -p "$W/docs/plans/active"
cat > "$W/docs/plans/active/wip.md" <<'EOF'
# WIP
## Objective
Stuff.
EOF
assert_warns "an active plan without a Next action warns" "$W" "no 'Next action' section"

# git-age arm: a plan committed long ago warns. Gated on git being present.
if command -v git >/dev/null 2>&1; then
    W=$(new_fixture)
    mkdir -p "$W/docs/plans/active"
    cat > "$W/docs/plans/active/old.md" <<'EOF'
# Old
## Next action
Finish it.
EOF
    ( cd "$W" \
        && git init -q \
        && git add -A \
        && GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
           git -c user.email=t@example.com -c user.name=t commit -qm seed ) >/dev/null 2>&1
    assert_warns "an active plan stale in git history warns" "$W" "days ago"
fi

# --- check #10c: provider-matrix stamp freshness (doctor WARNs) ---
W=$(new_fixture)
printf 'PROVIDER_MATRIX_DOC="references/matrix.md"\n' > "$W/scripts/harness.conf"
mkdir -p "$W/references"
cat > "$W/references/matrix.md" <<'EOF'
| Cap | X |
| --- | --- |
| Instructions verified 2020-01-01 | y |
EOF
assert_warns "a stale matrix 'verified' stamp warns" "$W" "older than"

W=$(new_fixture)
printf 'PROVIDER_MATRIX_DOC="references/matrix.md"\n' > "$W/scripts/harness.conf"
mkdir -p "$W/references"
cat > "$W/references/matrix.md" <<'EOF'
| Cap | X |
| --- | --- |
| Instructions | y |
EOF
assert_warns "a matrix table with no stamps warns" "$W" "no 'verified <date>' stamps"

W=$(new_fixture)
printf 'PROVIDER_MATRIX_DOC="references/matrix.md"\n' > "$W/scripts/harness.conf"
mkdir -p "$W/references"
cat > "$W/references/matrix.md" <<EOF
| Cap | X |
| --- | --- |
| Instructions verified $(date +%Y-%m-%d) | y |
EOF
assert_ok_without "a freshly-stamped matrix does not warn stale" "$W" "older than"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails check-harness case(s)"
    exit 1
fi
echo "PASSED: all check-harness cases"
