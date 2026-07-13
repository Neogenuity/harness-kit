#!/usr/bin/env bash
# test-eval.sh — deterministic fixture suite for the behavioral eval machinery.
# No model in the loop, so it belongs in verify.sh: it pins the pure functions
# (pass@k / pass^k / rate, TASK.md parsing), the results-JSON schema, the
# eval-harness.sh scorer (run selection, regression/violation exit codes,
# --update-baseline), bank-wide metadata hygiene, and — the load-bearing part —
# GRADER VALIDITY for the whole task bank:
#   * every task's reference solution scores as a PASS (the task is solvable and
#     the grader is valid), and
#   * every negative task's violation scores as a VIOLATION (exit 3 — the
#     grader actually catches the forbidden shortcut, not merely "some
#     non-pass" — a grader that can't is false-green).
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
    line="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x 1752345600 pass)"
    if printf '%s' "$line" | jq -e '
            .task=="demo" and .provider=="claude" and .pass==true and
            .trial==1 and .duration_s==5 and (has("agent_rc") and has("transcript")) and
            (.run_started_at == 1752345600) and (.run_started_at | type) == "number" and
            (.outcome == "pass") and (.outcome | type) == "string"' \
            >/dev/null 2>&1; then
        ok "results-JSON schema (run_started_at, outcome)"
    else
        bad "results-JSON schema (run_started_at, outcome)"
    fi
else
    ok "results-JSON schema (skipped: jq absent)"
fi

# ---- execution-variant dimension: schema default + back-compat ------------
# v0.14.0 item 6: eval.sh/eval-harness.sh gained a `variant` dimension (bare vs
# plugin-activated) so a plugin-activated run of a task/provider/model doesn't
# silently overwrite the bare cell it must be compared against. Every row must
# default to "bare" when the field is absent — both at the WRITER
# (eval_result_json, arg 15 omitted) and at the SCORER (eval-harness.sh
# aggregating a row with no .variant key at all, predating this dimension).
# The dedicated --update-baseline coexistence proof lives in the eval-harness
# scorer fixtures section below (fixture ix).
if ! command -v jq >/dev/null 2>&1; then
    ok "execution-variant schema (skipped: jq absent)"
else
    vrow_explicit="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x 1752345600 pass "" plugin-activated)"
    if printf '%s' "$vrow_explicit" | jq -e '.variant == "plugin-activated"' >/dev/null 2>&1; then
        ok "variant: eval_result_json embeds an explicit plugin-activated variant"
    else
        bad "variant: eval_result_json did not embed the explicit variant"
    fi

    vrow_default="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x 1752345600 pass)"
    if printf '%s' "$vrow_default" | jq -e '.variant == "bare"' >/dev/null 2>&1; then
        ok "variant: eval_result_json defaults to bare when omitted (legacy 13/14-arg call shape)"
    else
        bad "variant: eval_result_json should default to bare when omitted"
    fi

    if [ ! -f "$ROOT/scripts/eval-harness.sh" ]; then
        ok "variant: eval-harness.sh back-compat (skipped: script absent)"
    elif ! vtmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-variant-XXXXXX")" || [ -z "$vtmp" ]; then
        bad "variant: mktemp failed (eval-harness back-compat)"
    else
        # A row with NO .variant key at all (predates this change entirely —
        # stronger than merely omitting eval_result_json's optional arg, which
        # always stamps "bare" explicitly).
        rd="$vtmp/results/legacy-novariant"; mkdir -p "$rd"
        {
            eval_result_json legacy-novariant claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass | jq -c 'del(.variant)'
            eval_result_json legacy-novariant claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass | jq -c 'del(.variant)'
            eval_result_json legacy-novariant claude haiku capability positive run1 3 true 1 0 /tmp/x 1700000000 pass | jq -c 'del(.variant)'
        } > "$rd/results.jsonl"
        bl="$vtmp/baselines.json"
        bash "$ROOT/scripts/eval-harness.sh" --results-dir "$vtmp/results" --baseline "$bl" --update-baseline \
            >"$vtmp/out.log" 2>&1
        rc=$?
        key_present="$(jq -r '.tasks["legacy-novariant"].runs["claude/haiku"] // "MISSING"' "$bl" 2>/dev/null)"
        if [ "$rc" -eq 0 ] && [ "$key_present" != "MISSING" ]; then
            ok "variant: eval-harness.sh scores a row with NO .variant key at all as bare (legacy data)"
        else
            bad "variant: a .variant-less row should still score under the legacy claude/haiku key (rc=$rc)"
            sed 's/^/    /' "$vtmp/out.log"
        fi
        rm -rf "$vtmp"
    fi
fi

# ---- usage instrumentation: eval_usage_json extraction + row schema --------
# Exact provider-reported usage per trial (token/cost/tool-call fields), pinned
# by committed fixtures asserting the EXACT values the extractor pulls from a
# Claude stream-json / Codex --json transcript (not merely the shape). Also
# proves eval_result_json embeds the object, that a row missing it fails the
# check, and that eval-harness.sh tolerates a mixed usage/no-usage results dir.
if ! command -v jq >/dev/null 2>&1; then
    ok "usage instrumentation (skipped: jq absent)"
elif ! utmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-usage-XXXXXX")" || [ -z "$utmp" ]; then
    bad "usage instrumentation: mktemp failed"
