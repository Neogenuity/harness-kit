#!/usr/bin/env bash
# Deterministic fixture tests of the kit's install RECOVERY + dev.sh policy
# (scripts/harness/lib/install-lib.sh): no-local-git old-template recovery for
# copied/plugin installs, the missing-base fallback signal, and
# scripts/dev.sh's special status as pinned-but-never-templated project
# policy. Each case spins up a throwaway git repo in a scratch dir, drives
# the library — no model in the loop — and asserts concrete post-state, then
# tears the fixture down. See install-test-lib.sh for the shared preamble
# (nested-run guard, scratch base, make_fixture/repin/pass/fail/finish).
# Runnable standalone and in CI (it is a scripts/test-*.sh, so
# check-harness.sh check #6 and verify.sh's template-tests gate both pick it
# up by name).
#
# Clean init / non-clobber / gitignore / harness_conf_* live in
# test-install-core.sh; update-mode mechanics live in test-install-update.sh.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-test-lib.sh"

# --- old-template recovery for copied/plugin installs (no local git) ----------
# Update mode's tailored-file diff needs the OLD kit version's templates. A git
# checkout recovers them from the tag matching the manifest header, but plugin
# installs copy only plugins/harness-kit/ into a cache and copied installs need
# not keep .git — so the base is PERSISTED at init and recovered with no git in
# the loop. This drives exactly that no-local-git channel.
F=$(make_fixture) || exit 1
harness_persist_base "$SCRIPTS_DIR" "$F" "$KIT_VERSION"   # the init-time snapshot
rm -rf "${F:?}/.git"                                          # no local git at all
REC=$(mktemp -d "$WORK/recover.XXXXXX") || exit 1
recv=$(harness_recover_old_templates "$F" "$REC/old"); rc=$?
# Recovery must (a) succeed with no .git, (b) report the manifest-header version,
# and (c) reproduce the installed templates byte-for-byte (a faithful diff base)
# — spot-check a policy file and a hook.
if [ "$rc" = "0" ] && [ "$recv" = "$KIT_VERSION" ] \
   && cmp -s "$SCRIPTS_DIR/gates.conf" "$REC/old/gates.conf" \
   && cmp -s "$SCRIPTS_DIR/harness/hooks/guard-secrets.sh" "$REC/old/harness/hooks/guard-secrets.sh"; then
    pass "old-template recovery: no-local-git install recovers the version's base byte-for-byte"
else
    fail "old-template recovery: no-git recovery failed (rc=$rc version=$recv)"
fi
rm -rf "$REC"
# No persisted base (e.g. a teammate's fresh clone, where the git-ignored base was
# never checked out) → recovery returns non-zero so update falls back to the
# git-tag / upstream-fetch channels instead of silently diffing nothing.
rm -rf "${F:?}/.harness/var/base"
REC2=$(mktemp -d "$WORK/recover2.XXXXXX") || exit 1
harness_recover_old_templates "$F" "$REC2/old" >/dev/null 2>&1; rc=$?
if [ "$rc" != "0" ]; then
    pass "old-template recovery: an absent base returns non-zero so update can fall back"
else
    fail "old-template recovery: a missing base did not signal fallback"
fi
rm -rf "$REC2" "$F"

# --- optional scripts/dev.sh is pinned policy, never a copied template --------
# The kit can author this repo-specific launcher, but the installer cannot ship
# a useful generic body. A same-named file in a source dir is therefore ignored
# by install/persist/add; once a target authors one, manifest generation includes
# it and update is diff-only (even if pristine and unmarked).
ROGUE=$(mktemp -d "$WORK/rogue.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$ROGUE/scripts"
printf '#!/usr/bin/env bash\necho WRONG-GENERIC-TEMPLATE\n' > "$ROGUE/scripts/dev.sh"
chmod +x "$ROGUE/scripts/dev.sh"
F=$(mktemp -d "$WORK/rogue-install.XXXXXX") || exit 1; ( cd "${F:?}" && git init -q )
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
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/harness/.harness-manifest"
harness_update_apply "$ROGUE/scripts" "$F" >/dev/null
if [ ! -e "$F/scripts/dev.sh" ]; then
    pass "project policy: update add pass never installs scripts/dev.sh"
else
    fail "project policy: update add pass installed scripts/dev.sh"
fi

printf '#!/usr/bin/env bash\necho PROJECT-OWNED\n' > "$F/scripts/dev.sh"
chmod +x "$F/scripts/dev.sh"
repin "$F"
devpin=$(grep 'scripts/dev.sh' "$F/scripts/harness/.harness-manifest" || true)
if [ -n "$devpin" ] && [ "${devpin%% *}" = "$(sha_of "$F" scripts/dev.sh)" ]; then
    pass "project policy: authored scripts/dev.sh is manifest-pinned"
else
    fail "project policy: authored scripts/dev.sh was not pinned"
fi
# Mark it tailored and prove both update and re-pin preserve ownership/content.
grep -v 'scripts/dev.sh' "$F/scripts/harness/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/dev.sh # tailored\n' "$(sha_of "$F" scripts/dev.sh)" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/harness/.harness-manifest"
harness_update_apply "$ROGUE/scripts" "$F" >/dev/null
repin "$F" 9.9.9
if grep -qF 'PROJECT-OWNED' "$F/scripts/dev.sh" \
   && grep 'scripts/dev.sh' "$F/scripts/harness/.harness-manifest" | grep -qF '# tailored'; then
    pass "project policy: tailored scripts/dev.sh stays diff-only and its marker survives re-pin"
else
    fail "project policy: update replaced scripts/dev.sh or re-pin lost its tailored marker"
fi
rm -rf "$F" "$ROGUE"

finish "install-recovery-and-policy"
