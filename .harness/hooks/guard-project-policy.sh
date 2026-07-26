#!/usr/bin/env bash
# Agent hook (advisory, runs on agent stop): warn when newly added files break
# a project invariant that docs alone can't get agents to respect — the one
# rule that, when missed, costs a review cycle every time.
#
# Tailored for THIS repo (harness-kit): the invariant is shipped-mechanism
# discipline. When a mechanism template under plugins/harness-kit/.../templates/scripts/
# changes in the working tree, warn unless a regression test was touched too
# and the plugin version was bumped vs HEAD. Uses `git status --porcelain
# -uall` so a brand-new untracked directory expands to its individual files.
#
# Keep it advisory: hook_advise_once surfaces the warnings to the agent
# exactly once (Claude Code `decision:block`, Cursor `followup_message`; the
# loop guards make the second stop succeed), so the run is never hard-blocked.
# The enforcing gate belongs in tests or CI, not here.
set -uo pipefail

. "$(dirname "$0")/../../scripts/harness/hooks/lib.sh" 2>/dev/null || exit 0

hook_read_input
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 0
command -v git >/dev/null 2>&1 || exit 0

warnings=""
append() { warnings="${warnings}$1"$'\n'; }

# -- TAILOR: project invariant checks over newly added files ------------------
# This repo IS the kit: the invariant is shipped-mechanism discipline. Any
# change to the mechanism templates that ship inside the plugin must carry a
# regression test, and must not reach a release without a version bump.
# See docs/standards/templates.md.
TPL="plugins/harness-kit/skills/harness-kit/templates/scripts"
# -uall expands a brand-new untracked directory to its individual files (plain
# --porcelain collapses it to one "dir/" entry, so a test added inside it
# would be missed). Strip the XY status prefix and any "orig -> " rename arrow
# to leave bare paths (mechanism scripts are space-free).
changed=$(git status --porcelain -uall -- "$TPL" 2>/dev/null \
    | sed -e 's/^...//' -e 's/.* -> //')
if [ -n "$changed" ]; then
    # The TRIGGER is scoped to $TPL; the search for the accompanying test is
    # NOT -- it spans the whole working tree. Several shipped mechanism
    # libraries are, by settled convention, covered only by the maintainer
    # suites at the repo root: scripts/test-install-core.sh owns
    # templates/.../lib/install-lib.sh, scripts/test-check-harness.sh owns
    # templates/.../lib/check-doctor.sh. Neither has a shipped test under
    # templates/.../harness/tests/, and v0.29.0 descoped the adopter floor
    # deliberately, so demanding one there just to satisfy this hook would
    # reverse that decision. Searching only $TPL warned on every such change
    # even when it shipped with full regression coverage -- a policy signal
    # that fires on correct work is one the maintainer learns to ignore.
    # Computed here rather than beside $changed so a stop with no mechanism
    # change pays no second git call.
    # Three things this pipeline is careful about, each a real way to satisfy
    # the policy without adding coverage:
    #   - DELETED paths are dropped. `git rm` of a test file still lists that
    #     path in porcelain output, so a plain match counted removing a test
    #     as writing one.
    #   - the match is anchored to a path COMPONENT ((^|/)), so a file whose
    #     name merely ENDS with a test-like suffix -- "contest-policy.sh",
    #     which ends in "test-policy.sh" -- no longer passes as a test.
    #   - grep -c, never grep -q. -q exits at the first match and SIGPIPEs the
    #     upstream printf; under `set -o pipefail` (line 16) that makes the
    #     whole pipeline false and INVERTS this condition, warning precisely
    #     when a test was found. -c consumes all input, so it cannot. The same
    #     hazard is documented in scripts/harness/lib/check-drift.sh.
    touched=$(git status --porcelain -uall 2>/dev/null \
        | grep -vE '^(D|.D)' \
        | sed -e 's/^...//' -e 's/.* -> //')
    tests_touched=$(printf '%s\n' "$touched" | grep -cE '(^|/)test-[^/]*\.sh$')
    if [ "${tests_touched:-0}" -eq 0 ]; then
        append "POLICY WARNING: shipped mechanism templates changed ($(printf '%s' "$changed" | tr '\n' ' ')) but no regression test (test-*.sh) was touched. Every guard/mechanism change ships with a test — see docs/standards/templates.md."
    fi
    # Compare the actual version VALUE against HEAD, not just "did the file
    # change" (a rename or a description-only edit would fool that). Fail safe:
    # if either value is unreadable (no jq, or the file is new-at-path mid-move)
    # stay silent rather than warn wrongly.
    cur_ver=$(cat plugins/harness-kit/VERSION 2>/dev/null | tr -d '[:space:]')
    head_ver=$(git show HEAD:plugins/harness-kit/VERSION 2>/dev/null | tr -d '[:space:]')
    if [ -n "$cur_ver" ] && [ -n "$head_ver" ] && [ "$cur_ver" = "$head_ver" ]; then
        append "POLICY WARNING: shipped mechanism templates changed but the version is still $cur_ver. Bump plugins/harness-kit/VERSION (and both plugin.json versions) before release — see .agents/skills/release/SKILL.md."
    fi
fi

# Advisory verification: fast gates only — the full suite belongs in CI. Skip
# it on a clean working tree (nothing uncommitted can newly fail them; saves
# ~4s on every stop — the audit measured 0 useful fires across 54 clean stops).
if [ -x scripts/harness/verify ] && [ -n "$(git status --porcelain 2>/dev/null)" ] \
        && ! out=$(bash scripts/harness/verify --fast 2>&1); then
    append "VERIFY WARNING: fast quality gates are failing:"
    append "$out"
    append "Fix, then run 'bash scripts/harness/verify' before finishing."
fi
# ------------------------------------------------------------------------------

[ -n "$warnings" ] || exit 0
hook_advise_once "$warnings"
