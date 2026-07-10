#!/usr/bin/env bash
# Agent hook (advisory, runs on agent stop): warn when newly added files break
# a project invariant that docs alone can't get agents to respect — the one
# rule that, when missed, costs a review cycle every time.
#
# Tailored for THIS repo (harness-kit): the invariant is shipped-mechanism
# discipline. When a mechanism template under plugin/.../templates/scripts/
# changes in the working tree, warn unless a regression test was touched too
# and the plugin version was bumped vs HEAD. Uses `git status --porcelain
# -uall` so a brand-new untracked directory expands to its individual files.
#
# Keep it advisory: hook_advise_once surfaces the warnings to the agent
# exactly once (Claude Code `decision:block`, Cursor `followup_message`; the
# loop guards make the second stop succeed), so the run is never hard-blocked.
# The enforcing gate belongs in tests or CI, not here.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0

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
# See docs/conventions/templates.md.
TPL="plugin/skills/harness-kit/templates/scripts"
# -uall expands a brand-new untracked directory to its individual files (plain
# --porcelain collapses it to one "dir/" entry, so a test added inside it
# would be missed). Strip the XY status prefix and any "orig -> " rename arrow
# to leave bare paths (mechanism scripts are space-free).
changed=$(git status --porcelain -uall -- "$TPL" 2>/dev/null \
    | sed -e 's/^...//' -e 's/.* -> //')
if [ -n "$changed" ]; then
    if ! printf '%s\n' "$changed" | grep -q 'test-[^/]*\.sh$'; then
        append "POLICY WARNING: shipped mechanism templates changed ($(printf '%s' "$changed" | tr '\n' ' ')) but no regression test (test-*.sh) was touched. Every guard/mechanism change ships with a test — see docs/conventions/templates.md."
    fi
    # Compare the actual version VALUE against HEAD, not just "did the file
    # change" (a rename or a description-only edit would fool that). Fail safe:
    # if either value is unreadable (no jq, or the file is new-at-path mid-move)
    # stay silent rather than warn wrongly.
    cur_ver=$(jq -r '.version // empty' plugin/.claude-plugin/plugin.json 2>/dev/null)
    head_ver=$(git show HEAD:plugin/.claude-plugin/plugin.json 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
    if [ -n "$cur_ver" ] && [ -n "$head_ver" ] && [ "$cur_ver" = "$head_ver" ]; then
        append "POLICY WARNING: shipped mechanism templates changed but the plugin version is still $cur_ver. Bump plugin/.claude-plugin/plugin.json before release — see docs/skills/release/SKILL.md."
    fi
fi

# Advisory verification: fast gates only — the full suite belongs in CI.
if [ -x scripts/verify.sh ] && ! out=$(bash scripts/verify.sh --fast 2>&1); then
    append "VERIFY WARNING: fast quality gates are failing:"
    append "$out"
    append "Fix, then run 'bash scripts/verify.sh' before finishing."
fi
# ------------------------------------------------------------------------------

[ -n "$warnings" ] || exit 0
hook_advise_once "$warnings"
