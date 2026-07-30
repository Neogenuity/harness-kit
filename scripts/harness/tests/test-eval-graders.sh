#!/usr/bin/env bash
# test-eval-graders.sh — GRADER VALIDITY for this repo's golden-task bank.
# No model in the loop, so it belongs in the shipped floor. For every task under
# .harness/evals/scenarios/ it proves, offline:
#   * the reference solution scores a PASS — the task is solvable and the grader
#     is valid (a grader that cannot pass its own reference is false-red);
#   * every negative task's reference/violate*.sh scores a VIOLATION (check.sh
#     exit 3) — not merely "some non-pass" — proving the grader adopted the
#     exit-3 convention for every reward-hacking vector it ships a fixture for
#     (a grader that silently scores a violation as an ordinary miss is
#     false-green, and stays that way forever);
#   * every reference/wrongplace*.sh fixture is REJECTED (any non-pass).
#
# An empty bank is the default for a fresh install (the shipped _template is
# skipped by eval_list_tasks), and this exits 0 with a note — the cost appears
# only once this repo authors real tasks. Pass --quick to skip the per-task
# workspace clones for a fast local loop. Deliberately an ARGUMENT, not an
# environment variable: this file runs as a gate via `parallel-each`, where the
# command is generated and has nowhere to put an `env -u`, so an inherited
# variable here would be an escape hatch a gate could not close — one exported
# value would turn the gate into a vacuous pass.
#
# The maintainer-only conformance suite for the eval MACHINERY itself (pass@k
# math, results-JSON schema, the eval-harness.sh scorer, eval.sh runner guards)
# is not shipped; this is the half that grades repo-authored content.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/harness/lib/eval-lib.sh"