else
    _uexpect() { # <name> <actual-json> <expected-json>
        local a b; a="$(printf '%s' "$2" | jq -Sc . 2>/dev/null)"; b="$(printf '%s' "$3" | jq -Sc .)"
        if [ "$a" = "$b" ]; then ok "$1"; else bad "$1"; printf '    got: %s\n    exp: %s\n' "$a" "$b"; fi
    }
    cat > "$utmp/claude.jsonl" <<'UEOF'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":5,"output_tokens":10},"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a"}}]}}
{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":120,"output_tokens":30},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"b"}},{"type":"text","text":"ok"}]}}
{"type":"result","subtype":"success","total_cost_usd":0.0123,"usage":{"input_tokens":150,"cache_creation_input_tokens":20,"cache_read_input_tokens":125,"output_tokens":40}}
UEOF
    _uexpect "usage: claude result-line extraction (exact values)" \
        "$(eval_usage_json claude "$utmp/claude.jsonl")" \
        '{"input_uncached":150,"input_cached_read":125,"input_cache_write":20,"output":40,"cost":0.0123,"tool_calls":2}'

    cat > "$utmp/claude-timeout.jsonl" <<'UEOF'
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":5,"output_tokens":10},"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a"}}]}}
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":5,"output_tokens":10},"content":[]}}
{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":120,"output_tokens":30},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"b"}}]}}
UEOF
    _uexpect "usage: claude timeout fallback (no result line; per-message-id sum, deduped)" \
        "$(eval_usage_json claude "$utmp/claude-timeout.jsonl")" \
        '{"input_uncached":150,"input_cached_read":125,"input_cache_write":20,"output":40,"cost":null,"tool_calls":2}'

    cat > "$utmp/codex.jsonl" <<'UEOF'
{"type":"item.started","item":{"id":"item_1","item_type":"command_execution"}}
{"type":"item.completed","item":{"id":"item_1","item_type":"command_execution"}}
{"type":"item.started","item":{"id":"item_2","item_type":"file_change"}}
{"type":"item.completed","item":{"id":"item_2","item_type":"file_change"}}
{"type":"item.started","item":{"id":"item_3","item_type":"command_execution"}}
{"type":"item.completed","item":{"id":"item_4","item_type":"mcp_tool_call"}}
{"type":"item.completed","item":{"id":"item_5","item_type":"web_search"}}
{"type":"item.completed","item":{"id":"item_6","item_type":"agent_message"}}
{"type":"turn.completed","usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":300,"reasoning_output_tokens":50}}
UEOF
    # tool_calls = distinct tool item ids across started AND completed events,
    # minus message/reasoning: item_1 + item_2 each fire twice (dedup to one),
    # item_3 is a command with ONLY an item.started (Codex emits this shape — the
    # old item.completed-only counter dropped it), and item_4/item_5 are
    # mcp_tool_call + web_search. item_6 (agent_message) is excluded. So 5.
    _uexpect "usage: codex turn.completed extraction (uncached=input-cached; cost null; dedup tool ids across started/completed)" \
        "$(eval_usage_json codex "$utmp/codex.jsonl")" \
        '{"input_uncached":500,"input_cached_read":1500,"input_cache_write":null,"output":300,"cost":null,"tool_calls":5}'

    _uexpect "usage: missing transcript => all-null object" \
        "$(eval_usage_json claude "$utmp/does-not-exist.jsonl")" \
        '{"input_uncached":null,"input_cached_read":null,"input_cache_write":null,"output":null,"cost":null,"tool_calls":0}'

    _uexpect "usage: mock provider => all-null object" \
        "$(eval_usage_json mock "$utmp/claude.jsonl")" \
        '{"input_uncached":null,"input_cached_read":null,"input_cache_write":null,"output":null,"cost":null,"tool_calls":0}'

    # eval_result_json embeds the usage object; all six keys present, tool_calls numeric.
    urow="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x 1752345600 pass "$(eval_usage_json claude "$utmp/claude.jsonl")")"
    if printf '%s' "$urow" | jq -e '
            .usage | (has("input_uncached") and has("input_cached_read") and
                      has("input_cache_write") and has("output") and has("cost") and
                      has("tool_calls")) and (.tool_calls|type=="number")' >/dev/null 2>&1; then
        ok "usage: results row carries a well-formed usage object"
    else
        bad "usage: results row is missing a well-formed usage object"
    fi

    # The shape check must BITE: a row with .usage removed fails it (a row
    # "missing" the usage fields is detectable, per the item-1 acceptance).
    if printf '%s' "$urow" | jq -c 'del(.usage)' | jq -e '.usage.tool_calls|type=="number"' >/dev/null 2>&1; then
        bad "usage: a row missing .usage unexpectedly passed the shape check"
    else
        ok "usage: a row missing .usage fails the shape check"
    fi

    # Back-compat: eval_result_json called the legacy 13-arg way still emits an
    # all-null usage object, so every row has a uniform shape.
    udrow="$(eval_result_json demo claude haiku capability positive run1 1 true 5 0 /tmp/x 1752345600 pass)"
    if printf '%s' "$udrow" | jq -e '.usage.input_uncached==null and .usage.tool_calls==0' >/dev/null 2>&1; then
        ok "usage: omitted usage arg defaults to an all-null object (legacy 13-arg callers)"
    else
        bad "usage: omitted usage arg did not default to an all-null object"
    fi

    # eval-harness.sh tolerates a MIXED old/new results dir — usage on one row,
    # absent on another — because it scores correctness only (item-1 acceptance).
    if [ -f "$ROOT/scripts/eval-harness.sh" ]; then
        mrd="$utmp/results/mix-demo"; mkdir -p "$mrd"
        {
            eval_result_json mix-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass "$(eval_usage_json claude "$utmp/claude.jsonl")"
            eval_result_json mix-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass | jq -c 'del(.usage)'
        } > "$mrd/results.jsonl"
        if bash "$ROOT/scripts/eval-harness.sh" --results-dir "$utmp/results" --baseline "$utmp/none.json" >/dev/null 2>&1; then
            ok "usage: eval-harness scores a mixed usage/no-usage results dir without error"
        else
            bad "usage: eval-harness failed on a mixed old/new results dir"
        fi
    fi
    rm -rf "$utmp"
fi

# ---- bank-wide metadata enum validation (offline, cheap) -------------------
# Every task's suite/polarity/provider/grade metadata must be one of the
# values eval.sh enforces at runtime — a typo here (e.g. "suite: regresion")
# would otherwise silently bypass scorer behavior instead of failing loudly.
# Bank-independent (an empty bank has nothing to iterate and trivially passes),
# so it runs unconditionally, before the bank-dependent checks below decide
# whether they have anything to do.
BANK_TASKS="$(eval_list_tasks "$TASKS_DIR")"
if [ -z "$BANK_TASKS" ]; then
    ok "bank metadata enums (no tasks under $TASKS_DIR — nothing to check)"
else
    meta_fails=0
    for slug in $BANK_TASKS; do
        td="$TASKS_DIR/$slug"
        suite="$(eval_task_meta "$td" suite)"; suite="${suite:-capability}"
        polarity="$(eval_task_meta "$td" polarity)"; polarity="${polarity:-positive}"
        grade="$(eval_task_meta "$td" grade)"
        prov="$(eval_task_meta "$td" provider)"
        case "$suite" in
            capability|regression) ;;
            *) bad "$slug: invalid suite metadata '$suite'"; meta_fails=$((meta_fails+1)) ;;
        esac
        case "$polarity" in
            positive|negative) ;;
            *) bad "$slug: invalid polarity metadata '$polarity'"; meta_fails=$((meta_fails+1)) ;;
        esac
        case "$grade" in
            ''|check|'check+verify') ;;
            *) bad "$slug: invalid grade metadata '$grade'"; meta_fails=$((meta_fails+1)) ;;
        esac
        case "$prov" in
            ''|any|claude|codex) ;;
            *) bad "$slug: invalid provider metadata '$prov'"; meta_fails=$((meta_fails+1)) ;;
        esac
    done
    [ "$meta_fails" -eq 0 ] && ok "bank metadata enums ($(printf '%s\n' "$BANK_TASKS" | wc -l | tr -d ' ') task(s))"
