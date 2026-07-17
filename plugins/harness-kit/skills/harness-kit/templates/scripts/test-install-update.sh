#!/usr/bin/env bash
# Deterministic fixture tests of the kit's update MECHANICS
# (scripts/install-lib.sh's harness_update_decision/harness_update_apply):
# no-op re-application, pristine mechanism replacement, '# tailored'
# preservation, policy-file diff-only behavior, undeclared local drift,
# migrating in newly-shipped mechanism (toplevel AND hooks), and carrying
# forward an arbitrary repo-local tailored pin across repin. Each case spins
# up a throwaway git repo in a scratch dir, drives the library — no model in
# the loop — and asserts concrete post-state, then tears the fixture down.
# See install-test-lib.sh for the shared preamble (nested-run guard, scratch
# base, make_fixture/repin/pass/fail/finish). Runnable standalone and in CI
# (it is a scripts/test-*.sh, so check-harness.sh check #6 and verify.sh's
# template-tests gate both pick it up by name).
#
# Clean init / non-clobber / gitignore / harness_conf_* live in
# test-install-core.sh; recovery + dev.sh policy live in
# test-install-recovery.sh.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-test-lib.sh"

# --- (a) no-op update ---------------------------------------------------------
# Update at the same version, from the same source, changes nothing.
F=$(make_fixture) || exit 1
harness_update_apply "$SCRIPTS_DIR" "$F" >/dev/null
repin "$F"
dirty=$( cd "${F:?}" && git status --porcelain )
if [ -z "$dirty" ]; then
    pass "no-op update: idempotent (clean git status)"
else
    fail "no-op update: left changes in the working tree" "$dirty"
fi
rm -rf "$F"

# --- (b) mechanism upgrade ----------------------------------------------------
# An untailored file still matching its pin is replaced with the newer kit
# version and the manifest re-pinned to the new checksum.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/sync-agent-skills.sh"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
repin "$F" 9.9.9
newpin=$(grep "scripts/sync-agent-skills.sh" "$F/scripts/.harness-manifest" | awk '{print $1}')
actual=$(sha_of "$F" "scripts/sync-agent-skills.sh")
if grep -q "UPGRADED" "$F/scripts/sync-agent-skills.sh" && [ "$newpin" = "$actual" ]; then
    pass "mechanism upgrade: untailored file replaced and manifest re-pinned"
else
    fail "mechanism upgrade: file not replaced or manifest not re-pinned"
fi
rm -rf "$F" "$NEWKIT"

# --- (c) tailored-file preservation -------------------------------------------
# A '# tailored' file whose content differs from the template is NOT replaced by
# update; it is left for the user to diff, and its own checksum pin is honored.
F=$(make_fixture) || exit 1
printf '\n# LOCAL FORK\n' >> "$F/scripts/verify.sh"
newsha=$(sha_of "$F" "scripts/verify.sh")
grep -v "scripts/verify.sh" "$F/scripts/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/verify.sh # tailored\n' "$newsha" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/.harness-manifest"
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"   # pristine verify.sh differs
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
kept=$(sha_of "$F" "scripts/verify.sh")
if grep -q "LOCAL FORK" "$F/scripts/verify.sh" && [ "$kept" = "$newsha" ]; then
    pass "tailored preservation: '# tailored' file left untouched by update, pin honored"
else
    fail "tailored preservation: a tailored file was replaced or its pin drifted"
fi
rm -rf "$F" "$NEWKIT"

# --- (d) policy files are diff-only in update, even pristine + unmarked --------
# guard-secrets.sh is a policy file (SKILL update step 3): a kit change to it must
# be diffed, never auto-applied, regardless of the '# tailored' marker.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# KIT CHANGE\n' >> "$NEWKIT/scripts/hooks/guard-secrets.sh"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
if ! grep -q "KIT CHANGE" "$F/scripts/hooks/guard-secrets.sh"; then
    pass "policy diff-only: update does not auto-replace a pristine guard-secrets.sh"
