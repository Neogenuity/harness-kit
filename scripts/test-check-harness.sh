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

# One guarded scratch base for every fixture below. The guard is load-bearing,
# not decoration: bare `mktemp -d` ignores $TMPDIR on macOS (it resolves
# _CS_DARWIN_USER_TEMP_DIR, i.e. /var/folders) and fails outright in a sandbox.
# An unguarded failure leaves the path EMPTY, and bash `cd ""` is a silent rc=0
# no-op — so `( cd "$w" && git commit ... )` runs in the HOST repo. That put junk
# commits on this repo's main branch twice before check #6b existed. Fixtures
# carve subdirectories out of this base, so their own mktemp cannot fail loose.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-check-harness.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

fails=0

# new_fixture -> prints a fresh $WORK with an executable copy of check-harness.
# (cp does not preserve the exec bit, and check #5 flags a non-executable
# harness script — so chmod it, exactly as an install would.)
new_fixture() {
    local work
    work=$(mktemp -d "$WORK/fixture.XXXXXX") || return 1
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

    # Completeness explicitly includes the v0.15 helper and the optional,
    # project-authored dev.sh policy. Removing either line while leaving the
    # executable on disk must not silently exempt it from integrity checks.
    W=$(new_fixture)
    mkdir -p "$W/scripts/hooks"
    printf '#!/usr/bin/env bash\necho h000000000000\n' > "$W/scripts/dev-instance.sh"
    chmod +x "$W/scripts/dev-instance.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/check-harness.sh\n' \
        "$(sha "$W/scripts/check-harness.sh")" > "$W/scripts/.harness-manifest"
    assert_flags "manifest completeness: dev-instance helper missing-line is flagged" "$W" "dev-instance.sh' is present but not pinned"

    W=$(new_fixture)
    mkdir -p "$W/scripts/hooks"
    printf '#!/usr/bin/env bash\necho project\n' > "$W/scripts/dev.sh"
    chmod +x "$W/scripts/dev.sh"
    printf '# harness-kit 9.9.9\n%s  scripts/check-harness.sh\n' \
        "$(sha "$W/scripts/check-harness.sh")" > "$W/scripts/.harness-manifest"
    assert_flags "manifest completeness: optional dev.sh missing-line is flagged" "$W" "dev.sh' is present but not pinned"
fi

# --- check #9: a missing manifest is an ERROR once the harness is adopted ---
# (scripts/hooks/ present), but still a skip for a pre-adoption repo. Needs no
# sha tool — detecting an absent manifest hashes nothing — so it sits outside
# the sha gate above.
W=$(new_fixture)
mkdir -p "$W/scripts/hooks"          # adoption signal, but no .harness-manifest
assert_flags "adopted repo (scripts/hooks/) missing its manifest is flagged" "$W" ".harness-manifest is missing"

# Truncating the manifest to a header (or 0 bytes) must be caught too: sha256_of
# hashes an empty file to a real digest, so without the valid-pin guard the
# verify branch would accept a manifest that pins nothing.
W=$(new_fixture)
mkdir -p "$W/scripts/hooks"
printf '# harness-kit 9.9.9\n' > "$W/scripts/.harness-manifest"   # header only, no pins
assert_flags "adopted repo with an emptied manifest is flagged" "$W" "no valid pinned entries"

# A nonempty MALFORMED line must not count as a pin (it would otherwise satisfy
# the adopted-repo guard while enforcing nothing) — it is itself an error.
W=$(new_fixture)
printf '# harness-kit 9.9.9\nx\n' > "$W/scripts/.harness-manifest"   # garbage line
assert_flags "a malformed manifest entry is flagged" "$W" "malformed entry"

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
    ( cd "${W:?}" \
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

# --- check #8c: MCP trust inventory, split severity, cases (a)-(j) ---
# (f) no MCP configs + no inventory declared → fully silent (bare fixture).
W=$(new_fixture)
assert_ok_without "8c(f): no MCP configs, no inventory → silent" "$W" "trust inventory"

# TOML (.codex/config.toml) is parsed with awk, no jq — so these two run
# regardless of jq. Quoted-hyphenated table name + a disabled entry that must
# be skipped.
# (a-toml) undeclared server, no inventory → the no-inventory WARN.
W=$(new_fixture)
mkdir -p "$W/.codex"
cat > "$W/.codex/config.toml" <<'EOF'
[mcp_servers."my-linter"]
command = "npx"
args = ["-y", "@lint/mcp"]

[mcp_servers.turnedoff]
command = "foo"
enabled = false
EOF
assert_warns "8c(a) TOML server, no inventory → no-inventory WARN" "$W" "no trust inventory declared"

# (a-toml) inventory SET (empty, strict) → the quoted-hyphenated server ERRORs,
# naming file + server; the enabled=false entry stays silent.
W=$(new_fixture)
mkdir -p "$W/.codex"
printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
cat > "$W/.codex/config.toml" <<'EOF'
[mcp_servers."my-linter"]
command = "npx"
args = ["-y", "@lint/mcp"]

[mcp_servers.turnedoff]
command = "foo"
enabled = false
EOF
assert_flags "8c(a) TOML quoted-hyphen server, inventory set → ERROR" "$W" "'my-linter' in .codex/config.toml"

# (k) a name-only inventory line is itself an ERROR — an empty pin would make
#     the identity check vacuous (grep -F "" matches everything). Fires even
#     with no MCP configs present; trailing whitespace is still name-only.
W=$(new_fixture)
printf 'MCP_ALLOWED_SERVERS="\nok-server @good/pkg\nbare-name   \n"\n' > "$W/scripts/harness.conf"
assert_flags "8c(k) name-only inventory line → ERROR (even with no configs)" "$W" "'bare-name' has no identity substring"

# (l) the vacuous-pass attack the empty pin enables: a configured server whose
#     inventory line has no pin must FAIL the run, not silently match.
W=$(new_fixture)
mkdir -p "$W/.codex"
printf 'MCP_ALLOWED_SERVERS="bare-name"\n' > "$W/scripts/harness.conf"
cat > "$W/.codex/config.toml" <<'EOF'
[mcp_servers.bare-name]
command = "npx"
args = ["-y", "@whatever/mcp"]
EOF
assert_flags "8c(l) configured server with pin-less inventory line → ERROR, not a pass" "$W" "no identity substring"

# (m) a single-quoted (TOML literal-string) table name unwraps like a
#     double-quoted one: correctly pinned, the dotted name is clean — before
#     the fix the name parsed as 'dotted (mangled) and spuriously ERRORed.
W=$(new_fixture)
mkdir -p "$W/.codex"
printf 'MCP_ALLOWED_SERVERS="dotted.name @good/pkg"\n' > "$W/scripts/harness.conf"
cat > "$W/.codex/config.toml" <<'EOF'
[mcp_servers.'dotted.name']
command = "npx"
args = ["-y", "@good/pkg"]
EOF
assert_ok "8c(m) single-quoted dotted TOML name, correctly pinned → clean" "$W"

# (n) a TOML config whose only server is disabled stays fully silent even
#     under a strict (set-but-empty) inventory — disabled entries are not
#     audited, mirroring the JSON case (e).
W=$(new_fixture)
mkdir -p "$W/.codex"
printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
cat > "$W/.codex/config.toml" <<'EOF'
[mcp_servers.turnedoff]
command = "foo"
disabled = true
EOF
assert_ok_without "8c(n) disabled-only TOML server under strict inventory → silent" "$W" "turnedoff"

# The JSON providers need jq; the check skips (WARNs "not audited") without it,
# so the ERROR/clean assertions below are only meaningful where jq exists.
if command -v jq >/dev/null 2>&1; then
    # (a) .mcp.json — WARN with no inventory, ERROR (file + name) once set.
    W=$(new_fixture)
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"alpha":{"command":"npx","args":["-y","@a/mcp"]}}}
EOF
    assert_warns "8c(a) .mcp.json server, no inventory → WARN" "$W" "no trust inventory declared"

    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"alpha":{"command":"npx","args":["-y","@a/mcp"]}}}