fi

# ---- seeded fixtures: eval-harness.sh scorer behavior (bank-independent) ---
# Synthetic results trees and baseline files — no model, no task bank needed —
# that pin eval-harness.sh's aggregation/scoring/baseline logic directly, so
# these run even when the task bank under $TASKS_DIR is empty (they must run
# BEFORE any bank-empty early-exit; see the restructure note in the brief this
# suite was written against).
if ! command -v jq >/dev/null 2>&1; then
    ok "eval-harness.sh scorer fixtures (skipped: jq absent)"
elif [ ! -f "$ROOT/scripts/eval-harness.sh" ]; then
    ok "eval-harness.sh scorer fixtures (skipped: script absent)"
else
    _harness() { bash "$ROOT/scripts/eval-harness.sh" "$@"; }

    # (i) run selection: an old run "zzz" (no run_started_at — legacy shape)
    # is lexicographically GREATER than a timestamped run id, but a newer
    # run_started_at must still win.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (run selection)"
    else
        rd="$htmp/results/runsel-demo"; mkdir -p "$rd"
        {
            # Legacy run "zzz": 5/5 trials pass, no run_started_at field at all.
            for t in 1 2 3 4 5; do
                eval_result_json runsel-demo claude haiku capability positive zzz "$t" true 1 0 /tmp/x 0 pass \
                    | jq -c 'del(.run_started_at, .outcome)'
            done
            # Newer, timestamped run: only 1/2 trials pass.
            eval_result_json runsel-demo claude haiku capability positive 20260101-000000 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json runsel-demo claude haiku capability positive 20260101-000000 2 false 1 0 /tmp/x 1700000000 task_failure
        } > "$rd/results.jsonl"
        out="$(_harness --results-dir "$htmp/results" --baseline "$htmp/no-such-baseline.json" 2>&1)"
        if printf '%s\n' "$out" | grep -Eq 'runsel-demo[[:space:]]+capability[[:space:]]+haiku[[:space:]]+1/2'; then
            ok "eval-harness: newer run_started_at wins over a lexicographically-larger legacy run id"
        else
            bad "eval-harness: run selection did not pick the newer run"
            printf '%s\n' "$out" | sed 's/^/    /'
        fi
        rm -rf "$htmp"
    fi

    # (ii) regression-suite pass^k drop -> exit 1
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (regression drop)"
    else
        rd="$htmp/results/reg-demo"; mkdir -p "$rd"
        {
            eval_result_json reg-demo claude haiku regression positive run1 1 true  1 0 /tmp/x 1700000000 pass
            eval_result_json reg-demo claude haiku regression positive run1 2 true  1 0 /tmp/x 1700000000 pass
            eval_result_json reg-demo claude haiku regression positive run1 3 false 1 0 /tmp/x 1700000000 task_failure
        } > "$rd/results.jsonl"
        _harness --results-dir "$htmp/results" --baseline "$htmp/no-such-baseline.json" >"$htmp/out.log" 2>&1
        rc=$?
        if [ "$rc" -eq 1 ] && grep -q 'REGRESSION' "$htmp/out.log"; then
            ok "eval-harness: regression-suite pass^k<1 exits 1"
        else
            bad "eval-harness: regression-suite drop should exit 1 with a REGRESSION flag (got rc=$rc)"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (iii) a negative_violation outcome row -> exit 1, regardless of suite.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (violation)"
    else
        rd="$htmp/results/viol-demo"; mkdir -p "$rd"
        eval_result_json viol-demo claude haiku capability negative run1 1 false 1 0 /tmp/x 1700000000 negative_violation \
            > "$rd/results.jsonl"
        _harness --results-dir "$htmp/results" --baseline "$htmp/no-such-baseline.json" >"$htmp/out.log" 2>&1
        rc=$?
        if [ "$rc" -eq 1 ] && grep -q 'NEGATIVE VIOLATION' "$htmp/out.log"; then
            ok "eval-harness: negative_violation outcome exits 1"
        else
            bad "eval-harness: a negative_violation row should exit 1 with a NEGATIVE VIOLATION flag (got rc=$rc)"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (iv) a negative, capability-suite task with only task_failure outcomes
    # (no shortcut caught, goal just unmet) -> exit 0. Proves ordinary misses
    # never trip the violation-based failure path.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (ordinary negative failure)"
    else
        rd="$htmp/results/negfail-demo"; mkdir -p "$rd"
        {
            eval_result_json negfail-demo claude haiku capability negative run1 1 false 1 0 /tmp/x 1700000000 task_failure
            eval_result_json negfail-demo claude haiku capability negative run1 2 false 1 0 /tmp/x 1700000000 task_failure
        } > "$rd/results.jsonl"
        _harness --results-dir "$htmp/results" --baseline "$htmp/no-such-baseline.json" >"$htmp/out.log" 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "eval-harness: capability-suite task_failure-only outcomes exit 0 (not a violation)"
        else
            bad "eval-harness: ordinary task_failure outcomes should exit 0 (got rc=$rc)"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (v-a) --update-baseline: a cell with the wrong trial count refuses the
    # WHOLE update atomically — exit 1, baseline file left byte-unchanged.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (baseline atomic refusal)"
    else
        rd1="$htmp/results/base-demo"; rd2="$htmp/results/badtrials-demo"
        mkdir -p "$rd1" "$rd2"
        {
            eval_result_json base-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json base-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass
            eval_result_json base-demo claude haiku capability positive run1 3 true 1 0 /tmp/x 1700000000 pass
        } > "$rd1/results.jsonl"
        {
            eval_result_json badtrials-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json badtrials-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass
        } > "$rd2/results.jsonl"
        bl="$htmp/baselines.json"
        printf '{"recorded":"1999-01-01","tasks":{}}\n' > "$bl"
        before="$(cat "$bl")"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out.log" 2>&1
        rc=$?
        after="$(cat "$bl")"
        if [ "$rc" -eq 1 ] && [ "$before" = "$after" ] && grep -q 'badtrials-demo' "$htmp/out.log"; then
            ok "eval-harness --update-baseline: wrong trial count refuses atomically (baseline unchanged)"
        else
            bad "eval-harness --update-baseline: expected atomic refusal (rc=1, baseline unchanged); got rc=$rc"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (v-b) --update-baseline: mock-provider cells are excluded, and each
    # recorded cell's `recorded` date derives from its run_started_at.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (baseline mock exclusion)"
    else
        rd1="$htmp/results/base-demo"; rd2="$htmp/results/mock-demo"
        mkdir -p "$rd1" "$rd2"
        rs=1700000000
        {
            eval_result_json base-demo claude haiku capability positive run1 1 true 1 0 /tmp/x "$rs" pass
            eval_result_json base-demo claude haiku capability positive run1 2 true 1 0 /tmp/x "$rs" pass
            eval_result_json base-demo claude haiku capability positive run1 3 true 1 0 /tmp/x "$rs" pass
        } > "$rd1/results.jsonl"
        {
            eval_result_json mock-demo mock reference-solution capability positive run1 1 true 1 0 /tmp/x "$rs" pass
            eval_result_json mock-demo mock reference-solution capability positive run1 2 true 1 0 /tmp/x "$rs" pass
            eval_result_json mock-demo mock reference-solution capability positive run1 3 true 1 0 /tmp/x "$rs" pass
        } > "$rd2/results.jsonl"
        bl="$htmp/baselines.json"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out.log" 2>&1
        rc=$?
        expect_date="$(jq -nr --argjson t "$rs" '$t|gmtime|strftime("%Y-%m-%d")')"
        got_date="$(jq -r '.tasks["base-demo"].runs["claude/haiku"].recorded // "MISSING"' "$bl" 2>/dev/null)"
        has_mock="$(jq -r '(.tasks // {}) | has("mock-demo")' "$bl" 2>/dev/null)"
        if [ "$rc" -eq 0 ] && [ "$got_date" = "$expect_date" ] && [ "$has_mock" = "false" ]; then
            ok "eval-harness --update-baseline: mock excluded, per-cell recorded derives from run_started_at"
        else
            bad "eval-harness --update-baseline: expected mock excluded + recorded=$expect_date; got recorded=$got_date mock-present=$has_mock rc=$rc"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (vi) --update-baseline: a malformed EXISTING baseline dies loudly and
    # is left byte-unchanged (F1). Distinct from (v-a): that fixture covers a
    # well-formed-but-wrong-shape incoming cell; this one covers the baseline
    # FILE itself being unparseable JSON — the case that used to silently
    # truncate the baseline to empty while still printing "baseline updated".
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (malformed baseline)"
    else
        rd="$htmp/results/malformed-demo"; mkdir -p "$rd"
        {
            eval_result_json malformed-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json malformed-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass
            eval_result_json malformed-demo claude haiku capability positive run1 3 true 1 0 /tmp/x 1700000000 pass
        } > "$rd/results.jsonl"
        bl="$htmp/baselines.json"
        printf '{ this is not valid json' > "$bl"
        before="$(cat "$bl")"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out.log" 2>&1
        rc=$?
        after="$(cat "$bl")"
        if [ "$rc" -ne 0 ] && [ "$before" = "$after" ]; then
            ok "eval-harness --update-baseline: malformed existing baseline dies, file left byte-unchanged"
        else
            bad "eval-harness --update-baseline: malformed baseline should die without touching the file (rc=$rc)"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (vii) --update-baseline: a RETAINED cell (already in the baseline,
    # untouched by this update) with a trial count != --expected-trials only
    # WARNS, never refuses (F2) — this is the known-real
    # regression-fix-dangling-link/codex 2-trial cell's exact shape. An
    # incoming cell for a DIFFERENT task at the expected trial count must
    # still be written.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (retained-cell warning)"
    else
        rd="$htmp/results/newtask-demo"; mkdir -p "$rd"
        {
            eval_result_json newtask-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json newtask-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass
            eval_result_json newtask-demo claude haiku capability positive run1 3 true 1 0 /tmp/x 1700000000 pass
        } > "$rd/results.jsonl"
        bl="$htmp/baselines.json"
        printf '%s\n' '{"recorded":"1999-01-01","tasks":{"oldtask-demo":{"suite":"regression","polarity":"positive","runs":{"codex/gpt-5.6-terra":{"trials":2,"passes":2,"pass_at_k":1,"pass_hat_k":1,"pass_rate":1,"recorded":"1999-01-01"}}}}}' > "$bl"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out.log" 2>&1
        rc=$?
        has_new="$(jq -r '(.tasks // {}) | has("newtask-demo")' "$bl" 2>/dev/null)"
        if [ "$rc" -eq 0 ] && [ "$has_new" = "true" ] && grep -q 'oldtask-demo' "$htmp/out.log"; then
            ok "eval-harness --update-baseline: retained wrong-trial-count cell only warns, update still succeeds"
        else
            bad "eval-harness --update-baseline: retained-cell mismatch should warn (not refuse); rc=$rc has_new=$has_new"
            sed 's/^/    /' "$htmp/out.log"
        fi
        rm -rf "$htmp"
    fi

    # (viii) run selection by (run, run_started_at) PAIR, not run id alone
    # (F3): two DIFFERENT invocations that happen to share the hand-typed run
    # id "manual" must not have their trials merged — only the
    # chronologically newer run_started_at's trials should count. Before the
    # fix, selecting by .run alone would merge the older run's 2 trials with
    # the newer run's 1, reporting a merged 2/3 instead of the correct,
    # latest-only 0/1.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (run-id/run_started_at pair selection)"
    else
        rd="$htmp/results/pairsel-demo"; mkdir -p "$rd"
        {
            # Older invocation, run id "manual": 2/2 trials pass.
            eval_result_json pairsel-demo claude haiku capability positive manual 1 true  1 0 /tmp/x 1600000000 pass
            eval_result_json pairsel-demo claude haiku capability positive manual 2 true  1 0 /tmp/x 1600000000 pass
            # Newer invocation, SAME run id "manual" (a different launch): 0/1.
            eval_result_json pairsel-demo claude haiku capability positive manual 1 false 1 0 /tmp/x 1700000000 task_failure
        } > "$rd/results.jsonl"
        out="$(_harness --results-dir "$htmp/results" --baseline "$htmp/no-such-baseline.json" 2>&1)"
        if printf '%s\n' "$out" | grep -Eq 'pairsel-demo[[:space:]]+capability[[:space:]]+haiku[[:space:]]+0/1' \
                && ! printf '%s\n' "$out" | grep -Eq 'pairsel-demo[[:space:]]+capability[[:space:]]+haiku[[:space:]]+2/3'; then
            ok "eval-harness: run selection by (run, run_started_at) pair keeps a same-run-id collision from merging trials"
        else
            bad "eval-harness: expected only the newer run_started_at's 0/1 trials, not a merged 2/3"
            printf '%s\n' "$out" | sed 's/^/    /'
        fi
        rm -rf "$htmp"
    fi

    # (ix) execution-variant dimension (v0.14.0 item 6): a bare and a
    # plugin-activated cell for the SAME task/provider/model must coexist in
    # the baseline as DISTINCT keys — neither --update-baseline invocation may
    # overwrite the other. Proven by two SEPARATE invocations against the same
    # baseline file (mirroring how eval-harness.sh is actually used over
    # time): step 1 records only the bare cell (default variant — no variant
    # arg passed, exercising the writer's back-compat default too); step 2
    # separately records a plugin-activated cell for the identical
    # task/provider/model with a DIFFERENT pass count (2/3, not 3/3) — a
    # collision (merge or silent overwrite) would be visible immediately.
    if ! htmp="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-harness-XXXXXX")" || [ -z "$htmp" ]; then
        bad "eval-harness fixtures: mktemp failed (variant collision)"
    else
        bl="$htmp/baselines.json"

        rd1="$htmp/results/variant-demo-bare"; mkdir -p "$rd1"
        {
            eval_result_json variant-demo claude haiku capability positive run1 1 true 1 0 /tmp/x 1700000000 pass
            eval_result_json variant-demo claude haiku capability positive run1 2 true 1 0 /tmp/x 1700000000 pass
            eval_result_json variant-demo claude haiku capability positive run1 3 true 1 0 /tmp/x 1700000000 pass
        } > "$rd1/results.jsonl"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out1.log" 2>&1
        rc1=$?
        bare_after_1="$(jq -Sc '.tasks["variant-demo"].runs["claude/haiku"] // "MISSING"' "$bl" 2>/dev/null)"

        rd2="$htmp/results/variant-demo-activated"; mkdir -p "$rd2"
        {
            eval_result_json variant-demo claude haiku capability positive run2 1 true  1 0 /tmp/x 1700000100 pass "" plugin-activated
            eval_result_json variant-demo claude haiku capability positive run2 2 true  1 0 /tmp/x 1700000100 pass "" plugin-activated
            eval_result_json variant-demo claude haiku capability positive run2 3 false 1 0 /tmp/x 1700000100 task_failure "" plugin-activated
        } > "$rd2/results.jsonl"
        _harness --results-dir "$htmp/results" --baseline "$bl" --update-baseline >"$htmp/out2.log" 2>&1
        rc2=$?

        bare_after_2="$(jq -Sc '.tasks["variant-demo"].runs["claude/haiku"] // "MISSING"' "$bl" 2>/dev/null)"
        activated_after_2="$(jq -Sc '.tasks["variant-demo"].runs["claude/haiku/plugin-activated"] // "MISSING"' "$bl" 2>/dev/null)"
        bare_trials="$(printf '%s' "$bare_after_2" | jq -r '.trials // "MISSING"' 2>/dev/null)"
        bare_passes="$(printf '%s' "$bare_after_2" | jq -r '.passes // "MISSING"' 2>/dev/null)"
        act_trials="$(printf '%s' "$activated_after_2" | jq -r '.trials // "MISSING"' 2>/dev/null)"
        act_passes="$(printf '%s' "$activated_after_2" | jq -r '.passes // "MISSING"' 2>/dev/null)"
        act_variant="$(printf '%s' "$activated_after_2" | jq -r '.variant // "MISSING"' 2>/dev/null)"

        if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] \
                && [ "$bare_after_1" = "$bare_after_2" ] \
                && [ "$bare_trials" = 3 ] && [ "$bare_passes" = 3 ] \
                && [ "$act_trials" = 3 ] && [ "$act_passes" = 2 ] \
                && [ "$act_variant" = plugin-activated ]; then
            ok "eval-harness --update-baseline: bare and plugin-activated cells for the same task/provider/model coexist as distinct keys (neither overwrites the other)"
        else
            bad "eval-harness --update-baseline: expected distinct bare (3/3) + plugin-activated (2/3) cells, bare unchanged by the second update"
            printf '    bare after step 1: %s\n    bare after step 2: %s\n    activated after step 2: %s\n    rc1=%s rc2=%s\n' \
                "$bare_after_1" "$bare_after_2" "$activated_after_2" "$rc1" "$rc2"
            sed 's/^/    /' "$htmp/out1.log" "$htmp/out2.log"
        fi
        rm -rf "$htmp"
    fi