else
    fail "policy diff-only: guard-secrets.sh was auto-replaced by update"
fi
rm -rf "$F" "$NEWKIT"

# --- (e) local-drift-preserve: sha-mismatch alone forces a diff decision -------
# sync-agent-skills.sh is mechanism, unmarked, and NOT in _HARNESS_POLICY_FILES
# — the only way it yields 'diff' is the sha-mismatch branch of
# harness_update_decision (install-lib.sh:295-297), which nothing else in this
# suite drives: every other case here either still matches its pin (replace)
# or is '# tailored'/policy (diff via an earlier branch). This was
# CONFIRMED-MISSING before the split: local, undeclared drift — the file was
# hand-edited after install with no repin — must be preserved too, not
# silently overwritten by the next update.
F=$(make_fixture) || exit 1
printf '\n# LOCAL DRIFT\n' >> "$F/scripts/sync-agent-skills.sh"
line=$(grep 'scripts/sync-agent-skills.sh' "$F/scripts/.harness-manifest")
decision=$(harness_update_decision "$F" "$line")
if [ "$decision" = "diff" ]; then
    pass "local-drift-preserve: harness_update_decision classifies sha-mismatched drift as diff"
else
    fail "local-drift-preserve: harness_update_decision returned '$decision', expected diff"
fi
out=$(harness_update_apply "$SCRIPTS_DIR" "$F")
if printf '%s\n' "$out" | grep -qxF "keep scripts/sync-agent-skills.sh"; then
    pass "local-drift-preserve: harness_update_apply reports 'keep', not 'replace'"
else
    fail "local-drift-preserve: harness_update_apply did not report 'keep scripts/sync-agent-skills.sh'" "$out"
fi
if grep -q "LOCAL DRIFT" "$F/scripts/sync-agent-skills.sh"; then
    pass "local-drift-preserve: the drifted content survives the update"
else
    fail "local-drift-preserve: update overwrote the locally drifted file"
fi
rm -rf "$F"

# --- (f) synthetic-future-file migration: new-kit inventory adds new mechanism -
# An old install's manifest can't list files the previous kit didn't ship, and
# its OLD installed install-lib.sh doesn't know their names either — update
# must source the NEW kit's library before applying new templates. Simulate a
# kit release that ships a new top-level mechanism file AND a new hook (the
# hooks add pass at install-lib.sh:337-347 — never covered before this suite,
# since every historical NEW_FILES case was toplevel-only).
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '#!/usr/bin/env bash\necho future-mech\n' > "$NEWKIT/scripts/future-mech.sh"
chmod +x "$NEWKIT/scripts/future-mech.sh"
printf '#!/usr/bin/env bash\necho future-hook\n' > "$NEWKIT/scripts/hooks/future-hook.sh"
chmod +x "$NEWKIT/scripts/hooks/future-hook.sh"
# Reassignment, not sed -i (BSD/GNU divergence): append a line the NEW kit's
# own install-lib.sh executes when sourced, extending its inventory in place.
printf '\n_HARNESS_MECHANISM_TOPLEVEL="$_HARNESS_MECHANISM_TOPLEVEL future-mech.sh"\n' \
    >> "$NEWKIT/scripts/install-lib.sh"
# Subshell: sourcing the extended NEWKIT library here must not leak its
# inventory into the rest of this suite.
out1=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
)
if printf '%s\n' "$out1" | grep -qxF "add scripts/future-mech.sh"; then
    pass "synthetic-future-file: new-kit inventory adds the new toplevel file"
else
    fail "synthetic-future-file: 'add scripts/future-mech.sh' missing" "$out1"
fi
if printf '%s\n' "$out1" | grep -qxF "add scripts/hooks/future-hook.sh"; then
    pass "synthetic-future-file: new-kit inventory adds the new hook (hooks add pass)"
