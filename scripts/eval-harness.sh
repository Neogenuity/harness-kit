#!/usr/bin/env bash
# eval-harness.sh — the regression view over eval.sh's results. Reads the
# per-trial JSON lines, computes pass@k / pass^k / pass-rate per
# (task, provider, model, variant) from the *latest* run of each, compares
# against the recorded baseline (docs/evals/baselines.json), and reports
# deltas.
#
# Execution-variant dimension (v0.14.0 item 6): a row's `variant` (default
# "bare"; "plugin-activated" when eval.sh was run with --variant
# plugin-activated) is part of the grouping key, so a plugin-activated run of
# the same task/provider/model is scored as its OWN cell instead of merging
# with — or silently overwriting — the bare cell it must be compared against.
# The STORED baseline key reflects this without disturbing any baseline
# recorded before this dimension existed: "bare" keeps the plain "provider/model"
# key every existing baseline.json entry already uses (zero migration), and
# only a non-bare variant appends a third segment — "provider/model/variant".
# A results row or baseline entry with no `variant` field at all (recorded
# before this change) is treated as "bare".
#
# Regression-suite tasks carry an ABSOLUTE invariant: the latest run's pass^k
# must equal 1 (correct on every trial). eval-harness.sh fails whenever that
# invariant doesn't hold, full stop — the "vs baseline" column in the table is
# informational context, never the failure trigger, so a regression task fails
# even the very first time it's ever run (no prior baseline to "drop" from).
# Capability-suite tasks are informational: they legitimately sit below 100%,
# so a lower rate is reported, not failed. A negative task's
# outcome=negative_violation (its check.sh caught the forbidden shortcut —
# see eval-lib.sh's eval_grade) fails the run too, regardless of suite: a
# caught reward-hacking attempt is never merely informational. This is never a
# per-PR gate — a full run costs real model calls; run it on a schedule (see
# the CI template comment below) or by hand after a harness change.
#
#   bash scripts/eval-harness.sh                 # score latest results vs baseline
#   bash scripts/eval-harness.sh --update-baseline   # record current as the new baseline
#     --results-dir DIR   default .harness/eval-results
#     --baseline FILE     default docs/evals/baselines.json
#     --no-fail           report regressions/violations but exit 0 (for dashboards)
#     --expected-trials N (--update-baseline only, default 3) every INCOMING
#                         cell (this run's results) must have exactly N
#                         trials; if any disagrees, the WHOLE update is
#                         refused (atomic — pass^k cells with silently
#                         different denominators must never coexist). Pass
#                         this to accept a different count on purpose.
#                         Cells already in the baseline that this update
#                         doesn't touch are NOT refused on a mismatched trial
#                         count — only warned about (see the output) — so a
#                         partial update can never be blocked by an unrelated
#                         historical cell.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/eval-lib.sh"

die() { echo "eval-harness.sh: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq is required."

RESULTS_DIR="$EVAL_RESULTS_DIR_DEFAULT"; BASELINE="$EVAL_BASELINE_DEFAULT"
UPDATE=0; FAIL_ON_REGRESSION=1; EXPECTED_TRIALS=3
while [ $# -gt 0 ]; do
    case "$1" in
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        --update-baseline) UPDATE=1; shift ;;
        --expected-trials) EXPECTED_TRIALS="$2"; shift 2 ;;
        --no-fail) FAIL_ON_REGRESSION=0; shift ;;
        -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
case "$EXPECTED_TRIALS" in ''|*[!0-9]*) die "--expected-trials must be a non-negative integer" ;; esac

