#!/usr/bin/env bash
# Regression tests for verify.sh's serial/parallel gate orchestration.
# Runnable standalone and in CI; uses handshakes instead of timing thresholds so
# a slow runner cannot make the concurrency assertion flaky.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$SCRIPTS_DIR/verify.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-verify.XXXXXX") || exit 1
export TEST_WORK="$WORK"
export HARNESS_LOG_LIB="$SCRIPTS_DIR/log-lib.sh"
export HARNESS_LOG_FILE="$WORK/gates.jsonl"
fails=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

# build_verify <commands-file> <output-file> — replace only the TAILOR gate
# block, leaving the orchestration framework under test byte-for-byte intact.
build_verify() {
    local commands="$1" output="$2"
    awk -v commands="$commands" '
        /^# -- TAILOR:/ {
            print
            while ((getline line < commands) > 0) print line
            close(commands)
            in_tailor = 1
            next
        }
        in_tailor && /^# -+$/ { in_tailor = 0; print; next }
        !in_tailor { print }
    ' "$VERIFY" > "$output"
    chmod +x "$output"
}

# A rendezvous proves the two jobs overlap: either job would fail if the other
# had not started before it. Successful command output remains buffered/quiet.
cat > "$WORK/success.gates" <<'EOF'
gate "fast-probe" bash -c 'touch "$TEST_WORK/fast"'
parallel_full_gate "first" bash -c 'touch "$TEST_WORK/first.started"; i=0; while [ ! -f "$TEST_WORK/second.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/second.started" ]; echo first-detail'
parallel_full_gate "second" bash -c 'touch "$TEST_WORK/second.started"; i=0; while [ ! -f "$TEST_WORK/first.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/first.started" ]; echo second-detail'
EOF
build_verify "$WORK/success.gates" "$WORK/verify-success.sh"

