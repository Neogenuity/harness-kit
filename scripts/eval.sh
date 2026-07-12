#!/usr/bin/env bash
# eval.sh — run one behavioral golden task over N independent trials, each in a
# fresh isolated workspace, capture a transcript per trial, grade each against
# the task's acceptance check (check.sh) + optional verify.sh, and append one
# JSON line per trial to a results file. This is the *measurement* tool: it does
# NOT gate anything, is never wired into a guard hook, and may fail loudly.
#
# Provider invocations were re-verified against the installed toolchain at build
# time and are stamped here (SKILL update mode re-checks these on a provider
# shift):
#   Claude Code 2.1.207:  claude -p <prompt> --model <m> \
#                             --output-format stream-json --verbose \
#                             --dangerously-skip-permissions        (cwd = workspace)
#   Codex exec:           codex exec <prompt> --model <m> --cd <ws> \
#                             --sandbox workspace-write --json \
#                             --output-last-message <file>
# The workspace is a throwaway clone, which is why the sandbox-bypass flags are
# acceptable here and only here.
#
#   bash scripts/eval.sh <task-slug> [options]
#     --trials N        independent trials (default 3)
#     --provider P      claude | codex | mock   (default claude; mock runs the
#                       task's reference solution instead of a model — a
#                       plumbing/grader-validity check that costs nothing)
#     --model M         provider model (default: claude=haiku, codex=gpt-5.6-terra)
#     --run-id ID       results subdir name (default: UTC timestamp + provider +
#                       model, so two providers launched the same second never
#                       collide on a results dir)
#     --tasks-dir DIR   task bank (default docs/evals/tasks)
#     --results-dir DIR output root (default .harness/eval-results)
#     --timeout SECS    per-trial wall-clock cap (default 900; 0 disables). Uses
#                       `timeout`/`gtimeout` if present, else a portable
#                       background+poll — a hung agent can never stall the run.
#     --allow-dirty-head  proceed despite uncommitted changes in this repo
#                       (warns instead of refusing). Trial workspaces clone
#                       committed HEAD only (see eval_prepare_workspace), so
#                       without this flag a dirty tree refuses to run — the
#                       uncommitted changes would silently NOT be measured.
#
# A single-trial run is a smoke test, not an eval: interpret pass rates over
# trials with scripts/eval-harness.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=/dev/null
. "$ROOT/scripts/eval-lib.sh"

die() { echo "eval.sh: $*" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || die "jq is required (JSON results). Install jq and retry."
command -v git >/dev/null 2>&1 || die "git is required (workspace isolation)."

TASK=""; TRIALS=3; PROVIDER=claude; MODEL=""; RUN_ID=""; ALLOW_DIRTY_HEAD=0
TASKS_DIR="$EVAL_TASKS_DIR_DEFAULT"; RESULTS_DIR="$EVAL_RESULTS_DIR_DEFAULT"; TIMEOUT=900
while [ $# -gt 0 ]; do
    case "$1" in
        --trials) TRIALS="$2"; shift 2 ;;
        --provider) PROVIDER="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --run-id) RUN_ID="$2"; shift 2 ;;
        --tasks-dir) TASKS_DIR="$2"; shift 2 ;;
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --allow-dirty-head) ALLOW_DIRTY_HEAD=1; shift ;;
        -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) [ -z "$TASK" ] && TASK="$1" || die "unexpected arg: $1"; shift ;;
    esac
done
[ -n "$TASK" ] || die "usage: bash scripts/eval.sh <task-slug> [options]"
case "$TRIALS" in ''|*[!0-9]*) die "--trials must be a positive integer" ;; esac
[ "$TRIALS" -ge 1 ] || die "--trials must be >= 1"
# A non-integer --timeout would make every numeric test error out and the
# fallback poll loop spin forever (never reaching the cap), so validate it here.
case "$TIMEOUT" in ''|*[!0-9]*) die "--timeout must be a non-negative integer (seconds; 0 disables)" ;; esac

# One timestamp for the whole invocation — every trial's result line carries
# it (see eval_result_json), so eval-harness.sh can pick the truly-latest run
# instead of a lexicographic max over --run-id strings.
RUN_STARTED_AT="$(date +%s)"

