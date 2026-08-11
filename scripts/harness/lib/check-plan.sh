#!/usr/bin/env bash
# check-plan.sh — the "plan" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/validate-plan. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

_plan_valid_date() {
    printf '%s\n' "$1" | awk -F- '
      /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
        y=$1+0; m=$2+0; d=$3+0
        md[1]=31; md[2]=28; md[3]=31; md[4]=30; md[5]=31; md[6]=30
        md[7]=31; md[8]=31; md[9]=30; md[10]=31; md[11]=30; md[12]=31
        if ((y%4==0 && y%100!=0) || y%400==0) md[2]=29
        if (m>=1 && m<=12 && d>=1 && d<=md[m]) ok=1
      }
      END { exit(ok ? 0 : 1) }'
}

# New plans carry a fixed six-line lifecycle header. Legacy plans and plans with
# unrelated Markdown frontmatter remain valid and simply cannot contribute
# cycle metrics; only a frontmatter block that contains `harness_plan:` opts in.
# A partial or malformed opted-in header is an error because silently guessing
# dates would corrupt the audit. Directory and status must agree.
for plan in "$ROOT"/docs/plans/*.md "$ROOT"/docs/plans/active/*.md "$ROOT"/docs/plans/completed/*.md; do
    [ -f "$plan" ] || continue
    case "$(basename "$plan")" in README.md|PLANS.md) continue ;; esac
    [ "$(sed -n '1p' "$plan")" = "---" ] || continue
    awk 'NR==1 {next} /^---$/ {exit} /^harness_plan:/ {found=1} END {exit(found ? 0 : 1)}' "$plan" \
        || continue
    plan_rel=${plan#"$ROOT"/}
    harness_plan=$(sed -n '2s/^harness_plan: //p' "$plan")
    status=$(sed -n '3s/^status: //p' "$plan")
    started=$(sed -n '4s/^started: //p' "$plan")
    completed=$(sed -n '5s/^completed: //p' "$plan")
    closing=$(sed -n '6p' "$plan")
    if [ "$harness_plan" != 1 ] || [ "$closing" != "---" ] \
        || [ -z "$status" ] || [ -z "$started" ] || [ -z "$completed" ]; then
        echo "ERROR: $plan_rel has malformed lifecycle metadata — copy the exact six-line header from .harness/templates/execution-plan.md"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    case "$plan_rel" in
        docs/plans/active/*) expected=active ;;
        docs/plans/completed/*) expected=completed ;;
        docs/plans/*) expected=queued ;;
    esac
    if [ "$status" != "$expected" ]; then
        echo "ERROR: $plan_rel lifecycle status is '$status' but its directory requires '$expected'"
        ERRORS=$((ERRORS + 1))
    fi
    for date_field in started completed; do
        case "$date_field" in started) date_value=$started ;; completed) date_value=$completed ;; esac
        case "$date_value" in
            null) ;;
            ????-??-??) _plan_valid_date "$date_value" || {
                echo "ERROR: $plan_rel $date_field must be null or a real YYYY-MM-DD date"
                ERRORS=$((ERRORS + 1))
            } ;;
            *)
                echo "ERROR: $plan_rel $date_field must be null or a real YYYY-MM-DD date"
                ERRORS=$((ERRORS + 1)) ;;
        esac
    done
    case "$status" in
        queued)
            if [ "$started" != null ] || [ "$completed" != null ]; then
                echo "ERROR: $plan_rel queued lifecycle dates must both be null"
                ERRORS=$((ERRORS + 1))
            fi ;;
        active)
            if [ "$started" = null ] || [ "$completed" != null ]; then
                echo "ERROR: $plan_rel active lifecycle requires a started date and completed: null"
                ERRORS=$((ERRORS + 1))
            fi ;;
        completed)
            if [ "$started" = null ] || [ "$completed" = null ]; then
                echo "ERROR: $plan_rel completed lifecycle requires both dates"
                ERRORS=$((ERRORS + 1))
            elif [[ "$completed" < "$started" ]]; then
                echo "ERROR: $plan_rel completion date precedes its start date"
                ERRORS=$((ERRORS + 1))
            fi ;;
        *)
            echo "ERROR: $plan_rel lifecycle status must be queued, active, or completed"
            ERRORS=$((ERRORS + 1)) ;;
    esac
done

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
