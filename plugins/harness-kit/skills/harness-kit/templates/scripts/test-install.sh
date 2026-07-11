#!/usr/bin/env bash
# Deterministic fixture tests of the kit's install/update mechanics
# (scripts/install-lib.sh). Each case spins up a throwaway git repo in a scratch
# dir, drives the library — no model in the loop — and asserts concrete
# post-state, then tears the fixture down. Runnable standalone and in CI (it is
# a scripts/test-*.sh, so check-harness.sh check #6 and verify.sh's template-tests
# gate both pick it up by name).
#
# The MODEL-GRADED half of init/update — does the authored AGENTS.md read well,
# is a hand-written settings.json merged sensibly — is out of scope here by
# design; that is a behavioral-evals golden task. This suite pins only the
# deterministic floor.
set -uo pipefail

# Recursion guard. Cases (a)/drift install the full mechanism into a fixture and
# run the fixture's check-harness.sh, whose check #6 runs every scripts/test-*.sh
# — including a nested copy of THIS script, which would install-and-check
# forever. Exporting HARNESS_NESTED_FIXTURE tells that nested check #6 to skip
# ONLY test-install.sh (every other regression test still runs inside the
# fixture); seeing it already set on entry means we ARE such a nested run, so
# exit cleanly.
if [ -n "${HARNESS_NESTED_FIXTURE:-}" ]; then
    echo "ok:   test-install.sh skipped (HARNESS_NESTED_FIXTURE set — nested run)"
    exit 0
fi
export HARNESS_NESTED_FIXTURE=1

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-lib.sh"
KIT_VERSION="0.0.0-fixture"

fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; fails=$((fails + 1)); }

git_c() { git -c user.email=t@example.com -c user.name=t "$@"; }

# sha_of <root> <relpath> — the file's sha256, nothing else.
sha_of() { ( cd "$1" && _harness_sha256 "$2" | awk '{print $1}' ); }

# make_fixture — prints a fresh installed + committed fixture root: a throwaway
# git repo with one source file, the mechanism installed from this script's own
# scripts/ dir, a generated manifest, and .harness/ git-ignored.
make_fixture() {
    local w
    w=$(mktemp -d)
    ( cd "$w" && git init -q && mkdir -p src && printf 'echo hi\n' > src/app.sh )
    harness_install_mechanism "$SCRIPTS_DIR" "$w"
    harness_append_gitignore "$w"
    harness_generate_manifest "$w" "$KIT_VERSION" > "$w/scripts/.harness-manifest"
    ( cd "$w" && git_c add -A && git_c commit -qm init >/dev/null )
    printf '%s' "$w"
}

# write_mirrored_claude_settings <root> — a .claude/settings.json whose deny list
# mirrors the fixture's SECRET_PATTERNS, so check-harness.sh check #8 runs green.
write_mirrored_claude_settings() {
    local root="$1" pat sp deny=""
    sp=$(. "$root/scripts/harness.conf" && printf '%s' "$SECRET_PATTERNS")
    set -f
    for pat in $sp; do deny="$deny \"Read($pat)\","; done
    set +f
    deny=${deny%,}
    mkdir -p "$root/.claude"
    printf '{ "permissions": { "deny": [%s ] } }\n' "$deny" > "$root/.claude/settings.json"
}

# --- (a) clean init -----------------------------------------------------------
F=$(make_fixture)
write_mirrored_claude_settings "$F"
( cd "$F" && git_c add -A && git_c commit -qm claude >/dev/null )
missing=""
# harness.conf is a sourced config (not executable, like every non-.sh file);
# the .sh mechanism files must carry the exec bit (check-harness.sh check #5).
for f in check-harness.sh harness.conf install-lib.sh sync-agent-skills.sh \
         test-check-harness.sh test-install.sh verify.sh; do
    [ -f "$F/scripts/$f" ] || missing="$missing $f(absent)"