EOF
    assert_flags "8c(a) .mcp.json server, inventory set → ERROR" "$W" "'alpha' in .mcp.json"

    # (a) .cursor/mcp.json — same shape.
    W=$(new_fixture)
    mkdir -p "$W/.cursor"
    cat > "$W/.cursor/mcp.json" <<'EOF'
{"mcpServers":{"curserver":{"url":"https://c.example/mcp"}}}
EOF
    assert_warns "8c(a) .cursor/mcp.json server, no inventory → WARN" "$W" "no trust inventory declared"

    W=$(new_fixture)
    mkdir -p "$W/.cursor"
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    cat > "$W/.cursor/mcp.json" <<'EOF'
{"mcpServers":{"curserver":{"url":"https://c.example/mcp"}}}
EOF
    assert_flags "8c(a) .cursor/mcp.json server, inventory set → ERROR" "$W" "'curserver' in .cursor/mcp.json"

    # (a) opencode.json "mcp" — array-command shape, enabled flag.
    W=$(new_fixture)
    cat > "$W/opencode.json" <<'EOF'
{"mcp":{"ocserver":{"type":"local","command":["npx","-y","@oc/mcp"],"enabled":true}}}
EOF
    assert_warns "8c(a) opencode.json server, no inventory → WARN" "$W" "no trust inventory declared"

    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    cat > "$W/opencode.json" <<'EOF'
{"mcp":{"ocserver":{"type":"local","command":["npx","-y","@oc/mcp"],"enabled":true}}}
EOF
    assert_flags "8c(a) opencode.json server, inventory set → ERROR" "$W" "'ocserver' in opencode.json"

    # (b) name allowed but identity repointed → ERROR (identity drift).
    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS="alpha @good/pkg"\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"alpha":{"command":"npx","args":["-y","@evil/pkg"]}}}
EOF
    assert_flags "8c(b) allowed name, repointed identity → ERROR" "$W" "does not contain its pinned substring"

    # (c) fully covered, including names with dots and hyphens → clean.
    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS="\nmy.server @good/pkg\nmy-server https://x.example/mcp\n"\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"my.server":{"command":"npx","args":["-y","@good/pkg"]},"my-server":{"url":"https://x.example/mcp"}}}
EOF
    assert_ok "8c(c) every server covered (dotted/hyphenated names) → clean" "$W"

    # (d) empty maps (the shipped opencode "mcp": {}) → silent even undeclared.
    W=$(new_fixture)
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{}}
EOF
    cat > "$W/opencode.json" <<'EOF'
{"mcp":{}}
EOF
    assert_ok_without "8c(d) empty mcp maps → silent (no WARN)" "$W" "trust inventory"

    # (e) a single disabled server → silent (must not count as configured).
    W=$(new_fixture)
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"off1":{"command":"x","disabled":true}}}
EOF
    assert_ok_without "8c(e) disabled server → silent" "$W" "trust inventory"

    # (g) the no-inventory WARN fires EXACTLY once across multiple configs.
    W=$(new_fixture)
    mkdir -p "$W/.cursor"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"alpha":{"command":"npx","args":["-y","@a/mcp"]}}}
EOF
    cat > "$W/.cursor/mcp.json" <<'EOF'
{"mcpServers":{"beta":{"command":"npx","args":["-y","@b/mcp"]}}}
EOF
    out=$(bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    count=$(printf '%s\n' "$out" | grep -c "no trust inventory declared")
    if [ "$rc" = "0" ] && [ "$count" -eq 1 ]; then
        echo "ok:   8c(g) no-inventory WARN fires exactly once across configs"
    else
        echo "FAIL: 8c(g) no-inventory WARN once — rc=$rc count=$count"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    # (h) malformed JSON alongside a valid config → unaudited WARN for the
    #     malformed file AND the valid file is still checked (ERROR here).
    W=$(new_fixture)
    mkdir -p "$W/.cursor"
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    printf '{ this is not json\n' > "$W/.mcp.json"
    cat > "$W/.cursor/mcp.json" <<'EOF'
{"mcpServers":{"beta":{"command":"npx","args":["-y","@b/mcp"]}}}
EOF
    out=$(bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] \
        && printf '%s' "$out" | grep -qF ".mcp.json could not be parsed" \
        && printf '%s' "$out" | grep -qF "'beta' in .cursor/mcp.json"; then
        echo "ok:   8c(h) malformed config WARNs unaudited; valid config still checked"
    else
        echo "FAIL: 8c(h) malformed+valid — rc=$rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    # (i) jq removed via a PATH shim (symlink only the utilities check-harness
    #     needs) with a JSON config present → unaudited WARN, exit 0. Proves the
    #     jq-absent path is loud, not silent.
    shim=$(mktemp -d "$WORK/shim.XXXXXX") || return 1
    for u in bash sh env dirname basename grep egrep awk sed sort find wc tr head cat date git shasum sha256sum mktemp rm chmod ls uname printf seq; do
        p=$(command -v "$u" 2>/dev/null) && ln -s "$p" "$shim/$u" 2>/dev/null
    done
    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"gamma":{"command":"npx","args":["-y","@g/mcp"]}}}
EOF
    out=$(env PATH="$shim" bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "0" ] \
        && printf '%s' "$out" | grep -qF ".mcp.json is an MCP config but jq is unavailable"; then
        echo "ok:   8c(i) jq absent + JSON config → unaudited WARN, exit 0"
    else
        echo "FAIL: 8c(i) no-jq shim — rc=$rc (jq-in-shim: $(PATH="$shim" command -v jq || echo none))"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W" "$shim"

    # (j) same server name in two providers, one identity pinned → only the
    #     mismatching provider ERRORs; the matching one stays clean.
    W=$(new_fixture)
    mkdir -p "$W/.cursor"
    printf 'MCP_ALLOWED_SERVERS="dup @correct/pkg"\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"dup":{"command":"npx","args":["-y","@correct/pkg"]}}}
