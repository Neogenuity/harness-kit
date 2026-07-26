#!/usr/bin/env bash
# Regression tests for the fail-open v2 event writer.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/log-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-log.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

context=$(harness_log_context run-1 verify session-1 env codex env plan-1 env)
data='{"name":"unit","mode":"full","outcome":"pass","exit_code":0,"duration_s":1}'
HARNESS_LOG_FILE="$WORK/log.jsonl" harness_log_v2 "$WORK" verify.sh gate "" "" "$context" "$data"
if jq -e '
    (keys == ["context","data","detail","event","file","hook","ts","version"])
    and .version == 2 and .event == "gate"
    and (.context == {run_id:"run-1",session_id:"session-1",provider:"codex",plan_slug:"plan-1",provenance:{run_id:"verify",session_id:"env",provider:"env",plan_slug:"env"}})
    and .data.exit_code == 0' "$WORK/log.jsonl" >/dev/null 2>&1; then
    pass "v2 writer emits the exact envelope and explicit provenance"
else
    fail "v2 writer envelope/provenance drifted"
fi

long=$(printf '%0300d' 0)
bounded=$(harness_log_context '' '' "$long" env 'bad provider' env '../bad plan?' env)
if [ "$bounded" = '{}' ]; then
    pass "invalid or overlong attribution is omitted"
else
    fail "invalid attribution was logged: $bounded"
fi

HARNESS_LOG=0 HARNESS_LOG_FILE="$WORK/off.jsonl" harness_log_v2 "$WORK" x deny x x '{}' '{}'
if [ ! -e "$WORK/off.jsonl" ]; then pass "HARNESS_LOG=0 writes nothing"; else fail "HARNESS_LOG=0 wrote a file"; fi

# Invalid nested JSON and an unwritable destination degrade without changing rc.
HARNESS_LOG_FILE="$WORK/fallback.jsonl" harness_log_v2 "$WORK" x deny x x not-json '[]'; rc=$?
if [ "$rc" -eq 0 ] && jq -e '.context == {} and .data == {}' "$WORK/fallback.jsonl" >/dev/null 2>&1; then
    pass "invalid optional objects degrade to empty objects"
else
    fail "invalid optional objects did not fail open"
fi

HARNESS_LOG_FILE=/dev/null/nope harness_log_v2 "$WORK" x deny x x '{}' '{}'; rc=$?
if [ "$rc" -eq 0 ]; then pass "unwritable destination fails open"; else fail "unwritable destination returned $rc"; fi

no_jq_out=$(PATH=/nonexistent HARNESS_LOG_FILE="$WORK/no-jq.jsonl" "$BASH" -c '
    . "$1"
    harness_log_v2 "$2" x deny x x "{}" "{}"
' _ "$SCRIPTS_DIR/log-lib.sh" "$WORK" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$WORK/no-jq.jsonl" ] && [ -z "$no_jq_out" ]; then
    pass "missing jq fails open silently without telemetry"
else
    fail "missing jq changed output/exit behavior or wrote telemetry: $no_jq_out"
fi

: > "$WORK/concurrent.jsonl"
i=0
while [ "$i" -lt 32 ]; do
    HARNESS_LOG_FILE="$WORK/concurrent.jsonl" \
        harness_log_v2 "$WORK" test-log.sh advise "file-$i" "" '{}' '{}' &
    i=$((i + 1))
done
wait
if jq -e -s 'length == 32 and all(.[]; .version == 2 and .event == "advise")' \
        "$WORK/concurrent.jsonl" >/dev/null 2>&1; then
    pass "concurrent bounded appends remain complete JSON lines"
else
    fail "concurrent appends lost or interleaved event rows"
fi

# --- hook_log resolves the repo root from lib.sh, not from the caller -------
# The default log path is "$root/.harness/var/log.jsonl", and $root used to be
# computed as dirname($0)/../../.. -- three levels up from the CALLING hook.
# That is right for the kit's own guards at scripts/harness/hooks/<name>.sh
# and wrong for a tailored policy hook at .harness/hooks/<name>.sh (two levels
# down, the home ADR 010 documents): those resolved the repo's PARENT and
# wrote a stray .harness/var/ NEXT TO the repo. It fails open, so the only
# symptom was missing telemetry. The fixture root is nested two deep inside
# $WORK so "one level too high" still lands inside $WORK and is caught by the
# assertion rather than escaping into the temp dir at large.
HL="$WORK/hooklog/repo"
mkdir -p "$HL/scripts/harness/hooks" "$HL/scripts/harness/lib" "$HL/.harness/hooks"
cp "$SCRIPTS_DIR/../hooks/lib.sh" "$HL/scripts/harness/hooks/lib.sh"
cp "$SCRIPTS_DIR/log-lib.sh" "$HL/scripts/harness/lib/log-lib.sh"
cat > "$HL/.harness/hooks/policy.sh" <<'HOOKEOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../../scripts/harness/hooks/lib.sh" 2>/dev/null || exit 0
hook_log advise policy.sh detail
HOOKEOF
chmod +x "$HL/.harness/hooks/policy.sh"
( cd "$HL" && ./.harness/hooks/policy.sh >/dev/null 2>&1 )
if [ -f "$HL/.harness/var/log.jsonl" ] \
    && jq -e 'select(.version == 2 and .event == "advise")' "$HL/.harness/var/log.jsonl" >/dev/null 2>&1; then
    pass "hook_log from a .harness/hooks/ hook writes inside the repo"
else
    fail "hook_log from a .harness/hooks/ hook did not write $HL/.harness/var/log.jsonl"
fi
if [ -e "$WORK/hooklog/.harness" ] || [ -e "$WORK/.harness" ]; then
    fail "hook_log created a stray .harness/ ABOVE the repo root (the escape this pins)"
else
    pass "hook_log creates nothing above the repo root"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails log test(s)"; exit 1; fi
echo "OK: log writer tests passed"