done
for f in check-harness.sh install-lib.sh sync-agent-skills.sh \
         test-check-harness.sh test-install.sh verify.sh; do
    [ -x "$F/scripts/$f" ] || missing="$missing $f(not-exec)"
done
[ -f "$F/scripts/hooks/lib.sh" ] || missing="$missing hooks/lib.sh(absent)"
if [ -z "$missing" ]; then
    pass "clean init: mechanism installed and executable"
else
    fail "clean init: mechanism incomplete —$missing"
fi
grep -qxF '.harness/' "$F/.gitignore" \
    && pass "clean init: .harness/ is git-ignored" \
    || fail "clean init: .gitignore missing .harness/"
if grep -q "scripts/install-lib.sh" "$F/scripts/.harness-manifest" \
    && grep -q "scripts/test-install.sh" "$F/scripts/.harness-manifest" \
    && grep -q "scripts/harness.conf" "$F/scripts/.harness-manifest"; then
    pass "clean init: manifest enumerates install-lib.sh, test-install.sh, harness.conf"
else
    fail "clean init: manifest omits one of the new mechanism files"
fi
out=$(bash "$F/scripts/check-harness.sh" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "clean init: check-harness.sh passes in the fixture (deny list mirrors SECRET_PATTERNS)"
else
    fail "clean init: check-harness.sh failed in the fixture" "$out"
fi
rm -rf "$F"

# --- (b) non-clobber floor ----------------------------------------------------
# A partial-harness repo's hand-written files must survive install byte-for-byte.
F=$(mktemp -d)
( cd "$F" && git init -q && mkdir -p src && printf 'echo hi\n' > src/app.sh )
mkdir -p "$F/.claude"
printf '{ "hand": "written", "permissions": { "deny": [] } }\n' > "$F/.claude/settings.json"
printf '# My Project\n\nHand-authored AGENTS.md.\n' > "$F/AGENTS.md"
s_before=$(sha_of "$F" ".claude/settings.json")
a_before=$(sha_of "$F" "AGENTS.md")
harness_install_mechanism "$SCRIPTS_DIR" "$F"
harness_append_gitignore "$F"
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/.harness-manifest"
s_after=$(sha_of "$F" ".claude/settings.json")
a_after=$(sha_of "$F" "AGENTS.md")
if [ "$s_before" = "$s_after" ] && [ "$a_before" = "$a_after" ]; then
    pass "non-clobber floor: hand-written settings.json and AGENTS.md untouched by install"
else
    fail "non-clobber floor: install modified a hand-written file"
fi
rm -rf "$F"

# --- (c) no-op update ---------------------------------------------------------
# Update at the same version, from the same source, changes nothing.
F=$(make_fixture)
harness_update_apply "$SCRIPTS_DIR" "$F" >/dev/null
harness_repin_manifest "$F" "$KIT_VERSION" > "$F/scripts/.hm" \
    && mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
dirty=$( cd "$F" && git status --porcelain )
if [ -z "$dirty" ]; then
    pass "no-op update: idempotent (clean git status)"
else
    fail "no-op update: left changes in the working tree" "$dirty"
fi
rm -rf "$F"

# --- (d) mechanism upgrade ----------------------------------------------------
# An untailored file still matching its pin is replaced with the newer kit
# version and the manifest re-pinned to the new checksum.
F=$(make_fixture)
NEWKIT=$(mktemp -d); cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/sync-agent-skills.sh"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
harness_repin_manifest "$F" "9.9.9" > "$F/scripts/.hm" \
    && mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
newpin=$(grep "scripts/sync-agent-skills.sh" "$F/scripts/.harness-manifest" | awk '{print $1}')
actual=$(sha_of "$F" "scripts/sync-agent-skills.sh")
if grep -q "UPGRADED" "$F/scripts/sync-agent-skills.sh" && [ "$newpin" = "$actual" ]; then
    pass "mechanism upgrade: untailored file replaced and manifest re-pinned"
else
    fail "mechanism upgrade: file not replaced or manifest not re-pinned"
fi
rm -rf "$F" "$NEWKIT"

# --- (e) tailored-file preservation -------------------------------------------
# A '# tailored' file whose content differs from the template is NOT replaced by
# update; it is left for the user to diff, and its own checksum pin is honored.
F=$(make_fixture)
printf '\n# LOCAL FORK\n' >> "$F/scripts/verify.sh"
newsha=$(sha_of "$F" "scripts/verify.sh")
grep -v "scripts/verify.sh" "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/verify.sh # tailored\n' "$newsha" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
NEWKIT=$(mktemp -d); cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"   # pristine verify.sh differs
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
kept=$(sha_of "$F" "scripts/verify.sh")
if grep -q "LOCAL FORK" "$F/scripts/verify.sh" && [ "$kept" = "$newsha" ]; then
    pass "tailored preservation: '# tailored' file left untouched by update, pin honored"
else
    fail "tailored preservation: a tailored file was replaced or its pin drifted"
fi
rm -rf "$F" "$NEWKIT"

# --- drift detection ----------------------------------------------------------
# check-harness.sh is the scripted, model-free core of `audit`. Seed a drift it
# must catch — a native deny list missing a SECRET_PATTERNS entry — and assert it
# exits non-zero naming the real problem.
F=$(make_fixture)
mkdir -p "$F/.claude"
printf '{ "permissions": { "deny": ["Read(.env)"] } }\n' > "$F/.claude/settings.json"
out=$(bash "$F/scripts/check-harness.sh" 2>&1); rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q "auth.json"; then
    pass "drift detection: check-harness flags a deny list missing a secret pattern"
else
    fail "drift detection: seeded deny-list drift was not flagged (rc=$rc)" "$out"
fi
rm -rf "$F"

# --- completeness: partial pin deletion of a still-present guard is caught ------
# Removing only one guard's manifest line (leaving other pins, so the emptied-
# manifest guard doesn't fire) must still ERROR — every mechanism file on disk
# must be pinned, or an attacker could un-pin then rewrite a single guard.
F=$(make_fixture)
grep -v 'scripts/hooks/guard-secrets.sh' "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
out=$(bash "$F/scripts/check-harness.sh" 2>&1); rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF "guard-secrets.sh' is present but not pinned"; then
    pass "completeness: a present-but-unpinned mechanism file is flagged"
else
    fail "completeness: partial pin deletion was not caught (rc=$rc)" "$out"
fi
rm -rf "$F"

# --- policy files are diff-only in update, even pristine + unmarked ------------
# guard-secrets.sh is a policy file (SKILL update step 3): a kit change to it must
# be diffed, never auto-applied, regardless of the '# tailored' marker.
F=$(make_fixture)
NEWKIT=$(mktemp -d); cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# KIT CHANGE\n' >> "$NEWKIT/scripts/hooks/guard-secrets.sh"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
if ! grep -q "KIT CHANGE" "$F/scripts/hooks/guard-secrets.sh"; then
    pass "policy diff-only: update does not auto-replace a pristine guard-secrets.sh"
else
    fail "policy diff-only: guard-secrets.sh was auto-replaced by update"
fi
rm -rf "$F" "$NEWKIT"

# --- update installs newly-shipped mechanism files (v0.6 -> v0.7 migration) ----
# An old install's manifest can't list a file the previous kit didn't ship;
# update must still add it so the re-pin covers it and check #6/#9 run/verify it.
F=$(make_fixture)
rm "$F/scripts/install-lib.sh"
grep -v 'scripts/install-lib.sh' "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
harness_update_apply "$SCRIPTS_DIR" "$F" >/dev/null
if [ -f "$F/scripts/install-lib.sh" ]; then
    pass "migration: update re-adds a newly-shipped mechanism file absent from the target"
else
    fail "migration: update did not add the missing mechanism file"
fi
rm -rf "$F"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails install-mechanism case(s)"
    exit 1
fi
echo "PASSED: all install-mechanism cases"