fi

# ---- runner guards: eval.sh integration fixtures (bank-independent) --------
# The scorer fixtures above pin eval-harness.sh (aggregation/baselines)
# through its pure jq logic. This section instead exercises eval.sh ITSELF —
# the dirty-tree refusal, task-metadata enum validation, provider pin gate,
# results-dir collision refusal, and negative-violation recording — which
# previously had zero automated coverage. It runs eval.sh as a real
# subprocess against a throwaway fixture repo R, not the main dogfood repo,
# so the checked-out state here is fully controlled instead of depending on
# whatever this repo's working tree happens to look like.
#
# Fixture repo R is built ONCE and reused by every sub-case below: its
# scripts/ holds COPIES of this repo's rolled scripts/eval-lib.sh,
# scripts/eval.sh, scripts/eval-harness.sh (inside this dogfood repo they are
# byte-identical to the templates that generated them). eval.sh derives its
# own ROOT from its own location (`dirname "$0"`/..), so running
# `bash "$R/scripts/eval.sh"` makes R — not this repo — eval.sh's source
# repo: R's dirty/clean state is what the dirty-tree guard sees, and
# eval_prepare_workspace clones R, not $ROOT. R's own synthetic tasks live
# under R/tasks, entirely separate from $TASKS_DIR (the real docs/evals/tasks
# bank), so they are never subject to the bank-wide grader-validity checks
# above — a task here is free to have its reference "solution" deliberately
# take the forbidden shortcut (neg-violate) without that leaking into the
# real bank's checks.
if ! command -v git >/dev/null 2>&1; then
    ok "runner-guards fixtures (skipped: git absent)"
