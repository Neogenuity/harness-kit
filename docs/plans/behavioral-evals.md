# Behavioral eval layer

Status: queued

## Objective

Give the harness a way to measure itself: repo-specific golden tasks with
acceptance criteria independent of agent-authored tests, a runner that
executes them headlessly, and recorded baselines so harness changes are
regression-testable.

## Value

The kit can verify the harness is *coherent* (drift, links, checksums) but
not that it *works* — nothing tests whether a skill, convention doc, or hook
actually changes agent behavior. Evals are a top-level pillar of current
practice, and measurement is the prerequisite for judging every later
component: the reviewer loop earns its place only if a seeded-defect eval
shows it catches defects, per the test-and-remove discipline in
<https://www.anthropic.com/engineering/harness-design-long-running-apps>
(validated 2026-07-10). Böckeler's framing (martinfowler.com, 2026-04,
validated 2026-07-10:
<https://martinfowler.com/articles/harness-engineering.html>) calls the
behavioral harness the least-developed of the three — which makes it the
differentiation opportunity.

## Scope

1. **Convention**: `docs/evals/` — `README.md`, `tasks/<slug>/TASK.md`
   (prompt, setup, acceptance criteria as executable checks where possible),
   optional `rubrics/<slug>.md` for semantic criteria. Acceptance criteria
   must be independent of any tests the agent writes during the task.
2. **Runner**: `scripts/eval.sh <task>` — runs one golden task headlessly
   (provider-selectable; invocations re-verified against current provider
   CLI docs at build time and stamped), applies the task's acceptance
   checks + `verify.sh`, appends one JSON line per run to
   `.harness/eval-results/` (task, provider, pass/fail, duration, retries).
   Fail-open philosophy does not apply here — evals may fail loudly; they
   are never wired into guard hooks.
3. **Harness regression**: `scripts/eval-harness.sh` — runs the task set,
   compares against the recorded baseline, reports deltas. Non-blocking by
   default; optional CI job template (scheduled, not per-PR — cost honesty:
   multi-agent runs cost dollars, not cents).
4. **Kit dogfood**: 2–3 golden tasks for this repo (e.g. "add a guard hook
   with a regression test", "add a skill and sync stubs") with baselines
   recorded. *Acceptance: both tasks run green locally via `eval.sh`.*
5. **init integration**: interview question ("which 1–2 recurring tasks
   define success here?"); audit mode reports eval presence + last baseline
   age.

## Out of scope

Semantic/LLM-judged rubrics as blocking gates (advisory only); provider
*performance* benchmarking; token/cost telemetry (outcome-telemetry plan).

## Dependencies

The plans-machinery release: this roadmap's format ships as the template,
and its fixture recipe seeds eval fixtures.

## Verification

Kit's own golden tasks pass; `eval-harness.sh` detects an intentionally
broken skill description (regression demo); results land in
`.harness/eval-results/`; docs cross-linked from AGENTS.md.

## Progress

- 2026-07-10 — Hardened after two-agent review: false dependency clause on
  matrix CLI-invocation facts dropped (runner verifies invocations itself),
  citation attribution corrected to Böckeler.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice; both that review and an independent
  external one ranked evals top-two.

## Decisions

- 2026-07-10 — Measurement before more components: every later addition
  must be provable with this machinery.

## Next action

After plans-machinery ships: design the `TASK.md` acceptance-check format
(executable checks first, rubric fallback).