# Dirty-tree refusal: eval_prepare_workspace clones committed HEAD only, so
# uncommitted changes in this repo are invisible to every trial and would
# silently go unmeasured. --allow-dirty-head downgrades this to a warning.
DIRTY_COUNT=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "${DIRTY_COUNT:-0}" -gt 0 ]; then
    if [ "$ALLOW_DIRTY_HEAD" -eq 1 ]; then
        echo "eval.sh: WARNING — $DIRTY_COUNT uncommitted change(s) in $ROOT will NOT be measured (trials clone committed HEAD); proceeding (--allow-dirty-head)" >&2
    else
        die "$DIRTY_COUNT uncommitted change(s) in $ROOT would NOT be measured (trials clone committed HEAD) — commit or stash them, or pass --allow-dirty-head to proceed anyway"
    fi
fi

TASK_DIR="$TASKS_DIR/$TASK"
[ -f "$TASK_DIR/TASK.md" ] || die "no task at $TASK_DIR (need TASK.md)"
[ -f "$TASK_DIR/check.sh" ] || die "task $TASK has no check.sh grader"

case "$PROVIDER" in
    claude) [ -n "$MODEL" ] || MODEL=haiku ;;
    codex)  [ -n "$MODEL" ] || MODEL=gpt-5.6-terra ;;
    mock)   MODEL=reference-solution ;;
    *) die "unknown provider: $PROVIDER (claude|codex|mock)" ;;
esac
if [ "$PROVIDER" != mock ]; then
    command -v "$PROVIDER" >/dev/null 2>&1 || die "$PROVIDER CLI not found on PATH"
fi

# Default RUN_ID once PROVIDER/MODEL are resolved: embeds both so two
# providers (or two models of the same provider) launched in the same second
# never collide on a results dir. '/' in MODEL (a path-like model id) is
# sanitized to '-' so it can never create an unwanted subdirectory.
if [ -z "$RUN_ID" ]; then
    MODEL_SAFE="$(printf '%s' "$MODEL" | tr '/' '-')"
    RUN_ID="$(date -u +%Y%m%d-%H%M%S)-$PROVIDER-$MODEL_SAFE"
fi

SUITE="$(eval_task_meta "$TASK_DIR" suite)"; SUITE="${SUITE:-capability}"
POLARITY="$(eval_task_meta "$TASK_DIR" polarity)"; POLARITY="${POLARITY:-positive}"
GRADE_META="$(eval_task_meta "$TASK_DIR" grade)"
TASK_PROVIDER="$(eval_task_meta "$TASK_DIR" provider)"

# Metadata validation: a typo here would otherwise silently bypass scorer
# behavior (e.g. "suite: regresion" quietly scored as capability) instead of
# failing loudly at the one point where the value is known and nameable.
case "$SUITE" in
    capability|regression) ;;
    *) die "task $TASK: invalid suite metadata '$SUITE' (want capability|regression)" ;;
esac
case "$POLARITY" in
    positive|negative) ;;
    *) die "task $TASK: invalid polarity metadata '$POLARITY' (want positive|negative)" ;;
esac
case "$GRADE_META" in
    ''|check|'check+verify') ;;
    *) die "task $TASK: invalid grade metadata '$GRADE_META' (want check|check+verify)" ;;
esac
case "$TASK_PROVIDER" in
    ''|any|claude|codex) ;;
    *) die "task $TASK: invalid provider metadata '$TASK_PROVIDER' (want any|claude|codex)" ;;
esac

# Provider gate: a task pinned to one provider (its prompt or grader assumes
# that CLI's quirks) must not silently run under another. mock is exempt so a
# provider-pinned task still gets plumbing/grader-validity coverage without
# the pinned CLI installed.
if [ -n "$TASK_PROVIDER" ] && [ "$TASK_PROVIDER" != any ] && [ "$PROVIDER" != mock ] && [ "$TASK_PROVIDER" != "$PROVIDER" ]; then
    die "task $TASK is pinned to provider '$TASK_PROVIDER' — refusing to run under --provider $PROVIDER (use --provider $TASK_PROVIDER, or --provider mock for plumbing)"
