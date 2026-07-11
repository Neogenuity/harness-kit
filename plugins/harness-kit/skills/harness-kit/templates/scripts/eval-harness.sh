#!/usr/bin/env bash
# eval-harness.sh — the regression view over eval.sh's results. Reads the
# per-trial JSON lines, computes pass@k / pass^k / pass-rate per
# (task, provider, model) from the *latest* run of each, compares against the
# recorded baseline (docs/evals/baselines.json), and reports deltas.
#
# Regression-suite tasks are expected at pass^k = 1 (correct on every trial);
# a drop below that exits non-zero (loud — regressions must not pass silently).
# Capability-suite tasks are informational: they legitimately sit below 100%,
# so a lower rate is reported, not failed. This is never a per-PR gate — a full
# run costs real model calls; run it on a schedule (see the CI template comment
# below) or by hand after a harness change.
#
#   bash scripts/eval-harness.sh                 # score latest results vs baseline
#   bash scripts/eval-harness.sh --update-baseline   # record current as the new baseline
#     --results-dir DIR   default .harness/eval-results
#     --baseline FILE     default docs/evals/baselines.json
#     --no-fail           report regressions but exit 0 (for dashboards)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/eval-lib.sh"

die() { echo "eval-harness.sh: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq is required."

RESULTS_DIR="$EVAL_RESULTS_DIR_DEFAULT"; BASELINE="$EVAL_BASELINE_DEFAULT"
UPDATE=0; FAIL_ON_REGRESSION=1
while [ $# -gt 0 ]; do
    case "$1" in
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        --update-baseline) UPDATE=1; shift ;;
        --no-fail) FAIL_ON_REGRESSION=0; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -d "$RESULTS_DIR" ] || die "no results dir at $RESULTS_DIR — run scripts/eval.sh first"
# -exec cat {} + streams the files by argv (no word-splitting on paths with
# spaces, unlike `cat $(find ...)`); the count guards "no results" cleanly.
RESULT_COUNT=$(find "$RESULTS_DIR" -name results.jsonl -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$RESULT_COUNT" -gt 0 ] || die "no results.jsonl under $RESULTS_DIR — run scripts/eval.sh first"

# Aggregate: one row per (task,provider,model), using only the latest run's
# trials. Emits compact JSON objects (one per line). A jq failure (malformed or
# truncated results) must abort loudly — an empty aggregate would otherwise
# print a misleading "ok" and mask a regression.
if ! AGG=$(find "$RESULTS_DIR" -name results.jsonl -type f -exec cat {} + | jq -c -s '
      group_by([.task,.provider,.model])
      | map(
          . as $g
          | ($g | map(.run) | max) as $latest
          | ($g | map(select(.run==$latest))) as $t
          | ($t | map(select(.pass)) | length) as $passes
          | ($t | length) as $trials
          | { task:$t[0].task, provider:$t[0].provider, model:$t[0].model,
              suite:$t[0].suite, polarity:$t[0].polarity, run:$latest,
              trials:$trials, passes:$passes,
              pass_at_k:  (if $passes >= 1        then 1 else 0 end),
              pass_hat_k: (if $passes == $trials and $trials > 0 then 1 else 0 end),
              pass_rate:  (if $trials > 0 then (($passes/$trials*100|round)/100) else 0 end) }
        )
      | .[]'); then
    die "failed to parse results under $RESULTS_DIR (malformed or truncated results.jsonl?)"
fi
[ -n "$AGG" ] || die "results under $RESULTS_DIR produced an empty aggregate — nothing to score"

if [ "$UPDATE" -eq 1 ]; then
    base='{}'; [ -f "$BASELINE" ] && base=$(cat "$BASELINE")
    updated=$(printf '%s\n' "$AGG" | jq -s \
        --argjson base "$base" \
        --arg date "$(date -u +%Y-%m-%d)" '
        reduce .[] as $r ($base;
            .tasks[$r.task].suite = $r.suite
            | .tasks[$r.task].polarity = $r.polarity
            | .tasks[$r.task].runs[$r.provider + "/" + $r.model] = {
                trials:$r.trials, passes:$r.passes,
                pass_at_k:$r.pass_at_k, pass_hat_k:$r.pass_hat_k, pass_rate:$r.pass_rate }
        ) | .recorded = $date')
    mkdir -p "$(dirname "$BASELINE")"
    printf '%s\n' "$updated" | jq -S '.' > "$BASELINE"
    echo "baseline updated: $BASELINE"
    exit 0
fi

base='{}'; [ -f "$BASELINE" ] && base=$(cat "$BASELINE")
printf '%-26s %-8s %-16s %-6s %-8s %-8s %-7s %s\n' \
    TASK SUITE MODEL PASS "pass@k" "pass^k" RATE "vs baseline"
regressions=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    task=$(printf '%s' "$row"   | jq -r '.task')
    suite=$(printf '%s' "$row"  | jq -r '.suite')
    prov=$(printf '%s' "$row"   | jq -r '.provider')
    model=$(printf '%s' "$row"  | jq -r '.model')
    trials=$(printf '%s' "$row" | jq -r '.trials')
    passes=$(printf '%s' "$row" | jq -r '.passes')
    phk=$(printf '%s' "$row"    | jq -r '.pass_hat_k')
    pk=$(printf '%s' "$row"     | jq -r '.pass_at_k')
    rate=$(printf '%s' "$row"   | jq -r '.pass_rate')
    key="$prov/$model"
    brate=$(printf '%s' "$base" | jq -r --arg t "$task" --arg k "$key" \
        '.tasks[$t].runs[$k].pass_rate // "—"')
    note="baseline $brate"
    if [ "$brate" != "—" ]; then
        cmp=$(awk -v a="$rate" -v b="$brate" 'BEGIN{ if(a<b)print "down"; else if(a>b)print "up"; else print "same"}')
        case "$cmp" in
            down) note="DOWN from $brate";;
            up)   note="up from $brate";;
            same) note="= $brate";;
        esac
    fi
    # Regression-suite tasks must stay perfect; a drop is a hard failure.
    flag=""
    if [ "$suite" = regression ] && [ "$phk" != 1 ]; then
        flag=" ** REGRESSION"; regressions=$((regressions+1))
    fi
    printf '%-26s %-8s %-16s %-6s %-8s %-8s %-7s %s%s\n' \
        "$task" "$suite" "$model" "$passes/$trials" "$pk" "$phk" "$rate" "$note" "$flag"
done <<EOF
$AGG
EOF

echo "----"
if [ "$regressions" -gt 0 ]; then
    echo "$regressions regression-suite task(s) below pass^k=1"
    [ "$FAIL_ON_REGRESSION" -eq 1 ] && exit 1
fi
echo "ok"
exit 0

# --- CI (scheduled, NOT per-PR) -----------------------------------------------
# A full eval run costs real model calls, so wire this on a cron, never on every
# push. Example GitHub Actions schedule:
#   on: { schedule: [{ cron: "0 6 * * 1" }] }   # Mondays 06:00 UTC
#   jobs.evals.steps:
#     - run: bash scripts/eval.sh <task> --provider claude --model haiku --trials 3
#     - run: bash scripts/eval-harness.sh   # fails the job on a regression-suite drop
# ------------------------------------------------------------------------------
