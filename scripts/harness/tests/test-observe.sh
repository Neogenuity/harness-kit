#!/usr/bin/env bash
set -uo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-observe.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO/scripts/harness/lib" "$REPO/.harness/evals/scenarios"
cp "$SOURCE_ROOT/scripts/harness/observe" "$REPO/scripts/harness/observe"
cp "$SOURCE_ROOT/scripts/harness/eval-author" "$REPO/scripts/harness/eval-author"
cp "$SOURCE_ROOT/scripts/harness/lib/trace-lib.sh" "$SOURCE_ROOT/scripts/harness/lib/eval-lib.sh" \
    "$REPO/scripts/harness/lib/"
mkdir -p "$REPO/scripts/harness/tests"
cp "$SOURCE_ROOT/scripts/harness/tests/test-eval-graders.sh" "$REPO/scripts/harness/tests/"
cp -R "$SOURCE_ROOT/scripts/harness/eval-template" "$REPO/scripts/harness/eval-template"
printf '.harness/var/\n.harness/evals/scenarios/_draft-*/\n' > "$REPO/.gitignore"
( cd "$REPO" && git init -q && git add -A \
    && git -c user.email=test@example.invalid -c user.name=test commit -qm seed ) || exit 1
cat > "$WORK/transcript.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"private-session"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"src/private-name.txt"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"e1","is_error":false}]}}
{"type":"result","subtype":"success"}
EOF
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }
mode_of() {
    local path=$1 mode
    mode=$(stat -c '%a' "$path" 2>/dev/null || true)
    case "$mode" in
        [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) printf '%s\n' "$mode"; return 0 ;;
    esac
    mode=$(stat -f '%Lp' "$path" 2>/dev/null || true)
    case "$mode" in
        [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) printf '%s\n' "$mode"; return 0 ;;
    esac
    return 1
}

run_dir=$(bash "$REPO/scripts/harness/observe" import --provider claude \
    --transcript "$WORK/transcript.jsonl" --run-id run-1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$run_dir/transcript.jsonl" ] && [ -f "$run_dir/trace.jsonl" ] \
    && jq -e '.events == 4 and .files_modified == ["src/private-name.txt"]' "$run_dir/trajectory.json" >/dev/null 2>&1 \
    && [ "$(mode_of "$run_dir")" = 700 ] \
    && [ "$(mode_of "$run_dir/transcript.jsonl")" = 600 ]; then
    pass "local import preserves raw evidence and computes trajectory metrics"
else
    fail "local transcript import did not create the expected run artifacts"
fi

feedback=$(bash "$REPO/scripts/harness/observe" feedback run-1 bad --reason "missed convention"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$feedback" | jq -e '.rating == "bad" and .reason == "missed convention"' >/dev/null 2>&1; then
    pass "human feedback is recorded explicitly"
else
    fail "feedback record drifted"
fi

draft=$(bash "$REPO/scripts/harness/observe" promote run-1 observed-failure); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$draft/OBSERVATION.md" ] && [ -f "$draft/check.sh" ] \
    && grep -qF 'untrusted observational evidence' "$draft/OBSERVATION.md" \
    && [ -f "$draft/.harness-eval-draft" ] \
    && ! grep -qF 'private-session' "$draft/OBSERVATION.md" \
    && ! grep -qF 'private-name.txt' "$draft/OBSERVATION.md"; then
    pass "promotion creates an excluded untrusted draft with path-redacted metrics"
else
    fail "observation promotion trusted or leaked raw evidence"
fi

manual=$(bash "$REPO/scripts/harness/eval-author" new manual-case); rc=$?
if [ "$rc" -eq 0 ] && [ "$(basename "$manual")" = _draft-manual-case ] && [ -f "$manual/TASK.md" ]; then
    pass "manual authoring starts from the excluded draft template"
else
    fail "manual authoring did not create a draft scaffold"
fi

if bash "$REPO/scripts/harness/eval-author" finalize manual-case >/dev/null 2>&1; then
    fail "placeholder draft was activated without grader validation"
else
    pass "finalize refuses placeholder task, grader, and reference content"
fi

cat > "$manual/TASK.md" <<'EOF'
# Valid finalized task

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Create `result.txt`.

## Acceptance

The deterministic grader requires the exact known-good result.
EOF
printf '#!/usr/bin/env bash\n[ "$(cat result.txt 2>/dev/null)" = ok ]\n' > "$manual/check.sh"
printf '#!/usr/bin/env bash\nprintf "ok\\n" > result.txt\n' > "$manual/reference/apply.sh"
activated=$(bash "$REPO/scripts/harness/eval-author" finalize manual-case); rc=$?
if [ "$rc" -eq 0 ] && [ "$(basename "$activated")" = manual-case ] \
    && [ ! -e "$activated/.harness-eval-draft" ] && [ ! -e "$manual" ]; then
    pass "finalize activates only a grader/reference pair proven by the validity suite"
else
    fail "valid draft did not pass independent finalization"
fi

if bash "$REPO/scripts/harness/observe" import --provider claude \
        --transcript "$WORK/transcript.jsonl" --run-id run-1 >/dev/null 2>&1; then
    fail "an existing observation run was overwritten"
else
    pass "observation run ids refuse collisions"
fi

printf 'not-json\n"scalar"\n[]\n' > "$WORK/malformed.jsonl"
if bash "$REPO/scripts/harness/observe" import --provider claude \
        --transcript "$WORK/malformed.jsonl" --run-id bad-run >/dev/null 2>&1; then
    fail "invalid evidence was accepted"
elif [ ! -e "$REPO/.harness/var/runs/bad-run" ] \
    && [ -z "$(find "$REPO/.harness/var/runs" -maxdepth 1 \( -name '.import-bad-run-*' -o -name '.reserve-bad-run' \) -print)" ]; then
    pass "invalid evidence fails without retaining partial sensitive artifacts"
else
    fail "invalid evidence left partial run artifacts"
fi

assert_quick_failure() {
    label="$1"; shift
    "$@" >"$WORK/quick.out" 2>&1 & pid=$!
    polls=0
    while kill -0 "$pid" 2>/dev/null && [ "$polls" -lt 50 ]; do
        sleep 0.02
        polls=$((polls + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        fail "$label hung instead of rejecting a missing value"
    else
        wait "$pid"; qrc=$?
        [ "$qrc" -ne 0 ] && pass "$label rejects a missing value" || fail "$label unexpectedly passed"
    fi
}
assert_quick_failure "import --provider" bash "$REPO/scripts/harness/observe" import --provider
assert_quick_failure "feedback --reason" bash "$REPO/scripts/harness/observe" feedback run-1 bad --reason

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails observe test(s)"; exit 1; fi
echo "OK: observation and eval-author tests passed"