elif ! command -v jq >/dev/null 2>&1; then
    ok "runner-guards fixtures (skipped: jq absent)"
elif [ ! -f "$ROOT/scripts/eval.sh" ] || [ ! -f "$ROOT/scripts/eval-harness.sh" ] || [ ! -f "$ROOT/scripts/eval-lib.sh" ]; then
    ok "runner-guards fixtures (skipped: rolled eval scripts absent under $ROOT/scripts)"
elif ! R_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-eval-runner-XXXXXX")" || [ -z "$R_BASE" ]; then
    bad "runner-guards fixtures: mktemp failed (fixture repo)"
else
    trap 'rm -rf "$R_BASE" 2>/dev/null' EXIT
    R="$R_BASE/R"
    mkdir -p "$R/scripts" "$R/tasks"
    cp "$ROOT/scripts/eval-lib.sh" "$ROOT/scripts/eval.sh" "$ROOT/scripts/eval-harness.sh" "$R/scripts/"

    # ok-task: trivial positive capability task, always passes.
    mkdir -p "$R/tasks/ok-task/reference"
    cat > "$R/tasks/ok-task/TASK.md" <<'TASKEOF'
# ok-task

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Do nothing; this task exists only to exercise eval.sh's runner guards.
TASKEOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "$R/tasks/ok-task/check.sh"
    printf '#!/usr/bin/env bash\ntrue\n' > "$R/tasks/ok-task/reference/apply.sh"

    # bad-enum: suite metadata is deliberately misspelled ("regresion").
    mkdir -p "$R/tasks/bad-enum/reference"
    cat > "$R/tasks/bad-enum/TASK.md" <<'TASKEOF'