EOF
    cat > "$W/.cursor/mcp.json" <<'EOF'
{"mcpServers":{"dup":{"command":"npx","args":["-y","@evil/pkg"]}}}
EOF
    out=$(bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] \
        && printf '%s' "$out" | grep -qF "'dup' in .cursor/mcp.json" \
        && ! printf '%s' "$out" | grep -qF "'dup' in .mcp.json"; then
        echo "ok:   8c(j) only the mismatching provider ERRORs"
    else
        echo "FAIL: 8c(j) dup name across providers — rc=$rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    # (o) a non-object junk sibling under mcpServers must NOT crash the jq
    #     extraction and downgrade the real server's drift ERROR into a
    #     "could not be parsed" WARN — the junk is ignored, evil still ERRORs.
    W=$(new_fixture)
    printf 'MCP_ALLOWED_SERVERS=""\n' > "$W/scripts/harness.conf"
    cat > "$W/.mcp.json" <<'EOF'
{"mcpServers":{"evil":{"command":"npx","args":["-y","@evil/pkg"]},"junk":"not-a-server"}}
EOF
    out=$(bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] \
        && printf '%s' "$out" | grep -qF "'evil' in .mcp.json" \
        && ! printf '%s' "$out" | grep -qF "could not be parsed"; then
        echo "ok:   8c(o) junk non-object sibling ignored; evil server still ERRORs"
    else
        echo "FAIL: 8c(o) junk sibling downgrade — rc=$rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    # (p) jq absent + configs whose maps are trivially empty (the shipped
    #     opencode template shape) → fully silent, not a perpetual unaudited
    #     WARN: the dependency-free empty-map fast path.
    shim=$(mktemp -d "$WORK/shim.XXXXXX") || return 1
    for u in bash sh env dirname basename grep egrep awk sed sort find wc tr head cat date git shasum sha256sum mktemp rm chmod ls uname printf seq; do
        p=$(command -v "$u" 2>/dev/null) && ln -s "$p" "$shim/$u" 2>/dev/null
    done
    W=$(new_fixture)
    cat > "$W/.mcp.json" <<'EOF'
{ "mcpServers": {} }
EOF
    cat > "$W/opencode.json" <<'EOF'
{ "mcp": {} }
EOF
    out=$(env PATH="$shim" bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "0" ] \
        && ! printf '%s' "$out" | grep -qF "jq is unavailable" \
        && ! printf '%s' "$out" | grep -qF "trust inventory"; then
        echo "ok:   8c(p) jq absent + empty mcp maps → silent (no unaudited WARN)"
    else
        echo "FAIL: 8c(p) no-jq empty-map fast path — rc=$rc"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W" "$shim"
fi

# --- check #10d: CI action pinning (doctor WARNs) ---
# A mutable @tag ref WARNs; a full 40-hex SHA (and a local ./ ref) stays clean.
W=$(new_fixture)
mkdir -p "$W/.github/workflows"
cat > "$W/.github/workflows/ci.yml" <<'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/local-thing
EOF
assert_warns "10d: a mutable @tag action ref warns" "$W" "mutable ref"

W=$(new_fixture)
mkdir -p "$W/.github/workflows"
cat > "$W/.github/workflows/ci.yml" <<'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      - uses: 'actions/cache@36f1e144e1c8edb0a652766b484448563d8baf46' # v4.2.0
      - uses: ./.github/actions/local-thing
EOF
assert_ok_without "10d: SHA-pinned actions (bare and single-quoted) and a local ref are clean" "$W" "mutable ref"

# --- check #8d: semantic hook-wiring validation ------------------------------
# Needs jq (tuple parse) and a sha tool (a hook-wired install is adopted, so the
# fixture ships a real manifest to keep #9 green). new_hookwired_fixture builds a
# complete, check-harness-clean install declaring all three hook-wired providers;
# each case mutates ONE thing and asserts the specific failure class.
if command -v jq >/dev/null 2>&1 && { command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; }; then
    hsha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
    # repin_hookwired <work> — manifest over every mechanism file on disk
    # (check-harness.sh, harness.conf, every scripts/hooks/*.sh), so #9's
    # completeness/checksum checks pass after files are added or edited.
    repin_hookwired() {
        local w="$1" f
        { printf '# harness-kit 9.9.9\n'
          for f in scripts/check-harness.sh scripts/harness.conf; do
              [ -f "$w/$f" ] && printf '%s  %s\n' "$(hsha "$w/$f")" "$f"
          done
          for f in "$w"/scripts/hooks/*.sh; do
              [ -f "$f" ] && printf '%s  scripts/hooks/%s\n' "$(hsha "$f")" "$(basename "$f")"
          done
        } > "$w/scripts/.harness-manifest"
    }
    new_hookwired_fixture() {
        local work s
        work=$(new_fixture)
        mkdir -p "$work/scripts/hooks" "$work/.claude" "$work/.cursor" "$work/.codex"
        printf 'SECRET_PATTERNS=".env"\nHOOK_WIRED_PROVIDERS=".claude .cursor .codex"\n' > "$work/scripts/harness.conf"
        for s in session-context guard-secrets guard-config format guard-project-policy; do
            printf '#!/usr/bin/env bash\nexit 0\n' > "$work/scripts/hooks/$s.sh"
            chmod +x "$work/scripts/hooks/$s.sh"
        done
        cat > "$work/.claude/settings.json" <<'JSON'
{ "permissions": { "deny": ["Read(**/.env)"] },
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/session-context.sh" } ] } ],
    "PreToolUse": [
      { "matcher": "Read|Grep", "hooks": [ { "type": "command", "command": "scripts/hooks/guard-secrets.sh" } ] },
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "scripts/hooks/guard-config.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "scripts/hooks/format.sh" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/guard-project-policy.sh" } ] } ] } }
JSON
        cat > "$work/.cursor/hooks.json" <<'JSON'
{ "version": 1, "hooks": {
    "sessionStart": [ { "command": "scripts/hooks/session-context.sh" } ],
    "afterFileEdit": [ { "command": "scripts/hooks/format.sh" } ],
    "beforeReadFile": [ { "command": "scripts/hooks/guard-secrets.sh" } ],
    "stop": [ { "command": "scripts/hooks/guard-project-policy.sh" } ] } }
