#!/usr/bin/env bash
# Deterministic, read-only summary of mixed v1/v2 harness event logs.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG=""
FORMAT=table
RESULTS_DIR=""
BASELINE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) ROOT="$2"; shift 2 ;;
        --log) LOG="$2"; shift 2 ;;
        --format) FORMAT="$2"; shift 2 ;;
        --eval-results) RESULTS_DIR="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "audit-log.sh: unknown option: $1" >&2; exit 64 ;;
    esac
done
case "$FORMAT" in table|json) ;; *) echo "audit-log.sh: --format must be table or json" >&2; exit 64 ;; esac
[ -n "$LOG" ] || LOG="$ROOT/.harness/log.jsonl"
[ -n "$RESULTS_DIR" ] || RESULTS_DIR="$ROOT/.harness/eval-results"
[ -n "$BASELINE" ] || BASELINE="$ROOT/docs/evals/baselines.json"
command -v jq >/dev/null 2>&1 || { echo "audit-log.sh: jq is required" >&2; exit 1; }
LOG_STATUS=available
if [ ! -e "$LOG" ]; then
    LOG_STATUS=no_data
    LOG_INPUT=/dev/null
elif [ ! -r "$LOG" ]; then
    echo "audit-log.sh: log is not readable: $LOG" >&2
    exit 1
else
    LOG_INPUT=$LOG
fi

