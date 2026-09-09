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
# Two `diff --git` headers: the git shape, counted by its own file headers.
cat > "$WORK/change.patch" <<'EOF'
diff --git a/src/alpha.txt b/src/alpha.txt
index 1111111..2222222 100644
--- a/src/alpha.txt
+++ b/src/alpha.txt
@@ -1 +1 @@
-old
+DIFF-ONLY-MARKER-9f3a
diff --git a/src/beta.txt b/src/beta.txt
index 3333333..4444444 100644
--- a/src/beta.txt
+++ b/src/beta.txt
@@ -1 +1 @@
-old
+new
EOF
# No `diff --git` headers at all (plain `diff -u` output): the fallback shape.
cat > "$WORK/plain.patch" <<'EOF'
--- a/one.txt	2026-09-09 00:00:00
+++ b/one.txt	2026-09-09 00:00:01
@@ -1 +1 @@
-a
+b
--- a/two.txt	2026-09-09 00:00:00
+++ b/two.txt	2026-09-09 00:00:01
@@ -1 +1 @@
-c
+d
EOF
: > "$WORK/empty.patch"
mkdir -p "$WORK/diff-dir"
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }
skip() { echo "SKIP: $1"; }
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
    && jq -e '.events == 4 and .files_modified == ["src/private-name.txt"]' "$run_dir/trajectory.json" >/dev/null 2>&1; then
    pass "local import preserves raw evidence and computes trajectory metrics"
else
    fail "local transcript import did not create the expected run artifacts"
fi

run_mode=$(mode_of "$run_dir")
transcript_mode=$(mode_of "$run_dir/transcript.jsonl")
modes_assertable=1
if [ "$run_mode" = 700 ] && [ "$transcript_mode" = 600 ]; then
    pass "local import keeps observation artifacts private"
else
    # Git Bash/MSYS over NTFS reports a mode but does not record non-executable
    # chmod changes. Prove that host limitation independently before declining
    # the POSIX-mode assertion; a capable host with wrong run modes still fails.
    printf 'mode probe\n' > "$WORK/mode-probe"
    probe_ok=1
    chmod 644 "$WORK/mode-probe" || probe_ok=0
    mode_before=$(mode_of "$WORK/mode-probe")
    chmod 600 "$WORK/mode-probe" || probe_ok=0
    mode_after=$(mode_of "$WORK/mode-probe")
    if [ "$probe_ok" -ne 1 ]; then
        fail "observation mode capability probe could not apply 644 and 600"
    elif [ "$mode_before" = 644 ] && [ "$mode_after" = 644 ]; then
        modes_assertable=0
        skip "observation modes — this filesystem cannot prove a non-executable permission change (644 -> 600 reads back as 644)"
    elif [ "$mode_before" != 644 ]; then
        fail "observation mode capability probe baseline read ${mode_before:-unknown}; expected 644"
    else
        fail "local import modes were directory=${run_mode:-unknown}, transcript=${transcript_mode:-unknown}; expected 700 and 600"
    fi
fi

if jq -e '.version == 2 and .diff_present == false and .diff_files_changed == null
          and .diff_files_changed_source == null' "$run_dir/metadata.json" >/dev/null 2>&1 \
    && [ ! -e "$run_dir/diff.patch" ]; then
    pass "import without --diff records an explicit absent outcome diff"
else
    fail "import without --diff left the outcome-diff record ambiguous"
fi

run2_dir=$(bash "$REPO/scripts/harness/observe" import --provider claude \
    --transcript "$WORK/transcript.jsonl" --diff "$WORK/change.patch" --run-id run-2); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$run2_dir/diff.patch" ] \
    && cmp -s "$WORK/change.patch" "$run2_dir/diff.patch" \
    && jq -e '.diff_present == true and .diff_files_changed == 2
              and .diff_files_changed_source == "git-diff-headers"' \
        "$run2_dir/metadata.json" >/dev/null 2>&1; then
    pass "import --diff stores the outcome diff verbatim and counts its git file headers"
else
    fail "import --diff did not record the outcome diff and its file count"
fi

if [ "$modes_assertable" -eq 1 ]; then
    diff_mode=$(mode_of "$run2_dir/diff.patch")
    if [ "$diff_mode" = 600 ]; then
        pass "the imported outcome diff is stored as privately as the transcript"
    else
        fail "imported diff mode was ${diff_mode:-unknown}; expected 600"
    fi
else
    skip "imported diff mode — this filesystem cannot prove a non-executable permission change"
fi