else
    fail "synthetic-future-file: 'add scripts/hooks/future-hook.sh' missing" "$out1"
fi
if [ -x "$F/scripts/future-mech.sh" ] && [ -x "$F/scripts/hooks/future-hook.sh" ]; then
    pass "synthetic-future-file: both new files are installed executable"
else
    fail "synthetic-future-file: a new file was not installed executable"
fi
before_mech=$(sha_of "$F" "scripts/future-mech.sh")
before_hook=$(sha_of "$F" "scripts/hooks/future-hook.sh")
out2=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
)
after_mech=$(sha_of "$F" "scripts/future-mech.sh")
after_hook=$(sha_of "$F" "scripts/hooks/future-hook.sh")
if ! printf '%s\n' "$out2" | grep -qxF "add scripts/future-mech.sh" \
        && [ "$before_mech" = "$after_mech" ] && [ "$before_hook" = "$after_hook" ]; then
    pass "synthetic-future-file: a second apply is idempotent (no re-add, shas unchanged)"
else
    fail "synthetic-future-file: second apply re-added a file or changed its sha" "$out2"
fi
newmanifest=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/install-lib.sh"
    harness_repin_manifest "$F" "$KIT_VERSION"
)
mech_pin=$(printf '%s\n' "$newmanifest" | awk '$2 == "scripts/future-mech.sh" {print $1}')
hook_pin=$(printf '%s\n' "$newmanifest" | awk '$2 == "scripts/hooks/future-hook.sh" {print $1}')
if [ "$mech_pin" = "$after_mech" ] && [ "$hook_pin" = "$after_hook" ]; then
    pass "synthetic-future-file: repin via the new-kit library discovers and pins both new paths"
else
    fail "synthetic-future-file: repin missed or mis-pinned a new file (mech=$mech_pin hook=$hook_pin)"
fi
rm -rf "$F" "$NEWKIT"

# --- (g) arbitrary tailored-pin carry-forward: a repo-local gate survives repin
# harness_repin_manifest must carry forward a previously-tailored pin for a
# file the SHIPPED producer does not itself emit — a repo may pin its own
# local checks (a packaging or template-sync gate) as '# tailored'
# (install-lib.sh:115-138). Name deliberately avoids the test-*.sh glob: this
# is a repo-owned gate, not a kit regression test.
F=$(make_fixture) || exit 1
printf '#!/usr/bin/env bash\necho local-gate\n' > "$F/scripts/check-local-gate.sh"
chmod +x "$F/scripts/check-local-gate.sh"
gatesha=$(sha_of "$F" "scripts/check-local-gate.sh")
printf '%s  scripts/check-local-gate.sh # tailored\n' "$gatesha" >> "$F/scripts/.harness-manifest"
repin "$F" 9.9.9
line=$(grep 'scripts/check-local-gate.sh' "$F/scripts/.harness-manifest" || true)
recomputed=$(sha_of "$F" "scripts/check-local-gate.sh")
header=$(head -1 "$F/scripts/.harness-manifest")
if [ -n "$line" ] \
        && printf '%s\n' "$line" | grep -q '# tailored' \
        && [ "${line%% *}" = "$recomputed" ] \
        && [ "$header" = "# harness-kit 9.9.9" ]; then
    pass "tailored carry-forward: an arbitrary repo-local pin survives repin with its marker and sha"
else
    fail "tailored carry-forward: repin dropped, mis-marked, or mis-hashed the local pin" "$line"
fi
rm "$F/scripts/check-local-gate.sh"
repin "$F" 9.9.9
if grep -q 'scripts/check-local-gate.sh' "$F/scripts/.harness-manifest"; then
    fail "tailored carry-forward: repin re-pinned a deleted file (the [ -f ] filter did not drop it)"
else
    pass "tailored carry-forward: deleting the file drops its pin on the next repin"
fi
rm -rf "$F"

finish "install-update"
