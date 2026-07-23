#!/usr/bin/env bash
# Regression tests for the verify runner's serial/parallel gate orchestration
# and its .harness/gates.conf reader. Each case builds a throwaway fixture
# repo around the UNMODIFIED runner — the mechanism under test stays
# byte-for-byte the shipped file; only the repo's gates.conf policy data
# varies per case (the mechanism/policy split is itself what these tests pin).
# Runnable standalone and in CI; uses handshakes instead of timing thresholds
# so a slow runner cannot make the concurrency assertion flaky.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$(cd "$TESTS_DIR/.." && pwd)/verify"
LIB_DIR="$(cd "$TESTS_DIR/../lib" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-verify.XXXXXX") || exit 1
export TEST_WORK="$WORK"
export HARNESS_LOG_LIB="$LIB_DIR/log-lib.sh"
export HARNESS_LOG_FILE="$WORK/gates.jsonl"
fails=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

# has <haystack> <needle> — pure-shell substring test. `printf '%s' "$out" |
# grep -qF` is banned here: grep -q's early exit + an inherited ignored
# SIGPIPE + pipefail turns a MATCH into a phantom failure once $out (a full
# verify transcript) outgrows the pipe buffer. See the completeness note in
# the tests family (lib/check-tests.sh).
has() {
    case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

# make_fixture <name> <gates-file> — a minimal repo skeleton around a copy of
# the shipped runner; prints the runner path. The runner resolves its repo
# root from its own location (scripts/harness/ -> two up) and reads
# .harness/gates.conf from there.
make_fixture() {
    local dir="$WORK/$1"
    mkdir -p "$dir/scripts/harness" "$dir/.harness"
    cp "$VERIFY" "$dir/scripts/harness/verify"
    chmod +x "$dir/scripts/harness/verify"
    [ -n "${2:-}" ] && cp "$2" "$dir/.harness/gates.conf"
    printf '%s' "$dir/scripts/harness/verify"
}

# A rendezvous proves the two jobs overlap: either job would fail if the other
# had not started before it. Successful command output remains buffered/quiet.
cat > "$WORK/success.gates" <<'EOF'
# fixture gate policy: one fast serial gate + a two-job rendezvous
gate fast-probe touch "$TEST_WORK/fast"
parallel first touch "$TEST_WORK/first.started"; i=0; while [ ! -f "$TEST_WORK/second.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/second.started" ]; echo first-detail
parallel second touch "$TEST_WORK/second.started"; i=0; while [ ! -f "$TEST_WORK/first.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/first.started" ]; echo second-detail
EOF
V_SUCCESS=$(make_fixture success "$WORK/success.gates")

: > "$HARNESS_LOG_FILE"
out=$(bash "$V_SUCCESS" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
        && has "$out" 'ok:   first' \
        && has "$out" 'ok:   second' \
        && ! has "$out" 'first-detail'; then
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

stable_disabled=$(HARNESS_LOG=0 bash "$V_SUCCESS" 2>&1); disabled_rc=$?
stable_unwritable=$(HARNESS_LOG_FILE=/dev/null/nope bash "$V_SUCCESS" 2>&1); unwritable_rc=$?
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
    "$BASH" "$V_SUCCESS" 2>&1); missing_jq_rc=$?
if [ "$missing_jq_rc" -eq 0 ] && [ "$missing_jq" = "$stable_disabled" ] \
        && [ ! -e "$WORK/no-jq.jsonl" ]; then
    pass "missing jq leaves verify output, exit behavior, and gate execution unchanged"
else
    fail "missing jq changed verify behavior or wrote telemetry"
fi

# A serial full gate declared after a parallel producer must wait for it. This
# is the dependency-safe mixed mode the runner's header documents.
cat > "$WORK/barrier.gates" <<'EOF'
parallel producer sleep 0.1; touch "$TEST_WORK/ready"
full consumer test -f "$TEST_WORK/ready"
EOF
V_BARRIER=$(make_fixture barrier "$WORK/barrier.gates")

out=$(bash "$V_BARRIER" 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
        && has "$out" 'ok:   producer' \
        && has "$out" 'ok:   consumer'; then
    pass "serial full gates wait for queued dependencies"
else
    fail "a serial full gate raced a queued dependency"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

rm -f "$WORK/fast" "$WORK/first.started" "$WORK/second.started"
: > "$HARNESS_LOG_FILE"
out=$(bash "$V_SUCCESS" --fast 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WORK/fast" ] \
        && [ ! -e "$WORK/first.started" ] && [ ! -e "$WORK/second.started" ] \
        && has "$out" 'OK: all quality gates passed (fast)'; then
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
# the other jobs (the finisher marker proves the runner did not exit early).
cat > "$WORK/failure.gates" <<'EOF'
parallel broken echo broken-detail; exit 7
parallel finisher sleep 0.1; touch "$TEST_WORK/finished"
EOF
V_FAILURE=$(make_fixture failure "$WORK/failure.gates")

: > "$HARNESS_LOG_FILE"
out=$(bash "$V_FAILURE" 2>&1); rc=$?
# sed reads the whole input (no early exit); the first-line trim is pure shell
# so no early-exiting reader ever sits downstream of the printf.
rerun=$(printf '%s\n' "$out" | sed -n 's/^FAIL: broken — fix, then re-run: //p')
rerun=${rerun%%$'\n'*}
rerun_out=$(bash -c "$rerun" 2>&1); rerun_rc=$?
if [ "$rc" -eq 1 ] && [ -f "$WORK/finished" ] \
        && has "$out" 'broken-detail' \
        && has "$out" 'FAIL: broken — fix, then re-run:' \
        && has "$out" 'ok:   finisher' \
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
gate serial-broken echo serial-secret-output; exit 9
gate never-runs exit 0
EOF
V_SERIAL=$(make_fixture serial-failure "$WORK/serial-failure.gates")
: > "$HARNESS_LOG_FILE"
out=$(bash "$V_SERIAL" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" 'serial-secret-output' \
        && jq -e -s 'length == 1 and .[0].data.name == "serial-broken"
            and .[0].data.outcome == "fail" and .[0].data.exit_code == 9
            and ([.[0] | tostring] | all(.[]; contains("serial-secret-output") | not))' \
            "$HARNESS_LOG_FILE" >/dev/null 2>&1; then
    pass "serial failure logs before exit without capturing command output"
else
    fail "serial failure telemetry changed exit semantics or captured output"
fi

# parallel-each fans one gate out per glob match, expanded from the repo root,
# labeled with the file's basename.
cat > "$WORK/each.gates" <<'EOF'
parallel-each check checks/*.sh
EOF
V_EACH=$(make_fixture each "$WORK/each.gates")
mkdir -p "$WORK/each/checks"
printf '#!/usr/bin/env bash\ntouch "$TEST_WORK/ran-alpha"\n' > "$WORK/each/checks/alpha.sh"
printf '#!/usr/bin/env bash\ntouch "$TEST_WORK/ran-beta"\n'  > "$WORK/each/checks/beta.sh"
out=$(bash "$V_EACH" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$WORK/ran-alpha" ] && [ -f "$WORK/ran-beta" ] \
        && has "$out" 'ok:   check: alpha.sh' \
        && has "$out" 'ok:   check: beta.sh'; then
    pass "parallel-each runs one labeled gate per matching file"
else
    fail "parallel-each missed a file or mislabeled a gate"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

# The reader rejects bad policy data loudly: a missing gates.conf, a
# malformed declaration, and an unknown kind each fail with a pointed message
# instead of silently verifying nothing.
V_NOCONF=$(make_fixture noconf)
out=$(bash "$V_NOCONF" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" '.harness/gates.conf is missing'; then
    pass "missing gates.conf fails loudly instead of passing vacuously"
else
    fail "missing gates.conf should fail with a restore hint (rc=$rc)"
fi

printf 'gate onlylabel\n' > "$WORK/malformed.gates"
V_MALFORMED=$(make_fixture malformed "$WORK/malformed.gates")
out=$(bash "$V_MALFORMED" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" 'malformed .harness/gates.conf line'; then
    pass "a declaration without a command is rejected with the offending line"
else
    fail "malformed gates.conf line was not rejected (rc=$rc)"
fi

printf 'bogus label true\n' > "$WORK/badkind.gates"
V_BADKIND=$(make_fixture badkind "$WORK/badkind.gates")
out=$(bash "$V_BADKIND" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" "unknown gate kind 'bogus'"; then
    pass "an unknown gate kind is rejected"
else
    fail "unknown gate kind was not rejected (rc=$rc)"
fi

# Cleanup must signal only children that have not been reaped. A fake kill
# function makes the selection observable without signaling real processes;
# the HARNESS_VERIFY_PRELUDE seam injects it ahead of the (empty) gate list.
printf '# no gates\n' > "$WORK/empty.gates"
V_CLEANUP=$(make_fixture cleanup "$WORK/empty.gates")
cat > "$WORK/cleanup-prelude.sh" <<'EOF'
kill() { printf '%s\n' "$1" >> "$TEST_WORK/killed"; }
PARALLEL_PIDS=(111 222)
PARALLEL_ACTIVE=(0 1)
cleanup_parallel_gates
PARALLEL_PIDS=()
PARALLEL_ACTIVE=()
EOF
out=$(HARNESS_VERIFY_PRELUDE="$WORK/cleanup-prelude.sh" bash "$V_CLEANUP" 2>&1); rc=$?
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