JSON
        cat > "$work/.codex/hooks.json" <<'JSON'
{ "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/session-context.sh" } ] } ],
    "PreToolUse": [ { "hooks": [
      { "type": "command", "command": "scripts/hooks/guard-secrets.sh" },
      { "type": "command", "command": "scripts/hooks/guard-config.sh" } ] } ],
    "PostToolUse": [ { "matcher": "apply_patch", "hooks": [ { "type": "command", "command": "scripts/hooks/format.sh" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/guard-project-policy.sh" } ] } ] } }
JSON
        repin_hookwired "$work"
        printf '%s' "$work"
    }

    W=$(new_hookwired_fixture)
    assert_ok "8d: a complete hook-wired install passes" "$W"

    W=$(new_hookwired_fixture)
    jq 'del(.hooks)' "$W/.claude/settings.json" > "$W/.claude/s" && mv "$W/.claude/s" "$W/.claude/settings.json"
    assert_flags "8d: hooks object deleted (headline repro) is flagged" "$W" "guard session-context.sh is not wired in .claude/settings.json"

    W=$(new_hookwired_fixture); rm "$W/.cursor/hooks.json"
    assert_flags "8d: a declared provider's deleted config is flagged" "$W" "hook config .cursor/hooks.json is missing"

    W=$(new_hookwired_fixture)
    jq '.hooks.Stop[0].hooks += [{"type":"command","command":"scripts/hooks/guard-secrets.sh"}] | del(.hooks.PreToolUse[0])' "$W/.claude/settings.json" > "$W/.claude/s" && mv "$W/.claude/s" "$W/.claude/settings.json"
    assert_flags "8d: a guard on the wrong event is flagged" "$W" "guard-secrets.sh is wired on event 'Stop'"

    W=$(new_hookwired_fixture)
    jq '(.hooks.PreToolUse[] | select(.matcher=="Read|Grep") | .matcher) = "Read"' "$W/.claude/settings.json" > "$W/.claude/s" && mv "$W/.claude/s" "$W/.claude/settings.json"
    assert_flags "8d: a weakened matcher is flagged" "$W" "which does not cover the required 'Read|Grep'"

    # A WIDENED or reordered matcher fires on at least every required event, so it
    # is not a weakening and must pass (config matcher is tailored, not pinned).
    W=$(new_hookwired_fixture)
    jq '(.hooks.PreToolUse[] | select(.matcher=="Read|Grep") | .matcher) = "Grep|Read|Fetch"' "$W/.claude/settings.json" > "$W/.claude/s" && mv "$W/.claude/s" "$W/.claude/settings.json"
    assert_ok "8d: a widened/reordered matcher (superset of required) still passes" "$W"

    W=$(new_hookwired_fixture)
    jq '.hooks.Stop[0].hooks += [{"type":"command","command":"scripts/hooks/ghost.sh"}]' "$W/.codex/hooks.json" > "$W/.codex/s" && mv "$W/.codex/s" "$W/.codex/hooks.json"
    assert_flags "8d: a command pointing at a missing script is flagged" "$W" "points at 'scripts/hooks/ghost.sh'"

    W=$(new_hookwired_fixture)
    printf '#!/usr/bin/env bash\nexit 0\n' > "$W/scripts/hooks/project-extra.sh"; chmod +x "$W/scripts/hooks/project-extra.sh"
    jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"scripts/hooks/project-extra.sh"}]}]' "$W/.claude/settings.json" > "$W/.claude/s" && mv "$W/.claude/s" "$W/.claude/settings.json"
    repin_hookwired "$W"
    assert_ok "8d: a tailored-but-complete config (extra project guard) still passes" "$W"

    W=$(new_hookwired_fixture)
    grep -v '^HOOK_WIRED_PROVIDERS=' "$W/scripts/harness.conf" > "$W/scripts/hc" && mv "$W/scripts/hc" "$W/scripts/harness.conf"
    repin_hookwired "$W"
    assert_flags "8d: undeclared HOOK_WIRED_PROVIDERS on an adopted harness is flagged" "$W" "declares no HOOK_WIRED_PROVIDERS"
fi

# --- check #8e: declared stable execution-profile validation -----------------
# Profiles are optional: unset/empty is unadopted and must not inspect whatever
# provider files happen to survive. Once declared, exact semantic floors apply
# per provider while unrelated project config and legitimate subsets stay valid.
if command -v jq >/dev/null 2>&1; then
    write_execution_configs() {
        local work="$1"
        mkdir -p "$work/.claude" "$work/.cursor" "$work/.codex"
        cat > "$work/.claude/settings.json" <<'JSON'
{
  "unrelated": {"projectOwned": true},
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": true,
    "filesystem": {"allowWrite": []},
    "network": {
      "allowedDomains": [],
      "deniedDomains": ["blocked.example", "*"],
      "allowLocalBinding": false,
      "allowAllUnixSockets": false
    },
    "credentials": {
      "files": [
        {"mode": "deny", "path": "~/.ssh"},
        {"path": "~/.aws/credentials", "mode": "deny"}
      ],
      "envVars": [
        {"mode": "deny", "name": "NPM_TOKEN"},
        {"name": "GITHUB_TOKEN", "mode": "deny"}
      ]
    }
  }
}
JSON
        cat > "$work/.cursor/sandbox.json" <<'JSON'
{
  "unrelated": true,
  "networkPolicy": {"deny": [], "allow": [], "default": "deny"},
  "enableSharedBuildCache": false,
  "disableTmpWrite": false,
  "additionalReadonlyPaths": [],
  "additionalReadwritePaths": [],
  "type": "workspace_readwrite"
}
JSON
        cat > "$work/.codex/config.toml" <<'TOML'
# Required top-level keys may be reordered and use either TOML quote style.
allow_login_shell = false
approvals_reviewer = 'user'
approval_policy = "on-request"
sandbox_mode = 'workspace-write'

[unrelated]
project_owned = true

[sandbox_workspace_write]
exclude_slash_tmp = false # inline comments do not change the value
writable_roots = [ ]
network_access = false
exclude_tmpdir_env_var = false

[mcp_servers.demo]
command = "demo"
args = ["--safe"]

