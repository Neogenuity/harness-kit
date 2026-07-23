#!/usr/bin/env bash
# check-plan.sh — the "plan" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/validate-plan. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

# 10b. Doctor: active plans that have gone stale. A plan in PLANS_DIR that has
#      lost its 'Next action', or hasn't been touched in a month, is usually
#      abandoned — yet the session banner keeps announcing it. Age uses git
#      commit time (file mtime is checkout time), so it needs a real history:
#      it is a no-op in the shallow checkout the shipped CI uses
#      (actions/checkout defaults to fetch-depth 1) and skips gracefully with
#      no git at all — effective in local doctor runs.
PLANS_DIR="${PLANS_DIR:-docs/plans/active}"
PLAN_STALE_DAYS="${HARNESS_PLAN_STALE_DAYS:-30}"
if [ -d "$ROOT/$PLANS_DIR" ]; then
    _now=$(date +%s)
    for plan in "$ROOT/$PLANS_DIR"/*.md; do
        [ -f "$plan" ] || continue
        case "$(basename "$plan")" in README.md) continue ;; esac
        plan_rel=${plan#"$ROOT"/}
        grep -qE '^#+[[:space:]]+Next action' "$plan" \
            || echo "WARNING: $plan_rel (active plan) has no 'Next action' section — a resuming session can't tell what to do next"
        if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
            _ct=$(git -C "$ROOT" log -1 --format=%ct -- "$plan_rel" 2>/dev/null)
            if [ -n "$_ct" ]; then
                _age=$(( (_now - _ct) / 86400 ))
                [ "$_age" -ge "$PLAN_STALE_DAYS" ] \
                    && echo "WARNING: $plan_rel (active plan) last changed $_age days ago (>= $PLAN_STALE_DAYS) — update it or move it to completed/"
            fi
        fi
    done
fi


check_trailer "plan"
