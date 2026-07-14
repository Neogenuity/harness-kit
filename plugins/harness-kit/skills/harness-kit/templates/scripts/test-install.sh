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
    # This is a bare install-MECHANICS fixture: no provider hook configs or agent
    # personas are authored (that is the model-graded half). Declare the validated
    # provider sets EMPTY so check-harness's #8d hook check and agent-stub check
    # validate zero providers instead of failing on absent configs. Set BEFORE the
    # manifest so the harness.conf pin matches. Robust to a source conf that never
    # had the lines (strip-then-append). The non-empty sets get their own cases.
    { grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$w/scripts/harness.conf"
      printf 'HOOK_WIRED_PROVIDERS=""\nAGENT_PROVIDERS=""\n'
    } > "$w/scripts/harness.conf.tmp" && mv "$w/scripts/harness.conf.tmp" "$w/scripts/harness.conf"
    harness_generate_manifest "$w" "$KIT_VERSION" > "$w/scripts/.harness-manifest"
    ( cd "$w" && git_c add -A && git_c commit -qm init >/dev/null )
    printf '%s' "$w"
}

# repin <root> — regenerate the manifest after a harness.conf edit so check #9's
# checksum verification keeps passing (only harness.conf is manifest-pinned among
# the files these migration cases mutate; provider configs are not).
repin() {
    harness_repin_manifest "$1" "$KIT_VERSION" > "$1/scripts/.hm" \
        && mv "$1/scripts/.hm" "$1/scripts/.harness-manifest"
}