[shell_environment_policy]
ignore_default_excludes = false
inherit = 'core'
TOML
        cat > "$work/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": {"**/.env": "deny"},
    "websearch": "deny",
    "external_directory": "deny",
    "webfetch": "deny",
    "bash": "ask"
  },
  "mcp": {"demo": {"command": ["demo"]}},
  "unrelated": true
}
JSON
    }
    new_execution_fixture() {        # $1 optional declaration, __UNSET__ omits it
        local work declaration
        if [ "$#" -eq 0 ]; then declaration=".claude .cursor .codex .opencode"; else declaration="$1"; fi
        work=$(new_fixture)
        write_execution_configs "$work"
        if [ "$declaration" != "__UNSET__" ]; then
            printf 'EXECUTION_PROFILE_PROVIDERS="%s"\n' "$declaration" > "$work/scripts/harness.conf"
        fi
        printf '%s' "$work"
    }
    assert_execution_json_weakening() { # $1 description, $2 provider, $3 config, $4 jq edit, $5 diagnostic
        local desc="$1" provider="$2" cfg="$3" edit="$4" diagnostic="$5" work
        work=$(new_execution_fixture "$provider")
        jq "$edit" "$work/$cfg" > "$work/execution-profile.tmp" \
            && mv "$work/execution-profile.tmp" "$work/$cfg"
        assert_flags "$desc" "$work" "$diagnostic"
    }
    enable_codex_local_private_compat() { # $1 fixture; exact rules intentionally reordered/spaced
        local work="$1"
        sed 's/^network_access = false/network_access = true/' "$work/.codex/config.toml" > "$work/.codex/c" \
            && mv "$work/.codex/c" "$work/.codex/config.toml"
        cat >> "$work/.codex/config.toml" <<'TOML'

[features.network_proxy]
domains={ "127.0.0.1" = 'allow',   "localhost"="allow" }
dangerously_allow_all_unix_sockets = false
unix_sockets = { }
allow_local_binding=true
dangerously_allow_non_loopback_proxy = false
enabled = true
TOML
    }

    W=$(new_execution_fixture)
    assert_ok "8e: all four valid stable execution profiles pass with unrelated config/order" "$W"

    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    assert_ok "8e: explicit Codex broad local/private compatibility proxy passes independent of key/rule order and spacing" "$W"

    # A declared Codex profile fails closed when the complete-file TOML parser
    # is unavailable; the narrow tuple reader alone must never approve it.
    W=$(new_execution_fixture ".codex")
    pyshim=$(mktemp -d "$WORK/pyshim.XXXXXX") || return 1
    printf '#!/bin/sh\nexit 1\n' > "$pyshim/python3"
    chmod +x "$pyshim/python3"
    out=$(PATH="$pyshim:$PATH" bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
    if [ "$rc" = "1" ] && printf '%s' "$out" | grep -qF "Python 3.11+ with tomllib"; then
        echo "ok:   8e: declared Codex profile without a TOML parser is unverifiable"
    else
        echo "FAIL: 8e: declared Codex profile without a TOML parser should fail as unverifiable"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
    rm -rf "$W" "$pyshim"

    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^domains=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    cat >> "$W/.codex/config.toml" <<'TOML'

[features.network_proxy.domains]
"127.0.0.1" = "allow"
localhost = 'allow'
TOML
    assert_ok "8e: exact Codex local/private compatibility domains pass in equivalent child-table form" "$W"

    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^unix_sockets[[:space:]]*=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    printf '\n[features.network_proxy.unix_sockets]\n' >> "$W/.codex/config.toml"
    assert_ok "8e: empty Codex compatibility Unix sockets pass in equivalent child-table form" "$W"

    W=$(new_execution_fixture ".claude .codex")
    rm -f "$W/.cursor/sandbox.json" "$W/opencode.json"
    assert_ok "8e: a legitimate declared provider subset passes" "$W"

    W=$(new_execution_fixture ".cursor")
    jq '.networkPolicy.deny = ["telemetry.example", "*.tracking.example"]' "$W/.cursor/sandbox.json" > "$W/.cursor/s" && mv "$W/.cursor/s" "$W/.cursor/sandbox.json"
    assert_ok "8e: stricter Cursor project-specific deny entries pass" "$W"

    # Unset/empty means unadopted. Malformed surviving files prove the check does
    # not infer adoption from presence and does not silently create a declaration.
    W=$(new_execution_fixture "__UNSET__"); printf '{' > "$W/.claude/settings.json"
    assert_ok "8e: unset declaration is unadopted and does not infer from surviving configs" "$W"
    W=$(new_execution_fixture ""); printf '{' > "$W/.cursor/sandbox.json"
    assert_ok "8e: empty declaration is unadopted and passes" "$W"

    W=$(new_execution_fixture ".claude .future")
    assert_flags "8e: an unknown provider id is rejected" "$W" "unknown provider '.future'"
    W=$(new_execution_fixture ".codex .codex")
    assert_flags "8e: a duplicate provider id is rejected" "$W" "duplicate provider '.codex'"

    # Claude: missing/malformed plus each privilege-expansion class. Every
    # negative pins the required-key diagnostic so an incidental failure cannot
    # make the test pass.
    W=$(new_execution_fixture ".claude"); rm "$W/.claude/settings.json"
    assert_flags "8e: declared Claude config missing is rejected" "$W" ".claude/settings.json is missing"
    W=$(new_execution_fixture ".claude"); printf '{' > "$W/.claude/settings.json"
    assert_flags "8e: declared Claude malformed JSON is rejected" "$W" ".claude' config .claude/settings.json is malformed JSON"
    assert_execution_json_weakening "8e: disabled Claude sandbox is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.enabled = false' "sandbox.enabled = true"
    assert_execution_json_weakening "8e: Claude sandbox-unavailable fallback is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.failIfUnavailable = false' "sandbox.failIfUnavailable = true"
    assert_execution_json_weakening "8e: disabled Claude user-approved unsandboxed retry is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.allowUnsandboxedCommands = false' "sandbox.allowUnsandboxedCommands = true"
    assert_execution_json_weakening "8e: Claude excluded-command sandbox bypass is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.excludedCommands = ["company-runner"]' "sandbox.excludedCommands is absent or []"
    assert_execution_json_weakening "8e: null Claude excluded-command policy is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.excludedCommands = null' "sandbox.excludedCommands is absent or []"
    assert_execution_json_weakening "8e: extra Claude write roots are rejected" ".claude" ".claude/settings.json" \
        '.sandbox.filesystem.allowWrite = ["/tmp/project-cache"]' "sandbox.filesystem.allowWrite = []"
    assert_execution_json_weakening "8e: public Claude network allow-list is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.allowedDomains = ["registry.example"]' "sandbox.network.allowedDomains = []"
    assert_execution_json_weakening "8e: Claude network deny-list without wildcard is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.deniedDomains = ["blocked.example"]' "sandbox.network.deniedDomains contains *"
    assert_execution_json_weakening "8e: Claude local network binding is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.allowLocalBinding = true' "sandbox.network.allowLocalBinding = false"
    assert_execution_json_weakening "8e: Claude unrestricted Unix sockets are rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.allowAllUnixSockets = true' "sandbox.network.allowAllUnixSockets = false"
    assert_execution_json_weakening "8e: Claude Docker Unix-socket allow-list is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.allowUnixSockets = ["/var/run/docker.sock"]' "sandbox.network.allowUnixSockets is absent or []"
    assert_execution_json_weakening "8e: Claude Mach service lookup allow-list is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.network.allowMachLookup = ["com.example.helper"]' "sandbox.network.allowMachLookup is absent or []"
    assert_execution_json_weakening "8e: Claude weaker network isolation is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.enableWeakerNetworkIsolation = true' "sandbox.enableWeakerNetworkIsolation is absent or false"
    assert_execution_json_weakening "8e: Claude weaker nested sandbox is rejected" ".claude" ".claude/settings.json" \
        '.sandbox.enableWeakerNestedSandbox = true' "sandbox.enableWeakerNestedSandbox is absent or false"
    assert_execution_json_weakening "8e: missing Claude AWS credential deny is rejected" ".claude" ".claude/settings.json" \
        'del(.sandbox.credentials.files[] | select(.path == "~/.aws/credentials"))' "sandbox.credentials.files denies ~/.aws/credentials"
    assert_execution_json_weakening "8e: missing Claude credential-file deny is rejected" ".claude" ".claude/settings.json" \
        'del(.sandbox.credentials.files[] | select(.path == "~/.ssh"))' "sandbox.credentials.files denies ~/.ssh"
    assert_execution_json_weakening "8e: missing Claude credential-env deny is rejected" ".claude" ".claude/settings.json" \
        'del(.sandbox.credentials.envVars[] | select(.name == "GITHUB_TOKEN"))' "sandbox.credentials.envVars denies GITHUB_TOKEN"
    assert_execution_json_weakening "8e: missing Claude npm credential deny is rejected" ".claude" ".claude/settings.json" \
        'del(.sandbox.credentials.envVars[] | select(.name == "NPM_TOKEN"))' "sandbox.credentials.envVars denies NPM_TOKEN"

    # Cursor: missing/malformed plus filesystem and network expansion classes.
    W=$(new_execution_fixture ".cursor"); rm "$W/.cursor/sandbox.json"
    assert_flags "8e: declared Cursor config missing is rejected" "$W" ".cursor/sandbox.json is missing"
    W=$(new_execution_fixture ".cursor"); printf '{' > "$W/.cursor/sandbox.json"
    assert_flags "8e: declared Cursor malformed JSON is rejected" "$W" ".cursor' config .cursor/sandbox.json is malformed JSON"
    assert_execution_json_weakening "8e: full-access Cursor sandbox type is rejected" ".cursor" ".cursor/sandbox.json" \
        '.type = "danger-full-access"' "type = workspace_readwrite"
    assert_execution_json_weakening "8e: extra Cursor write roots are rejected" ".cursor" ".cursor/sandbox.json" \
        '.additionalReadwritePaths = ["../shared"]' "additionalReadwritePaths = []"
    assert_execution_json_weakening "8e: extra Cursor read roots are rejected" ".cursor" ".cursor/sandbox.json" \
        '.additionalReadonlyPaths = ["~/.config"]' "additionalReadonlyPaths = []"
    assert_execution_json_weakening "8e: Cursor temporary-directory write removal is rejected" ".cursor" ".cursor/sandbox.json" \
        '.disableTmpWrite = true' "disableTmpWrite = false"
    assert_execution_json_weakening "8e: Cursor shared build cache is rejected" ".cursor" ".cursor/sandbox.json" \
        '.enableSharedBuildCache = true' "enableSharedBuildCache = false"
    assert_execution_json_weakening "8e: permissive Cursor network default is rejected" ".cursor" ".cursor/sandbox.json" \
        '.networkPolicy.default = "allow"' "networkPolicy.default = deny"
    assert_execution_json_weakening "8e: nonempty Cursor network allow-list is rejected" ".cursor" ".cursor/sandbox.json" \
        '.networkPolicy.allow = ["registry.example"]' "networkPolicy.allow = []"
    assert_execution_json_weakening "8e: malformed Cursor network deny-list is rejected" ".cursor" ".cursor/sandbox.json" \
        '.networkPolicy.deny = "*"' "networkPolicy.deny is an array"

    # Codex: semantic TOML checks cover malformed/duplicate required values and
    # every high-impact execution, write, network, login, and env-filter floor.
    W=$(new_execution_fixture ".codex"); rm "$W/.codex/config.toml"
    assert_flags "8e: declared Codex config missing is rejected" "$W" ".codex/config.toml is missing"
    W=$(new_execution_fixture ".codex")
    sed 's/^sandbox_mode = .*/sandbox_mode = [/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: malformed required Codex TOML value is rejected" "$W" "malformed TOML"
    W=$(new_execution_fixture ".codex")
    printf '\nthis is not valid TOML\n' >> "$W/.codex/config.toml"
    assert_flags "8e: unrelated invalid Codex TOML syntax is rejected" "$W" "malformed TOML"
    W=$(new_execution_fixture ".codex")
    printf '\n[sandbox_workspace_write]\n' >> "$W/.codex/config.toml"
    assert_flags "8e: duplicate Codex TOML table is rejected" "$W" "malformed TOML"
    W=$(new_execution_fixture ".codex")
    sed 's/^approval_policy = .*/approval_policy = "never"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: weakened Codex approval policy is rejected" "$W" "approval_policy = on-request"
    W=$(new_execution_fixture ".codex")
    sed 's/^approvals_reviewer = .*/approvals_reviewer = "agent"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: non-user Codex approval reviewer is rejected" "$W" "approvals_reviewer = user"
    W=$(new_execution_fixture ".codex")
    awk '{ print } /^sandbox_mode[[:space:]]*=/{ print "sandbox_mode = \"workspace-write\"" }' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: duplicate required Codex TOML key is rejected" "$W" "malformed TOML"
    W=$(new_execution_fixture ".codex")
    sed 's/^sandbox_mode = .*/sandbox_mode = "danger-full-access"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: danger-full Codex sandbox is rejected" "$W" "sandbox_mode = workspace-write"
    W=$(new_execution_fixture ".codex")
    sed 's/^network_access = .*/network_access = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: Codex network access without the local/private compatibility proxy is rejected" "$W" "features.network_proxy.enabled = true"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/^enabled = true/enabled = false/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: disabled Codex local/private compatibility proxy is rejected" "$W" "features.network_proxy.enabled = true"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^domains=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: missing Codex local/private compatibility domains are rejected" "$W" "features.network_proxy.domains = exactly localhost/127.0.0.1 allow"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/"localhost"="allow"/"localhost"="allow", "public.example"="allow"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: public Codex compatibility proxy domain is rejected" "$W" "features.network_proxy.domains = exactly localhost/127.0.0.1 allow"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/"localhost"="allow"/"localhost"="allow", "*"="allow"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: wildcard Codex compatibility proxy domain is rejected" "$W" "features.network_proxy.domains = exactly localhost/127.0.0.1 allow"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^domains=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    cat >> "$W/.codex/config.toml" <<'TOML'

[features.network_proxy.domains]
localhost = "allow"
"127.0.0.1" = "allow"

[features.network_proxy.domains.public]
extra = "allow"
TOML
    assert_flags "8e: nested Codex public domain table is rejected" "$W" "features.network_proxy.domains = exactly localhost/127.0.0.1 allow"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^domains=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    cat >> "$W/.codex/config.toml" <<'TOML'

[features.network_proxy.domains]
localhost = "allow"
127.0.0.1 = "allow"
TOML
    assert_flags "8e: bare dotted Codex IP is not accepted as a literal compatibility domain" "$W" "features.network_proxy.domains = exactly localhost/127.0.0.1 allow"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/^allow_local_binding=true/allow_local_binding = false/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: nonfunctional narrow Codex binding is rejected for the compatibility variant" "$W" "features.network_proxy.allow_local_binding = true"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/^dangerously_allow_non_loopback_proxy = false/dangerously_allow_non_loopback_proxy = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: dangerous Codex non-loopback proxy is rejected" "$W" "features.network_proxy.dangerously_allow_non_loopback_proxy"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's/^dangerously_allow_all_unix_sockets = false/dangerously_allow_all_unix_sockets = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: dangerous Codex Unix-socket bypass is rejected" "$W" "features.network_proxy.dangerously_allow_all_unix_sockets"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^dangerously_allow_non_loopback_proxy = false/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    printf '\n[features.network_proxy.dangerously_allow_non_loopback_proxy]\n' >> "$W/.codex/config.toml"
    assert_flags "8e: dangerous Codex binding bypass with table type is rejected" "$W" "features.network_proxy.dangerously_allow_non_loopback_proxy"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^dangerously_allow_all_unix_sockets = false/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    printf '\n[features.network_proxy.dangerously_allow_all_unix_sockets]\n' >> "$W/.codex/config.toml"
    assert_flags "8e: dangerous Codex socket bypass with table type is rejected" "$W" "features.network_proxy.dangerously_allow_all_unix_sockets"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed 's|^unix_sockets = { }|unix_sockets = { "/var/run/docker.sock" = "allow" }|' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: Codex compatibility Unix-socket allow rule is rejected" "$W" "features.network_proxy.unix_sockets = absent or empty"
    W=$(new_execution_fixture ".codex"); enable_codex_local_private_compat "$W"
    sed '/^unix_sockets[[:space:]]*=/d' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    cat >> "$W/.codex/config.toml" <<'TOML'

[features.network_proxy.unix_sockets.extra]
socket = "allow"
TOML
    assert_flags "8e: nested Codex Unix-socket table is rejected" "$W" "features.network_proxy.unix_sockets = absent or empty"
    W=$(new_execution_fixture ".codex")
    sed 's/^writable_roots = .*/writable_roots = ["..\/shared"]/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: extra Codex writable roots are rejected" "$W" "sandbox_workspace_write.writable_roots = []"
    W=$(new_execution_fixture ".codex")
    sed 's/^exclude_tmpdir_env_var = .*/exclude_tmpdir_env_var = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: Codex tmpdir-env exclusion drift is rejected" "$W" "sandbox_workspace_write.exclude_tmpdir_env_var = false"
    W=$(new_execution_fixture ".codex")
    sed 's/^exclude_slash_tmp = .*/exclude_slash_tmp = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: Codex /tmp exclusion drift is rejected" "$W" "sandbox_workspace_write.exclude_slash_tmp = false"
    W=$(new_execution_fixture ".codex")
    sed 's/^allow_login_shell = .*/allow_login_shell = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: Codex login-shell inheritance is rejected" "$W" "allow_login_shell = false"
    W=$(new_execution_fixture ".codex")
    sed 's/^inherit = .*/inherit = "all"/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: broad Codex environment inheritance is rejected" "$W" "shell_environment_policy.inherit = core"
    W=$(new_execution_fixture ".codex")
    sed 's/^ignore_default_excludes = .*/ignore_default_excludes = true/' "$W/.codex/config.toml" > "$W/.codex/c" && mv "$W/.codex/c" "$W/.codex/config.toml"
    assert_flags "8e: disabled Codex environment filters are rejected" "$W" "shell_environment_policy.ignore_default_excludes = false"

    # OpenCode: missing/malformed and each external/shell/web permission class.
    # Existing secret-read and MCP maps stay accepted as unrelated content.
    W=$(new_execution_fixture ".opencode"); rm "$W/opencode.json"
    assert_flags "8e: declared OpenCode config missing is rejected" "$W" "opencode.json is missing"
    W=$(new_execution_fixture ".opencode"); printf '{' > "$W/opencode.json"
    assert_flags "8e: declared OpenCode malformed JSON is rejected" "$W" ".opencode' config opencode.json is malformed JSON"
    assert_execution_json_weakening "8e: OpenCode external-directory access is rejected" ".opencode" "opencode.json" \
        '.permission.external_directory = "allow"' "permission.external_directory = deny"
    assert_execution_json_weakening "8e: permissive OpenCode shell access is rejected" ".opencode" "opencode.json" \
        '.permission.bash = "allow"' "permission.bash = ask"
    assert_execution_json_weakening "8e: permissive OpenCode webfetch is rejected" ".opencode" "opencode.json" \
        '.permission.webfetch = "allow"' "permission.webfetch = deny"
    assert_execution_json_weakening "8e: permissive OpenCode websearch is rejected" ".opencode" "opencode.json" \
        '.permission.websearch = "allow"' "permission.websearch = deny"
fi

# --- agent-stub coherence (sync-agent-skills.sh --check, via check #3) --------
# check #3 delegates to sync-agent-skills.sh --check, which now validates agent
# stubs too (bidirectional set equality). Needs the generator present — new_fixture
# copies only check-harness.sh — plus a canonical persona and its generated stubs.
if [ -f "$SCRIPTS_DIR/sync-agent-skills.sh" ]; then
    new_agents_fixture() {           # $1 optional AGENT_PROVIDERS value
        local work provs="${1:-.claude .cursor .codex .opencode}"
        work=$(new_fixture)
        cp "$SCRIPTS_DIR/sync-agent-skills.sh" "$work/scripts/"; chmod +x "$work/scripts/sync-agent-skills.sh"
        printf 'AGENT_PROVIDERS="%s"\n' "$provs" > "$work/scripts/harness.conf"
        mkdir -p "$work/docs/agents"
        cat > "$work/docs/agents/code-reviewer.md" <<'MD'
---
name: code-reviewer
description: Inferential reviewer for a completed diff AFTER verify.sh passes. Delegate before opening a PR.
tools: Read, Grep, Glob, Bash
---

# Code Reviewer Agent

Body.
MD
        ( cd "${work:?}" && bash scripts/sync-agent-skills.sh >/dev/null 2>&1 )
        printf '%s' "$work"
    }

    W=$(new_agents_fixture)
    assert_ok "agent-stubs: canonical persona + generated stubs pass check-harness" "$W"

    W=$(new_agents_fixture)
    if grep -Fxq 'name = "code-reviewer"' "$W/.codex/agents/code-reviewer.toml" \
        && grep -Fxq 'description = "Inferential reviewer for a completed diff AFTER verify.sh passes. Delegate before opening a PR."' "$W/.codex/agents/code-reviewer.toml" \
        && grep -Fxq 'developer_instructions = """' "$W/.codex/agents/code-reviewer.toml" \
        && grep -Fq 'Canonical source: docs/agents/code-reviewer.md' "$W/.codex/agents/code-reviewer.toml" \
        && ! grep -Eq '^[[:space:]]*tools[[:space:]]*=' "$W/.codex/agents/code-reviewer.toml" \
        && grep -Fxq 'tools: Read, Grep, Glob, Bash' "$W/.claude/agents/code-reviewer.md" \
        && grep -Fxq 'tools: Read, Grep, Glob, Bash' "$W/.cursor/agents/code-reviewer.md" \
        && grep -Fxq 'tools: Read, Grep, Glob, Bash' "$W/.opencode/agents/code-reviewer.md"; then
        echo "ok:   agent-stubs: Codex schema omits tools while retaining identity/instructions; Markdown providers keep tools"
    else
        echo "FAIL: agent-stubs: provider-specific Codex/Markdown tool mappings were not generated as expected"
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    W=$(new_agents_fixture)
    sed 's/^description: .*/description: A completely different routing signal./' "$W/docs/agents/code-reviewer.md" > "$W/docs/agents/c" && mv "$W/docs/agents/c" "$W/docs/agents/code-reviewer.md"
    assert_flags "agent-stubs: a canonical-description change fails the TOML stub (every provider)" "$W" ".codex/agents/code-reviewer.toml does not match the generator output"

    W=$(new_agents_fixture)
    sed 's/AFTER/BEFORE/' "$W/.claude/agents/code-reviewer.md" > "$W/.claude/c" && mv "$W/.claude/c" "$W/.claude/agents/code-reviewer.md"
    assert_flags "agent-stubs: a stale stub description is flagged" "$W" ".claude/agents/code-reviewer.md does not match the generator output"

    W=$(new_agents_fixture); rm "$W/.opencode/agents/code-reviewer.md"
    assert_flags "agent-stubs: a missing stub is flagged" "$W" ".opencode/agents/code-reviewer.md is missing"

    W=$(new_agents_fixture); printf -- '---\nname: ghost\n---\n' > "$W/.claude/agents/ghost.md"
    assert_flags "agent-stubs: an orphan stub is flagged" "$W" "ORPHAN: .claude/agents/ghost.md"

    W=$(new_agents_fixture ".claude .cursor")
    assert_ok "agent-stubs: a legitimate subset declaration passes" "$W"

    W=$(new_agents_fixture); rm -rf "$W/.codex/agents"
    assert_flags "agent-stubs: deleting a declared provider's entire agents dir fails" "$W" ".codex/agents/code-reviewer.toml is missing"

    # Provider-specific frontmatter: OpenCode marks a subagent with mode:subagent
    # (provider matrix); the other Markdown providers must NOT carry it.
    W=$(new_agents_fixture)
    if grep -qx 'mode: subagent' "$W/.opencode/agents/code-reviewer.md" \
        && ! grep -q 'mode:' "$W/.claude/agents/code-reviewer.md"; then
        echo "ok:   agent-stubs: OpenCode stub carries 'mode: subagent'; Claude stub does not"
    else
        echo "FAIL: agent-stubs: OpenCode 'mode: subagent' frontmatter not emitted as expected"
        fails=$((fails + 1))
    fi
    rm -rf "$W"

    if grep -q 'CANONICAL_AGENTS' "$SCRIPTS_DIR/sync-agent-skills.sh"; then
        echo "ok:   agent-stubs: CANONICAL_AGENTS is consumed by mechanism code (sync-agent-skills.sh)"
    else
        echo "FAIL: agent-stubs: CANONICAL_AGENTS is not consumed by any mechanism code"
        fails=$((fails + 1))
    fi
fi

# --- check #5b: unsafe scratch-path creation in the scripts check #6 RUNS ------
# The defect this pins put junk commits on this repo's own main branch, twice:
# bare `mktemp -d` fails wherever only $TMPDIR is writable (it resolves
# /var/folders on macOS), the unguarded assignment leaves the path EMPTY, and
# `cd ""` is a silent rc=0 no-op — so the fixture's `git commit` runs in the HOST
# repo. shellcheck cannot see it (the variables are correctly quoted), so #5b is
# the only static layer that can.
#
# Every fixture test script below must exit 0: check #6 RUNS them.
#
# #5b scans THIS file too, and these fixtures deliberately contain the pattern it
# bans — so the literal is assembled via $MK rather than written out, keeping it
# out of command position here. The '# harness-mktemp-ok' marker would be the
# WRONG tool: this file allocates no scratch of its own, and a marker is
# line-scoped and unconditional, so it would also mask a genuinely bad mktemp
# added to that line later. Reserve the marker for real, verified allocations.
MK=mktemp

# A bare `mktemp -d` is an ERROR.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(%s -d)\nexit 0\n' "$MK" > "$W/scripts/test-leaky.sh"
chmod +x "$W/scripts/test-leaky.sh"
assert_flags "check #5b: bare 'mktemp -d' is flagged" "$W" "creates a scratch path unsafely"

# Templated but UNGUARDED is still an ERROR — the failure would just be silent.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(%s -d "${TMPDIR:-/tmp}/x.XXXXXX")\nexit 0\n' "$MK" > "$W/scripts/test-unguarded.sh"
chmod +x "$W/scripts/test-unguarded.sh"
assert_flags "check #5b: templated but unguarded is flagged" "$W" "no failure guard"

# Guarded but UNTEMPLATED is an ERROR — it simply fails wherever only $TMPDIR is
# writable, which is where agents run.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(%s -d) || exit 1\nexit 0\n' "$MK" > "$W/scripts/test-untemplated.sh"
chmod +x "$W/scripts/test-untemplated.sh"
assert_flags "check #5b: guarded but untemplated is flagged" "$W" "no explicit XXXXXX template"

# The canonical form passes.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(mktemp -d "${TMPDIR:-/tmp}/ok.XXXXXX") || exit 1\nexit 0\n' > "$W/scripts/test-safe.sh"
chmod +x "$W/scripts/test-safe.sh"
assert_ok "check #5b: the canonical guarded+templated form passes" "$W"

# The `if ! VAR=$(mktemp ...) || [ -z "$VAR" ]; then die` form passes, and so does
# templating into a directory OTHER than $TMPDIR on purpose (eval-harness.sh writes
# its baseline temp beside the target so the `mv` is a same-filesystem rename).
# What is pinned is an explicit XXXXXX template, NOT a literal $TMPDIR.
W=$(new_fixture)
cat > "$W/scripts/test-ifform.sh" <<'EOF'
#!/usr/bin/env bash
if ! T="$(mktemp "$(dirname "$0")/.b.XXXXXX")" || [ -z "$T" ]; then
    echo "mktemp failed"; exit 1
fi
rm -f "$T"; exit 0
EOF
chmod +x "$W/scripts/test-ifform.sh"
assert_ok "check #5b: the 'if !' guard form and a non-\$TMPDIR template pass" "$W"

# No false positive on a NON-INVOCATION: mktemp named in a word list or a message
# is not mktemp being run. Both shapes are live in this repo (the PATH-shim
# utility lists, and `die "mktemp failed ..."`).
W=$(new_fixture)
cat > "$W/scripts/test-mentions.sh" <<'EOF'
#!/usr/bin/env bash
for u in bash sha256sum mktemp rm sleep; do :; done
die() { echo "$1"; }
# mktemp -d
[ 1 = 2 ] && die "mktemp failed — cannot create a workspace"
exit 0
EOF
chmod +x "$W/scripts/test-mentions.sh"
assert_ok "check #5b: mktemp named in a word list, a message, or a comment is not flagged" "$W"

# The declared exception, same stance as the manifest's '# tailored': one comment,
# so an ERROR-severity gate can never wedge an adopter with a verified exception.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(%s -d)  # harness-mktemp-ok\nexit 0\n' "$MK" > "$W/scripts/test-declared.sh"
chmod +x "$W/scripts/test-declared.sh"
assert_ok "check #5b: a '# harness-mktemp-ok' declared exception is honored" "$W"

# Scope: #5b polices what check #6 RUNS, not an adopter's other scripts.
W=$(new_fixture)
printf '#!/usr/bin/env bash\nWORK=$(%s -d)\n' "$MK" > "$W/scripts/deploy.sh"
chmod +x "$W/scripts/deploy.sh"
assert_ok "check #5b: a non-test script the harness never runs is out of scope" "$W"


if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails check-harness case(s)"
    exit 1
fi
echo "PASSED: all check-harness cases"
