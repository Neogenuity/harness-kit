#!/usr/bin/env bash
set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-audit-log.XXXXXX") || exit 1
# No fixture may discover a Git repository ABOVE its own scratch base — $TMPDIR
# itself may sit inside a worktree (an agent sandbox, a CI scratch dir, a ~/tmp
# kept in dotfiles), and the no-Git case below would then resolve THAT repo and
# assert nothing. Cap the ascent at $WORK; fixture repos under it still resolve,
# because a directory that is itself a repo is found before any ascent.
export GIT_CEILING_DIRECTORIES="$WORK"
trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$WORK/repo/scripts/harness/lib" "$WORK/repo/.harness/var"
cp "$SCRIPTS_DIR/audit-log.sh" "$WORK/repo/scripts/harness/lib/audit-log.sh"
git -C "$WORK/repo" init -q
git -C "$WORK/repo" config user.email test@example.invalid
git -C "$WORK/repo" config user.name Test
printf 'x\n' > "$WORK/repo/x"
git -C "$WORK/repo" add x
git -C "$WORK/repo" commit -qm $'seed\n\nHarness-Session-Id: session-1'
seed_commit=$(git -C "$WORK/repo" rev-parse HEAD)
printf 'y\n' > "$WORK/repo/y"
git -C "$WORK/repo" add y
{
    printf 'trailer cases\n\n'
    printf 'Harness-Session-Id: alpha,beta\n'
    printf 'Harness-Session-Id: dupe\nHarness-Session-Id: dupe\n'
} > "$WORK/message"
git -C "$WORK/repo" commit -qF "$WORK/message"
trailer_commit=$(git -C "$WORK/repo" rev-parse HEAD)
printf 'malformed trailer\n\nHarness-Session-Id malformed\n' > "$WORK/message"
git -C "$WORK/repo" commit -q --allow-empty -F "$WORK/message"
printf 'control trailer\n\nHarness-Session-Id: bad\tid\n' > "$WORK/message"
git -C "$WORK/repo" commit -q --allow-empty -F "$WORK/message"
{ printf 'overlong trailer\n\nHarness-Session-Id: '; printf '%0257d\n' 0; } > "$WORK/message"
git -C "$WORK/repo" commit -q --allow-empty -F "$WORK/message"