fi

OUT="$RESULTS_DIR/$TASK/$RUN_ID"
# Atomic collision refusal: `mkdir` (no -p) on the final path component
# either creates the dir or fails if it already exists — a single syscall,
# so two invocations racing on the same run id in the same second can't both
# see "doesn't exist yet" and both proceed (the same race a separate
# `[ -f results.jsonl ] && die` / `: > results.jsonl` pair could not close,
# since a check-then-act has a window between the two). A leftover dir from
# a previous FAILED run also counts as taken — that's intentional: reusing
# it could interleave old and new trial output under one run id.
mkdir -p "$RESULTS_DIR/$TASK"
mkdir "$OUT" 2>/dev/null || die "results dir for run id '$RUN_ID' already exists at $OUT (from this run or a previous one, even a failed one) — pass a fresh --run-id"
RESULTS="$OUT/results.jsonl"
: > "$RESULTS" || die "cannot create results file at $RESULTS"

# Per-trial cap: prefer `timeout`/`gtimeout`, else a portable background+poll.
TIMEOUT_BIN=""
if [ "${TIMEOUT:-0}" -gt 0 ] 2>/dev/null; then
    if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
    elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout; fi
fi

# _eval_capped <stdout_file> <stderr_file> <cmd...>
# Runs <cmd> (redirected) under the $TIMEOUT cap. Uses a timeout binary when
# present; otherwise backgrounds the command and SIGTERM/SIGKILLs it on expiry —
# so a hung agent (e.g. an approval-retry loop) can never stall the whole run,
# even on a macOS box with no coreutils `timeout`. Returns the command's exit
# status, or 124 on timeout.
_eval_capped() {
    local out="$1" err="$2"; shift 2
    if [ "${TIMEOUT:-0}" -le 0 ]; then "$@" >"$out" 2>"$err"; return $?; fi
    if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$TIMEOUT" "$@" >"$out" 2>"$err"; return $?; fi
    # Portable fallback (stock macOS ships no `timeout`): run the agent in its
    # OWN process group via job control (`set -m`), so on expiry we can signal
    # the whole group — killing children the agent spawned, not just the top
    # process. A watchdog fires the kill and drops a marker; we detect the
    # marker to return 124 (timeout) vs the command's real status.
    local pid rc marker watchdog
    marker="$err.timedout"; rm -f "$marker"
    set -m
    { "$@" >"$out" 2>"$err"; } &
    pid=$!
    set +m
    { sleep "$TIMEOUT"; : > "$marker"; kill -TERM -"$pid" 2>/dev/null; sleep 2; kill -KILL -"$pid" 2>/dev/null; } &
    watchdog=$!
    wait "$pid" 2>/dev/null; rc=$?
    kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
    if [ -f "$marker" ]; then
        rm -f "$marker"; echo "eval.sh: trial exceeded ${TIMEOUT}s cap — killed" >&2; return 124
    fi
    return "$rc"
}

# run_agent <provider> <prompt> <workspace> <trial_dir>
# Invokes the provider headlessly in the workspace, capturing a transcript.
# Returns the CLI's exit status (non-zero = the run itself errored; 124 = timed out).
run_agent() {
    local prov="$1" prompt="$2" ws="$3" td="$4"
    case "$prov" in
        claude)
            # claude has no --cwd, so cd inside a bash -c and exec so the polled
            # pid IS claude (a kill on expiry reaches it directly).
            _eval_capped "$td/transcript.jsonl" "$td/agent.stderr" \
                bash -c 'cd "$1" && exec claude -p "$2" --model "$3" \
                    --output-format stream-json --verbose --dangerously-skip-permissions' \
                _ "$ws" "$prompt" "$MODEL"
            ;;
        codex)
            _eval_capped "$td/transcript.jsonl" "$td/agent.stderr" \
                codex exec "$prompt" --model "$MODEL" --cd "$ws" \
                    --sandbox workspace-write --skip-git-repo-check --json \
                    --output-last-message "$td/last-message.txt"
            ;;
        mock)
            # No model: the "agent" is the reference solution. Proves the whole
            # pipeline (isolate -> act -> grade -> record) end to end for free.
            eval_apply_reference "$TASK_DIR" "$ws" >"$td/transcript.jsonl" 2>"$td/agent.stderr"
            ;;
    esac
}

