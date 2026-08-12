#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=/dev/null
. "$ROOT/scripts/harness/lib/trace-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-trace.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

cat > "$WORK/claude.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s1"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"AGENTS.md"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"r1","is_error":false}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"bash scripts/harness/verify"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":true}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"ef","name":"Edit","input":{"file_path":"src/denied.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"ef","is_error":true}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"bash scripts/harness/verify"}},{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"src/a.sh"}},{"type":"tool_use","id":"r2","name":"Read","input":{"file_path":"AGENTS.md"}},{"type":"tool_use","id":"b3","name":"Bash","input":{"command":"rg verify docs"}},{"type":"tool_use","id":"b4","name":"Bash","input":{"command":"cat tests/example.txt"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b2","is_error":false},{"type":"tool_result","tool_use_id":"e1","is_error":false},{"type":"tool_result","tool_use_id":"r2","is_error":false},{"type":"tool_result","tool_use_id":"b3","is_error":false},{"type":"tool_result","tool_use_id":"b4","is_error":false}]}}
{"type":"result","subtype":"success"}
EOF
eval_normalize_trace claude "$WORK/claude.jsonl" > "$WORK/claude-trace.jsonl"
claude_metrics=$(eval_trajectory_json "$WORK/claude-trace.jsonl")
if jq -e -s 'length == 18 and ([.[].seq] == [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18])
    and all(.[]; keys == ["attributes","provider","seq","ts","type","version"])
    and all(.[]; .provider == "claude" and .version == 1)' "$WORK/claude-trace.jsonl" >/dev/null 2>&1 \
    && printf '%s' "$claude_metrics" | jq -e '
      .instruction_discovery_available and .instructions_discovered and (.edited_before_instruction_discovery|not)
      and .tests_executed == 2 and .verification_executed
      and .failed_commands == 1 and .recovery_successful
      and .repeated_reads == 1 and .repeated_commands == 1
      and .files_modified == ["src/a.sh"]' >/dev/null 2>&1; then
    pass "Claude transcript normalizes and yields deterministic trajectory metrics"
else
    fail "Claude trace or trajectory metrics drifted"
fi

cat > "$WORK/codex.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"s2"}
{"type":"item.completed","item":{"id":"f1","type":"file_change","changes":[{"path":"src/a.sh","kind":"update"}]}}
{"type":"item.started","item":{"id":"c1","type":"command_execution","command":"bash scripts/harness/verify"}}
{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"bash scripts/harness/verify","exit_code":1}}
{"type":"item.started","item":{"id":"c2","type":"command_execution","command":"bash scripts/harness/verify"}}
{"type":"item.completed","item":{"id":"c2","type":"command_execution","command":"bash scripts/harness/verify","exit_code":0}}
{"type":"turn.completed","usage":{}}
EOF
eval_normalize_trace codex "$WORK/codex.jsonl" > "$WORK/codex-trace.jsonl"
codex_metrics=$(eval_trajectory_json "$WORK/codex-trace.jsonl")
if jq -e -s 'length == 7 and ([.[].seq] == [1,2,3,4,5,6,7])
    and all(.[]; keys == ["attributes","provider","seq","ts","type","version"])
    and all(.[]; .provider == "codex" and .version == 1)' "$WORK/codex-trace.jsonl" >/dev/null 2>&1 \
    && printf '%s' "$codex_metrics" | jq -e '
      (.instruction_discovery_available|not) and .instructions_discovered == null
      and .edited_before_instruction_discovery == null
      and .tests_executed == 2 and .verification_executed
      and .failed_commands == 1 and .recovery_successful
      and .repeated_commands == 1 and .files_modified == ["src/a.sh"]' >/dev/null 2>&1; then
    pass "Codex transcript normalizes to the same schema and metrics contract"
else
    fail "Codex trace or trajectory metrics drifted"
fi

cat > "$WORK/unrelated-success.jsonl" <<'EOF'
{"version":1,"seq":1,"ts":null,"provider":"codex","type":"command.started","attributes":{"command":"npm test","tool_id":"c1"}}
{"version":1,"seq":2,"ts":null,"provider":"codex","type":"command.finished","attributes":{"command":"npm test","tool_id":"c1","exit_code":1,"success":false}}
{"version":1,"seq":3,"ts":null,"provider":"codex","type":"command.started","attributes":{"command":"pwd","tool_id":"c2"}}
{"version":1,"seq":4,"ts":null,"provider":"codex","type":"command.finished","attributes":{"command":"pwd","tool_id":"c2","exit_code":0,"success":true}}
EOF
if eval_trajectory_json "$WORK/unrelated-success.jsonl" \
    | jq -e '.failed_commands == 1 and (.recovery_successful|not) and .tests_executed == 1 and (.verification_executed|not)' >/dev/null 2>&1; then
    pass "recovery requires a successful retry of the failed command"
else
    fail "an unrelated success was mislabeled as command recovery"
fi

cat > "$WORK/claude-shell-read.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s3"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"cat AGENTS.md"}},{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"src/a.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":false},{"type":"tool_result","tool_use_id":"e1","is_error":false}]}}
EOF
eval_normalize_trace claude "$WORK/claude-shell-read.jsonl" > "$WORK/claude-shell-read-trace.jsonl"
if eval_trajectory_json "$WORK/claude-shell-read-trace.jsonl" \
    | jq -e '(.instruction_discovery_available|not) and .instructions_discovered == null and .edited_before_instruction_discovery == null' >/dev/null 2>&1; then
    pass "absence of a direct read stays unknown when shell reads may be hidden"