# bad-enum

- suite: regresion
- polarity: positive
- provider: any
- grade: check

## Prompt

Do nothing; this task's suite metadata is deliberately misspelled.
TASKEOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "$R/tasks/bad-enum/check.sh"
    printf '#!/usr/bin/env bash\ntrue\n' > "$R/tasks/bad-enum/reference/apply.sh"

    # pinned: pinned to the codex provider.
    mkdir -p "$R/tasks/pinned/reference"
    cat > "$R/tasks/pinned/TASK.md" <<'TASKEOF'
# pinned

- suite: capability
- polarity: positive
- provider: codex
- grade: check

## Prompt

Do nothing; this task is pinned to the codex provider.
TASKEOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "$R/tasks/pinned/check.sh"
    printf '#!/usr/bin/env bash\ntrue\n' > "$R/tasks/pinned/reference/apply.sh"

    # neg-violate: negative task whose reference solution deliberately takes
    # the forbidden shortcut (creates HACKED), so the mock run produces a
    # violation end to end. violate.sh mirrors apply.sh so nothing else in
    # the (bank-independent) grader-validity machinery breaks if pointed at it.
    mkdir -p "$R/tasks/neg-violate/reference"
    cat > "$R/tasks/neg-violate/TASK.md" <<'TASKEOF'
