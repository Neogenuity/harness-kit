#!/usr/bin/env bash
# eval-lib.sh — the model-free core of the behavioral eval layer. Everything a
# test can pin without a model in the loop: parse a TASK.md, prepare a clean
# isolated workspace, apply a reference solution, grade a post-agent workspace,
# and compute pass@k / pass^k from trial counts.
#
# The *model* half — actually invoking a provider CLI over N trials and
# capturing transcripts — lives in eval.sh, which sources this. eval-harness.sh
# (the pass-rate/regression comparator) and test-eval.sh (the deterministic
# fixture suite wired into verify.sh) source it too. Same split as
# install-lib.sh / the test-install-*.sh suites: the pure functions here are
# unit-testable, so the machinery that measures the harness is itself measured.
#
# Source it — it defines functions and runs nothing:
#   . scripts/eval-lib.sh
# Compatible with macOS (BSD) and Linux (GNU). Hard deps: git, tar (workspace
# isolation). jq is required by eval_result_json / eval_usage_json here (and by
# eval.sh / eval-harness.sh); the other pure functions do not need it.

# shellcheck disable=SC2034  # consumed by the sourcing scripts (eval.sh, eval-harness.sh, test-eval.sh)
EVAL_TASKS_DIR_DEFAULT="docs/evals/tasks"
# shellcheck disable=SC2034
EVAL_RESULTS_DIR_DEFAULT=".harness/eval-results"
# shellcheck disable=SC2034
EVAL_BASELINE_DEFAULT="docs/evals/baselines.json"

# eval_task_meta <task_dir> <key>
# Reads "- <key>: <value>" from the TASK.md metadata bullet list (suite,
# polarity, provider, grade, network, execution). Prints the value, or nothing
# if unset. First match wins; trailing CR (Windows checkouts) stripped.
eval_task_meta() {
    local dir="$1" key="$2"
    [ -f "$dir/TASK.md" ] || return 0
    sed -n "s/^- ${key}:[[:space:]]*//p" "$dir/TASK.md" | head -1 | tr -d '\r'
}

# eval_task_prompt <task_dir>
# Prints the verbatim body under the "## Prompt" heading, up to the next "## "
# heading, with leading and trailing blank lines trimmed but internal structure
# preserved. This is the exact instruction handed to the agent.
eval_task_prompt() {
    [ -f "$1/TASK.md" ] || return 1
    awk '
        /^## Prompt[[:space:]]*$/ { grab=1; next }
        grab && /^## / { grab=0 }
        grab { a[n++]=$0 }
        END {
            s=0; e=n-1
            while (s<n  && a[s] ~ /^[[:space:]]*$/) s++
            while (e>=0 && a[e] ~ /^[[:space:]]*$/) e--
            for (i=s; i<=e; i++) print a[i]
        }
    ' "$1/TASK.md"
}

# eval_prepare_workspace <repo_root> <dest> [task_dir]
# Creates a clean, isolated clone of the repo at committed HEAD in <dest> — no
# untracked files, no uncommitted edits, no shared object store (--no-hardlinks),
# so leftover state from one trial can never leak into another (Anthropic eval
# guidance: each trial starts from a clean isolated environment). If task_dir
# has a setup.sh, it runs inside the fresh workspace to seed task-specific state
# (e.g. a drifted file a regression task must tolerate). Prints nothing on
# success; returns non-zero if the clone fails.
eval_prepare_workspace() {
    local repo="$1" dest="$2" task_dir="${3:-}" abs_setup
    git clone --quiet --depth=1 --no-hardlinks "file://$(cd "$repo" && pwd)" "$dest" 2>/dev/null || return 1
    # Resolve setup.sh to an absolute path *before* cd'ing into the workspace —
    # task_dir is relative to the source repo, not to the fresh clone.
    if [ -n "$task_dir" ] && [ -f "$task_dir/setup.sh" ]; then
        abs_setup="$(cd "$task_dir" && pwd)/setup.sh"
        ( cd "$dest" && bash "$abs_setup" ) || return 1
    fi
    return 0
}

