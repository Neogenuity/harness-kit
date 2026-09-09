---
harness_plan: 1
status: queued
started: null
completed: null
---

# Automatic session capture for `observe`

Status: queued

## Objective

Ordinary agent sessions land in `observe`'s run store without anyone
remembering to export a transcript. A shipped, opt-in session-end hook writes
the provider's own transcript (and, where the provider gives one, the outcome
diff) into `.harness/var/runs/` via the existing `scripts/harness/observe
import` path, so the deterministic trajectory evidence v0.42.0 built is
produced by daily work rather than by a manual ritual. Capture stays local,
default-off, and fail-open; nothing new leaves the repo.

## Value

v0.42.0 shipped the whole downstream half of issue #36 — `trace-event.v1`
normalization, eleven deterministic trajectory fields, `observe
import|feedback|show|promote`, untrusted drafts
([completed/v0.42.0-open-issue-hardening.md](completed/v0.42.0-open-issue-hardening.md)).
Its one remaining gap is the intake: every run in the store is there because a
human typed an import command. That makes the observational corpus a
convenience sample of the sessions someone already thought were interesting —
exactly the sessions least likely to contain the failures the eval bank needs.
The mechanism is built and idle; this plan supplies it with input. Doing it now
is cheap (one hook, one wiring row, one knob) and doing it later costs the
corpus every session that passes through in the meantime.

## Provider session-end signals

Each fact below is stamped with whether it was fetched and confirmed. Anything
unverified must be re-checked before it is built against — the same discipline
[ADR 004](../architecture/decisions/004-provider-matrix-verification.md)
imposes on the provider matrix.

| Provider | Session-end signal | Transcript path in payload? | Status |
| --- | --- | --- | --- |
| Claude Code | `SessionEnd` | yes — `transcript_path` | **verified 2026-09** |
| Codex | `SessionEnd` | yes — `transcript_path` | **verified 2026-09** |
| Cursor | `sessionEnd` | **no** | **verified 2026-09** |
| OpenCode | `session.idle` (bus event) | **no** | **verified 2026-09** |

- **Claude Code — verified 2026-09** against
  <https://code.claude.com/docs/en/hooks>. `SessionEnd` receives `session_id`,
  `transcript_path`, `cwd`, `hook_event_name`, and `reason`; documented `reason`
  values are `clear`, `resume`, `logout`, `prompt_input_exit`, `other`.
  `SessionEnd` is **not** in the page's exit-code-2 blocking table — it cannot
  block, which removes the usual guard-hook risk but does **not** remove the
  time budget (a slow hook still delays teardown).
- **Codex — verified 2026-09** against <https://learn.chatgpt.com/docs/hooks>,
  the source the provider matrix already cites for Codex hooks. `SessionEnd` is
  documented ("when a session ends") and receives `session_id`,
  `transcript_path`, `cwd`, `hook_event_name`, `reason`. `Stop` and
  `SubagentStop` also carry `transcript_path`. Note the matrix's Codex event
  list (`references/provider-matrix.md`, per-provider notes) predates this and
  does **not** name `SessionEnd`; correcting that row with its own
  `verified` stamp is part of this plan's scope.
- **Cursor — verified 2026-09** against <https://cursor.com/docs/hooks>. A
  `sessionEnd` hook exists, but its documented input is `session_id`, `reason`,
  `duration_ms`, `is_background_agent`, `final_status`, and optional
  `error_message` — **no `transcript_path`**, even though the common hook schema
  documents `transcript_path` for other events. Cursor therefore has no usable
  session-end capture signal today.
- **OpenCode — verified 2026-09** against <https://opencode.ai/docs/plugins/>.
  The plugin event bus exposes `session.idle`, `session.updated`,
  `session.deleted`, `session.compacted` and friends; none is documented as
  carrying a transcript path, and `session.idle` is an idleness signal rather
  than a session terminator. OpenCode has no usable session-end capture signal
  today.

**Plainly: only Claude Code and Codex can be auto-captured.** They are also the
only two providers `eval_normalize_trace` understands, so the capture set and
the normalization set coincide — no provider is left half-supported.

## The blocking finding: `transcript_path` is not the shape `import` accepts

Measured 2026-09-09 on this machine against a real Claude Code session file
under `~/.claude/projects/<project>/<session>.jsonl` (structure only; no
content was read into the repo):

- Row types present: `assistant`, `user`, `last-prompt`, `custom-title`,
  `attachment`, `queue-operation`, `system/stop_hook_summary`, `pr-link`.
