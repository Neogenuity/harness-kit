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

# --- (h) retirement: pristine + unmarked retired file is REMOVED ---------------
# The NEW kit's kit-manifest moves a shipped file to the retired layer. The
# installed copy still matches its pin and carries no '# tailored' marker, so
# update removes it, and the subsequent repin drops its pin — the exact
# sequence that needed a manual `rm` at v0.20.0.
retire_in_newkit() {  # retire_in_newkit <newkit_scripts_dir> <repo-relative-path>
    local kmf="$1/harness/kit-manifest" path="$2"
    awk -v p="$path" '!($2 == p && ($1 == "mechanism" || $1 == "policy"))' "$kmf" > "$kmf.tmp" \
        && mv "$kmf.tmp" "$kmf"
    printf 'retired %s\n' "$path" >> "$kmf"
}
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
out=$(harness_update_apply "$NEWKIT/scripts" "$F")
if has_line "$out" "remove scripts/harness/tests/test-log.sh" && [ ! -f "$F/scripts/harness/tests/test-log.sh" ]; then
    pass "retirement: pristine unmarked retired file is removed and reported"
else
    fail "retirement: pristine retired file not removed or not reported" "$out"
fi
if has_line "$out" "add scripts/harness/tests/test-log.sh"; then
    fail "retirement: the add pass re-installed a retired file"
else
    pass "retirement: the add pass does not resurrect a retired file"
fi
# The NEW kit's kit-manifest replaced the fixture's during apply, so the
# repin (driven by the new ship contract) must drop the removed file's pin.
newmanifest=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_repin_manifest "$F" "$KIT_VERSION"
)
if printf '%s\n' "$newmanifest" | awk '$2 == "scripts/harness/tests/test-log.sh" {found=1} END {exit !found}'; then
    fail "retirement: repin still pins the removed file"
else
    pass "retirement: repin drops the removed file's pin"
fi
rm -rf "$F" "$NEWKIT"

# --- (i) retirement: locally DRIFTED retired file is kept and reported ---------
# Retirement must never delete local changes: a hand-edited (sha-mismatched,
# unmarked) copy of a retired path is kept, reported as 'retire-keep', and
# left for manual review.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
printf '\n# LOCAL DRIFT\n' >> "$F/scripts/harness/tests/test-log.sh"
out=$(harness_update_apply "$NEWKIT/scripts" "$F")
if has_line "$out" "retire-keep scripts/harness/tests/test-log.sh" \
        && [ -f "$F/scripts/harness/tests/test-log.sh" ] \
        && grep -q "LOCAL DRIFT" "$F/scripts/harness/tests/test-log.sh"; then
    pass "retirement: drifted retired file is kept with its local changes and reported"
else
    fail "retirement: drifted retired file was deleted or not reported" "$out"
fi
rm -rf "$F" "$NEWKIT"

# --- (j) retirement: '# tailored' retired file is kept and its pin carried -----
# A deliberate fork of a now-retired path survives: the file stays, apply
# reports 'retire-keep', and repin carries its pin forward with the marker.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
printf '\n# LOCAL FORK\n' >> "$F/scripts/harness/tests/test-log.sh"
forksha=$(sha_of "$F" "scripts/harness/tests/test-log.sh")
grep -v "scripts/harness/tests/test-log.sh" "$F/scripts/harness/.harness-manifest" > "$F/scripts/.hm"
printf '%s  scripts/harness/tests/test-log.sh # tailored\n' "$forksha" >> "$F/scripts/.hm"
mv "$F/scripts/.hm" "$F/scripts/harness/.harness-manifest"
out=$(harness_update_apply "$NEWKIT/scripts" "$F")
if has_line "$out" "retire-keep scripts/harness/tests/test-log.sh" && [ -f "$F/scripts/harness/tests/test-log.sh" ]; then
    pass "retirement: tailored retired file is kept and reported"
else
    fail "retirement: tailored retired file was deleted or not reported" "$out"
fi
newmanifest=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_repin_manifest "$F" "$KIT_VERSION"
)
line=$(printf '%s\n' "$newmanifest" | awk '$2 == "scripts/harness/tests/test-log.sh" {print; exit}')
case "$line" in *"# tailored"*) fork_marked=1 ;; *) fork_marked=0 ;; esac
if [ -n "$line" ] && [ "$fork_marked" = 1 ] && [ "${line%% *}" = "$forksha" ]; then
    pass "retirement: repin carries the tailored retired pin forward with marker and sha"
else
    fail "retirement: repin dropped or mis-marked the tailored retired pin" "$line"
fi
rm -rf "$F" "$NEWKIT"

