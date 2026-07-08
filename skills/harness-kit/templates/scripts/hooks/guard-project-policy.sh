#!/usr/bin/env bash
# Agent hook (advisory, runs on agent stop): warn when newly added files break
# a project invariant that docs alone can't get agents to respect — the one
# rule that, when missed, costs a review cycle every time.
#
# Ships as a no-op skeleton. Add checks in the TAILOR block; each check scans
# files added in the working tree (vs HEAD, including brand-new untracked
# directories via hook_new_files) and appends a warning naming the file and
# the convention doc that explains the fix.
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
# Example (Laravel multi-tenancy — new models must opt in to tenant scoping):
#
# while IFS= read -r file; do
#     [ -f "$file" ] || continue
#     if ! grep -qE 'TenantOwnedModel|IntentionallyUnscopedTenantModel' "$file"; then
#         append "POLICY WARNING: new model '$file' does not extend TenantOwnedModel (or implement IntentionallyUnscopedTenantModel). See docs/conventions/multi-tenancy.md."
#     fi
# done < <(hook_new_files '^modules/[^/]+/src/Domain/Models/.+\.php$')
#
# Close with a pointer to the enforcing gate, e.g.:
# [ -n "$warnings" ] && append "Run the architecture test suite to verify before finishing."
# ------------------------------------------------------------------------------

[ -n "$warnings" ] || exit 0
hook_advise_once "$warnings"