- There is **no** `{"type":"system","subtype":"init"}` row and **no**
  `{"type":"result"}` row.
- The session id is `sessionId` (camelCase), not `session_id`.
- The parts that *do* match: `assistant` rows carry
  `message.content[] .type == "tool_use"` with `id`/`name`/`input`, and `user`
  rows carry `tool_result` with `tool_use_id`/`is_error` — the exact blocks
  `eval_normalize_trace claude` reads.

`scripts/harness/observe import` requires a `session.started` anchor and dies
with `transcript has no recognized session-start anchor` without one, so
handing it a raw `transcript_path` **fails today**. `eval_normalize_trace` was
written for the `claude -p --output-format stream-json` dialect the eval runner
produces, which is a different serialization of the same session.

This is the single largest piece of work in the plan and the reason it is not a
one-file hook. It must be resolved deliberately — see Scope item 2 — not by
loosening `observe import`'s anchor check, which is what stops a truncated or
unrelated file from being imported as evidence.

## Scope

1. **Opt-in knob** — a `HARNESS_OBSERVE_CAPTURE` TAILOR entry in
   `scripts/harness/harness.conf`, defaulting to `0` (off), documented next to
   `HARNESS_LOG` with the same local-only framing. Capture is a behavior change
   in an adopter's repo; naming a provider must never switch it on, the same
   asymmetry [ADR 011](../architecture/decisions/011-provider-declaration-and-capability-table.md)
   applies to execution profiles.
   *Acceptance: with the knob unset or `0`, the hook exits 0 having created no
   file under `.harness/var/runs/`; with `1`, the same payload produces exactly
   one run directory.*