# --- (k) v0.22.0 descope migration: a pre-descope install updates clean --------
# Simulate the real migration this suite's own descope shipped: a
# v0.21.0-layout install still carries the seven conformance-suite files at
# their OLD flat paths, pinned and pristine; updating to THIS kit must remove
# every one and leave no retired-but-pinned residue after repin. (The
# smoke-suite add pass is the generic add behavior case (f) already pins —
# make_fixture installs the current shipped set, so the smoke test is present
# from the start here.)
F=$(make_fixture) || exit 1
DESCOPED="scripts/install-test-lib.sh scripts/test-install-core.sh scripts/test-install-update.sh scripts/test-install-recovery.sh scripts/test-check-harness.sh scripts/test-eval.sh scripts/test-fixture-isolation.sh"
for p in $DESCOPED; do
    printf '#!/usr/bin/env bash\necho old-suite\n' > "$F/$p"
    chmod +x "$F/$p"
    printf '%s  %s\n' "$(sha_of "$F" "$p")" "$p" >> "$F/scripts/harness/.harness-manifest"
done
out=$(harness_update_apply "$SCRIPTS_DIR" "$F")
missing=""
for p in $DESCOPED; do
    has_line "$out" "remove $p" || missing="$missing $p(no-remove)"
    if [ -f "$F/$p" ]; then missing="$missing $p(still-present)"; fi
done
if [ -z "$missing" ]; then
    pass "descope migration: all seven pre-descope suites removed and reported"
else
    fail "descope migration: incomplete removal —$missing" "$out"
fi
repin "$F"
leftover=$(awk '$2 ~ /install-test-lib|test-install-(core|update|recovery)|test-check-harness|test-eval\.sh|test-fixture-isolation/ {print $2}' "$F/scripts/harness/.harness-manifest")
if [ -z "$leftover" ]; then
    pass "descope migration: repin leaves no pins for the removed suites"
else
    fail "descope migration: stale pins survive repin" "$leftover"
fi
rm -rf "$F"

# --- (l) v0.23.0 mechanism re-home: a v0.22.0-layout install updates clean -----
# The whole flat scripts/ layout moved under scripts/harness/ (and the verify
# gate list to .harness/gates.conf). A pre-move install carries the OLD
# integrity-manifest location, old flat mechanism files (pinned, pristine),
# and the broad '.harness/' gitignore. Update must migrate the manifest,
# remove every pristine old path, install the new tree, and the gitignore
# helper must narrow the old ignore line — retirement is the migration.
F=$(mktemp -d "$WORK/oldlayout.XXXXXX") || exit 1
( cd "${F:?}" && git init -q . )
printf '.harness/\n' > "$F/.gitignore"
mkdir -p "$F/scripts/hooks"
OLDFILES="scripts/check-harness.sh scripts/sync-agent-skills.sh scripts/install-lib.sh scripts/verify.sh scripts/log-lib.sh scripts/hooks/lib.sh scripts/hooks/guard-secrets.sh"
printf '# harness-kit 0.22.0\n' > "$F/scripts/.harness-manifest"
for p in $OLDFILES; do
    printf '#!/usr/bin/env bash\necho old\n' > "$F/$p"
    chmod +x "$F/$p"
    printf '%s  %s\n' "$(sha_of "$F" "$p")" "$p" >> "$F/scripts/.harness-manifest"
done
out=$(harness_update_apply "$SCRIPTS_DIR" "$F")
harness_append_gitignore "$F"
rehome_bad=""
has_line "$out" "migrate scripts/harness/.harness-manifest" || rehome_bad="$rehome_bad no-manifest-migrate"
[ -f "$F/scripts/.harness-manifest" ] && rehome_bad="$rehome_bad old-manifest-left"
for p in $OLDFILES; do
    if [ -f "$F/$p" ]; then rehome_bad="$rehome_bad $p(still-present)"; fi
done
[ -x "$F/scripts/harness/verify" ] || rehome_bad="$rehome_bad no-new-runner"
[ -f "$F/.harness/gates.conf" ] || rehome_bad="$rehome_bad no-gates-conf"
[ -f "$F/.harness/hooks/guard-project-policy.sh" ] || rehome_bad="$rehome_bad no-policy-hook"
grep -qxF '.harness/var/' "$F/.gitignore" || rehome_bad="$rehome_bad gitignore-not-narrowed"
if grep -qxF '.harness/' "$F/.gitignore"; then rehome_bad="$rehome_bad broad-ignore-left"; fi
if [ -z "$rehome_bad" ]; then
    pass "v0.23.0 re-home: manifest migrated, old flat layout removed, new tree + policy installed, gitignore narrowed"
else
    fail "v0.23.0 re-home: migration incomplete —$rehome_bad" "$out"
