#!/usr/bin/env bash
# check-doctor.sh — the "doctor" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/check-harness. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

# 10. Doctor: conditions that silently weaken the harness. Warnings only —
#     they don't fail the build, they tell you where the floor is soft.
command -v jq >/dev/null 2>&1 \
    || echo "WARNING: jq not found — every guard hook fails open without it; the native permission deny lists are the only live layer"
if [ -f "$ROOT/AGENTS.md" ]; then
    agents_lines=$(wc -l < "$ROOT/AGENTS.md" | tr -d '[:space:]')
    [ "$agents_lines" -gt 120 ] \
        && echo "WARNING: AGENTS.md is $agents_lines lines (target <=120) — it should route to docs/, not explain; instruction compliance degrades as it grows"
fi
for skill in "$ROOT/$CANONICAL_SKILLS"/*/SKILL.md; do
    [ -f "$skill" ] || continue
    skill_rel=${skill#"$ROOT"/}
    skill_lines=$(wc -l < "$skill" | tr -d '[:space:]')
    [ "$skill_lines" -gt 500 ] \
        && echo "WARNING: $skill_rel is $skill_lines lines (target <=500) — move detail into the skill's references/ (progressive disclosure)"
done
# (Skill name/description spec conformance — kebab-case, length, non-empty,
#  name==dir — is now enforced as ERRORs in check 1, not warned here.)


# 10d. Doctor: CI workflow actions should be pinned to an immutable commit SHA.
#      A `uses:` ref pointing at a tag or branch is mutable — a retagged or
#      compromised third-party action would run with the workflow's token, the
#      supply-chain exposure the shipped-CI hardening closes. Local `uses: ./path`
#      composite actions are first-party and skipped, as are `docker://` refs
#      (a different pinning model). Freshness/hygiene WARNING like the other
#      doctor checks — it never fails the build. Best-effort line scan; full
#      YAML parsing is out of scope.
if [ -d "$ROOT/.github/workflows" ]; then
    for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
        [ -f "$wf" ] || continue
        wf_rel=${wf#"$ROOT"/}
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            case "$ref" in
                ./*|docker://*) continue ;;
            esac
            # ${ref##*@} is the pin (the whole ref when there is no '@' — an
            # unpinned owner/repo is mutable too). A full commit SHA is 40 hex.
            if ! printf '%s' "${ref##*@}" | grep -qE '^[0-9a-fA-F]{40}$'; then
                echo "WARNING: $wf_rel uses '$ref' pinned to a mutable ref — pin third-party actions to a full 40-char commit SHA (a tag or branch can be moved under you); keep the human-readable tag in a trailing comment"
            fi
        done < <(grep -oE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$wf" 2>/dev/null \
                    | sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//' \
                    | tr -d "\"'")
    done
fi


check_trailer "doctor"
