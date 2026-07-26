#!/usr/bin/env bash
# Regression tests for THIS repo's tailored stop-hook policy
# (.harness/hooks/guard-project-policy.sh, TAILOR block: shipped-mechanism
# discipline). Root-only and maintainer-only by necessity, not preference: the
# shipped test-guard-project-policy.sh resolves whichever guard-project-policy
# .sh the checkout provides and therefore runs against an ADOPTER's tailored
# hook in an adopter repo, where this repo's mechanism-template rule does not
# exist at all (the shipped template is a no-op skeleton with a commented
# example). Asserting that rule there would fail in every install. So the
# shipped suite keeps the mechanism-level properties (lib.sh sourcing,
# clean-tree skip) and this suite owns the dogfood policy content.
#
# What it pins: the trigger stays SCOPED to the mechanism templates while the
# search for the accompanying regression test spans the WHOLE tree — the fix
# for a false positive that fired on every install-lib.sh/check-doctor.sh
# change, both of which are covered only by the root maintainer suites.
set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GPP="$ROOT/.harness/hooks/guard-project-policy.sh"
[ -f "$GPP" ] || { echo "FAIL: $GPP not found"; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-project-policy.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0

TPL_REL="plugins/harness-kit/skills/harness-kit/templates/scripts"
MECH="$TPL_REL/harness/lib/mech.sh"
TPL_TEST="$TPL_REL/harness/tests/test-shipped-thing.sh"

# new_repo -> a fixture repo with the hook installed, a committed mechanism
# template, a root maintainer suite, a template-side test, an unrelated root
# file, and a VERSION — all clean at HEAD. Each case dirties one combination.
# The stub lib.sh prints the advisory text so the assertions can read it; the
# fixture ships no scripts/harness/verify, so the hook's advisory-verify arm
# is inert here (it has its own coverage in the shipped suite).
new_repo() {
    local w
    w=$(mktemp -d "$WORK/repo.XXXXXX") || return 1
    mkdir -p "$w/scripts/harness/hooks" "$w/.harness/hooks" \
             "$w/$TPL_REL/harness/lib" "$w/$TPL_REL/harness/tests" \
             "$w/plugins/harness-kit" "$w/docs" || return 1
    cat > "$w/scripts/harness/hooks/lib.sh" <<'LIB'
hook_read_input()     { cat >/dev/null 2>&1 || :; }
hook_advise_once()    { printf '%s\n' "$1"; }
hook_log()            { :; }
hook_deny()           { :; }
hook_affected_files() { :; }
hook_command_string() { :; }
LIB
    cp "$GPP" "$w/.harness/hooks/guard-project-policy.sh" || return 1
    chmod +x "$w/.harness/hooks/guard-project-policy.sh" || return 1
    printf '# mechanism\n' > "$w/$MECH"
    printf '# shipped test\n' > "$w/$TPL_TEST"
    printf '# root maintainer suite\n' > "$w/scripts/test-root-suite.sh"
    printf 'notes\n' > "$w/docs/notes.md"
    printf '0.34.0\n' > "$w/plugins/harness-kit/VERSION"
    ( cd "$w" && git init -q . && git config user.email t@e.invalid \
        && git config user.name t && git add -A && git commit -q -m seed ) || return 1
    printf '%s' "$w"
}

run_hook() { ( cd "$1" && printf '{}' | ./.harness/hooks/guard-project-policy.sh 2>&1 ); }

# assert_warns_no_test <name> <repo>   -- the regression-test warning fires
# assert_silent_no_test <name> <repo>  -- it does not
_assert() {
    local want="$1" name="$2" repo="$3" out got
    out=$(run_hook "$repo")
    case "$out" in *"no regression test"*) got=warns ;; *) got=silent ;; esac
    if [ "$got" = "$want" ]; then
        echo "ok:   $name"
    else
        echo "FAIL: $name (expected $want, got $got)"
        printf '%s\n' "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}
assert_warns_no_test()  { _assert warns "$1" "$2"; }
assert_silent_no_test() { _assert silent "$1" "$2"; }

# --- (a) mechanism change + a ROOT maintainer suite -> silent -----------------
# The false positive this suite exists for. install-lib.sh and check-doctor.sh
# are covered by scripts/test-install-core.sh and scripts/test-check-harness.sh
# respectively; neither has a shipped test, so a $TPL-scoped search declared
# every fully-tested change untested.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
printf '# case added\n' >> "$R/scripts/test-root-suite.sh"
assert_silent_no_test "mechanism change accompanied by a root maintainer suite does not warn" "$R"

