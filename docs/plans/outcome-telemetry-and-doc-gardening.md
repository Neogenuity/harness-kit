# Outcome telemetry + doc gardening

Status: queued

## Objective

Grow observability from friction metrics (what guards denied) to outcome
metrics (what work succeeded), and keep the knowledge base fresh
mechanically — completing the outer-harness story for a 1.0.

## Value

`.harness/log.jsonl` currently measures harness *friction* — denies,
advisories, lint findings. It can't answer "do tasks of this type fail
verification often?" or "did that skill reduce retries?". The
observability-driven improvement loop is where the field is heading —
formalized as far as autonomous harness evolution
(<https://arxiv.org/abs/2604.25850>, 2026-04, validated 2026-07-10); the
kit's audit mode is the manual, human-judged version of the same loop and
should feed on outcome data, not just denials. Doc gardening is the
knowledge-base analog: OpenAI runs a recurring agent that scans for stale
docs and opens fix-up PRs
(<https://openai.com/index/harness-engineering/>, validated 2026-07-10) —
this repo's own per-fact verification stamps are the natural substrate for
the same treatment.

## Scope

1. **Log schema v2** (`hook_log`): add session/provider identifiers, gate
   name + duration + outcome, retry counts, plan slug (from `active/`),
   optional token/cost fields. Review-findings lines are already emitted in
   v1-compatible form by the reviewer loop — consumed here, not redefined.
   Backward compatible — v1 lines keep parsing.
2. **verify.sh emits gate events**: one line per gate run (name, mode,
   outcome, duration) so the definition of done becomes a data source.
3. **Audit trends**: audit mode grows from counts to trends — failure rate
   by gate over time, repeat-deny paths, plan cycle time, eval baseline
   drift (behavioral-evals results). Output stays a table + "what to
   engineer away next".
4. **Doc-gardening skill**: `templates/docs/skills/doc-garden/SKILL.md` —
   scan for dead links beyond AGENTS.md, stale verified-date stamps past a
   configurable age, docs referencing deleted paths; open a fix-up PR.
   Scheduled-run guidance (provider cron/scheduled-agent features), not a
   daemon. *Acceptance: run against this repo, it flags the oldest matrix
   stamps.*
5. **Session→PR joins**: audit joins log sessions to merged PRs via the
   commit-trailer convention the reviewer-loop plan documents (defined
   there, consumed here).

## Out of scope

Hosted dashboards/collectors (point at OTel per the execution-sandbox-profiles
plan); autonomous harness self-modification (the arXiv direction — the kit
keeps a human in the audit loop by design, per ADR 001's advisory
philosophy).

## Dependencies

Behavioral-evals (results to trend), reviewer-loop (findings lines + the
trailer convention), execution-sandbox-profiles' audit-log-export item
(the OTel/monitoring export pointers, which trails runtime-legibility). This is
deliberately last: outcome telemetry is only worth building once gates,
reviews, and evals emit outcomes.

## Verification

Schema v2 regression tests; audit renders a trend summary from this repo's
real log; gardening skill flags a seeded stale stamp; `verify.sh` green.

## Progress

- 2026-07-10 — Hardened after two-agent review: review-findings fields
  removed from the schema-v2 list (the reviewer loop defines them; this
  plan consumes), session→PR attribution deduplicated to the reviewer-loop
  plan.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-10 — Human-in-the-loop stays: audit recommends, people decide —
  autonomous harness evolution is explicitly out of scope for 1.0.

## Next action

After execution-sandbox-profiles ships: design log schema v2 with a version
field first; everything else consumes it.