cat > "$WORK/repo/.harness/var/log.jsonl" <<'EOF'
{"ts":"2026-07-15T10:00:00Z","hook":"code-reviewer","event":"review-finding","file":"x","detail":"{}"}
{"version":2,"ts":"2026-07-15T10:00:01Z","hook":"verify.sh","event":"gate","file":"","detail":"","context":{"session_id":"session-1","provenance":{"session_id":"env"}},"data":{"name":"tests","mode":"full","outcome":"fail","exit_code":7,"duration_s":2}}
{"version":2,"ts":"2026-07-15T10:00:02Z","hook":"verify.sh","event":"gate","file":"","detail":"","context":{"session_id":"session-1","provenance":{"session_id":"env"}},"data":{"name":"tests","mode":"full","outcome":"pass","exit_code":0,"duration_s":1}}
{"version":2,"ts":"2026-07-15T10:00:03Z","hook":"guard-secrets.sh","event":"deny","file":".env","detail":"x","context":{},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:04Z","hook":"guard-secrets.sh","event":"deny","file":".env","detail":"x","context":{},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:04Z","hook":"guard-secrets.sh","event":"deny","file":"","detail":"x","context":{},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:05Z","hook":"future","event":"future-event","file":"","detail":"","context":{},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:06Z","hook":"verify.sh","event":"gate","file":"","detail":"","context":{},"data":{"name":"tests","mode":"full","outcome":"pass","exit_code":7,"duration_s":1}}
{"version":2,"ts":"2026-07-15T10:00:07Z","hook":"verify.sh","event":"gate","file":"","detail":"","context":{},"data":{"name":"tests","mode":"full","outcome":"fail","exit_code":0,"duration_s":1}}
{"version":2,"ts":"2026-07-15T10:00:08Z","hook":"x","event":"deny","file":"x","detail":"","context":{"provider":7,"provenance":{"provider":"env"}},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:09Z","hook":"x","event":"deny","file":"x","detail":"","context":{"run_id":"run-1","provenance":{"run_id":"payload"}},"data":{}}
{"version":2,"ts":"2026-07-15T10:00:10Z","hook":"x","event":"deny","file":"x","detail":"","context":{"provenance":null},"data":{}}
{"version":3,"ts":"x"}
{"version":2,"ts":"bad","hook":"x","event":"deny","file":"","detail":"","context":{},"data":{}}
not-json
EOF

report=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/repo" \
    --log "$WORK/repo/.harness/var/log.jsonl" --format json); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$report" | jq -e --arg seed "$seed_commit" --arg trailer "$trailer_commit" '
    .parser == {valid_v1:1,valid_v2:5,invalid_json:1,invalid_schema:6,unsupported_version:1,unknown_event:1}
    and .log.status == "available"
    and .gate_outcomes_daily == [
      {day:"2026-07-15",name:"tests",mode:"full",runs:2,passes:1,failures:1,failure_rate:0.5,duration_s:3}]
    and .retry_episodes[0].episodes == 1 and .retry_episodes[0].retries == 1
    and .repeat_denies == [{hook:"guard-secrets.sh",file:".env",count:2}]
    and .review_findings == {count:1}
    and .session_commits == {status:"available",items:[
      {session_id:"alpha,beta",commit:$trailer},{session_id:"dupe",commit:$trailer},
      {session_id:"session-1",commit:$seed}],reason:null}
    and .plan_cycles.status == "not_available"
    and .eval.status == "not_available"
    and [.recommendations[].code] == ["repair_invalid_log_rows","address_gate_failures","reduce_gate_retries","engineer_repeat_denies"]' >/dev/null; then
    pass "schemas, reviews, denies, and lossless deduplicated trailers are deterministic"
else
    fail "audit JSON report drifted"
    printf '%s\n' "$report"
fi

mkdir -p "$WORK/alternate/scripts/harness/lib" "$WORK/alternate/.harness/var/eval-results" "$WORK/alternate/.harness/evals"
printf '%s\n' '{"ts":"2026-07-15T11:00:00Z","hook":"code-reviewer","event":"review-finding","file":"alt","detail":"{}"}' \
    > "$WORK/alternate/.harness/var/log.jsonl"
printf '{}\n' > "$WORK/alternate/.harness/evals/baselines.json"
cat > "$WORK/alternate/scripts/harness/lib/eval-harness.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"version":1,"status":"pass","regressions":0,"violations":0,"cells":[]}'
EOF
chmod +x "$WORK/alternate/scripts/harness/lib/eval-harness.sh"
alternate=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/alternate" --format json); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$alternate" | jq -e '
    .log.status == "available" and .parser.valid_v1 == 1
    and .review_findings == {count:1}
    and .session_commits.reason == "no_git_repository"
    and .eval.status == "available" and .eval.report.status == "pass"' >/dev/null; then
    pass "--repo rebases default log, eval-result, and baseline paths"
else
    fail "--repo mixed selected-repo state with script-repo defaults"
fi

empty=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/repo" \
    --log "$WORK/repo/.harness/absent.jsonl" --format json); rc=$?
empty_table=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/repo" \
    --log "$WORK/repo/.harness/absent.jsonl" --format table); table_rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$empty" | jq -e '
    .log.status == "no_data" and ([.parser[]] | add) == 0
    and .gate_outcomes_daily == [] and .review_findings == {count:0}
    and .recommendations == []' >/dev/null \
    && [ "$table_rc" -eq 0 ] && printf '%s' "$empty_table" | grep -qF 'Harness log: status=no_data'; then
    pass "an absent log is honest no-data, not an operational failure"
else
    fail "absent-log no-data handling drifted"
fi

mkdir -p "$WORK/no-git/scripts/harness/lib" "$WORK/no-git/.harness/var"
cp "$SCRIPTS_DIR/audit-log.sh" "$WORK/no-git/scripts/harness/lib/audit-log.sh"
no_git=$(bash "$WORK/no-git/scripts/harness/lib/audit-log.sh" --repo "$WORK/no-git" --format json); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$no_git" | jq -e '
    .session_commits == {status:"not_available",items:[],reason:"no_git_repository"}
    and .review_findings == {count:0}' >/dev/null; then
    pass "no-Git attribution state and zero review count are explicit"
else
    fail "no-Git attribution state drifted"
fi

git clone -q --depth 1 "file://$WORK/repo" "$WORK/shallow"
mkdir -p "$WORK/shallow/.harness/var" "$WORK/shallow/scripts/harness/lib"
cp "$SCRIPTS_DIR/audit-log.sh" "$WORK/shallow/scripts/harness/lib/audit-log.sh"
shallow=$(bash "$WORK/shallow/scripts/harness/lib/audit-log.sh" --repo "$WORK/shallow" --format json); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$shallow" | jq -e '
    .session_commits == {status:"not_available",items:[],reason:"shallow_history"}' >/dev/null; then
    pass "shallow-history attribution state is explicit"
else
    fail "shallow-history attribution state drifted"
fi

mkdir -p "$WORK/repo/.harness/var/eval-results" "$WORK/repo/.harness/evals"
printf '{}\n' > "$WORK/repo/.harness/evals/baselines.json"
cat > "$WORK/repo/scripts/harness/lib/eval-harness.sh" <<'EOF'
#!/usr/bin/env bash
case " $* " in *' --format json '*) ;; *) exit 2 ;; esac
printf '%s\n' '{"version":1,"status":"fail","regressions":1,"violations":0,"cells":[]}'
EOF
chmod +x "$WORK/repo/scripts/harness/lib/eval-harness.sh"
with_eval=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/repo" \
    --log "$WORK/repo/.harness/var/log.jsonl" --format json); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$with_eval" | jq -e '
    .eval.status == "available" and .eval.report.status == "fail"
    and ([.recommendations[].code] | index("investigate_eval_regression")) != null' >/dev/null; then
    pass "optional eval section consumes eval-harness JSON mode"