else
    fail "incomplete Claude read evidence became a false instruction-discovery negative"
fi

cat > "$WORK/claude-mixed-read.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s4"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"cat AGENTS.md"}},{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"src/a.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":false},{"type":"tool_result","tool_use_id":"e1","is_error":false}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"AGENTS.md"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"r1","is_error":false}]}}
EOF
eval_normalize_trace claude "$WORK/claude-mixed-read.jsonl" > "$WORK/claude-mixed-read-trace.jsonl"
if eval_trajectory_json "$WORK/claude-mixed-read-trace.jsonl" \
    | jq -e '.instruction_discovery_available and .instructions_discovered and .edited_before_instruction_discovery == null' >/dev/null 2>&1; then
    pass "a late direct read cannot prove an edit preceded every opaque read channel"
else
    fail "a late direct read became a false edit-before-discovery positive"
fi

cat > "$WORK/claude-shell-write.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s4b"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"printf changed > src/a.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","is_error":false}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"AGENTS.md"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"r1","is_error":false}]}}
EOF
eval_normalize_trace claude "$WORK/claude-shell-write.jsonl" > "$WORK/claude-shell-write-trace.jsonl"
if eval_trajectory_json "$WORK/claude-shell-write-trace.jsonl" \
    | jq -e '.instruction_discovery_available and .instructions_discovered and .edited_before_instruction_discovery == null' >/dev/null 2>&1; then
    pass "an opaque command before discovery cannot prove that no earlier edit occurred"
else
    fail "a hidden shell mutation became a false edit-before-discovery negative"
fi

cat > "$WORK/claude-edit-first.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s4c"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"src/a.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"e1","is_error":false}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"AGENTS.md"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"r1","is_error":false}]}}
EOF
eval_normalize_trace claude "$WORK/claude-edit-first.jsonl" > "$WORK/claude-edit-first-trace.jsonl"
if eval_trajectory_json "$WORK/claude-edit-first-trace.jsonl" \
    | jq -e '.edited_before_instruction_discovery == true' >/dev/null 2>&1; then
    pass "an edit with no opaque event before it proves edit-before-discovery"
else
    fail "a provable edit-before-discovery violation did not report true"
fi

cat > "$WORK/malformed-objects.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"s5"}
{"type":"assistant","message":"malformed"}
{"type":"assistant","message":{"content":["malformed",42]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":{"bad":1},"name":"Read","input":{"file_path":"AGENTS.md"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x","name":"Read","input":"malformed"}]}}
{"type":"user","message":42}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":{"bad":1},"is_error":false}]}}
{"type":"result","subtype":"success"}
EOF
cat > "$WORK/malformed-codex-objects.jsonl" <<'EOF'
{"type":"thread.started","thread_id":"s6"}
{"type":"item.started","item":"malformed"}
{"type":"item.completed","item":[]}
{"type":"item.completed","item":{"id":"bad","type":"file_change","changes":"malformed"}}
{"type":"turn.completed"}
EOF
if eval_normalize_trace claude "$WORK/malformed-objects.jsonl" > "$WORK/malformed-objects-trace.jsonl" \
    && eval_normalize_trace codex "$WORK/malformed-codex-objects.jsonl" > "$WORK/malformed-codex-objects-trace.jsonl" \
    && jq -e -s 'length == 3' "$WORK/malformed-objects-trace.jsonl" >/dev/null 2>&1 \
    && jq -e -s 'length == 2' "$WORK/malformed-codex-objects-trace.jsonl" >/dev/null 2>&1; then
    pass "malformed nested provider rows are ignored without aborting anchored evidence"
else
    fail "malformed nested provider rows aborted trace normalization"
fi

printf 'not-json\n"scalar"\n42\n[]\nnull\n' > "$WORK/malformed.jsonl"
if eval_normalize_trace claude "$WORK/malformed.jsonl" > "$WORK/empty-trace.jsonl" \
    && [ ! -s "$WORK/empty-trace.jsonl" ] \
    && eval_trajectory_json "$WORK/empty-trace.jsonl" | jq -e '.events == 0 and .files_modified == [] and .instructions_discovered == null' >/dev/null 2>&1; then
    pass "malformed and non-object rows are ignored and an empty trace remains explicit"
else
    fail "malformed transcript handling was not deterministic"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails trace test(s)"; exit 1; fi
echo "OK: trace tests passed"
