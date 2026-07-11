#!/usr/bin/env bash
# test-eval.sh — deterministic fixture suite for the behavioral eval machinery.
# No model in the loop, so it belongs in verify.sh: it pins the pure functions
# (pass@k / pass^k / rate, TASK.md parsing), the results-JSON schema, and — the
# load-bearing part — GRADER VALIDITY for the whole task bank:
#   * every task's reference solution scores as a PASS (the task is solvable and
#     the grader is valid), and
#   * every negative task's violation scores as a FAIL (the grader actually
#     catches the forbidden shortcut — a grader that can't is false-green).
# This is the offline half of the behavioral-evals plan; live pass-rate
# baselines come from scripts/eval.sh against a real provider.
#
# Set EVAL_TEST_QUICK=1 to skip the per-task workspace clones (unit + schema
# checks only) for a fast local loop; verify.sh runs the full suite.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/eval-lib.sh"

TASKS_DIR="${EVAL_TASKS_DIR:-docs/evals/tasks}"
fails=0
ok()   { printf 'ok:   %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fails=$((fails+1)); }

# ---- unit: pass@k / pass^k / rate ------------------------------------------
{ [ "$(eval_passk 3 0)" = 0 ] && [ "$(eval_passk 3 1)" = 1 ] && [ "$(eval_passk 3 3)" = 1 ]; } \
    && ok "pass@k math" || bad "pass@k math"
{ [ "$(eval_passhatk 3 2)" = 0 ] && [ "$(eval_passhatk 3 3)" = 1 ] && [ "$(eval_passhatk 0 0)" = 0 ]; } \
    && ok "pass^k math" || bad "pass^k math"
{ [ "$(eval_passrate 3 2)" = 0.67 ] && [ "$(eval_passrate 0 0)" = 0.00 ] && [ "$(eval_passrate 4 4)" = 1.00 ]; } \
    && ok "pass-rate math" || bad "pass-rate math"

# ---- schema: results-JSON line (bank-independent) --------------------------
if command -v jq >/dev/null 2>&1; then
    line="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x)"
    if printf '%s' "$line" | jq -e '
            .task=="demo" and .provider=="claude" and .pass==true and
            .trial==1 and .duration_s==5 and (has("agent_rc") and has("transcript"))' \
            >/dev/null 2>&1; then
        ok "results-JSON schema"
    else
        bad "results-JSON schema"
    fi
else
    ok "results-JSON schema (skipped: jq absent)"
fi

# An empty bank is legitimate (a fresh install, or the shipped _template only):
# the pure-function checks above still ran; the bank-dependent checks below have
# nothing to validate, so pass with a note instead of failing.
tdir0="$(eval_list_tasks "$TASKS_DIR" | head -1)"
if [ -z "$tdir0" ]; then
    ok "no golden tasks under $TASKS_DIR — bank-dependent checks skipped"
    echo "----"; echo "test-eval: all checks passed"; exit 0
fi

# ---- unit: TASK.md parsing --------------------------------------------------
td="$TASKS_DIR/$tdir0"
[ -n "$(eval_task_meta "$td" suite)" ] && ok "meta parse (suite)" || bad "meta parse (suite)"
[ -n "$(eval_task_prompt "$td")" ] && ok "prompt parse (non-empty)" || bad "prompt parse (non-empty)"

# ---- grader validity: reference passes, violation fails --------------------
if [ "${EVAL_TEST_QUICK:-0}" = 1 ]; then
    ok "grader validity (skipped: EVAL_TEST_QUICK=1)"
elif ! command -v git >/dev/null 2>&1; then
    ok "grader validity (skipped: git absent)"
else
    for slug in $(eval_list_tasks "$TASKS_DIR"); do
        td="$TASKS_DIR/$slug"
        if ! base="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-XXXXXX")" || [ -z "$base" ]; then
            bad "$slug: mktemp failed"; continue
        fi
        ws="$base/repo"; logd="$base/log"
        if ! eval_prepare_workspace "$ROOT" "$ws" "$td"; then
            bad "$slug: workspace prep"; rm -rf "$base"; continue
        fi
        eval_apply_reference "$td" "$ws" >"$base/apply.log" 2>&1 || bad "$slug: reference/apply.sh errored"
        v="$(eval_grade "$td" "$ws" "$logd")"
        if [ "$v" = pass ]; then ok "$slug: reference scores pass"
        else bad "$slug: reference must pass (grader invalid) — see $logd/check.log"; sed 's/^/    /' "$logd/check.log" 2>/dev/null; fi

        # Every negative task's forbidden shortcuts (reference/violate*.sh) must
        # each score a FAIL — one per reward-hacking vector, so a grader that
        # catches only some of them is caught here.
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
                    [ "$v2" = fail ] && ok "$slug: $vname scores fail" \
                        || bad "$slug: $vname must fail (false-green grader)"
                else
                    bad "$slug: reference/$vname errored"
                fi
            done
        fi
        rm -rf "$base"
    done
fi

echo "----"
if [ "$fails" -eq 0 ]; then echo "test-eval: all checks passed"; exit 0; fi
echo "test-eval: $fails check(s) failed"; exit 1
