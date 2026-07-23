# Local outcome telemetry

The harness writes local, git-ignored events to `.harness/var/log.jsonl`. This is a
repository feedback stream, not provider telemetry: it installs no collector,
imports no provider export, and makes no team-wide or retention guarantee.
Use `bash scripts/harness/lib/audit-log.sh --format table` for deterministic reduction; do
not recompute rates or joins by hand.

## Mixed-version contract

Old logs are not migrated. Consumers accept exact v1 hook/reviewer records and
v2 records in the same file.

A v1 record has exactly five top-level keys:

```json
{"ts":"2026-07-15T12:00:00Z","hook":"code-reviewer","event":"review-finding","file":"src/example.py","detail":"{\"severity\":\"high\",\"line\":7,\"category\":\"weak-tests\",\"evidence\":\"...\",\"suggested_fix\":\"...\"}"}
```

Review findings remain exact v1 records. Their structured finding stays encoded
inside the `detail` string; do not add a version or attribution key to that
five-key envelope.

A v2 record has exactly these eight top-level keys:

```json
{
  "version": 2,
  "ts": "2026-07-15T12:00:00Z",
  "hook": "verify.sh",
  "event": "gate",
  "file": "",
  "detail": "",
  "context": {
    "run_id": "verify-1234",
    "session_id": "opaque-session-id",
    "provider": "codex",
    "plan_slug": "v0.17.0-outcome-telemetry-and-doc-gardening",
    "provenance": {
      "run_id": "verify",
      "session_id": "env",
      "provider": "env",
      "plan_slug": "env"
    }
  },
  "data": {
    "name": "tests",
    "mode": "full",
    "outcome": "pass",
    "exit_code": 0,
    "duration_s": 12
  }
}
```

| Key | Contract |
| --- | --- |
| `version` | Integer `2`. Any other explicit version is unsupported, not v1. |
| `ts` | UTC `YYYY-MM-DDTHH:MM:SSZ`. |
| `hook`, `event`, `file`, `detail` | Strings. They retain the v1 names so simple mixed-log consumers can still select familiar fields. |
| `context` | Object for optional, explicitly sourced attribution. `{}` is valid and means unknown. |
| `data` | Object owned by the event type. `{}` is valid for deny, advise, and lint events. |

`context` and `data` are the nested extension points: consumers ignore unknown
nested fields, while producers write only fields whose meaning and provenance
are documented. The eight-key top level does not grow implicitly.

## Attribution and privacy

Known context fields are `run_id`, `session_id`, `provider`, `plan_slug`, and
`provenance`. Attribution values are strings; an unknown or invalid value and
its provenance key are both omitted:

| Field | Value and source |
| --- | --- |
| `run_id` | At most 128 `A-Za-z0-9._/-` characters. Provenance is `verify` when generated for one `verify` invocation or `env` when explicitly supplied to another producer. |
| `session_id` | At most 256 characters with no control characters. Provenance is `env` when supplied explicitly, or `payload` when copied from a supported hook `.session_id`/`.conversation_id` field. |
| `provider` | At most 64 `A-Za-z0-9._/-` characters. Provenance is `env`; no inference fallback exists. |
| `plan_slug` | At most 128 `A-Za-z0-9._/-` characters. Provenance is `env`; no active-directory fallback exists. |
| `provenance` | Object mapping every present attribution field to its source above. It is absent when `context` is empty. |

Never infer provider, skill, plan, or session from directories, filenames,
models, surviving configs, or prose. If multiple plans are active and no plan
was explicitly supplied, omit `plan_slug`; do not choose one. Skill identity,
token/cost data, and PR identity have no v0.17 producer and remain N/A. Do not
copy provider exports into this log to fill them.

Treat every identifier and path as local operational data. Keep the
runtime-state dir `.harness/var/` git-ignored (only `var/` — the rest of
`.harness/` is committed repo-owned policy, personas, schemas, and evals).
Producers may record selected, bounded categorical labels or counts
whose meaning is documented. They never serialize raw hook payloads, prompts,
commands or arguments, diagnostic/tool-output buffers, transcripts, environment
contents, credentials, collector endpoints, authorization headers, or other
secrets. A `Harness-Session-Id:` Git trailer is an explicit, public commit
choice; it is not written automatically from the local log.

Malformed JSON, an invalid v1/v2 shape, and an unsupported explicit version are
counted and skipped by the reducer. They do not abort the rest of the report.
An unknown v2 event remains a valid unknown event but contributes to no typed
trend. Logging is fail-open: disabled logging, missing `jq`, or an unwritable log
must not change a hook or gate's output or exit status.