# eval_apply_reference <task_dir> <workspace>
# Applies the task's reference solution (reference/apply.sh) inside <workspace>.
# This is both the grader-validity proof (a known-good solution the grader must
# pass) and the "mock agent" eval.sh uses to exercise the full pipeline without
# spending on a real model. Returns apply.sh's exit status.
eval_apply_reference() {
    local task_dir ws="$2"
    task_dir="$(cd "$1" && pwd)"
    [ -f "$task_dir/reference/apply.sh" ] || { echo "eval-lib: no reference/apply.sh in $1" >&2; return 2; }
    ( cd "$ws" && bash "$task_dir/reference/apply.sh" )
}

# eval_apply_violation <task_dir> <workspace> [violation_script]
# Applies one of a negative task's *forbidden* changes (reference/<script>,
# default violate.sh) inside <workspace>. A task may ship several — one per
# reward-hacking vector (neuter the gate, delete the evidence, …) — and
# test-eval.sh runs check.sh against each to prove the grader catches them all.
# Returns 2 if the named violation fixture is absent.
eval_apply_violation() {
    local task_dir ws="$2" script="${3:-violate.sh}"
    task_dir="$(cd "$1" && pwd)"
    [ -f "$task_dir/reference/$script" ] || return 2
    ( cd "$ws" && bash "$task_dir/reference/$script" )
}

# eval_grade <task_dir> <workspace> <log_dir>
# Runs the task's acceptance grader (check.sh) inside <workspace>, and — when
# the task's `grade` metadata is `check+verify` — also runs the workspace's own
# scripts/verify.sh. check.sh inspects its cwd (the workspace). Writes check.log
# and (when run) verify.log into <log_dir>.
#
# check.sh's exit code is a three-way convention, not a bare pass/fail:
#   exit 0  -> prints "pass",      returns 0  (the goal was met honestly)
#   exit 3  -> prints "violation", returns 1  (a NEGATIVE task's grader
#              detected the forbidden shortcut itself — e.g. the gate script
#              was modified or the evidence was deleted — a stronger signal
#              than an ordinary miss; callers map this to outcome
#              negative_violation)
#   other   -> prints "fail",      returns 1  (ordinary unmet goal)
# The check+verify path's verify.sh failure always prints "fail" (verify.sh
# has no violation concept). A missing check.sh is a hard error (return 2): a
# task with no grader cannot be scored.
eval_grade() {
    local task_dir ws="$2" log_dir="$3" grade rc
    task_dir="$(cd "$1" && pwd)"
    [ -f "$task_dir/check.sh" ] || { echo "eval-lib: no check.sh in $1" >&2; return 2; }
    mkdir -p "$log_dir"
    ( cd "$ws" && bash "$task_dir/check.sh" ) >"$log_dir/check.log" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ]; then
        echo violation; return 1
    elif [ "$rc" -ne 0 ]; then
        echo fail; return 1
    fi
    grade="$(eval_task_meta "$1" grade)"
    if [ "$grade" = "check+verify" ]; then
        if [ -f "$ws/scripts/verify.sh" ]; then
            if ! ( cd "$ws" && bash scripts/verify.sh ) >"$log_dir/verify.log" 2>&1; then
                echo fail; return 1
            fi
        fi
    fi
    echo pass; return 0
}

# eval_passk <n_trials> <n_passes>
# pass@k = "at least one correct in k attempts" (Anthropic eval guidance):
# 1 if any trial passed, else 0.
eval_passk() { [ "${2:-0}" -ge 1 ] 2>/dev/null && echo 1 || echo 0; }

# eval_passhatk <n_trials> <n_passes>
# pass^k = "correct on all k attempts": 1 if every trial passed, else 0.
eval_passhatk() {
    local n="${1:-0}" c="${2:-0}"
    [ "$n" -ge 1 ] 2>/dev/null || { echo 0; return; }
    [ "$c" -eq "$n" ] 2>/dev/null && echo 1 || echo 0
}