# write_provider_hook_configs <root> — the three shipped-shape hook configs, with
# .claude's deny list derived from the fixture's SECRET_PATTERNS (so check #8
# passes) and every guard on its frozen-contract event/matcher (so #8d passes).
write_provider_hook_configs() {
    local root="$1" pat sp deny=""
    sp=$(. "$root/scripts/harness.conf" && printf '%s' "$SECRET_PATTERNS")
    set -f
    for pat in $sp; do deny="$deny \"Read($pat)\","; done
    set +f
    deny=${deny%,}
    mkdir -p "$root/.claude" "$root/.cursor" "$root/.codex"
    cat > "$root/.claude/settings.json" <<JSON
{ "permissions": { "deny": [$deny ] },
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/session-context.sh" } ] } ],
    "PreToolUse": [
      { "matcher": "Read|Grep", "hooks": [ { "type": "command", "command": "scripts/hooks/guard-secrets.sh" } ] },
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "scripts/hooks/guard-config.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "scripts/hooks/format.sh" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "scripts/hooks/guard-project-policy.sh" } ] } ] } }
JSON
    cat > "$root/.cursor/hooks.json" <<'JSON'
{ "version": 1, "hooks": {
    "sessionStart": [ { "command": "scripts/hooks/session-context.sh" } ],
    "afterFileEdit": [ { "command": "scripts/hooks/format.sh" } ],
    "beforeReadFile": [ { "command": "scripts/hooks/guard-secrets.sh" } ],
    "stop": [ { "command": "scripts/hooks/guard-project-policy.sh" } ] } }
JSON
    # Codex uses the shipped Git-root-resolver wrapper so test-codex-hooks-cwd.sh
    # (a guard test check #6 runs inside this full-install fixture) is satisfied.
    cat > "$root/.codex/hooks.json" <<'JSON'
{ "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "bash -c 'root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; exec bash \"$root/scripts/hooks/session-context.sh\"'" } ] } ],
    "PreToolUse": [ { "hooks": [
      { "type": "command", "command": "bash -c 'root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; exec bash \"$root/scripts/hooks/guard-secrets.sh\"'" },
      { "type": "command", "command": "bash -c 'root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; exec bash \"$root/scripts/hooks/guard-config.sh\"'" } ] } ],
    "PostToolUse": [ { "matcher": "apply_patch", "hooks": [ { "type": "command", "command": "bash -c 'root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; exec bash \"$root/scripts/hooks/format.sh\"'" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "bash -c 'root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; exec bash \"$root/scripts/hooks/guard-project-policy.sh\"'" } ] } ] } }
JSON
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

# --- runtime-prerequisite preflight detection ---------------------------------
# harness_missing_prereqs is the deterministic core of init/update's early
# preflight: it NAMES any missing hard dependency so the user can acknowledge
# that (notably) a jq-less install ships an inert feedback layer — every guard
# fails open. Detection only; it changes no guard's fail-open posture. jq present
# on PATH → not reported; jq hidden (empty PATH) → reported. Robust to whatever
# the ambient env has by gating the present-case assertion on jq being real.
if command -v jq >/dev/null 2>&1; then
    if harness_missing_prereqs | grep -qx 'jq'; then
        fail "preflight: jq reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present jq"
    fi
fi
EMPTYPATH=$(mktemp -d)
if PATH="$EMPTYPATH" harness_missing_prereqs | grep -qx 'jq'; then
    pass "preflight: harness_missing_prereqs names jq when it is off PATH"
else
    fail "preflight: jq not reported missing when hidden from PATH"
fi
rm -rf "$EMPTYPATH"

# --- (a) clean init -----------------------------------------------------------
F=$(make_fixture)
write_mirrored_claude_settings "$F"
( cd "$F" && git_c add -A && git_c commit -qm claude >/dev/null )
missing=""
# harness.conf is a sourced config (not executable, like every non-.sh file);
# the .sh mechanism files must carry the exec bit (check-harness.sh check #5).
for f in check-harness.sh harness.conf install-lib.sh sync-agent-skills.sh \
         dev-instance.sh test-dev-instance.sh test-check-harness.sh \
         test-install.sh test-verify.sh verify.sh; do
    [ -f "$F/scripts/$f" ] || missing="$missing $f(absent)"
done
for f in check-harness.sh install-lib.sh sync-agent-skills.sh dev-instance.sh \
         test-dev-instance.sh test-check-harness.sh test-install.sh \
         test-verify.sh verify.sh; do
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
    && grep -q "scripts/dev-instance.sh" "$F/scripts/.harness-manifest" \
    && grep -q "scripts/test-dev-instance.sh" "$F/scripts/.harness-manifest" \
    && grep -q "scripts/harness.conf" "$F/scripts/.harness-manifest"; then
    pass "clean init: manifest enumerates install library, dev-instance helper/test, and harness.conf"
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

# --- old-template recovery for copied/plugin installs (no local git) ----------
# Update mode's tailored-file diff needs the OLD kit version's templates. A git
# checkout recovers them from the tag matching the manifest header, but plugin
# installs copy only plugins/harness-kit/ into a cache and copied installs need
# not keep .git — so the base is PERSISTED at init and recovered with no git in
# the loop. This drives exactly that no-local-git channel.
F=$(make_fixture)
harness_persist_base "$SCRIPTS_DIR" "$F" "$KIT_VERSION"   # the init-time snapshot
rm -rf "$F/.git"                                          # no local git at all
REC=$(mktemp -d)
recv=$(harness_recover_old_templates "$F" "$REC/old"); rc=$?
# Recovery must (a) succeed with no .git, (b) report the manifest-header version,
# and (c) reproduce the installed templates byte-for-byte (a faithful diff base)
# — spot-check a policy file and a hook.
if [ "$rc" = "0" ] && [ "$recv" = "$KIT_VERSION" ] \
   && cmp -s "$SCRIPTS_DIR/verify.sh" "$REC/old/verify.sh" \
   && cmp -s "$SCRIPTS_DIR/hooks/guard-secrets.sh" "$REC/old/hooks/guard-secrets.sh"; then
    pass "old-template recovery: no-local-git install recovers the version's base byte-for-byte"
else
    fail "old-template recovery: no-git recovery failed (rc=$rc version=$recv)"
fi
rm -rf "$REC"
# No persisted base (e.g. a teammate's fresh clone, where the git-ignored base was
# never checked out) → recovery returns non-zero so update falls back to the
# git-tag / upstream-fetch channels instead of silently diffing nothing.
rm -rf "$F/.harness/base"
REC2=$(mktemp -d)
harness_recover_old_templates "$F" "$REC2/old" >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ]; then
    pass "old-template recovery: an absent base returns non-zero so update can fall back"
else
    fail "old-template recovery: a missing base did not signal fallback"
fi
rm -rf "$REC2" "$F"

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

# --- update installs newly-shipped mechanism files using the NEW kit library ---
# An old install's manifest can't list files the previous kit didn't ship. More
# subtly, its OLD installed install-lib.sh does not know their names either, so
# update must source the NEW kit's library before applying the new templates.
# Simulate pre-v0.15 by removing both helper files and their pins, then prove
# the new library discovers, installs, and chmods both.
F=$(make_fixture)
rm "$F/scripts/dev-instance.sh" "$F/scripts/test-dev-instance.sh"
grep -vE 'scripts/(test-)?dev-instance\.sh' "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
NEWKIT=$(mktemp -d); cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
(
    # This source is the behavior under test: update orchestration must use the
    # incoming kit's list, not the legacy target's install-lib.sh.
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
) >/dev/null
if [ -x "$F/scripts/dev-instance.sh" ] && [ -x "$F/scripts/test-dev-instance.sh" ]; then
    pass "migration: new-kit install library adds executable v0.15 helper and test"
else
    fail "migration: new-kit install library did not add both v0.15 files executable"
fi
rm -rf "$F" "$NEWKIT"

# --- optional scripts/dev.sh is pinned policy, never a copied template --------
# The kit can author this repo-specific launcher, but the installer cannot ship
# a useful generic body. A same-named file in a source dir is therefore ignored
# by install/persist/add; once a target authors one, manifest generation includes
# it and update is diff-only (even if pristine and unmarked).
ROGUE=$(mktemp -d); cp -R "$SCRIPTS_DIR" "$ROGUE/scripts"
printf '#!/usr/bin/env bash\necho WRONG-GENERIC-TEMPLATE\n' > "$ROGUE/scripts/dev.sh"
chmod +x "$ROGUE/scripts/dev.sh"
F=$(mktemp -d); ( cd "$F" && git init -q )
harness_install_mechanism "$ROGUE/scripts" "$F"
if [ ! -e "$F/scripts/dev.sh" ]; then
    pass "project policy: install never copies a source scripts/dev.sh template"
else
    fail "project policy: install copied forbidden generic scripts/dev.sh"
fi
harness_persist_base "$ROGUE/scripts" "$F" "$KIT_VERSION"
BASE=$(harness_base_dir "$F" "$KIT_VERSION")
if [ ! -e "$BASE/dev.sh" ]; then
    pass "project policy: persisted mechanism base excludes scripts/dev.sh"
else
    fail "project policy: persisted base captured scripts/dev.sh as mechanism"
fi
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/.harness-manifest"
harness_update_apply "$ROGUE/scripts" "$F" >/dev/null
if [ ! -e "$F/scripts/dev.sh" ]; then
    pass "project policy: update add pass never installs scripts/dev.sh"
else
    fail "project policy: update add pass installed scripts/dev.sh"
fi

printf '#!/usr/bin/env bash\necho PROJECT-OWNED\n' > "$F/scripts/dev.sh"
chmod +x "$F/scripts/dev.sh"
harness_repin_manifest "$F" "$KIT_VERSION" > "$F/scripts/.hm" \
    && mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
devpin=$(grep 'scripts/dev.sh' "$F/scripts/.harness-manifest" || true)
if [ -n "$devpin" ] && [ "${devpin%% *}" = "$(sha_of "$F" scripts/dev.sh)" ]; then
    pass "project policy: authored scripts/dev.sh is manifest-pinned"
else
    fail "project policy: authored scripts/dev.sh was not pinned"
fi
# Mark it tailored and prove both update and re-pin preserve ownership/content.
grep -v 'scripts/dev.sh' "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/dev.sh # tailored\n' "$(sha_of "$F" scripts/dev.sh)" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
harness_update_apply "$ROGUE/scripts" "$F" >/dev/null
harness_repin_manifest "$F" "9.9.9" > "$F/scripts/.hm" \
    && mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
if grep -qF 'PROJECT-OWNED' "$F/scripts/dev.sh" \
   && grep 'scripts/dev.sh' "$F/scripts/.harness-manifest" | grep -qF '# tailored'; then
    pass "project policy: tailored scripts/dev.sh stays diff-only and its marker survives re-pin"
else
    fail "project policy: update replaced scripts/dev.sh or re-pin lost its tailored marker"
fi
rm -rf "$F" "$ROGUE"

# --- HOOK_WIRED_PROVIDERS migration for a legacy pre-declaration install -------
# harness.conf is diff-only on update, so a pre-v0.14 install never grows the
# declaration on its own. Update/audit must PROPOSE a set and record the user's
# CONFIRMED choice — never infer it from whichever configs survive. This walks
# the whole flow: undeclared→loud, a pre-migration deletion that must NOT be
# silently adopted, confirmation, idempotency, and the post-migration bite.
if command -v jq >/dev/null 2>&1; then
    F=$(make_fixture)
    # Simulate the legacy state: strip the declaration entirely (make_fixture
    # leaves it set-but-empty; a pre-v0.14 conf had no line at all).
    grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness.conf" > "$F/scripts/hc" \
        && mv "$F/scripts/hc" "$F/scripts/harness.conf"
    repin "$F"
    if ! harness_conf_declared "$F" HOOK_WIRED_PROVIDERS; then
        pass "migration: a pre-declaration harness.conf reads as undeclared"
    else
        fail "migration: undeclared conf misreported as declared"
    fi
    write_provider_hook_configs "$F"
    rm "$F/.cursor/hooks.json"            # pre-migration deletion of one config
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF "declares no HOOK_WIRED_PROVIDERS"; then
        pass "migration: undeclared adopted harness stays a loud error (deletion not silently adopted)"
    else
        fail "migration: undeclared adopted harness not flagged (rc=$rc)" "$out"
    fi
    # Confirm the FULL wired set (the user's choice) — NOT inferred from the
    # survivors, which would have blessed the .cursor deletion.
    harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude .cursor .codex"
    harness_conf_declare "$F" AGENT_PROVIDERS ""
    repin "$F"
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF ".cursor/hooks.json is missing"; then
        pass "migration: after confirming the full set, the deleted .cursor config surfaces as an ERROR"
    else
        fail "migration: deleted config not surfaced post-migration (rc=$rc)" "$out"
    fi
    # Second update: idempotent — no duplicate line, and it does NOT reset a value
    # the user has since edited (proves a re-run of the migration is a no-op).
    harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude"
    n=$(grep -c '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness.conf")
    v=$(grep '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness.conf")
    if [ "$n" -eq 1 ] && [ "$v" = 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"' ]; then
        pass "migration: second update is idempotent (no duplicate line, no reset)"
    else
        fail "migration: not idempotent (n=$n v=$v)"
    fi
    # Restore the config → the migrated harness is green.
    write_provider_hook_configs "$F"
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    [ "$rc" = "0" ] && pass "migration: restoring the config makes the migrated harness green" \
        || fail "migration: restored config still failing (rc=$rc)" "$out"
    # Legacy-upgrade bite: post-migration, deleting the hooks object is caught.
    jq 'del(.hooks)' "$F/.claude/settings.json" > "$F/.claude/s" && mv "$F/.claude/s" "$F/.claude/settings.json"
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF "is not wired in .claude/settings.json"; then
        pass "migration: legacy-upgrade — deleting hooks post-migration is flagged"
    else
        fail "migration: post-migration hooks deletion not flagged (rc=$rc)" "$out"
    fi
    rm -rf "$F"
fi

# --- real shipped provider hook configs validate against the frozen contract ---
# Not synthetic: install the ACTUAL templates/providers/* hook configs and prove
# every tuple in the provider-matrix hook table holds. Guarded on the templates
# dir being reachable as a sibling of scripts/ — true when this runs as the
# template copy (SCRIPTS_DIR = templates/scripts) during verify.sh's template-tests
# gate; skipped in a user install that ships only scripts/.
PROVIDERS_TPL="$SCRIPTS_DIR/../providers"
if command -v jq >/dev/null 2>&1 && [ -d "$PROVIDERS_TPL" ]; then
    F=$(mktemp -d)
    ( cd "$F" && git init -q )
    harness_install_mechanism "$SCRIPTS_DIR" "$F"
    harness_append_gitignore "$F"
    { grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness.conf"
      printf 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"\nAGENT_PROVIDERS=""\n'
    } > "$F/scripts/hc" && mv "$F/scripts/hc" "$F/scripts/harness.conf"
    mkdir -p "$F/.claude" "$F/.cursor" "$F/.codex"
    cp "$PROVIDERS_TPL/claude/settings.json" "$F/.claude/settings.json"
    cp "$PROVIDERS_TPL/cursor/hooks.json" "$F/.cursor/hooks.json"
    cp "$PROVIDERS_TPL/codex/hooks.json" "$F/.codex/hooks.json"
    harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/.harness-manifest"
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    if [ "$rc" = "0" ]; then
        pass "real templates: shipped provider hook configs validate all tuples (#8d)"
    else
        fail "real templates: shipped hook configs failed check-harness" "$out"
    fi
    jq 'del(.hooks)' "$F/.claude/settings.json" > "$F/.claude/s" && mv "$F/.claude/s" "$F/.claude/settings.json"
    out=$(cd "$F" && bash scripts/check-harness.sh 2>&1); rc=$?
    if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF "is not wired in .claude/settings.json"; then
        pass "real templates: deleting .hooks from the shipped settings.json is flagged"
    else
        fail "real templates: #8d did not bite the shipped settings.json (rc=$rc)" "$out"
    fi
    rm -rf "$F"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails install-mechanism case(s)"
    exit 1
fi
echo "PASSED: all install-mechanism cases"
