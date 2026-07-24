#!/usr/bin/env bash
# Deterministic fixture tests of the kit's update MECHANICS
# (scripts/harness/lib/install-lib.sh's harness_update_decision/harness_update_apply):
# no-op re-application, pristine mechanism replacement, '# tailored'
# preservation, policy-file diff-only behavior, undeclared local drift,
# migrating in newly-shipped mechanism (toplevel AND hooks), and carrying
# forward an arbitrary repo-local tailored pin across repin. Each case spins
# up a throwaway git repo in a scratch dir, drives the library — no model in
# the loop — and asserts concrete post-state, then tears the fixture down.
# See install-test-lib.sh for the shared preamble (nested-run guard, scratch
# base, make_fixture/repin/pass/fail/finish). Runnable standalone and in CI
# (since v0.23.0 it runs as this repo's explicit `install-suite-update` gate
# in .harness/gates.conf).
#
# Clean init / non-clobber / gitignore / harness_conf_* live in
# test-install-core.sh; recovery + dev.sh policy live in
# test-install-recovery.sh.
#
# Retirement (pristine/drifted/tailored), the v0.22.0 descope migration, the
# v0.23.0 flat re-home, the v0.25.0 provider-declaration upgrade, cp-failure,
# --dry-run, staged-replace, and symlinked-destination cases split out to
# test-install-migrate.sh so the two halves run as independent parallel
# gates.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-test-lib.sh"

# has_line <haystack> <line> — pure-shell exact-line membership (the $'\n'
# sandwich). Replaces `printf '%s\n' | grep -qxF`, whose early exit + an
# inherited ignored SIGPIPE + pipefail phantom-fails on a MATCH once the
# update plan outgrows the pipe buffer — the plan grows one line per shipped
# mechanism file. See the check #9 completeness note in check-harness.sh.
has_line() {
    case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; *) return 1 ;; esac
}

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
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/harness/sync"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
repin "$F" 9.9.9
newpin=$(grep "scripts/harness/sync" "$F/scripts/harness/.harness-manifest" | awk '{print $1}')
actual=$(sha_of "$F" "scripts/harness/sync")
if grep -q "UPGRADED" "$F/scripts/harness/sync" && [ "$newpin" = "$actual" ]; then
    pass "mechanism upgrade: untailored file replaced and manifest re-pinned"
else
    fail "mechanism upgrade: file not replaced or manifest not re-pinned"
fi
rm -rf "$F" "$NEWKIT"

# --- (c) tailored-file preservation -------------------------------------------
# A '# tailored' file whose content differs from the template is NOT replaced by
# update; it is left for the user to diff, and its own checksum pin is honored.
F=$(make_fixture) || exit 1
printf '\n# LOCAL FORK\n' >> "$F/scripts/harness/verify"
newsha=$(sha_of "$F" "scripts/harness/verify")
grep -v "scripts/harness/verify" "$F/scripts/harness/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/harness/verify # tailored\n' "$newsha" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/harness/.harness-manifest"
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"   # pristine verify.sh differs
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
kept=$(sha_of "$F" "scripts/harness/verify")
if grep -q "LOCAL FORK" "$F/scripts/harness/verify" && [ "$kept" = "$newsha" ]; then
    pass "tailored preservation: '# tailored' file left untouched by update, pin honored"
else
    fail "tailored preservation: a tailored file was replaced or its pin drifted"
fi
rm -rf "$F" "$NEWKIT"

# --- (d) policy layer is diff-only in update, even pristine + unmarked ---------
# guard-project-policy.sh is the one policy-layer hook left (SKILL update
# step 3): a kit change to it must be diffed, never auto-applied, regardless
# of the '# tailored' marker. guard-secrets.sh (v0.21.0) and format.sh
# (v0.23.0) are the counter-cases: reclassified policy→mechanism once their
# policy moved fully into harness.conf data, so a pristine copy IS
# auto-replaced — pin all three so no classification silently flips.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# KIT CHANGE\n' >> "$NEWKIT/.harness/hooks/guard-project-policy.sh"
printf '\n# KIT CHANGE\n' >> "$NEWKIT/scripts/harness/hooks/guard-secrets.sh"
printf '\n# KIT CHANGE\n' >> "$NEWKIT/scripts/harness/hooks/format.sh"
harness_update_apply "$NEWKIT/scripts" "$F" >/dev/null
if ! grep -q "KIT CHANGE" "$F/.harness/hooks/guard-project-policy.sh"; then
    pass "policy diff-only: update does not auto-replace a pristine guard-project-policy.sh"
else
    fail "policy diff-only: guard-project-policy.sh was auto-replaced by update"
fi
if grep -q "KIT CHANGE" "$F/scripts/harness/hooks/guard-secrets.sh"; then
    pass "mechanism reclassification: pristine guard-secrets.sh IS auto-replaced (v0.21.0 layer change)"
else
    fail "mechanism reclassification: pristine guard-secrets.sh was not replaced — did it fall back into a policy layer?"
fi
if grep -q "KIT CHANGE" "$F/scripts/harness/hooks/format.sh"; then
    pass "mechanism reclassification: pristine format.sh IS auto-replaced (v0.23.0 layer change)"
else
    fail "mechanism reclassification: pristine format.sh was not replaced — did it fall back into a policy layer?"
fi
rm -rf "$F" "$NEWKIT"