else
    fail "optional eval scorer integration drifted"
fi

table=$(bash "$WORK/repo/scripts/harness/lib/audit-log.sh" --repo "$WORK/repo" \
    --log "$WORK/repo/.harness/var/log.jsonl" --format table); rc=$?
expected_table=$(cat <<'EOF'
Harness log: status=available v1=1 v2=5 invalid-json=1 invalid-schema=6 unsupported=1 unknown-event=1
DAY        GATE                     MODE   RUNS  PASS  FAIL  FAILURE-RATE
2026-07-15 tests                    full   2     1     1     0.5
Plan cycles: N/A (no machine-readable lifecycle)
Review findings: 1
Session commits: available
Recommendations: repair_invalid_log_rows, address_gate_failures, reduce_gate_retries, engineer_repeat_denies, investigate_eval_regression
EOF
)
if [ "$rc" -eq 0 ] && [ "$table" = "$expected_table" ]; then
    pass "table output matches the mixed-log golden rendering"
else
    fail "table output drifted from the mixed-log golden rendering"
    # BYTE-level, not just the rendered table. Every difference this case has
    # ever caught was invisible on screen: a jq built for Windows terminates
    # each line with CRLF, and command substitution leaves the CR embedded
    # mid-row, so the printed table looked identical to the golden and the
    # failure named nothing. `od -c` is the one dump tool present everywhere
    # this floor runs (diff, cmp and `od -t` variants are not uniformly
    # available on Git Bash); it renders a stray \r as plainly as a missing
    # column.
    printf '    --- actual (rc=%s) ---\n' "$rc"
    printf '%s\n' "$table" | od -c | sed 's/^/    /'
    printf '    --- expected ---\n'
    printf '%s\n' "$expected_table" | od -c | sed 's/^/    /'