shown=$(bash "$REPO/scripts/harness/observe" show run-2); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$shown" | jq -e \
        '.diff.present == true and .diff.files_changed == 2
         and .diff.counted_by == "git-diff-headers"
         and .trajectory.events == 4' >/dev/null 2>&1; then
    pass "show reports outcome-diff presence and file count beside the trajectory"
else
    fail "show did not summarize the outcome diff"
fi

run3_dir=$(bash "$REPO/scripts/harness/observe" import --provider claude \
    --transcript "$WORK/transcript.jsonl" --diff "$WORK/plain.patch" --run-id run-3); rc=$?
if [ "$rc" -eq 0 ] && jq -e '.diff_present == true and .diff_files_changed == 2
        and .diff_files_changed_source == "unified-target-headers"' \
        "$run3_dir/metadata.json" >/dev/null 2>&1; then
    pass "a diff with no git headers falls back to target headers and says so"
else
    fail "the no-git-header fallback count or its source label drifted"
fi

run4_dir=$(bash "$REPO/scripts/harness/observe" import --provider claude \
    --transcript "$WORK/transcript.jsonl" --diff "$WORK/empty.patch" --run-id run-4); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$run4_dir/diff.patch" ] && [ ! -s "$run4_dir/diff.patch" ] \
    && jq -e '.diff_present == true and .diff_files_changed == 0
              and .diff_files_changed_source == "unified-target-headers"' \
        "$run4_dir/metadata.json" >/dev/null 2>&1; then
    pass "an empty diff is accepted and recorded as present with zero files"
else
    fail "an empty diff was rejected or recorded as absent"
fi

bad_diff=0
bash "$REPO/scripts/harness/observe" import --provider claude --transcript "$WORK/transcript.jsonl" \
    --diff "$WORK/missing.patch" --run-id diff-run >/dev/null 2>&1 && bad_diff=1
bash "$REPO/scripts/harness/observe" import --provider claude --transcript "$WORK/transcript.jsonl" \
    --diff "$WORK/diff-dir" --run-id diff-dir-run >/dev/null 2>&1 && bad_diff=1
if [ "$bad_diff" -eq 1 ]; then
    fail "an unreadable --diff path was accepted"
elif [ ! -e "$REPO/.harness/var/runs/diff-run" ] && [ ! -e "$REPO/.harness/var/runs/diff-dir-run" ] \
    && [ -z "$(find "$REPO/.harness/var/runs" -maxdepth 1 \
        \( -name '.import-diff-run-*' -o -name '.reserve-diff-run' \
           -o -name '.import-diff-dir-run-*' -o -name '.reserve-diff-dir-run' \) -print)" ]; then
    pass "an unreadable --diff path fails before staging and leaves no partial run"
else
    fail "an unreadable --diff path left partial run artifacts"
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

# Drafts are authored to be committed. The raw outcome diff is local evidence
# that can carry secrets or private paths, so it must never ride along.
diff_draft=$(bash "$REPO/scripts/harness/observe" promote run-2 observed-diff); rc=$?
if [ "$rc" -eq 0 ] && [ -d "$diff_draft" ] && [ ! -e "$diff_draft/diff.patch" ] \
    && ! grep -R -qF 'DIFF-ONLY-MARKER-9f3a' "$diff_draft"; then
    pass "promotion never copies the run's outcome diff into a committed draft"
else
    fail "promotion leaked the run's outcome diff into the draft scenario"
fi

reject_ok=1
bash "$REPO/scripts/harness/observe" feedback run-2 good --diff "$WORK/change.patch" >/dev/null 2>&1 && reject_ok=0
bash "$REPO/scripts/harness/observe" show run-2 --diff "$WORK/change.patch" >/dev/null 2>&1 && reject_ok=0
bash "$REPO/scripts/harness/observe" promote run-2 stray-diff --diff "$WORK/change.patch" >/dev/null 2>&1 && reject_ok=0
if [ "$reject_ok" -eq 1 ] && [ ! -e "$REPO/.harness/evals/scenarios/_draft-stray-diff" ]; then
    pass "--diff is refused by every subcommand except import"
else
    fail "a non-import subcommand accepted --diff"
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
assert_quick_failure "import --diff" bash "$REPO/scripts/harness/observe" import \
    --provider claude --transcript "$WORK/transcript.jsonl" --diff
assert_quick_failure "feedback --reason" bash "$REPO/scripts/harness/observe" feedback run-1 bad --reason

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails observe test(s)"; exit 1; fi
echo "OK: observation and eval-author tests passed"