# --- (e) local-drift-preserve: sha-mismatch alone forces a diff decision -------
# sync-agent-skills.sh is mechanism-layer in the kit-manifest, unmarked, and
# not diff-only — the only way it yields 'diff' is the sha-mismatch branch of
# harness_update_decision, which nothing else in this
# suite drives: every other case here either still matches its pin (replace)
# or is '# tailored'/policy (diff via an earlier branch). This was
# CONFIRMED-MISSING before the split: local, undeclared drift — the file was
# hand-edited after install with no repin — must be preserved too, not
# silently overwritten by the next update.
F=$(make_fixture) || exit 1
printf '\n# LOCAL DRIFT\n' >> "$F/scripts/harness/sync"
line=$(grep 'scripts/harness/sync' "$F/scripts/harness/.harness-manifest")
decision=$(harness_update_decision "$F" "$line")
if [ "$decision" = "diff" ]; then
    pass "local-drift-preserve: harness_update_decision classifies sha-mismatched drift as diff"
else
    fail "local-drift-preserve: harness_update_decision returned '$decision', expected diff"
fi
out=$(harness_update_apply "$SCRIPTS_DIR" "$F")
if has_line "$out" "keep scripts/harness/sync"; then
    pass "local-drift-preserve: harness_update_apply reports 'keep', not 'replace'"
else
    fail "local-drift-preserve: harness_update_apply did not report 'keep scripts/harness/sync'" "$out"
fi
if grep -q "LOCAL DRIFT" "$F/scripts/harness/sync"; then
    pass "local-drift-preserve: the drifted content survives the update"
else
    fail "local-drift-preserve: update overwrote the locally drifted file"
fi
rm -rf "$F"

# --- (f) synthetic-future-file migration: new-kit inventory adds new mechanism -
# An old install's manifest can't list files the previous kit didn't ship, and
# its OLD installed kit-manifest doesn't know their names either — update must
# read the NEW kit's kit-manifest (and source the new library) before applying
# new templates. Simulate a kit release that ships a new top-level mechanism
# file AND a new hook — one unified add pass covers both since v0.21.0, but
# both shapes stay pinned here.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '#!/usr/bin/env bash\necho future-mech\n' > "$NEWKIT/scripts/future-mech.sh"
chmod +x "$NEWKIT/scripts/future-mech.sh"
printf '#!/usr/bin/env bash\necho future-hook\n' > "$NEWKIT/scripts/harness/hooks/future-hook.sh"
chmod +x "$NEWKIT/scripts/harness/hooks/future-hook.sh"
# The NEW kit declares both files in its ship contract — inventory is data
# (kit-manifest lines), not code, since v0.21.0.
printf 'mechanism scripts/future-mech.sh\nmechanism scripts/harness/hooks/future-hook.sh\n' \
    >> "$NEWKIT/scripts/harness/kit-manifest"
# Subshell sourcing of the NEW kit's library mirrors the real update flow
# (update.md: always source the incoming kit's install-lib.sh) and keeps any
# of its state out of the rest of this suite.
out1=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
)
if has_line "$out1" "add scripts/future-mech.sh"; then
    pass "synthetic-future-file: new-kit inventory adds the new toplevel file"
else
    fail "synthetic-future-file: 'add scripts/future-mech.sh' missing" "$out1"
fi
if has_line "$out1" "add scripts/harness/hooks/future-hook.sh"; then
    pass "synthetic-future-file: new-kit inventory adds the new hook (hooks add pass)"
else
    fail "synthetic-future-file: 'add scripts/harness/hooks/future-hook.sh' missing" "$out1"
fi
if [ -x "$F/scripts/future-mech.sh" ] && [ -x "$F/scripts/harness/hooks/future-hook.sh" ]; then
    pass "synthetic-future-file: both new files are installed executable"
else
    fail "synthetic-future-file: a new file was not installed executable"
fi
before_mech=$(sha_of "$F" "scripts/future-mech.sh")
before_hook=$(sha_of "$F" "scripts/harness/hooks/future-hook.sh")
out2=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
)
after_mech=$(sha_of "$F" "scripts/future-mech.sh")
after_hook=$(sha_of "$F" "scripts/harness/hooks/future-hook.sh")
if ! has_line "$out2" "add scripts/future-mech.sh" \
        && [ "$before_mech" = "$after_mech" ] && [ "$before_hook" = "$after_hook" ]; then
    pass "synthetic-future-file: a second apply is idempotent (no re-add, shas unchanged)"
else
    fail "synthetic-future-file: second apply re-added a file or changed its sha" "$out2"
fi
newmanifest=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_repin_manifest "$F" "$KIT_VERSION"
)
mech_pin=$(printf '%s\n' "$newmanifest" | awk '$2 == "scripts/future-mech.sh" {print $1}')
hook_pin=$(printf '%s\n' "$newmanifest" | awk '$2 == "scripts/harness/hooks/future-hook.sh" {print $1}')
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
printf '%s  scripts/check-local-gate.sh # tailored\n' "$gatesha" >> "$F/scripts/harness/.harness-manifest"
repin "$F" 9.9.9
line=$(grep 'scripts/check-local-gate.sh' "$F/scripts/harness/.harness-manifest" || true)
recomputed=$(sha_of "$F" "scripts/check-local-gate.sh")
header=$(head -1 "$F/scripts/harness/.harness-manifest")
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
if grep -q 'scripts/check-local-gate.sh' "$F/scripts/harness/.harness-manifest"; then
    fail "tailored carry-forward: repin re-pinned a deleted file (the [ -f ] filter did not drop it)"
else
    pass "tailored carry-forward: deleting the file drops its pin on the next repin"
fi
rm -rf "$F"

finish "install-update"
