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
# GitHub Actions and most runners export CI=true, and the runner under test
# deliberately REFUSES --changed there (the cache is writable by the agent whose
# work verify gates, so the one place it must never run is the place where the
# green is the artifact). This suite drives --changed directly, so it has to
# control that variable rather than inherit it. The case that asserts the
# refusal sets CI=true for its own invocation only.
unset CI
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
# Run with an explicit --jobs 4 so the overlap proof cannot deadlock under the
# bounded default on a low-core host (the default job cap is the core count).
cat > "$WORK/success.gates" <<'EOF'
# fixture gate policy: one fast serial gate + a two-job rendezvous
gate fast-probe touch "$TEST_WORK/fast"
parallel first touch "$TEST_WORK/first.started"; i=0; while [ ! -f "$TEST_WORK/second.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/second.started" ]; echo first-detail
parallel second touch "$TEST_WORK/second.started"; i=0; while [ ! -f "$TEST_WORK/first.started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done; [ -f "$TEST_WORK/first.started" ]; echo second-detail
EOF
V_SUCCESS=$(make_fixture success "$WORK/success.gates")

: > "$HARNESS_LOG_FILE"
out=$(bash "$V_SUCCESS" --jobs 4 2>&1); rc=$?
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

stable_disabled=$(HARNESS_LOG=0 bash "$V_SUCCESS" --jobs 4 2>&1); disabled_rc=$?
stable_unwritable=$(HARNESS_LOG_FILE=/dev/null/nope bash "$V_SUCCESS" --jobs 4 2>&1); unwritable_rc=$?
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
    "$BASH" "$V_SUCCESS" --jobs 4 2>&1); missing_jq_rc=$?
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

# --- bounded concurrency (--jobs / HARNESS_JOBS) ------------------------------
# Under --jobs 1 the queue is strictly serial: the second gate must observe the
# first's completion marker (spawning it blocks on reaping the first). The same
# fixture also proves a throttle-reaped job still reports at the barrier in
# declaration order with its real status.
cat > "$WORK/serial.gates" <<'EOF'
parallel one touch "$TEST_WORK/one.done"
parallel two test -f "$TEST_WORK/one.done"
EOF
V_JOBS=$(make_fixture jobs "$WORK/serial.gates")
rm -f "$WORK/one.done"
out=$(bash "$V_JOBS" --jobs 1 2>&1); rc=$?
if [ "$rc" -eq 0 ] && has "$out" 'ok:   one' && has "$out" 'ok:   two'; then
    pass "--jobs 1 serializes parallel gates (later gates see earlier completions)"
else
    fail "--jobs 1 did not serialize, or a throttle-reaped gate lost its status"
    printf '%s\n' "$out" | sed 's/^/        /'