# Parse without aborting on bad rows. Input line number is retained as the
# deterministic tiebreaker for events sharing a one-second timestamp.
PARSED=$(jq -Rn '
  def known: . == "deny" or . == "advise" or . == "lint-findings" or . == "review-finding" or . == "gate";
  def str: type == "string";
  def tsok: str and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
  def v1schema:
    (keys | sort) == ["detail","event","file","hook","ts"]
    and (.ts|tsok) and (.hook|str) and (.event|str) and (.file|str) and (.detail|str);
  def gatedata:
    (.data|type) == "object"
    and (.data|keys|sort) == ["duration_s","exit_code","mode","name","outcome"]
    and (.data.name|str) and (.data.mode == "full" or .data.mode == "fast")
    and (.data.outcome == "pass" or .data.outcome == "fail")
    and (.data.exit_code|type) == "number" and (.data.exit_code|floor) == .data.exit_code
    and (.data.duration_s|type) == "number" and .data.duration_s >= 0 and (.data.duration_s|floor) == .data.duration_s
    and ((.data.outcome == "pass" and .data.exit_code == 0)
         or (.data.outcome == "fail" and .data.exit_code != 0));
  def slug($max): type == "string" and length > 0 and length <= $max and test("^[A-Za-z0-9._/-]+$");
  def session: type == "string" and length > 0 and length <= 256
    and (test("[\\x00-\\x1F\\x7F]") | not);
  def contextok:
    ((.context|has("provenance")|not) or (.context.provenance|type) == "object")
    and (if (.context|has("run_id")) then
           (.context.run_id|slug(128))
           and (.context.provenance.run_id as $source | ["verify","env"] | index($source) != null)
         else ((.context.provenance // {})|has("run_id")|not) end)
    and (if (.context|has("session_id")) then
           (.context.session_id|session)
           and (.context.provenance.session_id as $source | ["env","payload"] | index($source) != null)
         else ((.context.provenance // {})|has("session_id")|not) end)
    and (if (.context|has("provider")) then
           (.context.provider|slug(64)) and .context.provenance.provider == "env"
         else ((.context.provenance // {})|has("provider")|not) end)
    and (if (.context|has("plan_slug")) then
           (.context.plan_slug|slug(128)) and .context.provenance.plan_slug == "env"
         else ((.context.provenance // {})|has("plan_slug")|not) end);
  def v2schema:
    (keys | sort) == ["context","data","detail","event","file","hook","ts","version"]
    and .version == 2 and (.ts|tsok) and (.hook|str) and (.event|str)
    and (.file|str) and (.detail|str) and (.context|type) == "object" and contextok and (.data|type) == "object"
    and (if .event == "gate" then gatedata else true end);
  [inputs] | to_entries | map(
    .key as $zero | .value as $raw
    | (try ($raw|fromjson) catch null) as $j
    | if $j == null then {line:($zero+1),classification:"invalid_json"}
      elif ($j|type) != "object" then {line:($zero+1),classification:"invalid_schema"}
      elif ($j|has("version")) and $j.version != 2 then {line:($zero+1),classification:"unsupported_version"}
      elif ($j|has("version")|not) and ($j|v1schema) then
        {line:($zero+1),classification:(if ($j.event|known) then "valid_v1" else "unknown_event" end),event:$j}
      elif ($j.version == 2) and ($j|v2schema) then
        {line:($zero+1),classification:(if ($j.event|known) then "valid_v2" else "unknown_event" end),event:$j}
      else {line:($zero+1),classification:"invalid_schema"} end)
' < "$LOG_INPUT") || { echo "audit-log.sh: failed to parse $LOG" >&2; exit 1; }

EVENTS=$(printf '%s' "$PARSED" | jq -c '[.[] | select(.classification == "valid_v1" or .classification == "valid_v2") | .event + {line:.line}]')
COUNTERS=$(printf '%s' "$PARSED" | jq -c '
  reduce .[] as $r ({valid_v1:0,valid_v2:0,invalid_json:0,invalid_schema:0,unsupported_version:0,unknown_event:0};
    .[$r.classification] += 1)')

GATES=$(printf '%s' "$EVENTS" | jq -c '
  [.[] | select(.event == "gate")
    | {day:(.ts[0:10]),name:.data.name,mode:.data.mode,outcome:.data.outcome,
       exit_code:.data.exit_code,duration_s:.data.duration_s,
       session_id:(.context.session_id // ""),line,ts}]
  | sort_by([.day,.name,.mode,.ts,.line])')
GATE_DAILY=$(printf '%s' "$GATES" | jq -c '
  group_by([.day,.name,.mode])
  | map((length) as $runs
      | ([.[] | select(.outcome == "pass")] | length) as $passes
      | ([.[] | select(.outcome == "fail")] | length) as $failures
      | {day:.[0].day,name:.[0].name,mode:.[0].mode,runs:$runs,passes:$passes,failures:$failures,
         failure_rate:(if $runs > 0 then $failures/$runs else 0 end),
         duration_s:(map(.duration_s)|add)})')
RETRIES=$(printf '%s' "$GATES" | jq -c '
  [.[] | select(.session_id != "")]
  | group_by([.session_id,.name,.mode])
  | map(sort_by([.ts,.line]) as $g
      | (reduce $g[] as $e ({failed:false,episodes:0,retries:0};
          if $e.outcome == "fail" then
            if .failed then .retries += 1 else .failed=true | .episodes += 1 end
          elif .failed then .retries += 1 | .failed=false else . end)) as $r
      | {session_id:$g[0].session_id,name:$g[0].name,mode:$g[0].mode,
         episodes:$r.episodes,retries:$r.retries})
  | sort_by([.session_id,.name,.mode])')
DENIES=$(printf '%s' "$EVENTS" | jq -c '
  [.[] | select(.event == "deny" and .file != "")]
  | group_by([.hook,.file])
  | map({hook:.[0].hook,file:.[0].file,count:length})
  | sort_by([-.count,.hook,.file])')

# The durable attribution available in a complete Git repository is the exact
# trailer-to-commit join. NUL separates multiple trailer values, so a comma is
# ordinary identifier content rather than an accidental delimiter.
SESSION_COMMITS=$(jq -cn '{status:"not_available",items:[],reason:"no_git_repository"}')
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    shallow=$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null) || shallow=unknown
    if [ "$shallow" = true ]; then
        SESSION_COMMITS=$(jq -cn '{status:"not_available",items:[],reason:"shallow_history"}')
    elif [ "$shallow" = unknown ]; then
        SESSION_COMMITS=$(jq -cn '{status:"not_available",items:[],reason:"git_log_failed"}')
    elif items=$(git -C "$ROOT" log --format='%H%x09%(trailers:key=Harness-Session-Id,valueonly,separator=%x00)' 2>/dev/null \
        | jq -Rsc '
            split("\n")
            | map(select(length>0) | split("\t") | select(length == 2)
                | .[0] as $commit | .[1] | split("\u0000")[]
                | select(length > 0 and length <= 256)
                | select((test("[\\x00-\\x1F\\x7F]") | not))
                | . as $session | select(($session | gsub("^\\s+|\\s+$";"")) == $session)
                | select($commit | test("^[0-9a-f]{40}([0-9a-f]{24})?$"))
                | {session_id:.,commit:$commit})
            | unique_by([.session_id,.commit]) | sort_by([.session_id,.commit])' 2>/dev/null); then
        SESSION_COMMITS=$(jq -cn --argjson items "$items" '{status:"available",items:$items,reason:null}')
    else
        SESSION_COMMITS=$(jq -cn '{status:"not_available",items:[],reason:"git_log_failed"}')
    fi
fi

REVIEW_FINDINGS=$(printf '%s' "$EVENTS" | jq -c '{count:([.[] | select(.event == "review-finding")] | length)}')

EVAL=$(jq -cn '{status:"not_available",reason:"current_results_or_baseline_absent"}')
if [ -d "$RESULTS_DIR" ] && [ -f "$BASELINE" ] && [ -x "$ROOT/scripts/eval-harness.sh" ]; then
    if eval_json=$(bash "$ROOT/scripts/eval-harness.sh" --results-dir "$RESULTS_DIR" \
            --baseline "$BASELINE" --format json --no-fail 2>/dev/null); then
        EVAL=$(jq -cn --argjson report "$eval_json" '{status:"available",report:$report}')
    else
        EVAL=$(jq -cn '{status:"invalid",reason:"eval_scorer_failed"}')
    fi
fi

REPORT=$(jq -cn --arg log_status "$LOG_STATUS" --argjson counters "$COUNTERS" --argjson gate_daily "$GATE_DAILY" \
    --argjson retries "$RETRIES" --argjson denies "$DENIES" --argjson reviews "$REVIEW_FINDINGS" --argjson session_commits "$SESSION_COMMITS" \
    --argjson eval "$EVAL" '
  {version:1,log:{status:$log_status},parser:$counters,gate_outcomes_daily:$gate_daily,retry_episodes:$retries,
   repeat_denies:$denies,review_findings:$reviews,session_commits:$session_commits,
   plan_cycles:{status:"not_available",reason:"no_machine_readable_lifecycle"},eval:$eval}
  | .recommendations = ([
      (if (.parser.invalid_json + .parser.invalid_schema + .parser.unsupported_version) > 0
       then {code:"repair_invalid_log_rows",count:(.parser.invalid_json + .parser.invalid_schema + .parser.unsupported_version)} else empty end),
      (if ([.gate_outcomes_daily[].failures] | add // 0) > 0
       then {code:"address_gate_failures",count:([.gate_outcomes_daily[].failures] | add)} else empty end),
      (if ([.retry_episodes[].retries] | add // 0) > 0
       then {code:"reduce_gate_retries",count:([.retry_episodes[].retries] | add)} else empty end),
      (if ([.repeat_denies[] | select(.count >= 2)] | length) > 0
       then {code:"engineer_repeat_denies",count:([.repeat_denies[] | select(.count >= 2)] | length)} else empty end),
      (if .eval.status == "available" and .eval.report.status == "fail"
       then {code:"investigate_eval_regression",count:(.eval.report.regressions + .eval.report.violations)} else empty end)
    ])') || { echo "audit-log.sh: failed to build report" >&2; exit 1; }

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$REPORT" | jq -S '.'
else
    printf 'Harness log: status=%s v1=%s v2=%s invalid-json=%s invalid-schema=%s unsupported=%s unknown-event=%s\n' \
        "$LOG_STATUS" "$(printf '%s' "$COUNTERS" | jq -r .valid_v1)" "$(printf '%s' "$COUNTERS" | jq -r .valid_v2)" \
        "$(printf '%s' "$COUNTERS" | jq -r .invalid_json)" "$(printf '%s' "$COUNTERS" | jq -r .invalid_schema)" \
        "$(printf '%s' "$COUNTERS" | jq -r .unsupported_version)" "$(printf '%s' "$COUNTERS" | jq -r .unknown_event)"
    printf '%-10s %-24s %-6s %-5s %-5s %-5s %s\n' DAY GATE MODE RUNS PASS FAIL FAILURE-RATE
    printf '%s' "$GATE_DAILY" | jq -r '.[] | [.day,.name,.mode,(.runs|tostring),(.passes|tostring),(.failures|tostring),(.failure_rate|tostring)] | @tsv' \
        | while IFS="$(printf '\t')" read -r day name mode runs passes failures rate; do
            printf '%-10s %-24s %-6s %-5s %-5s %-5s %s\n' "$day" "$name" "$mode" "$runs" "$passes" "$failures" "$rate"
          done
    printf 'Plan cycles: N/A (no machine-readable lifecycle)\n'
    printf 'Review findings: %s\n' "$(printf '%s' "$REVIEW_FINDINGS" | jq -r .count)"
    printf 'Session commits: %s%s\n' "$(printf '%s' "$SESSION_COMMITS" | jq -r .status)" \
        "$(printf '%s' "$SESSION_COMMITS" | jq -r 'if .reason then " ("+.reason+")" else "" end')"
    printf 'Recommendations: %s\n' "$(printf '%s' "$REPORT" | jq -r '[.recommendations[].code] | if length==0 then "none" else join(", ") end')"
fi
