# Eval discrimination

Status: queued

## Objective

Grow the behavioral eval bank and its recorded baselines until they actually
discriminate model and harness behavior, and give the discipline a scheduled,
cost-honest cadence instead of ad hoc manual runs.

## Value

The v0.8.0 dogfood bank hit pass^k=1 on 15 of 16 recorded cells (8 tasks ×
2 providers) — a bank that strong models clear every trial cannot demonstrate
that a harness change *improved* behavior, because there is no headroom left
to move. The reviewer-loop plan's ship gate is a seeded-defect eval built on
this same machinery; it needs a bank capable of showing a catch-rate that
isn't already saturated at 100%. A fuller baseline matrix (more providers,
more models) and a scheduled run are the difference between an eval layer
that was exercised once at launch and one that stays a living regression
signal.

## Scope

1. **Harder capability tasks** — author at least two new capability tasks
   where the strongest cheap model in the current matrix (Claude Code /
   haiku) scores below 100% pass^k, so the bank has room to show improvement
   or regression. *Acceptance: `eval.sh --trials 3` run against the new
   tasks on haiku records a pass^k below 1.0 for at least two tasks.*
2. **Fuller baseline matrix** — record Claude Code/sonnet and
   Codex/gpt-5.6-luna baselines across the full task bank (the v0.8.0 bank
   recorded only haiku and gpt-5.6-terra). *Acceptance:
   `docs/evals/baselines.json` carries cells for both additional
   provider/model pairs across every task in the bank.*
3. **Re-record the under-trialed regression cell** — the
   `regression-fix-dangling-link` codex/gpt-5.6-terra cell was recorded at 2
   trials, predating the `--expected-trials` guard added in
   [completed/v0.9.0-eval-integrity-and-plan-hygiene.md](completed/v0.9.0-eval-integrity-and-plan-hygiene.md);
   re-run it at the now-standard 3. *Acceptance: the cell's trial count in
   `docs/evals/baselines.json` matches `--expected-trials` (3).*
4. **A scheduled eval run** — a GitHub Actions cron workflow template
   invoking `eval.sh` + `eval-harness.sh` on a schedule (never per-PR — a
   multi-trial, multi-provider run costs real dollars, not cents), with cost
   honesty notes in the template comments so an adopting repo understands
   what it's turning on before it does. *Acceptance: the workflow template
   exists, is documented as opt-in, and a dry run against this repo's own
   bank completes and appends results.*
5. **Backfill per-cell `recorded` dates** — the current
   [baselines.json](../evals/baselines.json) predates the v0.9.0 per-cell
   `recorded` feature its own README documents: no cell carries a date, only
   the back-compat top-level stamp, so a single stale cell inside an
   otherwise-fresh file is invisible — the exact case the per-cell date
   exists to expose. When recording the fuller matrix (item 2), also
   re-record the existing claude/haiku and codex/gpt-5.6-terra cells so every
   cell carries its own date. *Acceptance: every `tasks.*.runs.*` cell in
   `docs/evals/baselines.json` carries a `recorded` date.*

## Out of scope

Any change to the scoring mechanism itself (aggregation, outcome taxonomy,
baseline-write guards) — that is
[completed/v0.9.0-eval-integrity-and-plan-hygiene.md](completed/v0.9.0-eval-integrity-and-plan-hygiene.md)'s
territory, and this plan depends on it landing first so new baselines aren't
recorded against a scorer with known bugs. LLM-judged rubrics as blocking
gates (already out of scope for the eval layer generally, per
[completed/v0.8.0-behavioral-evals.md](completed/v0.8.0-behavioral-evals.md)).

## Dependencies

[completed/v0.9.0-eval-integrity-and-plan-hygiene.md](completed/v0.9.0-eval-integrity-and-plan-hygiene.md)
— the integrity fixes. Recording new baselines on top of a lexicographic
run-selection bug, an unenforced mock exclusion, or uneven trial counts would
bake those bugs into cells this plan treats as ground truth.

## Verification

New capability tasks pass `test-eval.sh`'s offline grader-validity check
(reference solution scores a pass, and for any negative task the violation
scores `negative_violation`); the fuller matrix and re-recorded cell are
visible in `docs/evals/baselines.json`; `eval-harness.sh` runs clean against
the grown bank; the scheduled workflow's dry run appends a results file
without per-PR triggering.

## Progress

- 2026-07-12 — Added scope item 5 from the 2026-07-12 project review:
  `baselines.json` predates the per-cell `recorded` feature the evals README
  documents (no cell carries a date — only the back-compat top-level stamp).
  Folded here rather than a new plan — it's one more re-record on the
  same runs this plan already schedules.
- 2026-07-11 — Scoped from v0.8.0's Next-action follow-up note and the
  2026-07-11 project review, which flagged the saturated bank as the reason
  the reviewer-loop's seeded-defect eval has nothing to discriminate against
  yet.

## Decisions

- 2026-07-11 — Blocked on the integrity plan rather than run in parallel:
  new baseline cells are only as trustworthy as the scorer recording them.

## Next action

Author the first harder capability task.