2. **Session-file dialect support** — teach `eval_normalize_trace` the
   on-disk session-transcript shape, or add an explicit pre-normalization step
   in the hook, so a real `transcript_path` becomes a valid `trace-event.v1`
   stream. Whichever is chosen, the `session.started` anchor must come from an
   observed fact in the file (e.g. the first row's `sessionId`), never
   synthesized to satisfy the check. Decide and record which of the two
   approaches is taken before writing code; do not do both.
   *Acceptance: a committed fixture in the session-file dialect normalizes to
   the same event vocabulary as the existing stream-json fixture, and
   `observe import` accepts it; the existing stream-json fixture still passes
   unchanged.*
3. **Shipped hook** — `scripts/harness/hooks/capture-session.sh` under
   `templates/scripts/harness/hooks/`, reading the payload through the existing
   `lib.sh` helpers rather than a per-provider field layout. It must obey the
   fail-open contract in
   [docs/standards/templates.md](../standards/templates.md): missing `jq`, empty
   stdin, an unknown JSON shape, an absent or unreadable `transcript_path`, or a
   failed import all `exit 0` silently. It must also carry its own time budget —
   `SessionEnd` cannot block, but it still runs during teardown, so bound the
   import (the v0.42.0 OpenCode adapter's bounded child runner is the precedent)
   and abandon rather than hang.
   *Acceptance: every one of those degraded inputs exits 0 with no partial run
   directory; a well-formed payload produces one run whose `metadata.json`
   validates as a version-2 record.*
4. **Claude wiring + check #8d** — a `SessionEnd` entry in
   `templates/providers/claude/settings.json`, and a matching
   `capture-session.sh SessionEnd` row in the frozen `.claude` tuple table in
   `scripts/harness/lib/check-instructions.sh`. **The wiring ships
   unconditionally and the hook gates itself on the knob** — #8d asserts every
   listed tuple is *present*, so conditional wiring would either fail the check
   or (if left out of the table) ship an entirely unvalidated hook.
   **This is not an ADR 011 reopen trigger.** The capability table
   (`scripts/harness/lib/provider-caps`) records each provider's `hook_config`
   *path and shape*, not its event list, and `.claude` is already hook-wired —
   the event/matcher tuples are deliberately held inline in
   `check-instructions.sh` as "a frozen, richer contract than a table cell". The
   table would only reopen if a provider had to enter or leave the hook-wired
   set, which none does here.
   *Acceptance: `check-harness` #8d fails when the `SessionEnd` entry is deleted
   from `settings.json`, and passes on the shipped tree; `test-provider-templates.sh`
   stays green.*
5. **Retention** — bound the run store the way v0.42.0 bounded the event log:
   rotation, not deletion. Adopt the
   [outcome-telemetry](../standards/outcome-telemetry.md) posture verbatim —
   the kit does not auto-delete an operator's evidence — with a
   `HARNESS_OBSERVE_MAX_RUNS` cap that prunes only runs the operator has not
   labelled via `observe feedback`, and a documented manual sweep for the rest.
   *Acceptance: importing past the cap leaves the cap's worth of unlabelled runs
   plus every labelled run, and the standards doc states what pruning loses.*
6. **Regression test** — `scripts/harness/tests/test-capture-session.sh`,
   shipped beside the hook per the "every guard ships with a regression test"
   rule, and listed **individually** in both
   `templates/scripts/harness/kit-manifest` and `scripts/harness/kit-manifest`
   (a shipped test missing from the manifest never reaches an adopter and no
   gate catches the gap).
   *Acceptance: the suite runs standalone, is picked up by the `parallel-each
   template-test` gate, and both manifests list it identically.*
7. **Docs** — the capture path, the knob, the two-provider limit, and the
   privacy stance in [.harness/evals/README.md](../../.harness/evals/README.md)
   and its template counterpart; the Codex `SessionEnd` correction in
   `references/provider-matrix.md` with a `verified` stamp and a Sources entry.
   *Acceptance: `check-harness` doc-ref and matrix-stamp checks pass; the
   shipped and dogfood READMEs stay consistent.*

## Privacy

A transcript is the most sensitive artifact this kit ever writes: it contains
absolute repository paths, file contents the agent read, and the full text of
every command it ran. The existing controls already cover the destination and
must not be weakened — `.harness/var/` is git-ignored, `observe` runs under
`umask 077` (runs are `0700`, files `0600`), and `promote` copies only
path-redacted trajectory metrics into a draft, never the transcript or
`diff.patch`. Two additions belong to this plan: capture is **off by default**
so no adopter starts recording without deciding to, and the hook must never
echo transcript content to stdout or stderr — a `SessionEnd` hook's output is
still an operator-visible channel.

## Out of scope

Phase 5 integrations, unchanged from
[completed/v0.42.0-open-issue-hardening.md](completed/v0.42.0-open-issue-hardening.md):
hosted or uploaded transcript collection, OTLP and third-party observability
exports, LLM trajectory judges, and any observational CI gate. Cursor and
OpenCode capture stay out until those providers expose a transcript path —
re-check their docs, do not reconstruct a transcript from event streams.
Automatic *diff* capture is also out: nothing in a session-end payload names
the outcome diff, and having the hook run `git diff` itself would guess at a
boundary the operator owns. `observe import --diff` stays manual.

## Dependencies

The v0.42.0 observation mechanism (`observe`, `trace-lib.sh`, `eval-author`)
and the outcome-diff support that ships with it. No new external dependency:
`bash` + `jq`, with `jq`'s absence degrading to a no-op as everywhere else.

## Verification

- `bash scripts/harness/tests/test-capture-session.sh` standalone, covering the
  knob off/on, each fail-open input, and the time budget.
- `bash scripts/harness/tests/test-observe.sh` unchanged and green — the
  existing import contract must not shift under the new caller.
- A mutation check on the #8d row: delete the `SessionEnd` entry from
  `templates/providers/claude/settings.json`, confirm `check-harness` fails,
  restore.
- An end-to-end local capture: run a real Claude Code session with the knob on,
  confirm exactly one run appears under `.harness/var/runs/`, and that
  `observe show <run-id>` reports a trajectory with a non-zero `events` count.
- `bash scripts/harness/verify` and `bash scripts/harness/check-harness` clean.

## Progress

- 2026-09-09 — Scoped. Provider session-end signals verified for all four
  providers; the transcript-dialect mismatch measured against a real session
  file and recorded as the blocking finding.

## Decisions

- 2026-09-09 — Capture is opt-in and default-off because it starts recording
  command text and file paths in a repo the adopter did not ask to be recorded;
  the ADR 011 execution-profile asymmetry is the precedent.
- 2026-09-09 — Wire the `SessionEnd` hook unconditionally and gate behavior
  inside the hook, because check #8d's tuple table asserts presence; a
  conditionally-present hook is either a check failure or an unchecked hook.
- 2026-09-09 — Do not relax `observe import`'s session-start anchor to accept
  the on-disk dialect. The anchor is what stops an unrelated or truncated file
  from being imported as evidence; the dialect gap is fixed on the
  normalization side.
- 2026-09-09 — Automatic diff capture is excluded rather than deferred: the
  session-end payload does not name one, and inferring it from `git diff` would
  make the kit guess where the operator's change began.

## Next action

Decide Scope item 2 — extend `eval_normalize_trace` with the session-file
dialect, or pre-normalize inside the hook — and record the choice in this
plan's Decisions log before any code is written.