# neg-violate

- suite: capability
- polarity: negative
- provider: any
- grade: check

## Prompt

Do nothing; this task's reference solution deliberately takes the forbidden
shortcut so the mock run produces a recorded violation.
TASKEOF
    cat > "$R/tasks/neg-violate/check.sh" <<'TASKEOF'
#!/usr/bin/env bash
if [ -f HACKED ]; then
    echo violation
    exit 3
fi
echo pass
exit 0
TASKEOF
    cat > "$R/tasks/neg-violate/reference/apply.sh" <<'TASKEOF'
#!/usr/bin/env bash
touch HACKED
TASKEOF
    cp "$R/tasks/neg-violate/reference/apply.sh" "$R/tasks/neg-violate/reference/violate.sh"

    (
        cd "$R" || exit 1
        git init -q .
        git config user.email "test-eval@example.invalid"
        git config user.name "test-eval"
        git add -A
        git commit -q -m "seed runner-guards fixture repo" >/dev/null
    )

    # (a) dirty-tree refusal, then --allow-dirty-head override.
    echo "untracked" > "$R/scratch.txt"
    rd_a="$R_BASE/results-a"
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_a" --run-id dirty-no \
        >"$R_BASE/a-no.out" 2>"$R_BASE/a-no.err"
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q -- '--allow-dirty-head' "$R_BASE/a-no.err"; then
        ok "runner guards: dirty tree refuses without --allow-dirty-head"
    else
        bad "runner guards: dirty tree should refuse and mention --allow-dirty-head (rc=$rc)"
        sed 's/^/    /' "$R_BASE/a-no.err"
    fi
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_a" --run-id dirty-yes --allow-dirty-head \
        >"$R_BASE/a-yes.out" 2>"$R_BASE/a-yes.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "runner guards: --allow-dirty-head proceeds despite the dirty tree"
    else
        bad "runner guards: --allow-dirty-head should still succeed (rc=$rc)"
        sed 's/^/    /' "$R_BASE/a-yes.err"
    fi
    rm -f "$R/scratch.txt"

    # (b) enum rejection — pins eval.sh's OWN enum-validation logic directly
    # (not test-eval.sh's private re-implementation of the same enums used
    # for the bank-metadata check above), mitigating the drift risk of two
    # independent copies of "suite is capability|regression" disagreeing.
    rd_b="$R_BASE/results-b"
    bash "$R/scripts/eval.sh" bad-enum --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_b" --run-id benum \
        >"$R_BASE/b.out" 2>"$R_BASE/b.err"
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q "regresion" "$R_BASE/b.err"; then
        ok "runner guards: invalid suite metadata is rejected by eval.sh itself"
    else
        bad "runner guards: bad-enum task should be rejected by eval.sh and name the bad value (rc=$rc)"
        sed 's/^/    /' "$R_BASE/b.err"
    fi

    # (c) provider gate + mock exemption. The claude-pinned-refusal half uses
    # a shim `claude` on PATH that would prove it was invoked (prints
    # SHIM-INVOKED and exits 7) — if the gate ever regresses and lets the
    # call through, the shim absorbs it instead of any live spend, and the
    # assertion below catches the regression via the SHIM-INVOKED marker.
    rd_c="$R_BASE/results-c"
    bash "$R/scripts/eval.sh" pinned --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_c" --run-id pin-mock \
        >"$R_BASE/c-mock.out" 2>"$R_BASE/c-mock.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "runner guards: mock is exempt from the provider pin"
    else
        bad "runner guards: mock should be exempt from the provider pin (rc=$rc)"
        sed 's/^/    /' "$R_BASE/c-mock.err"
    fi

    shimdir="$R_BASE/shim"
    mkdir -p "$shimdir"
    cat > "$shimdir/claude" <<'TASKEOF'