fi
repin "$F"
leftover=$(awk '$2 ~ /^scripts\/(hooks\/|[^\/]+\.sh$)/ {print $2}' "$F/scripts/harness/.harness-manifest")
if [ -z "$leftover" ]; then
    pass "v0.23.0 re-home: repin leaves no pins for the old flat layout"
else
    fail "v0.23.0 re-home: stale flat-layout pins survive repin" "$leftover"
fi
rm -rf "$F"

# --- (m) v0.24.0 -> v0.25.0: capability table + derivation lib land; a legacy
#         four-list harness.conf is preserved as overrides ---------------------
# v0.25.0 adds scripts/harness/lib/provider-caps + provider-lib.sh (mechanism)
# and collapses the four provider lists to one HARNESS_PROVIDERS. harness.conf
# is policy (diff-only), so a v0.24.0 install keeps its explicit four lists,
# which still validate as overrides. Update must install the two new mechanism
# files and leave the legacy conf untouched.
F=$(mktemp -d "$WORK/v0240.XXXXXX") || exit 1
( cd "${F:?}" && git init -q . )
printf '.harness/var/\n' > "$F/.gitignore"
mkdir -p "$F/scripts/harness/lib"
printf '# harness-kit 0.24.0\n' > "$F/scripts/harness/.harness-manifest"
cat > "$F/scripts/harness/harness.conf" <<'CONF'
PROVIDERS=".claude .cursor .opencode"
HOOK_WIRED_PROVIDERS=".claude .cursor .codex"
AGENT_PROVIDERS=".claude .cursor .codex .opencode"
CANONICAL_SKILLS=".agents/skills"
CANONICAL_AGENTS=".harness/agents"
CONF
out=$(harness_update_apply "$SCRIPTS_DIR" "$F")
v25_bad=""
[ -f "$F/scripts/harness/lib/provider-caps" ]   || v25_bad="$v25_bad no-provider-caps"
[ -f "$F/scripts/harness/lib/provider-lib.sh" ] || v25_bad="$v25_bad no-provider-lib"
conf=$(cat "$F/scripts/harness/harness.conf")
has_line "$conf" 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"' || v25_bad="$v25_bad hook-list-clobbered"
has_line "$conf" 'AGENT_PROVIDERS=".claude .cursor .codex .opencode"' || v25_bad="$v25_bad agent-list-clobbered"
if [ -z "$v25_bad" ]; then
    pass "v0.25.0 provider decl: caps table + derivation lib installed, legacy four-list harness.conf preserved as overrides"
else
    fail "v0.25.0 provider decl: update incomplete —$v25_bad" "$out"
fi
rm -rf "$F"

# --- (n) failure path: a failed copy aborts non-zero BEFORE the destructive
# retire pass ------------------------------------------------------------------
# harness_update_apply must never re-pin a partial upgrade as a success: a copy
# failure returns non-zero, and because retirement is deferred to the LAST pass,
# the destructive rm never runs on a failed upgrade. Failure is injected WITHOUT
# file permissions (root-independent, deterministic): a new shipped file's
# parent dir is pre-occupied by a regular FILE in the target, so the add pass's
# `mkdir -p` fails. A pristine retirement is also pending, so we prove it stays.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
mkdir -p "$NEWKIT/scripts/harness/blocked"
printf '#!/usr/bin/env bash\necho blocked\n' > "$NEWKIT/scripts/harness/blocked/newmech.sh"
printf 'mechanism scripts/harness/blocked/newmech.sh\n' >> "$NEWKIT/scripts/harness/kit-manifest"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
# Occupy the add path's parent with a regular file so its `mkdir -p` fails.
printf 'not a dir\n' > "$F/scripts/harness/blocked"
out=$(
    # shellcheck source=/dev/null
    . "$NEWKIT/scripts/harness/lib/install-lib.sh"
    harness_update_apply "$NEWKIT/scripts" "$F"
); rc=$?
if [ "$rc" -ne 0 ]; then
    pass "cp-failure: a failed copy makes harness_update_apply return non-zero (no false-green upgrade)"
else
    fail "cp-failure: update_apply returned 0 despite a failed copy" "$out"
fi
if [ -f "$F/scripts/harness/tests/test-log.sh" ] && ! has_line "$out" "remove scripts/harness/tests/test-log.sh"; then
    pass "cp-failure: retire-last leaves the pending retirement intact when a copy fails"
else
    fail "cp-failure: a pending retirement was removed despite the failed copy" "$out"
fi
rm -rf "$F" "$NEWKIT"

