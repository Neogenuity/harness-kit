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
LOG_LIB_PATH="${HARNESS_LOG_LIB:-$ROOT/scripts/log-lib.sh}"
# shellcheck source=/dev/null
[ -f "$LOG_LIB_PATH" ] && . "$LOG_LIB_PATH" 2>/dev/null || true

MODE=full
case "${1:-}" in
    "") ;;
    --fast) MODE=fast ;;
    *)
        echo "usage: bash scripts/verify.sh [--fast]" >&2
        exit 64
        ;;
esac

VERIFY_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
VERIFY_CONTEXT='{}'
if command -v harness_log_context >/dev/null 2>&1; then
    VERIFY_CONTEXT=$(harness_log_context "$VERIFY_RUN_ID" verify \
        "${HARNESS_SESSION_ID:-}" "${HARNESS_SESSION_ID:+env}" \
        "${HARNESS_PROVIDER:-}" "${HARNESS_PROVIDER:+env}" \
        "${HARNESS_PLAN_SLUG:-}" "${HARNESS_PLAN_SLUG:+env}")
fi

emit_gate_event() {
    local label="$1" outcome="$2" exit_code="$3" duration_s="$4" data
    command -v harness_log_v2 >/dev/null 2>&1 || return 0
    data=$(jq -cn --arg name "$label" --arg mode "$MODE" --arg outcome "$outcome" \
        --argjson exit_code "$exit_code" --argjson duration_s "$duration_s" \
        '{name:$name,mode:$mode,outcome:$outcome,exit_code:$exit_code,duration_s:$duration_s}' \
        2>/dev/null) || return 0
    harness_log_v2 "$ROOT" verify.sh gate "" "" "$VERIFY_CONTEXT" "$data"
}

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
    local label="$1" out command status started duration outcome; shift
    command=$(format_command "$@")
    started=$SECONDS
    if out=$("$@" 2>&1); then
        status=0
        outcome=pass
        duration=$((SECONDS - started))
        emit_gate_event "$label" "$outcome" "$status" "$duration"
        echo "ok:   $label"
    else
        status=$?
        outcome=fail
        duration=$((SECONDS - started))
        emit_gate_event "$label" "$outcome" "$status" "$duration"
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
PARALLEL_METAS=()
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
    local label="$1" index out meta; shift
    if [ -z "$PARALLEL_DIR" ]; then
        PARALLEL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/harness-verify.XXXXXX") || {
            echo "FAIL: could not create parallel-gate scratch directory" >&2
            exit 1
        }
    fi
    index=${#PARALLEL_PIDS[@]}
    out="$PARALLEL_DIR/$index.out"
    meta="$PARALLEL_DIR/$index.meta"
    (
        started=$SECONDS
        "$@" >"$out" 2>&1
        status=$?
        duration=$((SECONDS - started))
        printf '%s %s\n' "$status" "$duration" >"$meta" 2>/dev/null || true
        exit "$status"
    ) &
    PARALLEL_PIDS[$index]=$!
    PARALLEL_ACTIVE[$index]=1
    PARALLEL_LABELS[$index]="$label"
    PARALLEL_OUTPUTS[$index]="$out"
    PARALLEL_METAS[$index]="$meta"
    PARALLEL_COMMANDS[$index]=$(format_command "$@")
}

wait_parallel_gates() {
    local index status recorded_status duration outcome failed=0
    for ((index = 0; index < ${#PARALLEL_PIDS[@]}; index++)); do
        if wait "${PARALLEL_PIDS[$index]}"; then
            status=0
        else
            status=$?
        fi
        # wait reaped this child; never retain a stale PID that could be reused
        # and signaled by the EXIT cleanup while a later gate is still running.
        PARALLEL_ACTIVE[$index]=0
        recorded_status=$status
        duration=0
        if [ -s "${PARALLEL_METAS[$index]}" ]; then
            read -r recorded_status duration < "${PARALLEL_METAS[$index]}" || true
        fi
        case "$recorded_status" in ''|*[!0-9]*) recorded_status=$status ;; esac
        case "$duration" in ''|*[!0-9]*) duration=0 ;; esac
        if [ "$recorded_status" -eq 0 ]; then outcome=pass; else outcome=fail; fi
        emit_gate_event "${PARALLEL_LABELS[$index]}" "$outcome" "$recorded_status" "$duration"
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
    PARALLEL_METAS=()
    PARALLEL_COMMANDS=()
    PARALLEL_ACTIVE=()
    [ -n "$PARALLEL_DIR" ] && rm -rf "$PARALLEL_DIR"
    PARALLEL_DIR=""
    return "$failed"
}

# -- TAILOR: the quality gates -------------------------------------------------
# Fill these from the project's real toolchain at init. Examples:
#
# gate      "format"    vendor/bin/pint --test
# gate      "lint"      npx oxlint
# parallel_full_gate "typecheck" vendor/bin/phpstan analyse --no-progress
# parallel_full_gate "tests"     php artisan test --parallel
# Use full_gate instead when a gate consumes another gate's output.
# full_gate "smoke" bash scripts/dev.sh health

full_gate "harness" bash scripts/check-harness.sh
# ------------------------------------------------------------------------------

wait_parallel_gates || exit 1
echo "OK: all quality gates passed ($MODE)"
exit 0