#!/bin/sh
echo SHIM-INVOKED >&2
exit 7
TASKEOF
    chmod +x "$shimdir/claude"
    rd_c2="$R_BASE/results-c2"
    PATH="$shimdir:$PATH" bash "$R/scripts/eval.sh" pinned --provider claude --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_c2" --run-id pin-claude \
        >"$R_BASE/c-claude.out" 2>"$R_BASE/c-claude.err"
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q "pinned to provider" "$R_BASE/c-claude.err" \
            && ! grep -q "SHIM-INVOKED" "$R_BASE/c-claude.err"; then
        ok "runner guards: provider gate refuses claude on a codex-pinned task before the shim is ever invoked"
    else
        bad "runner guards: provider gate should refuse and never reach the shimmed CLI (rc=$rc)"
        sed 's/^/    /' "$R_BASE/c-claude.err"
    fi

    # (d) results-dir collision refusal: same --run-id, same --results-dir,
    # second invocation must refuse rather than merge/overwrite.
    rd_d="$R_BASE/results-d"
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_d" --run-id fixed \
        >"$R_BASE/d1.out" 2>"$R_BASE/d1.err"
    rc1=$?
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_d" --run-id fixed \
        >"$R_BASE/d2.out" 2>"$R_BASE/d2.err"
    rc2=$?
    if [ "$rc1" -eq 0 ] && [ "$rc2" -ne 0 ] && grep -q "fresh --run-id" "$R_BASE/d2.err"; then
        ok "runner guards: reusing a run id with recorded results is refused"
    else
        bad "runner guards: second run with the same --run-id should refuse (rc1=$rc1 rc2=$rc2)"
        sed 's/^/    /' "$R_BASE/d2.err"
    fi

    # (e) end-to-end violation: mock applies the reference solution (creates
    # HACKED), check.sh catches it (exit 3) -> eval.sh must still exit 0 (a
    # violation is a recorded outcome, not a runner error) with the row
    # correctly shaped; eval-harness.sh must then fail loudly on it.
    rd_e="$R_BASE/results-e"
    bash "$R/scripts/eval.sh" neg-violate --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_e" --run-id viol1 \
        >"$R_BASE/e.out" 2>"$R_BASE/e.err"
    rc=$?
    resline="$(find "$rd_e" -name results.jsonl -type f -exec cat {} + 2>/dev/null)"
    if [ "$rc" -eq 0 ] && printf '%s' "$resline" \
            | jq -e '.outcome=="negative_violation" and .pass==false and .run_started_at>0' >/dev/null 2>&1; then
        ok "runner guards: a caught reward-hacking shortcut is recorded as negative_violation, not a runner error"
    else
        bad "runner guards: neg-violate mock run should exit 0 with a negative_violation row (rc=$rc)"
        sed 's/^/    /' "$R_BASE/e.err"
    fi

    bash "$R/scripts/eval-harness.sh" --results-dir "$rd_e" --baseline "$R_BASE/nonexistent-baseline.json" \
        >"$R_BASE/e-harness.out" 2>&1
    rc2=$?
    if [ "$rc2" -ne 0 ] && grep -qi "violation" "$R_BASE/e-harness.out"; then
        ok "runner guards: eval-harness.sh fails loudly on a negative_violation row"
    else
        bad "runner guards: eval-harness.sh should exit non-zero and mention the violation (rc=$rc2)"
        sed 's/^/    /' "$R_BASE/e-harness.out"
    fi

    # (f) --variant flag: pins eval.sh's OWN enum validation and default for
    # the newest metadata dimension (mirrors the suite-enum gate in (b)) —
    # a valid value flows through to the recorded row, an invalid value is
    # rejected before any trial runs, and the default (no flag) is "bare".
    rd_f="$R_BASE/results-f"
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_f" --run-id variant-ok --variant plugin-activated \
        >"$R_BASE/f.out" 2>"$R_BASE/f.err"
    rc=$?
    resline_f="$(find "$rd_f" -name results.jsonl -type f -exec cat {} + 2>/dev/null)"
    if [ "$rc" -eq 0 ] && printf '%s' "$resline_f" | jq -e '.variant == "plugin-activated"' >/dev/null 2>&1; then
        ok "runner guards: --variant plugin-activated flows through to the recorded row"
    else
        bad "runner guards: --variant plugin-activated should be recorded on the row (rc=$rc)"
        sed 's/^/    /' "$R_BASE/f.err"
    fi

    rd_f2="$R_BASE/results-f2"
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_f2" --run-id variant-bad --variant nonsense \
        >"$R_BASE/f2.out" 2>"$R_BASE/f2.err"
    rc2f=$?
    if [ "$rc2f" -ne 0 ] && grep -q -- "--variant" "$R_BASE/f2.err"; then
        ok "runner guards: an invalid --variant value is rejected by eval.sh itself"
    else
        bad "runner guards: invalid --variant should be rejected (rc=$rc2f)"
        sed 's/^/    /' "$R_BASE/f2.err"
    fi

    rd_f3="$R_BASE/results-f3"
    bash "$R/scripts/eval.sh" ok-task --provider mock --trials 1 \
        --tasks-dir "$R/tasks" --results-dir "$rd_f3" --run-id variant-default \
        >"$R_BASE/f3.out" 2>"$R_BASE/f3.err"
    rc3f=$?
    resline_f3="$(find "$rd_f3" -name results.jsonl -type f -exec cat {} + 2>/dev/null)"
    if [ "$rc3f" -eq 0 ] && printf '%s' "$resline_f3" | jq -e '.variant == "bare"' >/dev/null 2>&1; then
        ok "runner guards: --variant defaults to bare when not passed"
    else
        bad "runner guards: default variant should be bare (rc=$rc3f)"
        sed 's/^/    /' "$R_BASE/f3.err"
    fi

    rm -rf "$R_BASE"
    trap - EXIT
fi

# ---- bank-dependent checks (skipped when the bank is empty) ----------------
# An empty bank is legitimate (a fresh install, or the shipped _template
# only): everything above still ran; these two sections need at least one real
# task, so they pass with a note instead of failing when there is none.
if [ -z "$BANK_TASKS" ]; then
    ok "no golden tasks under $TASKS_DIR — TASK.md parsing / grader-validity checks skipped"
else
    tdir0="$(printf '%s\n' "$BANK_TASKS" | head -1)"

    # ---- unit: TASK.md parsing ----------------------------------------------
    td="$TASKS_DIR/$tdir0"
    [ -n "$(eval_task_meta "$td" suite)" ] && ok "meta parse (suite)" || bad "meta parse (suite)"
    [ -n "$(eval_task_prompt "$td")" ] && ok "prompt parse (non-empty)" || bad "prompt parse (non-empty)"

    # ---- grader validity: reference passes, violation scores "violation" ---
    if [ "${EVAL_TEST_QUICK:-0}" = 1 ]; then
        ok "grader validity (skipped: EVAL_TEST_QUICK=1)"
    elif ! command -v git >/dev/null 2>&1; then
        ok "grader validity (skipped: git absent)"
    else
        for slug in $BANK_TASKS; do
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

            # Every negative task's forbidden shortcuts (reference/violate*.sh)
            # must each score "violation" (check.sh exit 3) — not merely
            # "some non-pass" — proving the grader adopted the exit-3
            # convention for every reward-hacking vector it ships a fixture for.
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

            # Any reference/wrongplace*.sh fixture (the template-first "edited
            # the installed root copy instead of the shipped template" shortcut)
            # must be REJECTED by check.sh — a non-'pass' outcome. NOT
            # polarity-gated: a positive task can ship a wrong-place fixture, and
            # only violate*.sh on negative tasks is exercised above — so without
            # this that grader branch is never run and could silently rot.
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
    fi
fi

echo "----"
if [ "$fails" -eq 0 ]; then echo "test-eval: all checks passed"; exit 0; fi
echo "test-eval: $fails check(s) failed"; exit 1