# --- (o) --dry-run: the plan IS apply's decision table, with zero mutation ----
# One code path computes both (the dry-run flag only suppresses the
# mutations), so the plan can never diverge from what apply would do — the
# check-vs-mutate divergence class. The dry run must report the pending
# replace/add/remove and leave the tree byte-identical.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/harness/sync"
printf '#!/usr/bin/env bash\necho new\n' > "$NEWKIT/scripts/harness/tests/test-brandnew.sh"
printf 'mechanism scripts/harness/tests/test-brandnew.sh\n' >> "$NEWKIT/scripts/harness/kit-manifest"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
sync_sha_before=$(sha_of "$F" "scripts/harness/sync")
out=$(harness_update_apply "$NEWKIT/scripts" "$F" --dry-run); rc=$?
dirty=$( cd "${F:?}" && git status --porcelain )
if [ "$rc" -eq 0 ] \
        && has_line "$out" "replace scripts/harness/sync" \
        && has_line "$out" "add scripts/harness/tests/test-brandnew.sh" \
        && has_line "$out" "remove scripts/harness/tests/test-log.sh"; then
    pass "dry-run: reports the pending replace/add/remove plan"
else
    fail "dry-run: plan incomplete (rc=$rc)" "$out"
fi
if [ -z "$dirty" ] && [ "$(sha_of "$F" "scripts/harness/sync")" = "$sync_sha_before" ] \
        && [ -f "$F/scripts/harness/tests/test-log.sh" ] \
        && [ ! -f "$F/scripts/harness/tests/test-brandnew.sh" ]; then
    pass "dry-run: mutates nothing (clean tree, pending retirement kept, no add)"
else
    fail "dry-run: the tree changed" "$dirty"
fi
rm -rf "$F" "$NEWKIT"

# --- (p) staged replace: a read-only dest dir refuses cleanly, never tears ----
# The pre-staging failure mode: `cp src dest` O_TRUNCs a writable FILE even
# inside a read-only DIR, so a failing update could tear the destination in
# place (a torn mechanism file reads as local drift forever after). Staging
# beside the destination makes the same situation refuse up front: the stage
# file cannot be created, the original stays byte-identical, no stage litter
# is left, and the destructive retire pass never runs.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/harness/sync"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
sync_sha_before=$(sha_of "$F" "scripts/harness/sync")
chmod a-w "$F/scripts/harness"
out=$(harness_update_apply "$NEWKIT/scripts" "$F" 2>&1); rc=$?
chmod u+w "$F/scripts/harness"
stage_litter=$(find "$F" -name '.hk-stage.*' 2>/dev/null)
if [ "$rc" -ne 0 ] && [ "$(sha_of "$F" "scripts/harness/sync")" = "$sync_sha_before" ] \
        && [ -z "$stage_litter" ] && [ -f "$F/scripts/harness/tests/test-log.sh" ]; then
    pass "staged replace: read-only dest dir refuses non-zero; original intact, no litter, retire-last held"
else
    fail "staged replace: in-place write, stage litter, or the destructive pass ran (rc=$rc)" "$out"
fi
rm -rf "$F" "$NEWKIT"

# --- (q) symlinked destination: replace refuses to write through a link -------
# A link planted at a pinned mechanism path reads through to content that
# still matches the pin, so the decision says 'replace'; the copy layer must
# refuse (writing would land OUTSIDE the tree the ship contract names), the
# link target must stay untouched, and the destructive retire pass must not
# run on the failed upgrade.
F=$(make_fixture) || exit 1
NEWKIT=$(mktemp -d "$WORK/newkit.XXXXXX") || exit 1; cp -R "$SCRIPTS_DIR" "$NEWKIT/scripts"
printf '\n# UPGRADED\n' >> "$NEWKIT/scripts/harness/sync"
retire_in_newkit "$NEWKIT/scripts" "scripts/harness/tests/test-log.sh"
LINKTARGET=$(mktemp -d "$WORK/linktarget.XXXXXX") || exit 1
cp "$F/scripts/harness/sync" "$LINKTARGET/real-sync"
victim_sha=$( cd "$LINKTARGET" && _harness_sha256 real-sync | awk '{print $1}' )
rm "$F/scripts/harness/sync"
ln -s "$LINKTARGET/real-sync" "$F/scripts/harness/sync"
out=$(harness_update_apply "$NEWKIT/scripts" "$F" 2>&1); rc=$?
after_sha=$( cd "$LINKTARGET" && _harness_sha256 real-sync | awk '{print $1}' )
if [ "$rc" -ne 0 ] && [ "$after_sha" = "$victim_sha" ] && [ -L "$F/scripts/harness/sync" ] \
        && [ -f "$F/scripts/harness/tests/test-log.sh" ]; then
    pass "symlinked dest: replace refuses, the link target is untouched, retire-last held"
else
    fail "symlinked dest: wrote through a symlink or ran the destructive pass (rc=$rc)" "$out"
fi
rm -rf "$F" "$NEWKIT" "$LINKTARGET"

finish "install-update"