PROMPT="$(eval_task_prompt "$TASK_DIR")"
[ -n "$PROMPT" ] || die "task $TASK has an empty ## Prompt section"

echo "eval: $TASK  provider=$PROVIDER  model=$MODEL  suite=$SUITE  polarity=$POLARITY  trials=$TRIALS"
echo "run:  $OUT"

passes=0
i=1
while [ "$i" -le "$TRIALS" ]; do
    TRIAL_DIR="$OUT/trial-$i"
    mkdir -p "$TRIAL_DIR"
    # Guard mktemp: a failed (empty) result would make WS="/repo" and the
    # teardown `rm -rf` target "/" — catastrophic on BSD rm. Never build a path
    # from an unchecked mktemp, and only ever rm the base dir it returned.
    if ! WS_BASE="$(mktemp -d "${TMPDIR:-/tmp}/eval-$TASK-XXXXXX")" || [ -z "$WS_BASE" ]; then
        die "mktemp failed — cannot create an isolated trial workspace"
    fi
    WS="$WS_BASE/repo"
    start=$(date +%s)
    if ! eval_prepare_workspace "$ROOT" "$WS" "$TASK_DIR"; then
        # Record the failed trial (do NOT silently skip): a skipped trial would
        # leave < N records and let eval-harness compute pass^k from fewer trials
        # than requested, overstating reliability.
        echo "  trial $i: FAILED to prepare workspace — recorded as fail" >&2
        eval_result_json "$TASK" "$PROVIDER" "$MODEL" "$SUITE" "$POLARITY" "$RUN_ID" \
            "$i" false 0 127 "$TRIAL_DIR" "$RUN_STARTED_AT" task_failure >> "$RESULTS" \
            || { rm -rf "$WS_BASE"; die "cannot write results to $RESULTS (trial $i)"; }
        rm -rf "$WS_BASE"; i=$((i+1)); continue
    fi
    run_agent "$PROVIDER" "$PROMPT" "$WS" "$TRIAL_DIR"; agent_rc=$?
    verdict="$(eval_grade "$TASK_DIR" "$WS" "$TRIAL_DIR")"; grade_rc=$?
    end=$(date +%s)
    dur=$((end - start))
    if [ "$grade_rc" -eq 2 ]; then rm -rf "$WS_BASE"; die "grader error on trial $i (no check.sh?)"; fi
    passed=false; [ "$verdict" = pass ] && { passed=true; passes=$((passes+1)); }
    # Map eval_grade's verdict to the recorded outcome: pass stays pass;
    # violation (exit 3 — the shortcut was caught) becomes negative_violation;
    # anything else (ordinary fail) becomes task_failure.
    case "$verdict" in
        pass) outcome=pass ;;
        violation) outcome=negative_violation ;;
        *) outcome=task_failure ;;
    esac

    eval_result_json "$TASK" "$PROVIDER" "$MODEL" "$SUITE" "$POLARITY" "$RUN_ID" \
        "$i" "$passed" "$dur" "$agent_rc" "$TRIAL_DIR" "$RUN_STARTED_AT" "$outcome" >> "$RESULTS" \
        || { rm -rf "$WS_BASE"; die "cannot write results to $RESULTS (trial $i) — a read-only or full disk must not exit 0 with missing rows"; }

    printf '  trial %d: %s  (%ds%s)\n' "$i" \
        "$([ "$passed" = true ] && echo PASS || echo fail)" "$dur" \
        "$([ "$agent_rc" -ne 0 ] && echo ", agent rc=$agent_rc")"
    rm -rf "$WS_BASE"
    i=$((i+1))
done

pk=$(eval_passk "$TRIALS" "$passes")
phk=$(eval_passhatk "$TRIALS" "$passes")
rate=$(eval_passrate "$TRIALS" "$passes")
echo "----"
echo "$TASK: $passes/$TRIALS passed  pass@k=$pk  pass^k=$phk  rate=$rate"
echo "results: $RESULTS"
exit 0