fi
rm -f "$WORK/one.done"
out=$(HARNESS_JOBS=1 bash "$V_JOBS" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && has "$out" 'ok:   two'; then
    pass "HARNESS_JOBS=1 applies the same cap via the environment"
else
    fail "HARNESS_JOBS=1 was not honored"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

# A throttle-reaped FAILURE must still be reported as a failure at the barrier
# (the reap path records the status the barrier's wait can no longer observe).
cat > "$WORK/serial-fail.gates" <<'EOF'
parallel sf-broken exit 3
parallel sf-later exit 0
EOF
V_JOBSFAIL=$(make_fixture jobsfail "$WORK/serial-fail.gates")
out=$(bash "$V_JOBSFAIL" --jobs 1 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" 'FAIL: sf-broken' && has "$out" 'ok:   sf-later'; then
    pass "--jobs 1 preserves a throttle-reaped failure and its peers' results"
else
    fail "a throttle-reaped failure was lost or misreported under --jobs 1 (rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

# The barrier semantics survive throttling: a serial full gate after a queued
# producer still waits for it under --jobs 1.
rm -f "$WORK/ready"
out=$(bash "$V_BARRIER" --jobs 1 2>&1); rc=$?
if [ "$rc" -eq 0 ] && has "$out" 'ok:   consumer'; then
    pass "serial full gates still wait for queued dependencies under --jobs 1"
else
    fail "the dependency barrier broke under --jobs 1"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

# Invalid job counts are usage errors, not silently-adopted values. "00" is
# all digits but numerically zero (a digit-only pattern alone admits it, and
# the throttle loop then reaps job index -1); the 20-digit value is past
# intmax, where `[ -lt ]` errors mid-throttle instead of comparing.
for badjobs in 0 00 nope -2 99999999999999999999; do
    out=$(bash "$V_JOBS" --jobs "$badjobs" 2>&1); rc=$?
    if [ "$rc" -eq 64 ] && has "$out" 'usage:'; then
        pass "--jobs $badjobs is rejected as a usage error"
    else
        fail "--jobs $badjobs was not rejected (rc=$rc)"
    fi
done

# --- parallel-each with a glob matching nothing -------------------------------
# A typo'd glob must FAIL loudly, never declare zero gates and pass vacuously.
cat > "$WORK/ghost.gates" <<'EOF'
parallel-each ghost checks-that-do-not-exist/*.sh
EOF
V_GHOST=$(make_fixture ghost "$WORK/ghost.gates")
out=$(bash "$V_GHOST" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && has "$out" 'matched no files'; then
    pass "a parallel-each glob matching nothing fails loudly instead of passing vacuously"
else
    fail "an empty parallel-each glob did not fail (rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/        /'
fi

# --- --changed: memoization on proof ------------------------------------------
# A gate is skipped ONLY on a digest proving its declared inputs are unchanged.
# Every case below pins a FAIL-CLOSED property: the cost of a wrong skip is a
# green verify that proved nothing, so each hazard must produce a run (or a
# hard failure), never a silent hit.

# changed_fixture <name> — a fixture whose gate appends to a run-log, so "did
# the gate body actually execute" is a fact on disk rather than an inference
# from the transcript.
changed_fixture() {
    local dir="$WORK/$1" v
    mkdir -p "$dir/scripts/harness" "$dir/.harness" "$dir/inputs"
    cp "$VERIFY" "$dir/scripts/harness/verify"
    chmod +x "$dir/scripts/harness/verify"
    printf 'one\n' > "$dir/inputs/a.txt"
    printf 'two\n' > "$dir/inputs/b.txt"
    printf '# inputs probe inputs\nparallel probe bash -c "echo ran >> %s/%s.ran; true"\n' \
        "$WORK" "$1" > "$dir/.harness/gates.conf"
    v="$dir/scripts/harness/verify"
    printf '%s' "$v"
}
ran_count() { [ -f "$WORK/$1.ran" ] && wc -l < "$WORK/$1.ran" | tr -d ' ' || echo 0; }

V_C=$(changed_fixture hit)
out=$(bash "$V_C" --changed 2>&1)
out2=$(bash "$V_C" --changed 2>&1)
if has "$out2" "(cached" && [ "$(ran_count hit)" = "1" ]; then
    pass "a second --changed run skips the gate on proof and says so out loud"
else
    fail "expected a loud cached skip on the second run (ran=$(ran_count hit))"
    printf '%s\n' "$out2" | sed 's/^/        /'
fi

printf 'mutated\n' > "$WORK/hit/inputs/a.txt"
out=$(bash "$V_C" --changed 2>&1)
if ! has "$out" "(cached" && [ "$(ran_count hit)" = "2" ]; then
    pass "touching a declared input re-runs the gate"
else
    fail "a changed declared input did not re-run the gate (ran=$(ran_count hit))"
fi

printf 'x\n' > "$WORK/hit/unrelated.txt"
out=$(bash "$V_C" --changed 2>&1)
if has "$out" "(cached"; then
    pass "a file outside the declared input set does not invalidate"
else
    fail "an undeclared file wrongly invalidated the cache"
fi

# The runner and the whole gate list are key material: a runner upgrade or a
# neighbouring gate's edit both change what a recorded pass described.
printf '\n# touched\n' >> "$WORK/hit/scripts/harness/verify"
out=$(bash "$V_C" --changed 2>&1)
if ! has "$out" "(cached"; then
    pass "editing the runner invalidates every cached gate"
else
    fail "a modified runner still served a cached result"
fi
bash "$V_C" --changed >/dev/null 2>&1
printf 'parallel other bash -c "true"\n' >> "$WORK/hit/.harness/gates.conf"
out=$(bash "$V_C" --changed 2>&1)
if ! has "$out" "probe (cached"; then
    pass "editing an unrelated gates.conf line invalidates (ordering and neighbours are key material)"
else
    fail "an edited gates.conf still served a cached result"
fi

# A failing gate must never be recorded: a cached failure would be permanent.
V_C=$(changed_fixture failing)
printf '# inputs probe inputs\nparallel probe bash -c "exit 3"\n' > "$WORK/failing/.harness/gates.conf"
bash "$V_C" --changed >/dev/null 2>&1
out=$(bash "$V_C" --changed 2>&1); rc=$?
if [ "$rc" -ne 0 ] && ! has "$out" "(cached"; then
    pass "a failing gate is never cached"
else
    fail "a failing gate was cached or stopped failing (rc=$rc)"
fi

# A gate that rewrites its own declared inputs cannot be proven: the digest
# after the run differs from the one before it, so nothing is recorded.
V_C=$(changed_fixture selfmutating)
printf '# inputs probe inputs\nparallel probe bash -c "date >> inputs/a.txt; true"\n' \
    > "$WORK/selfmutating/.harness/gates.conf"
bash "$V_C" --changed >/dev/null 2>&1
out=$(bash "$V_C" --changed 2>&1)
if ! has "$out" "(cached"; then
    pass "a gate that mutates its own declared inputs is never cached"
else
    fail "a self-mutating gate was cached"
fi

# Config errors fail the run BEFORE any gate executes; a silently inert or
# vacuous annotation is the whole hazard this feature has to avoid.
for probe_case in \
    "nomatch:# inputs probe does/not/exist:matched no files" \
    "orphan:# inputs typoed src:no gate/full/parallel line declares" \
    "dup:# inputs probe inputs\n# inputs probe inputs:declared more than once" \
    "bogus:# inputs probe @nope inputs:unknown"; do
    name=${probe_case%%:*}
    rest=${probe_case#*:}
    decl=${rest%:*}
    want=${rest##*:}
    V_C=$(changed_fixture "cfg$name")
    # shellcheck disable=SC2059
    printf "$decl\nparallel probe bash -c \"true\"\n" > "$WORK/cfg$name/.harness/gates.conf"
    out=$(bash "$V_C" --changed 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && has "$out" "$want"; then
        pass "a $name '# inputs' annotation fails the run instead of skipping silently"
    else
        fail "$name annotation did not fail loudly (rc=$rc)"
        printf '%s\n' "$out" | sed 's/^/        /'
    fi
done

# --fast asks for LESS coverage, --changed for the same coverage minus what is
# proven: resolving the pair silently is how a caller over-trusts a run.
V_C=$(changed_fixture modes)
out=$(bash "$V_C" --fast --changed 2>&1); rc=$?
if [ "$rc" -eq 64 ] && has "$out" "usage:"; then
    pass "--fast and --changed together are a usage error, not a silent winner"
else
    fail "--fast --changed was accepted (rc=$rc)"
fi
out=$(CI=true bash "$V_C" --changed 2>&1); rc=$?
if [ "$rc" -ne 0 ] && has "$out" "CI"; then
    pass "--changed refuses under CI=true, where the green is the artifact"
else
    fail "--changed ran under CI=true (rc=$rc)"
fi

# A skipped gate is not fabricated as a run, and a gate that DOES run under
# --changed reports mode "full" — same command, same exit-status contract — so
# the audit log's mode enum needs no widening.
V_C=$(changed_fixture telemetry)
: > "$HARNESS_LOG_FILE"
bash "$V_C" --changed >/dev/null 2>&1
before=$(wc -l < "$HARNESS_LOG_FILE" | tr -d ' ')
bash "$V_C" --changed >/dev/null 2>&1
after=$(wc -l < "$HARNESS_LOG_FILE" | tr -d ' ')
if [ "$before" = "$after" ]; then
    pass "a cached skip emits no gate event"
else
    fail "a cached skip fabricated a gate event ($before -> $after)"
fi
if command -v jq >/dev/null 2>&1; then
    if [ "$(jq -r 'select(.data.name=="probe") | .data.mode' "$HARNESS_LOG_FILE" | sort -u)" = "full" ]; then
        pass "a gate that runs under --changed reports mode \"full\""
    else
        fail "a --changed run emitted a mode outside the audit log's enum"
    fi
fi
: > "$HARNESS_LOG_FILE"

# The separation between "a warmed cache" and "a skipped CI gate" is one mode
# test in each hit site. Nothing else stops full mode from serving hits, and CI
# runs full mode — so pin it directly.
V_C=$(changed_fixture fullmode)
bash "$V_C" --changed >/dev/null 2>&1
bash "$V_C" --changed >/dev/null 2>&1
before=$(ran_count fullmode)
out=$(bash "$V_C" 2>&1)
if [ "$(ran_count fullmode)" != "$before" ] && ! has "$out" "(cached"; then
    pass "full mode warms the cache but never serves a hit from it"
else
    fail "full mode served a cached result — CI would stop running gates"
fi

# Two gates sharing a label share one key: the passing twin warms it and the
# failing twin is served it, turning a red run green on the next pass.
V_C=$(changed_fixture duplabel)
printf '# inputs probe inputs\nparallel probe bash -c "true"\nparallel probe bash -c "exit 7"\n' \
    > "$WORK/duplabel/.harness/gates.conf"
out=$(bash "$V_C" --changed 2>&1); rc=$?
if [ "$rc" -ne 0 ] && has "$out" "declared more than once"; then
    pass "a duplicate gate label is rejected before it can share a cache key"
else
    fail "duplicate gate labels were accepted (rc=$rc)"
fi

# `for tok in $toks` already pathname-expands, so a second split would break a
# path containing a space into fragments — hashing a same-named decoy while the
# declared file stays invisible.
V_C=$(changed_fixture spaced)
printf 'original\n' > "$WORK/spaced/inputs/a b.txt"
bash "$V_C" --changed >/dev/null 2>&1
before=$(ran_count spaced)
printf 'mutated\n' > "$WORK/spaced/inputs/a b.txt"
out=$(bash "$V_C" --changed 2>&1)
if [ "$(ran_count spaced)" != "$before" ] && ! has "$out" "(cached"; then
    pass "a declared path containing a space is real key material"
else
    fail "a spaced filename was invisible to the key"
fi

# Ambient environment is not otherwise in the key, and this release's other half
# exists because ambient variables can hollow out a gate.
V_C=$(changed_fixture envkey)
bash "$V_C" --changed >/dev/null 2>&1
out=$(HARNESS_PROBE_SWITCH=1 bash "$V_C" --changed 2>&1)
if ! has "$out" "(cached"; then
    pass "a changed HARNESS_* variable invalidates the cache"
else
    fail "the environment is not key material"
fi

# The serial kinds have their own hit/record sites, and the shipped template
# aims adopters at `full` — so exercise them, not just `parallel`.
V_C=$(changed_fixture serial)
printf '# inputs probe inputs\ngate probe bash -c "echo ran >> %s/serial.ran; true"\n' "$WORK" \
    > "$WORK/serial/.harness/gates.conf"
bash "$V_C" --changed >/dev/null 2>&1
before=$(ran_count serial)
out=$(bash "$V_C" --changed 2>&1)
if has "$out" "(cached" && [ "$(ran_count serial)" = "$before" ]; then
    pass "a serial gate takes the same proof-based skip as a parallel one"
else
    fail "the serial cache path did not hit (ran=$(ran_count serial))"
fi

# @tool: pins a binary's identity; a different resolved path must invalidate.
V_C=$(changed_fixture tooltok)
printf '# inputs probe inputs @tool:git\nparallel probe bash -c "true"\n' \
    > "$WORK/tooltok/.harness/gates.conf"
if command -v git >/dev/null 2>&1; then
    bash "$V_C" --changed >/dev/null 2>&1
    out=$(bash "$V_C" --changed 2>&1)
    if has "$out" "(cached"; then
        mkdir -p "$WORK/tooltok/fakebin"
        printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v git)" > "$WORK/tooltok/fakebin/git"
        chmod +x "$WORK/tooltok/fakebin/git"
        out=$(PATH="$WORK/tooltok/fakebin:$PATH" bash "$V_C" --changed 2>&1)
        if ! has "$out" "(cached"; then
            pass "@tool: makes a binary's resolved identity key material"
        else
            fail "@tool: did not notice a different binary on PATH"
        fi
    else
        fail "@tool: fixture never cached on the second run"
    fi
fi

# @git-head exists because a gate reading COMMITTED state would otherwise be
# keyed on a working tree it never reads: a commit that leaves the tree
# byte-identical must still invalidate.
if command -v git >/dev/null 2>&1; then
    V_C=$(changed_fixture githead)
    G="$WORK/githead"
    printf '# inputs probe inputs @git-head\nparallel probe bash -c "true"\n' > "$G/.harness/gates.conf"
    ( cd "$G" && git init -q . && git config user.email t@e.st && git config user.name t \
        && git add -A && git commit -qm one ) >/dev/null 2>&1
    bash "$V_C" --changed >/dev/null 2>&1
    out=$(bash "$V_C" --changed 2>&1)
    if has "$out" "(cached"; then
        ( cd "$G" && git commit -q --allow-empty -m two ) >/dev/null 2>&1
        out=$(bash "$V_C" --changed 2>&1)
        if ! has "$out" "(cached"; then
            pass "@git-head invalidates on a commit that leaves the working tree identical"
        else
            fail "@git-head did not track HEAD"
        fi
    else
        fail "@git-head fixture never cached on the second run"
    fi
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails verify orchestration test(s)"
    exit 1
fi
echo "OK: verify orchestration tests passed"
exit 0