fi

# --- a CRLF-emitting jq must leave no CR in the table -------------------------
# jq built for Windows opens stdio in TEXT mode, so every line it prints ends
# CRLF. Command substitution strips the LF and leaves the CR, which lands
# MID-ROW in the assembled table ("status=available<CR> v1=1<CR> ..."). On
# screen that is invisible, while a terminal actually renders the row
# overwritten from column 0.
#
# This is NOT the cause of the Git Bash failure of the golden case above. It
# reproduces that symptom exactly, which is why it was suspected — but under a
# CRLF-emitting jq nine other shipped suites fail too, and all nine pass on that
# runner. This case pins the hardening; the real cause is still open.
#
# Stubbed rather than skipped, so the behavior is pinned on every runner and
# not only on the one platform that ships such a jq; same technique as the
# binary-mode sha256 case in test-install-core.sh. awk builds the CRLF, not
# `sed 's/$/\r/'` — BSD sed's handling of \r in a replacement is not portable,
# and test-install-core.sh's CRLF kit-manifest case set that precedent.
CR=$(printf '\r')
STUBJQ=$(mktemp -d "$WORK/crlfjq.XXXXXX") || exit 1
# `type -P` searches PATH for an executable FILE and skips builtins, so the
# wrapper always has a resolvable absolute target.
realjq=$(type -P jq 2>/dev/null)
if [ -z "$realjq" ]; then
    fail "CRLF-jq case: no jq on PATH to wrap (the suite cannot have got this far without one)"
else
    # `set -o pipefail` in the stub, or the wrapper always exits 0 and silently
    # converts every jq failure into a success — which would disable the
    # `|| { ...; exit 1; }` arms inside audit-log.sh for the whole case and
    # destroy `jq -e`'s false-means-non-zero contract for any future call site.
    # bash, NOT /bin/sh: `set -o pipefail` is not POSIX, and /bin/sh is dash on
    # Ubuntu — `dash -c 'set -o pipefail'` exits 2, so the stub would die before
    # ever reaching jq and fail this case on the Linux runner.
    cat > "$STUBJQ/jq" <<EOF
#!/usr/bin/env bash
set -o pipefail
"$realjq" "\$@" | awk '{ printf "%s\r\n", \$0 }'
EOF
    # 755 explicitly: `chmod +x` is masked by the caller's umask.
    chmod 755 "$STUBJQ/jq"
    # Prove the stub really emits CRLF first, or the assertion below is vacuous
    # — it would pass just as well against a stub that did nothing.
    stub_raw=$(printf '{"a":1}' | PATH="$STUBJQ:$PATH" jq -r .a)
    case "$stub_raw" in *"$CR"*) stub_crlf=1 ;; *) stub_crlf=0 ;; esac
    crlf_table=$(PATH="$STUBJQ:$PATH" bash "$WORK/repo/scripts/harness/lib/audit-log.sh" \
        --repo "$WORK/repo" --log "$WORK/repo/.harness/var/log.jsonl" --format table); rc=$?
    case "$crlf_table" in *"$CR"*) table_crlf=1 ;; *) table_crlf=0 ;; esac
    if [ "$stub_crlf" -eq 1 ] && [ "$rc" -eq 0 ] \
            && [ "$table_crlf" -eq 0 ] && [ "$crlf_table" = "$expected_table" ]; then
        pass "a text-mode jq's CRLF never reaches the rendered table"
    else
        fail "CR from a text-mode jq reached the table (stub emitted CRLF=$stub_crlf, rc=$rc, table carries CR=$table_crlf)"
        printf '%s\n' "$crlf_table" | od -c | sed 's/^/        /'
    fi
fi
rm -rf "$STUBJQ"

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails audit-log test(s)"; exit 1; fi
echo "OK: audit-log tests passed"