[ -d "$RESULTS_DIR" ] || die "no results dir at $RESULTS_DIR — run scripts/eval.sh first"
# -exec cat {} + streams the files by argv (no word-splitting on paths with
# spaces, unlike `cat $(find ...)`); the count guards "no results" cleanly.
RESULT_COUNT=$(find "$RESULTS_DIR" -name results.jsonl -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$RESULT_COUNT" -gt 0 ] || die "no results.jsonl under $RESULTS_DIR — run scripts/eval.sh first"

# Aggregate: one row per (task,provider,model,variant), using only the latest
# run's trials. Emits compact JSON objects (one per line). A jq failure
# (malformed or truncated results) must abort loudly — an empty aggregate
# would otherwise print a misleading "ok" and mask a regression.
#
# Latest-run selection: max_by([(.run_started_at // 0), .run]) picks the
# winning ROW by (run_started_at, run) — an array comparison, so
# run_started_at (numeric epoch seconds) dominates and .run only breaks ties.
# Legacy rows written before run_started_at existed default to 0, so any new
# timestamped run always outranks them; legacy-vs-legacy (both 0) falls back
# to the old plain-string max over .run. This replaced a bare
# `map(.run) | max` that compared run ids as strings: a hand-picked
# --run-id like "haiku" lexicographically outranks any "20260711-..."
# timestamp, so a one-off custom run could permanently "win" over every
# later timestamped run forever.
#
# Trial selection then filters the group down to rows matching the winner's
# (run, run_started_at) PAIR, not run id alone: a hand-typed --run-id (e.g.
# both launched with --run-id "haiku") can collide across two entirely
# different invocations — possibly from different --results-dir trees merged
# under the same aggregation — launched at different times. Selecting by
# .run alone would silently merge both invocations' trials into one cell,
# inflating the trial count beyond what either run actually produced
# (verified: a same-run-id, different-results-dir collision merged into a
# 2/3 aggregate instead of the latest-only 0/1 it should have been). Matching
# run_started_at too keeps the two invocations separate even when their run
# id strings collide. This also lets run_started_at flow into $latest's own
# run_started_at below, for --update-baseline's per-cell `recorded` date.
if ! AGG=$(find "$RESULTS_DIR" -name results.jsonl -type f -exec cat {} + | jq -c -s '
      group_by([.task,.provider,.model,(.variant // "bare")])
      | map(
          . as $g
          | ($g | max_by([(.run_started_at // 0), .run])) as $winner
          | ($winner.run) as $latest
          | ($g | map(select(.run == $winner.run and (.run_started_at // 0) == ($winner.run_started_at // 0)))) as $t
          | ($t | map(select(.pass)) | length) as $passes
          | ($t | length) as $trials
          | ($t | map(select(.outcome == "negative_violation")) | length) as $violations
          | { task:$t[0].task, provider:$t[0].provider, model:$t[0].model,
              variant: ($t[0].variant // "bare"),
              suite:$t[0].suite, polarity:$t[0].polarity, run:$latest,
              run_started_at: ($winner.run_started_at // 0),
              trials:$trials, passes:$passes, violations:$violations,
              pass_at_k:  (if $passes >= 1        then 1 else 0 end),
              pass_hat_k: (if $passes == $trials and $trials > 0 then 1 else 0 end),
              pass_rate:  (if $trials > 0 then (($passes/$trials*100|round)/100) else 0 end) }
        )
      | .[]'); then
    die "failed to parse results under $RESULTS_DIR (malformed or truncated results.jsonl?)"
fi
[ -n "$AGG" ] || die "results under $RESULTS_DIR produced an empty aggregate — nothing to score"

if [ "$UPDATE" -eq 1 ]; then
    # Baselines record only live-model numbers — mock is a plumbing/grader
    # check (see eval.sh) with no bearing on a real model's pass rate.
    MOCK_ROWS=$(printf '%s\n' "$AGG" | jq -c 'select(.provider == "mock")')
    if [ -n "$MOCK_ROWS" ]; then
        echo "excluding mock-provider cell(s) from baseline (mock is plumbing, not a measurement):"
        printf '%s\n' "$MOCK_ROWS" | while IFS= read -r r; do
            [ -n "$r" ] || continue
            printf '  %s %s/%s\n' \
                "$(printf '%s' "$r" | jq -r .task)" \
                "$(printf '%s' "$r" | jq -r .provider)" \
                "$(printf '%s' "$r" | jq -r .model)"
        done
    fi
    LIVE_AGG=$(printf '%s\n' "$AGG" | jq -c 'select(.provider != "mock")')
    [ -n "$LIVE_AGG" ] || die "no live-provider results to record (mock rows are excluded) — nothing to baseline"

    # Atomic refusal: a baseline mixing trial counts would let one pass^k=1
    # cell mean "3 for 3" and another mean "1 for 1" with no visible
    # difference. Refuse the WHOLE update rather than write a
    # partially-consistent file — --update-baseline is all-or-nothing.
    BAD_TRIALS=$(printf '%s\n' "$LIVE_AGG" | jq -c --argjson n "$EXPECTED_TRIALS" 'select(.trials != $n)')
    if [ -n "$BAD_TRIALS" ]; then
        echo "refusing to update baseline: cell(s) with trials != $EXPECTED_TRIALS (--expected-trials):"
        printf '%s\n' "$BAD_TRIALS" | while IFS= read -r r; do
            [ -n "$r" ] || continue
            printf '  %s %s/%s: trials=%s\n' \
                "$(printf '%s' "$r" | jq -r .task)" \
                "$(printf '%s' "$r" | jq -r .provider)" \
                "$(printf '%s' "$r" | jq -r .model)" \
                "$(printf '%s' "$r" | jq -r .trials)"
        done
        echo "pass --expected-trials N to accept a different count on purpose. Baseline NOT written."
        exit 1
    fi

    # Malformed-baseline guard: an existing baseline that isn't valid JSON
    # must die HERE, loudly and before anything downstream runs. Left
    # unchecked, `--argjson base "$base"` below would fail, `updated` would
    # come out empty, and the write step would happily truncate the baseline
    # to nothing while still printing "baseline updated" — a silent
    # corruption with no error trail.
    base='{}'
    if [ -f "$BASELINE" ]; then
        jq empty "$BASELINE" >/dev/null 2>&1 \
            || die "existing baseline at $BASELINE is not valid JSON — fix or remove it before --update-baseline (refusing to touch it)"
        base=$(cat "$BASELINE")
    fi

    # Baseline key: "bare" keeps the plain provider/model key every existing
    # baseline.json entry already uses (zero migration for the common case);
    # a non-bare variant appends a third segment so it can never collide with
    # — or overwrite — its bare counterpart's cell (v0.14.0 item 6).
    updated=$(printf '%s\n' "$LIVE_AGG" | jq -s \
        --argjson base "$base" \
        --arg date "$(date -u +%Y-%m-%d)" '
        reduce .[] as $r ($base;
            (if (($r.variant // "bare") == "bare") then ($r.provider + "/" + $r.model)
             else ($r.provider + "/" + $r.model + "/" + ($r.variant // "bare")) end) as $key
            | .tasks[$r.task].suite = $r.suite
            | .tasks[$r.task].polarity = $r.polarity
            | .tasks[$r.task].runs[$key] = {
                variant: ($r.variant // "bare"),
                trials:$r.trials, passes:$r.passes,
                pass_at_k:$r.pass_at_k, pass_hat_k:$r.pass_hat_k, pass_rate:$r.pass_rate,
                recorded: (if ($r.run_started_at // 0) > 0
                           then ($r.run_started_at | gmtime | strftime("%Y-%m-%d"))
                           else $date end) }
        ) | .recorded = $date') || die "failed to build the updated baseline (jq error) — baseline NOT written"
    [ -n "$updated" ] || die "baseline update produced empty output — baseline NOT written"

    # Retained-cell trial-count warning (NOT a refusal): cells already in the
    # baseline that this update doesn't touch may carry a trials count that
    # disagrees with --expected-trials (e.g. the known historical 2-trial
    # regression-fix-dangling-link/codex cell). Incoming cells are refused
    # atomically above (BAD_TRIALS) because a partial write there would mix
    # denominators within the SAME update. Retained cells only warn: refusing
    # on them too would mean every partial baseline update is bricked until
    # every historical cell in the file is re-recorded, which defeats the
    # point of an incremental --update-baseline (design reviewed). Key shape
    # mirrors the reducer above so a touched plugin-activated cell is matched
    # against its OWN key, not its bare counterpart's.
    TOUCHED=$(printf '%s\n' "$LIVE_AGG" | jq -c -s '[.[] | (.task + "|" +
        (if ((.variant // "bare") == "bare") then (.provider + "/" + .model)
         else (.provider + "/" + .model + "/" + (.variant // "bare")) end))]')
    RETAINED_BAD=$(printf '%s\n' "$updated" | jq -c --argjson n "$EXPECTED_TRIALS" --argjson touched "$TOUCHED" '
        .tasks | to_entries[] | . as $te
        | ($te.value.runs // {}) | to_entries[]
        | select(.value.trials != $n)
        | select((($te.key) + "|" + .key) as $k | ($touched | index($k) | not))
        | {task: $te.key, key: .key, trials: .value.trials}')
    if [ -n "$RETAINED_BAD" ]; then
        echo "warning: retained baseline cell(s) with trials != $EXPECTED_TRIALS (not touched by this update):"
        printf '%s\n' "$RETAINED_BAD" | while IFS= read -r r; do
            [ -n "$r" ] || continue
            printf '  %s %s: trials=%s\n' \
                "$(printf '%s' "$r" | jq -r .task)" \
                "$(printf '%s' "$r" | jq -r .key)" \
                "$(printf '%s' "$r" | jq -r .trials)"
        done
        echo "re-recording those cells (a fresh --update-baseline run that covers them) is the fix."
    fi

    # Atomic write: build the new content in a checked temp file IN THE SAME
    # DIRECTORY as $BASELINE (so the final `mv` is a same-filesystem rename,
    # not a cross-device copy) and rename it over the baseline. An interrupted
    # write (disk full, killed mid-write) then leaves either the old baseline
    # or the new one intact — never a truncated file.
    mkdir -p "$(dirname "$BASELINE")"
    if ! BASELINE_TMP="$(mktemp "$(dirname "$BASELINE")/.baseline.XXXXXX")" || [ -z "$BASELINE_TMP" ]; then
        die "mktemp failed — cannot write baseline (baseline NOT written)"
    fi
    if ! printf '%s\n' "$updated" | jq -S '.' > "$BASELINE_TMP"; then
        rm -f "$BASELINE_TMP"
        die "failed to write updated baseline to a temp file (baseline NOT written)"
    fi
    if ! mv "$BASELINE_TMP" "$BASELINE"; then
        rm -f "$BASELINE_TMP"
        die "failed to move the updated baseline into place at $BASELINE"
    fi
    echo "baseline updated: $BASELINE"
    exit 0
fi

base='{}'; [ -f "$BASELINE" ] && base=$(cat "$BASELINE")
printf '%-26s %-8s %-16s %-18s %-6s %-8s %-8s %-7s %s\n' \
    TASK SUITE MODEL VARIANT PASS "pass@k" "pass^k" RATE "vs baseline"
regressions=0
violations=0
while IFS= read -r row; do
    [ -n "$row" ] || continue
    task=$(printf '%s' "$row"   | jq -r '.task')
    suite=$(printf '%s' "$row"  | jq -r '.suite')
    prov=$(printf '%s' "$row"   | jq -r '.provider')
    model=$(printf '%s' "$row"  | jq -r '.model')
    variant=$(printf '%s' "$row" | jq -r '.variant // "bare"')
    trials=$(printf '%s' "$row" | jq -r '.trials')
    passes=$(printf '%s' "$row" | jq -r '.passes')
    phk=$(printf '%s' "$row"    | jq -r '.pass_hat_k')
    pk=$(printf '%s' "$row"     | jq -r '.pass_at_k')
    rate=$(printf '%s' "$row"   | jq -r '.pass_rate')
    viol=$(printf '%s' "$row"   | jq -r '.violations // 0')
    # Same conditional key shape as the --update-baseline reducer: "bare"
    # looks up the plain provider/model cell every existing baseline uses;
    # a non-bare variant looks up its own distinct provider/model/variant cell.
    if [ "$variant" = bare ]; then key="$prov/$model"; else key="$prov/$model/$variant"; fi
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
    # Regression-suite tasks carry the absolute pass^k=1 invariant — any run
    # below that is a hard failure, independent of the baseline comparison.
    flag=""
    if [ "$suite" = regression ] && [ "$phk" != 1 ]; then
        flag=" ** REGRESSION"; regressions=$((regressions+1))
    fi
    # A negative_violation outcome means check.sh caught a forbidden shortcut
    # (exit 3) — a hard failure regardless of suite; capability-suite's
    # "informational" latitude never covers a caught reward hack.
    if [ "${viol:-0}" -gt 0 ] 2>/dev/null; then
        flag="$flag ** NEGATIVE VIOLATION"; violations=$((violations+1))
    fi
    printf '%-26s %-8s %-16s %-18s %-6s %-8s %-8s %-7s %s%s\n' \
        "$task" "$suite" "$model" "$variant" "$passes/$trials" "$pk" "$phk" "$rate" "$note" "$flag"
done <<EOF
$AGG
EOF

echo "----"
fail_run=0
if [ "$regressions" -gt 0 ]; then
    echo "$regressions regression-suite task(s) below pass^k=1"
    fail_run=1
fi
if [ "$violations" -gt 0 ]; then
    echo "$violations task(s) with a negative_violation outcome (forbidden shortcut caught)"
    fail_run=1
fi
if [ "$fail_run" -eq 1 ]; then
    if [ "$FAIL_ON_REGRESSION" -eq 1 ]; then
        exit 1
    fi
    # --no-fail keeps the exit code 0, but printing a bare "ok" after
    # regression/violation lines above would directly contradict them —
    # say plainly that something failed and was reported, not swallowed.
    echo "not ok (reported above; --no-fail)"
    exit 0
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