The parser counters are exactly `valid_v1`, `valid_v2`, `invalid_json`,
`invalid_schema`, `unsupported_version`, and `unknown_event`. Keep these
classifications visible; never silently discard a bad row.

## Gate outcomes and trends

A `gate` event uses exactly these `data` fields:

| Field | Contract |
| --- | --- |
| `name` | Stable gate label string. |
| `mode` | `fast` or `full`. |
| `outcome` | `pass` or `fail`. |
| `exit_code` | Integer exit code from the gate command. |
| `duration_s` | Nonnegative integer wall duration measured with portable Bash `SECONDS`. |

Each gate actually run emits one event. A serial failure logs before
`verify` exits; the parent serializes completed parallel results; a full gate
skipped under `--fast` is not fabricated as a run. Event writing records no gate
command or output and cannot change reporting order, cleanup, or exit behavior.

`outcome: "pass"` pairs with exit code `0`; `outcome: "fail"` pairs with the
nonzero gate-command exit code. The harness's own final exit remains its
existing success/failure contract and is not replaced by the recorded command
code.

`audit-log.sh` owns the math and stable ordering. Gate failure rate uses valid
gate runs as its denominator. Repeated deny paths group the reducer's documented
hook/file key. A retry is derived only inside an explicit session: for the same
`session_id`, gate name, and mode, an execution after an earlier failure is a
retry. Without a session id, retry attribution is N/A rather than guessed.
No rows means no data; one row is a valid count/rate but not an over-time trend.

Retry summaries are exactly
`{session_id,name,mode,episodes,retries}`. `episodes` counts failure episodes;
`retries` counts later executions in those episodes. Rows without a session id
contribute to gate outcomes but never to retry summaries.

Daily gate summaries are exactly
`{day,name,mode,runs,passes,failures,failure_rate,duration_s}` and sort by UTC
day, name, then mode. `failure_rate` is failures divided by runs in the range
0..1; `duration_s` is the summed observed duration. An absent log reports
`log.status: "no_data"` with zero parser counters, empty gate/retry/deny
sections, and review count zero; Git/eval sections remain independently
derived. An existing unreadable log is an input error, not no data.

`review_findings` is exactly `{count}` and counts valid `review-finding` records
across the mixed stream. The reducer owns this count; audit prose does not
recount raw JSONL.

Plan-cycle timing is `not_available` in v0.17 because free-form progress prose
and Git rename history are not a portable lifecycle clock. With usable local Git
history, exact session trailers produce
`{status:"available",items:[{session_id,commit}],reason:null}`. Without Git,
with shallow history, or when local history cannot be read, `status` is
`not_available`, `items` is empty, and `reason` is respectively
`no_git_repository`, `shallow_history`, or `git_log_failed`. PR enrichment is
N/A without an explicit versioned metadata producer. Available items sort by
session id then commit and de-duplicate identical pairs; a comma inside a valid
session id remains part of that one id. Eval drift comes only from the existing
local eval baseline/results artifacts through the reducer/scorer. Missing or
malformed inputs stay visibly unavailable or invalid; they never become zero or
success.

## Audit boundary

Run the reducer against local artifacts:

```bash
bash scripts/harness/lib/audit-log.sh --format table
```

Use `--format json` when another deterministic tool consumes the result. Its
version-1 report has the stable top-level keys `version`, `log`, `parser`,
`gate_outcomes_daily`, `retry_episodes`, `repeat_denies`, `review_findings`,
`session_commits`, `plan_cycles`, `eval`, and `recommendations`. Repeat-deny
rows are `{hook,file,count}`; `review_findings` is `{count}`; available session
joins are `session_commits.items` rows shaped `{session_id,commit}` from exact
local Git trailers. `plan_cycles` is
`{status:"not_available",reason:"no_machine_readable_lifecycle"}`. Eval is
`not_available` when current results or a baseline is absent, `invalid` when the
existing scorer fails, and `available` only with the scorer's JSON report.

Recommendations have stable code order: repair invalid log rows, address gate
failures, reduce gate retries, engineer repeat denials, then investigate an eval
regression. They recommend; they never mutate the repository.

Keep the provider-observability availability table separate: provider OTel, product
analytics, local provider logs, and exports have different schemas, privacy,
scope, and retention, and this harness neither ingests nor automatically joins
them.