# --- (b) mechanism change alone -> warns --------------------------------------
# The rule still has teeth: widening WHERE a test may live must not weaken
# WHETHER one is required.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
assert_warns_no_test "mechanism change with no test touched anywhere still warns" "$R"

# --- (c) mechanism change + an unrelated non-test file -> warns ---------------
# Guards the widening against collapsing into "did anything else change" — the
# obvious way to over-correct a false positive into a useless check.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
printf 'more\n' >> "$R/docs/notes.md"
assert_warns_no_test "mechanism change plus an unrelated non-test file still warns" "$R"

# --- (d) mechanism change + a test INSIDE the template tree -> silent ---------
# The original behavior, unchanged: a shipped test next to the mechanism it
# covers is still the primary answer, not a legacy path.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
printf '# case added\n' >> "$R/$TPL_TEST"
assert_silent_no_test "mechanism change accompanied by a shipped template test does not warn" "$R"

# --- (e) no mechanism change -> silent even with a test touched ---------------
# The TRIGGER stays scoped to $TPL: editing tests alone is not a policy event.
R=$(new_repo) || exit 1
printf '# case added\n' >> "$R/scripts/test-root-suite.sh"
assert_silent_no_test "a root-suite edit with no mechanism change is not a policy event" "$R"

# --- (g) DELETING a test is not writing one -----------------------------------
# `git rm` leaves the path in porcelain output, so a plain filename match
# counted removing coverage as adding it -- the policy's easiest false pass.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
( cd "$R" && git rm -q scripts/test-root-suite.sh )
assert_warns_no_test "deleting a test does not satisfy the policy" "$R"

# --- (h) the match is anchored to a path component ----------------------------
# scripts/contest-policy.sh merely ENDS with "test-policy.sh"; an unanchored
# match accepted it as a regression test.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
printf '# not a test\n' > "$R/scripts/contest-policy.sh"
assert_warns_no_test "a file whose name merely ends with 'test-*.sh' does not satisfy the policy" "$R"

# --- (i) a large status list must not invert the check (SIGPIPE) --------------
# `grep -q` exits at its first match, SIGPIPEing the upstream printf; with
# `set -o pipefail` (which this hook sets) the pipeline then reports failure
# and the `!` inverts the condition, so the hook warns precisely BECAUSE it
# found a test. It needs two things to bite: SIGPIPE ignored in the hook's
# process (inherited here via `trap "" PIPE`, the technique this repo already
# documents) and more than a pipe buffer of output after the match -- hence
# the filler files, and the matching test named so it sorts first.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
mkdir -p "$R/a-early" "$R/zzz"
printf '# a real test\n' > "$R/a-early/test-early.sh"
( cd "$R/zzz" && seq -f 'filler-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-%04g.txt' 1 3000 | xargs touch )
out=$( trap '' PIPE; run_hook "$R" )
case "$out" in
    *"no regression test"*)
        echo "FAIL: a large status list inverted the test search (SIGPIPE under pipefail) -- warned despite finding a-early/test-early.sh"
        fails=$((fails + 1)) ;;
    *) echo "ok:   a large status list does not invert the test search (no SIGPIPE inversion)" ;;
esac

# --- (f) the sibling version rule is undisturbed -------------------------------
# Both rules live in the same `if [ -n "$changed" ]` block that this fix
# restructured; a bumped VERSION must still silence the version warning while
# an unbumped one still fires it.
R=$(new_repo) || exit 1
printf '# changed\n' >> "$R/$MECH"
printf '# case added\n' >> "$R/scripts/test-root-suite.sh"
out=$(run_hook "$R")
case "$out" in
    *"version is still 0.34.0"*) echo "ok:   an unbumped VERSION still warns alongside a mechanism change" ;;
    *) echo "FAIL: version warning did not fire for an unbumped VERSION"
       printf '%s\n' "$out" | sed 's/^/        /'; fails=$((fails + 1)) ;;
esac
printf '0.35.0\n' > "$R/plugins/harness-kit/VERSION"
out=$(run_hook "$R")
case "$out" in
    *"version is still"*) echo "FAIL: version warning fired despite a bumped VERSION"
       printf '%s\n' "$out" | sed 's/^/        /'; fails=$((fails + 1)) ;;
    *) echo "ok:   a bumped VERSION silences the version warning" ;;
esac

if [ "$fails" -eq 0 ]; then
    echo "PASSED: all project-policy cases"
else
    echo "FAILED: $fails project-policy case(s)"
    exit 1
fi