# eval_passrate <n_trials> <n_passes>
# Observed pass rate c/n to two decimals (0.00 when n=0). Pure awk, locale-safe.
eval_passrate() {
    awk -v n="${1:-0}" -v c="${2:-0}" 'BEGIN{ if(n<=0){print "0.00"} else {printf "%.2f", c/n} }'
}

# eval_usage_json <provider> <transcript_file>
# Emits the compact `usage` object embedded in each results row: exact
# provider-reported token/cost usage plus a tool-call count, extracted from the
# trial's captured transcript. Fields are integers (cost a float) when the
# provider reports them and JSON null when it does not — never 0, so
# "unreported" and "measured zero" stay distinguishable:
#   input_uncached     new input tokens NOT served from cache
#   input_cached_read  input tokens served from a prompt cache
#   input_cache_write  input tokens written to the cache (Claude cache creation;
#                      null for Codex, which reports no cache-write figure)
#   output             output tokens
#   cost               total USD when reported, else null (Codex on a ChatGPT
#                      plan reports tokens but no cost)
#   tool_calls         number of tool invocations in the transcript
# Extraction is provider-specific — Claude stream-json (the `result` event, or a
# per-message-id usage sum when a timeout killed the run before the result line)
# vs Codex --json (`turn.completed`; its input_tokens INCLUDES the cached subset,
# so uncached = input - cached). A missing/empty transcript, the mock provider,
# or an unknown provider yields an all-null object (tool_calls 0), so every row's
# shape is uniform. Requires jq; malformed transcript lines are skipped.
eval_usage_json() {
    local provider="$1" transcript="${2:-}"
    local nullobj='{"input_uncached":null,"input_cached_read":null,"input_cache_write":null,"output":null,"cost":null,"tool_calls":0}'
    if ! command -v jq >/dev/null 2>&1 || [ -z "$transcript" ] || [ ! -s "$transcript" ]; then
        printf '%s' "$nullobj"; return 0
    fi
    case "$provider" in
        claude)
            jq -sRc '
              [ split("\n")[] | select(length>0) | (fromjson? // empty) ] as $rows
              | ($rows | map(select(.type=="result")) | last) as $r
              | ($rows | map(select(.type=="assistant")
                    | ((.message.content // []) | map(select(.type=="tool_use")) | length)) | add // 0) as $tools
              | if $r != null then
                  {input_uncached: ($r.usage.input_tokens // null),
                   input_cached_read: ($r.usage.cache_read_input_tokens // null),
                   input_cache_write: ($r.usage.cache_creation_input_tokens // null),
                   output: ($r.usage.output_tokens // null),
                   cost: ($r.total_cost_usd // null),
                   tool_calls: $tools}
                else
                  ([ $rows | map(select(.type=="assistant" and .message.id != null and .message.usage != null))
                       | group_by(.message.id)[] | (.[-1].message.usage) ]) as $u
                  | if ($u | length) == 0 then
                      {input_uncached:null,input_cached_read:null,input_cache_write:null,output:null,cost:null,tool_calls:$tools}
                    else
                      {input_uncached: ($u | map(.input_tokens // 0) | add),
                       input_cached_read: ($u | map(.cache_read_input_tokens // 0) | add),
                       input_cache_write: ($u | map(.cache_creation_input_tokens // 0) | add),
                       output: ($u | map(.output_tokens // 0) | add),
                       cost: null, tool_calls: $tools}
                    end
                end
            ' "$transcript" 2>/dev/null || printf '%s' "$nullobj"
            ;;
        codex)
            jq -sRc '
              [ split("\n")[] | select(length>0) | (fromjson? // empty) ] as $rows
              | ($rows | map(select(.type=="turn.completed")) | last) as $t
              | ([ $rows[] | select(.type=="item.started" or .type=="item.completed")
                    | select(((.item.item_type // .item.type // "")) | test("message|reasoning") | not)
                    | (.item.id // .id) | select(. != null) ] | unique | length) as $tools
              | if $t != null then
                  ($t.usage.input_tokens // null) as $in
                  | ($t.usage.cached_input_tokens // null) as $cr
                  | {input_uncached: (if $in == null then null else ($in - ($cr // 0)) end),
                     input_cached_read: $cr,
                     input_cache_write: null,
                     output: ($t.usage.output_tokens // null),
                     cost: null, tool_calls: $tools}
                else
                  {input_uncached:null,input_cached_read:null,input_cache_write:null,output:null,cost:null,tool_calls:$tools}
                end
            ' "$transcript" 2>/dev/null || printf '%s' "$nullobj"
            ;;
        *) printf '%s' "$nullobj" ;;
    esac
}

# eval_result_json <task> <provider> <model> <suite> <polarity> <run> \
#                  <trial> <pass:true|false> <duration_s> <agent_rc> <transcript> \
#                  <run_started_at> <outcome> [usage_json] [variant]
# Emits one compact JSON object — the results.jsonl schema. The single source for
# that shape, so eval.sh (writer) and test-eval.sh (shape assertion) can never
# disagree. Requires jq (the only jq-dependent function in this lib).
#   arg 12  run_started_at  integer epoch seconds, the SAME value for every
#                           row of one eval.sh invocation (see eval.sh's
#                           RUN_STARTED_AT) — lets eval-harness.sh pick the
#                           truly-latest run instead of a lexicographic max
#                           over the (often hand-typed) --run-id string.
#   arg 13  outcome         "pass" | "task_failure" | "negative_violation" —
#                           eval_grade's verdict mapped by the caller (pass ->
#                           pass, violation -> negative_violation, fail /
#                           workspace-prep failure -> task_failure).
#   arg 14  usage_json     (optional) a JSON object from eval_usage_json — exact
#                           provider-reported token/cost usage + tool_calls.
#                           Omitted/empty => an all-null usage object, so every
#                           row carries the field; legacy rows written without
#                           it still score (eval-harness.sh reads correctness
#                           fields only and never reads usage).
#   arg 15  variant        (optional) "bare" | "plugin-activated" — the
#                           execution-variant dimension (v0.14.0 item 6): a
#                           plugin-activated run of the same task/provider/model
#                           must coexist with its bare counterpart instead of
#                           colliding on the same baseline cell (see
#                           eval-harness.sh's group_by and baseline key).
#                           Omitted/empty => "bare", so every row carries the
#                           field and legacy rows/callers written before this
#                           dimension existed still score as bare.
eval_result_json() {
    local usage="${14:-}"
    [ -n "$usage" ] || usage='{"input_uncached":null,"input_cached_read":null,"input_cache_write":null,"output":null,"cost":null,"tool_calls":0}'
    local variant="${15:-}"
    [ -n "$variant" ] || variant="bare"
    jq -cn \
        --arg task "$1" --arg provider "$2" --arg model "$3" \
        --arg suite "$4" --arg polarity "$5" --arg run "$6" \
        --argjson trial "$7" --argjson pass "$8" --argjson duration_s "$9" \
        --argjson agent_rc "${10}" --arg transcript "${11}" \
        --argjson run_started_at "${12}" --arg outcome "${13}" \
        --argjson usage "$usage" --arg variant "$variant" \
        '{task:$task, provider:$provider, model:$model, variant:$variant,
          suite:$suite, polarity:$polarity, run:$run, trial:$trial, pass:$pass,
          duration_s:$duration_s, agent_rc:$agent_rc, transcript:$transcript,
          run_started_at:$run_started_at, outcome:$outcome, usage:$usage}'
}

# eval_list_tasks <tasks_dir>
# Prints the slug of every task directory (one that has a TASK.md), sorted.
# Skips names starting with "_" (templates/examples).
eval_list_tasks() {
    local d="$1" t
    [ -d "$d" ] || return 0
    for t in "$d"/*/; do
        [ -f "${t}TASK.md" ] || continue
        t="$(basename "$t")"
        case "$t" in _*) continue ;; esac
        printf '%s\n' "$t"
    done | sort
}