: > "$HARNESS_LOG_FILE"
out=$(bash "$WORK/verify-success.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
        && printf '%s\n' "$out" | grep -qF 'ok:   first' \
        && printf '%s\n' "$out" | grep -qF 'ok:   second' \
        && ! printf '%s\n' "$out" | grep -qF 'first-detail'; then
    pass "parallel full gates overlap and keep successful output quiet"
else
    fail "parallel full gates did not overlap or report cleanly"
    printf '%s\n' "$out" | sed 's/^/        /'
fi
if jq -e -s '
    length == 3
    and map(.data.name) == ["fast-probe","first","second"]
    and all(.[]; keys == ["context","data","detail","event","file","hook","ts","version"])
    and all(.[]; .version == 2 and .event == "gate" and .data.mode == "full"
        and .data.outcome == "pass" and .data.exit_code == 0
        and (.data.duration_s | type) == "number")' "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    pass "completed gates emit exact v2 events in declaration order"
else
    fail "successful gate telemetry is missing, reordered, or malformed"
fi

stable_disabled=$(HARNESS_LOG=0 bash "$WORK/verify-success.sh" 2>&1); disabled_rc=$?
stable_unwritable=$(HARNESS_LOG_FILE=/dev/null/nope bash "$WORK/verify-success.sh" 2>&1); unwritable_rc=$?
if [ "$disabled_rc" -eq 0 ] && [ "$unwritable_rc" -eq 0 ] \
        && [ "$stable_disabled" = "$stable_unwritable" ]; then
    pass "telemetry failure leaves successful gate output and exit behavior unchanged"
else
    fail "telemetry failure changed successful gate output or exit behavior"
fi

mkdir -p "$WORK/no-jq-bin"
for tool in bash date dirname mktemp rm sleep touch; do
    ln -s "$(command -v "$tool")" "$WORK/no-jq-bin/$tool"
done
rm -f "$WORK/no-jq.jsonl"
missing_jq=$(PATH="$WORK/no-jq-bin" HARNESS_LOG_FILE="$WORK/no-jq.jsonl" \
    "$BASH" "$WORK/verify-success.sh" 2>&1); missing_jq_rc=$?
if [ "$missing_jq_rc" -eq 0 ] && [ "$missing_jq" = "$stable_disabled" ] \
        && [ ! -e "$WORK/no-jq.jsonl" ]; then
    pass "missing jq leaves verify output, exit behavior, and gate execution unchanged"
else
    fail "missing jq changed verify behavior or wrote telemetry"
fi

# A serial full gate declared after a parallel producer must wait for it. This
# is the dependency-safe mixed mode documented by the verify template.
cat > "$WORK/barrier.gates" <<'EOF'
parallel_full_gate "producer" bash -c 'sleep 0.1; touch "$TEST_WORK/ready"'
full_gate "consumer" bash -c 'test -f "$TEST_WORK/ready"'
EOF
build_verify "$WORK/barrier.gates" "$WORK/verify-barrier.sh"

out=$(bash "$WORK/verify-barrier.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
        && printf '%s\n' "$out" | grep -qF 'ok:   producer' \
        && printf '%s\n' "$out" | grep -qF 'ok:   consumer'; then
    pass "serial full gates wait for queued dependencies"
else
    fail "a serial full gate raced a queued dependency"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

rm -f "$WORK/fast" "$WORK/first.started" "$WORK/second.started"
: > "$HARNESS_LOG_FILE"
out=$(bash "$WORK/verify-success.sh" --fast 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WORK/fast" ] \
        && [ ! -e "$WORK/first.started" ] && [ ! -e "$WORK/second.started" ] \
        && printf '%s\n' "$out" | grep -qF 'OK: all quality gates passed (fast)'; then
    pass "--fast runs serial fast gates and skips parallel full gates"
else
    fail "--fast did not preserve its gate boundary"
    printf '%s\n' "$out" | sed 's/^/        /'
fi
if jq -e -s 'length == 1 and .[0].data.name == "fast-probe" and .[0].data.mode == "fast"' \
        "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    pass "--fast emits no events for skipped full gates"
else
    fail "--fast logged a skipped full gate"
fi

# A failed peer must expose its buffered details while the barrier still reaps
# the other jobs (the finisher marker proves verify.sh did not exit prematurely).
cat > "$WORK/failure.gates" <<'EOF'
parallel_full_gate "broken" bash -c 'echo broken-detail; exit 7'
parallel_full_gate "finisher" bash -c 'sleep 0.1; touch "$TEST_WORK/finished"'
EOF
build_verify "$WORK/failure.gates" "$WORK/verify-failure.sh"

: > "$HARNESS_LOG_FILE"
out=$(bash "$WORK/verify-failure.sh" 2>&1); rc=$?
rerun=$(printf '%s\n' "$out" | sed -n 's/^FAIL: broken — fix, then re-run: //p' | head -1)
rerun_out=$(bash -c "$rerun" 2>&1); rerun_rc=$?
if [ "$rc" -eq 1 ] && [ -f "$WORK/finished" ] \
        && printf '%s\n' "$out" | grep -qF 'broken-detail' \
        && printf '%s\n' "$out" | grep -qF 'FAIL: broken — fix, then re-run:' \
        && printf '%s\n' "$out" | grep -qF 'ok:   finisher' \
        && [ "$rerun_rc" -eq 7 ] && [ "$rerun_out" = "broken-detail" ]; then
    pass "parallel failure reports a copy-safe rerun and waits for every peer"
else
    fail "parallel failure handling lost output, quoting, or a peer"
    printf '%s\n' "$out" | sed 's/^/        /'
fi
if jq -e -s '
    map(.data.name) == ["broken","finisher"]
    and .[0].data.outcome == "fail" and .[0].data.exit_code == 7
    and .[1].data.outcome == "pass" and .[1].data.exit_code == 0' \
        "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    pass "parallel failure telemetry preserves status and reaps every peer"
else
    fail "parallel failure telemetry lost status or a peer"
fi

# A serial failure logs before the existing immediate exit. A later gate must
# not run or emit, and command output remains outside the event.
cat > "$WORK/serial-failure.gates" <<'EOF'
gate "serial-broken" bash -c 'echo serial-secret-output; exit 9'
gate "never-runs" bash -c 'exit 0'
EOF
build_verify "$WORK/serial-failure.gates" "$WORK/verify-serial-failure.sh"
: > "$HARNESS_LOG_FILE"
out=$(bash "$WORK/verify-serial-failure.sh" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF serial-secret-output \
        && jq -e -s 'length == 1 and .[0].data.name == "serial-broken"
            and .[0].data.outcome == "fail" and .[0].data.exit_code == 9
            and ([.[0] | tostring] | all(.[]; contains("serial-secret-output") | not))' \
            "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    pass "serial failure logs before exit without capturing command output"
else
    fail "serial failure telemetry changed exit semantics or captured output"
fi

# Cleanup must signal only children that have not been reaped. A fake kill
# function makes the selection observable without signaling real processes.
cat > "$WORK/cleanup.gates" <<'EOF'
kill() { printf '%s\n' "$1" >> "$TEST_WORK/killed"; }
PARALLEL_PIDS=(111 222)
PARALLEL_ACTIVE=(0 1)
cleanup_parallel_gates
PARALLEL_PIDS=()
PARALLEL_ACTIVE=()
EOF
build_verify "$WORK/cleanup.gates" "$WORK/verify-cleanup.sh"

out=$(bash "$WORK/verify-cleanup.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/killed" 2>/dev/null)" = "222" ]; then
    pass "cleanup ignores PIDs that were already reaped"
else
    fail "cleanup retained a stale PID or missed an active child"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails verify orchestration test(s)"
    exit 1
fi
echo "OK: verify orchestration tests passed"
exit 0