TASKS_DIR="${EVAL_TASKS_DIR:-.harness/evals/scenarios}"
fails=0
skips=0
ok()  { printf 'ok:   %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }
# skip <reason> — a check this HOST cannot run, as opposed to one that failed.
# Counted and echoed in the summary so a skipped task can never hide behind the
# suite's success line; the shipped floor's CI step sums these '^SKIP:' lines
# across suites for the same reason.
skip() { printf 'SKIP: %s\n' "$1"; skips=$((skips + 1)); }

finish() {
    echo "----"
    if [ "$fails" -eq 0 ]; then
        if [ "$skips" -gt 0 ]; then
            echo "test-eval-graders: all checks passed ($skips skipped)"
        else
            echo "test-eval-graders: all checks passed"
        fi
        exit 0
    fi
    echo "test-eval-graders: $fails check(s) failed"; exit 1
}

BANK_TASKS="$(eval_list_tasks "$TASKS_DIR")"

if [ -z "$BANK_TASKS" ]; then
    ok "no golden tasks under $TASKS_DIR — grader-validity checks skipped"
    finish
fi

if [ "${1:-}" = "--quick" ]; then
    skip "grader validity (--quick requested)"
    finish
fi

if ! command -v git >/dev/null 2>&1; then
    skip "grader validity (git absent)"
    finish
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-eval-graders.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Offline grader validity re-proves the SAME test floor once per scenario via
# the nested check-harness calls in the graders. That floor is already running
# as verify's parallel-each gate — this very file is one of its entries — so
# skip it here (check #6 only). This affects ONLY this offline validity loop:
# real model eval runs go through scripts/harness/run-evals and never set it,
# so live grading is unchanged.
export HARNESS_SKIP_TESTS_FAMILY=1

for slug in $BANK_TASKS; do
    td="$TASKS_DIR/$slug"
    base="$WORK/$slug"

    # A task may need more of the host than a POSIX shell and git — a live dev
    # server, a language runtime, a bindable port. reference/precheck.sh is how
    # it says so: exit 0 when this host can run the task, non-zero with a reason
    # on stdout when it cannot, and THIS task's grader-validity check is skipped
    # rather than failed.
    #
    # Per-task rather than a TASK.md metadata enum on purpose. The shipped floor
    # must not hardcode what any one task's runtime needs: this repo's
    # live-runtime task wants python3 and a loopback bind, an adopter's might
    # want node, a database, or a container. The task knows; the runner cannot.
    #
    # Without it the failure was "verify-live-runtime: reference/apply.sh
    # errored" — which reads as a broken grader and sent triage at the eval
    # bank, when the real answer was that Git Bash ships no python3. The skip is
    # counted and named, so a precheck that always declines cannot quietly
    # retire its own task's coverage.
    #
    # Runs BEFORE mkdir/clone: the workspace prep is the expensive step, and a
    # host that cannot run the task should not pay for it.
    if [ -f "$td/reference/precheck.sh" ]; then
        why=$(bash "$td/reference/precheck.sh" 2>&1); pc_rc=$?
        # EXACTLY 1 means "this host cannot run the task". Any OTHER non-zero is
        # the precheck itself breaking — a syntax error (2), a missing
        # interpreter (126/127), a killed process — and must FAIL, not skip.
        # Treating every non-zero as a decline is how a typo'd probe silently
        # retires its own task's coverage forever, which is the exact failure
        # this whole release is about.
        case "$pc_rc" in
            0) ;;
            1) skip "$slug: host cannot run this task — ${why:-reference/precheck.sh declined}"
               continue ;;
            *) bad "$slug: reference/precheck.sh exited $pc_rc (expected 0=can run, 1=cannot) — the probe is broken, not the host"
               printf '%s\n' "$why" | sed 's/^/    /'
               continue ;;
        esac
    fi

    mkdir -p "$base" || { bad "$slug: scratch dir"; continue; }

    ws="$base/repo"; logd="$base/log"
    if ! eval_prepare_workspace "$ROOT" "$ws" "$td"; then
        bad "$slug: workspace prep"; rm -rf "$base"; continue
    fi
    eval_apply_reference "$td" "$ws" >"$base/apply.log" 2>&1 || bad "$slug: reference/apply.sh errored"
    v="$(eval_grade "$td" "$ws" "$logd")"
    if [ "$v" = pass ]; then ok "$slug: reference scores pass"
    else bad "$slug: reference must pass (grader invalid) — see $logd/check.log"; sed 's/^/    /' "$logd/check.log" 2>/dev/null; fi

    # Negative tasks: each forbidden shortcut must score exit-3 "violation".
    if [ "$(eval_task_meta "$td" polarity)" = negative ]; then
        for vs in "$td"/reference/violate*.sh; do
            [ -f "$vs" ] || continue
            vname="$(basename "$vs")"
            ws2="$base/repo-$vname"; logd2="$base/log-$vname"
            if ! eval_prepare_workspace "$ROOT" "$ws2" "$td"; then
                bad "$slug: workspace prep ($vname)"; continue
            fi
            if eval_apply_violation "$td" "$ws2" "$vname" >"$base/$vname.log" 2>&1; then
                v2="$(eval_grade "$td" "$ws2" "$logd2")"
                [ "$v2" = violation ] && ok "$slug: $vname scores violation" \
                    || bad "$slug: $vname must score 'violation' (exit 3) — grader hasn't adopted the exit-3 convention (got '$v2')"
            else
                bad "$slug: reference/$vname errored"
            fi
        done
    fi

    # Any reference/wrongplace*.sh fixture (the template-first "edited the
    # installed copy instead of the shipped template" shortcut) must be
    # REJECTED — a non-'pass' outcome. NOT polarity-gated: a positive task can
    # ship a wrong-place fixture, and only violate*.sh on negative tasks is
    # exercised above, so without this that grader branch is never run and
    # could silently rot.
    for wp in "$td"/reference/wrongplace*.sh; do
        [ -f "$wp" ] || continue
        wpname="$(basename "$wp")"
        ws3="$base/repo-$wpname"; logd3="$base/log-$wpname"
        if ! eval_prepare_workspace "$ROOT" "$ws3" "$td"; then
            bad "$slug: workspace prep ($wpname)"; continue
        fi
        if eval_apply_violation "$td" "$ws3" "$wpname" >"$base/$wpname.log" 2>&1; then
            v3="$(eval_grade "$td" "$ws3" "$logd3")"
            [ "$v3" != pass ] && ok "$slug: $wpname rejected by grader (scored '$v3')" \
                || bad "$slug: $wpname must be rejected (wrong-place edit) but scored 'pass' — grader branch unproven"
        else
            bad "$slug: reference/$wpname errored"
        fi
    done
    rm -rf "$base"
done

finish
