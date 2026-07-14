#!/usr/bin/env bash
# The executable definition of "done": the ordered quality gates every task
# must pass before it is complete. AGENTS.md, CLAUDE.md, and the skills all
# point HERE instead of listing commands, so the gates can never disagree
# across files — edit this file, never the docs.
#
#   bash scripts/verify.sh          # run every gate; independent full gates may overlap
#   bash scripts/verify.sh --fast   # fast gates only (formatter, linter) —
#                                   # cheap enough for an agent stop-hook
#
# Keep serial gates ordered cheapest-first so failures surface early. A failing
# serial gate stops immediately. Parallel full gates are all reaped at the final
# barrier, with buffered output and the exact command to re-run for each failure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MODE=full
case "${1:-}" in
    "") ;;
    --fast) MODE=fast ;;
    *)
        echo "usage: bash scripts/verify.sh [--fast]" >&2
        exit 64
        ;;
esac

# gate <label> <command...>          — runs in both modes; keep these fast (ms-s).
# full_gate <label> <command...>     — serial; skipped under --fast.
# parallel_full_gate <label> <cmd...> — independent; queued until the barrier.
# Commands run verbatim ("$@"); wrap pipelines in `bash -c '...'`.
format_command() {
    local arg escaped rendered=""
    for arg in "$@"; do
        printf -v escaped '%q' "$arg"
        rendered="${rendered}${rendered:+ }${escaped}"
    done
    printf '%s' "$rendered"
}

run_gate() {
    local label="$1" out command; shift
    command=$(format_command "$@")
    if out=$("$@" 2>&1); then
        echo "ok:   $label"
    else
        printf '%s\n' "$out"
        echo "FAIL: $label — fix, then re-run: $command"
        exit 1
    fi
}
gate() { run_gate "$@"; }
full_gate() {
    [ "$MODE" = "fast" ] && return 0
    # A serial full gate is also a dependency barrier for any parallel phase
    # declared before it. Do not let a consumer race its queued producers.
    wait_parallel_gates || exit 1
    run_gate "$@"
}

# Bash 3.2-compatible parallel gate queue (macOS still ships Bash 3.2). Output
# is buffered per gate so concurrent commands cannot interleave unreadably.
# Declaration order controls reporting order, not execution order.
PARALLEL_PIDS=()
PARALLEL_LABELS=()
PARALLEL_OUTPUTS=()
PARALLEL_COMMANDS=()
PARALLEL_ACTIVE=()
PARALLEL_DIR=""

cleanup_parallel_gates() {
    local index pid
    for ((index = 0; index < ${#PARALLEL_PIDS[@]}; index++)); do
        [ "${PARALLEL_ACTIVE[$index]:-0}" -eq 1 ] || continue
        pid=${PARALLEL_PIDS[$index]}
        kill "$pid" 2>/dev/null || true
    done
    [ -n "$PARALLEL_DIR" ] && rm -rf "$PARALLEL_DIR"
}
trap cleanup_parallel_gates EXIT

parallel_full_gate() {
    [ "$MODE" = "fast" ] && return 0
    local label="$1" index out; shift
    if [ -z "$PARALLEL_DIR" ]; then
        PARALLEL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/harness-verify.XXXXXX") || {
            echo "FAIL: could not create parallel-gate scratch directory" >&2
            exit 1
        }
    fi
    index=${#PARALLEL_PIDS[@]}
    out="$PARALLEL_DIR/$index.out"
    ( "$@" >"$out" 2>&1 ) &
    PARALLEL_PIDS[$index]=$!
    PARALLEL_ACTIVE[$index]=1
    PARALLEL_LABELS[$index]="$label"
    PARALLEL_OUTPUTS[$index]="$out"
    PARALLEL_COMMANDS[$index]=$(format_command "$@")
}

wait_parallel_gates() {
    local index status failed=0
    for ((index = 0; index < ${#PARALLEL_PIDS[@]}; index++)); do
        if wait "${PARALLEL_PIDS[$index]}"; then
            status=0
        else
            status=$?
        fi
        # wait reaped this child; never retain a stale PID that could be reused
        # and signaled by the EXIT cleanup while a later gate is still running.
        PARALLEL_ACTIVE[$index]=0
        if [ "$status" -eq 0 ]; then
            echo "ok:   ${PARALLEL_LABELS[$index]}"
        else
            [ -s "${PARALLEL_OUTPUTS[$index]}" ] \
                && cat "${PARALLEL_OUTPUTS[$index]}"
            echo "FAIL: ${PARALLEL_LABELS[$index]} — fix, then re-run: ${PARALLEL_COMMANDS[$index]}"
            failed=1
        fi
    done
    PARALLEL_PIDS=()
    PARALLEL_LABELS=()
    PARALLEL_OUTPUTS=()
    PARALLEL_COMMANDS=()
    PARALLEL_ACTIVE=()
    [ -n "$PARALLEL_DIR" ] && rm -rf "$PARALLEL_DIR"
    PARALLEL_DIR=""
    return "$failed"
}

# -- TAILOR: the quality gates -------------------------------------------------
# This repo is shell + markdown + JSON: lint every script (shipped templates
# and the installed copies), validate the plugin manifests, run the template
# regression tests, and the harness drift gate (which runs the installed hook
# tests itself).

gate      "shellcheck" bash -c 'shellcheck -x --severity=warning \
    plugins/harness-kit/skills/harness-kit/templates/scripts/*.sh \
    plugins/harness-kit/skills/harness-kit/templates/scripts/hooks/*.sh \
    scripts/*.sh scripts/hooks/*.sh'
full_gate "manifests" bash scripts/check-packaging.sh
# Every template regression script owns its scratch fixtures, so these are safe
# to schedule independently. The long install suite no longer serializes the
# eval, hook, and harness suites behind it.
for t in plugins/harness-kit/skills/harness-kit/templates/scripts/test-*.sh \
         plugins/harness-kit/skills/harness-kit/templates/scripts/hooks/test-*.sh; do
    parallel_full_gate "template-test: ${t#plugins/harness-kit/skills/harness-kit/templates/scripts/}" bash "$t"
done
# Behavioral-eval grader validity for THIS repo's real golden-task bank. The
# template test above only runs the shipped _template (empty bank), and
# the nested harness gate below skips the root test-eval.sh (its graders call
# check-harness.sh — would recurse). So the real bank is validated here, once,
# with no model in the loop. Dogfood-only, same rationale as the dedup below.
parallel_full_gate "evals" bash scripts/test-eval.sh
# HARNESS_NESTED_FIXTURE here skips check-harness.sh's re-run of test-install.sh
# and test-check-harness.sh (each spins up fixtures / sub-checks and is already
# run above on the byte-identical templates, so re-running the root copies is
# pure duplication). Every guard behavioral test still runs, so the harness drift
# gate keeps full coverage. This double-run only exists in THIS dogfood repo (a
# user install has just the harness gate), which is why it lives in the tailored
# verify.sh, not the shipped template.
parallel_full_gate "harness" env HARNESS_NESTED_FIXTURE=1 bash scripts/check-harness.sh
# ------------------------------------------------------------------------------

wait_parallel_gates || exit 1
echo "OK: all quality gates passed ($MODE)"
exit 0
