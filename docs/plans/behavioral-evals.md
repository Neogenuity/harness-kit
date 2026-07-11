# Behavioral eval layer

Status: queued

## Objective

Give the harness a way to measure itself: repo-specific golden tasks with
acceptance criteria independent of agent-authored tests, a runner that
executes each task over **multiple independent trials** in **isolated
environments**, captures **transcripts**, scores with **reference-solution-
validated graders**, and records **pass-rate baselines** so harness changes
are regression-testable rather than judged from a single lucky (or unlucky)
run.

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

**A single-trial demo is not an eval.** Anthropic's current eval guidance
(<https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>,
validated 2026-07-11) is explicit that agent behavior is non-deterministic
and must be interpreted with pass-rate metrics over multiple trials
(pass@k = "at least one correct in k attempts"; pass^k = "correct on all k",
for consistency), that each trial must start from a **clean, isolated
environment** to avoid correlated failures from shared state, that a
**transcript** (outputs, tool calls, reasoning, intermediate state) is
captured per trial, that each task needs a **reference solution** proving it
is solvable and the grader valid, that **capability** suites (start at a low
pass rate) are distinguished from **regression** suites (near-100%), that
both **positive and negative** cases are tested, and that graders (especially
LLM-as-judge) are **calibrated against human review** by periodically reading
transcripts. Two or three one-shot dogfood tasks would demonstrate the
plumbing but would not be a credible measurement — this plan is scoped to the
full discipline from the start.

## Scope

1. **Convention**: `docs/evals/` — `README.md`, `tasks/<slug>/TASK.md`
   (prompt, setup, acceptance criteria as executable checks where possible,
   a `suite: capability|regression` tag, and a `polarity: positive|negative`
   note for tasks that assert a behavior must *not* happen), a
   `tasks/<slug>/reference/` reference solution (a known-good output the
   graders pass, proving the task is solvable and the grader valid), and an
   optional `rubrics/<slug>.md` for semantic criteria. Acceptance criteria
   must be independent of any tests the agent writes during the task.
2. **Runner**: `scripts/eval.sh <task> [--trials N]` — runs one golden task
   headlessly (provider-selectable; invocations re-verified against current
   provider CLI docs at build time and stamped) for **N independent trials
   (default 3)**, each in a **fresh isolated workspace** (throwaway clone /
   scratch dir per trial — no shared state between trials, so leftover files
   or caches can't cause correlated pass/fail), captures a **transcript per
   trial** under `.harness/eval-results/<task>/<run>/` (agent output, tool
   calls, verify.sh output), applies the task's acceptance checks +
   `verify.sh` + reference-solution grader, and appends one JSON line per
   *trial* (task, provider, suite, trial index, pass/fail, duration, retries,
   transcript path). Fail-open philosophy does not apply here — evals may
   fail loudly; they are never wired into guard hooks.
3. **Harness regression**: `scripts/eval-harness.sh` — runs the task set,
   computes **pass@k and pass^k per task** from the trials, compares against
   the recorded baseline (capability tasks expected below 100%, regression
   tasks at/near 100%), reports deltas. Non-blocking by default; optional CI
   job template (scheduled, not per-PR — cost honesty: multi-agent runs cost
   dollars, not cents).
4. **Kit dogfood bank**: an **initial bank of 8–12 golden tasks** for this
   repo spanning both suites and both polarities — capability examples ("add
   a guard hook with a regression test", "add a skill and sync stubs", "add a
   provider matrix row and stamp it"); regression examples (a known-good
   change that must keep passing); at least one **negative** task (the agent
   must *not* weaken a guard or edit a `# tailored` file to make a check pass).
   Each task ships with its reference solution and a recorded pass@k/pass^k
   baseline. *Acceptance: the bank runs via `eval.sh --trials 3`; every
   task's reference solution scores as a pass (grader validity); baselines
   recorded.*
5. **Grader calibration**: a documented calibration step — for any
   LLM-as-judge rubric, a human reads a sample of transcripts and confirms
   the grader's verdicts match, recorded as a dated calibration note next to
   the rubric; re-run when a rubric or the judged model changes. Executable
   checks (the default) need no calibration; only semantic rubrics do.
6. **init integration**: interview question ("which 1–2 recurring tasks
   define success here?"); audit mode reports eval presence, suite counts,
   and last baseline age.

## Out of scope

Semantic/LLM-judged rubrics as blocking gates (advisory only); provider
*performance* benchmarking; token/cost telemetry (outcome-telemetry plan);
a hosted eval-orchestration service (the runner stays local/CI-scheduled).

## Dependencies

The plans-machinery release: this roadmap's format ships as the template,
and its fixture recipe seeds eval fixtures. The install/update-verification
release (deterministic fixtures): its throwaway-repo harness is the
isolation substrate the per-trial clean environments reuse, and "does init
produce a passing harness" is the natural first **model-driven** golden task
here (the deterministic filesystem half lives in that plan).

## Verification

Kit's dogfood bank runs green via `eval.sh --trials 3` with pass@k/pass^k
baselines recorded; every task's reference solution scores as a pass;
`eval-harness.sh` detects an intentionally broken skill description as a
pass-rate regression (regression-suite demo) and a negative task catches a
seeded guard-weakening (negative-case demo); per-trial transcripts land under
`.harness/eval-results/`; any semantic rubric carries a dated calibration note
whose verdicts a human confirmed against a transcript sample; docs
cross-linked from AGENTS.md.

## Progress

- 2026-07-11 — Strengthened against Anthropic's eval guidance
  (<https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>,
  validated 2026-07-11) after a standards-coverage audit found the plan
  demonstrated plumbing but not measurement: added multi-trial runs with
  pass@k/pass^k, per-trial isolated environments, transcript capture,
  reference solutions as grader-validity proofs, the capability/regression
  suite split, a required negative case, grader calibration, and grew the
  dogfood bank from 2–3 one-shot tasks to an 8–12-task bank at 3 trials each.
  Added the install/update-verification plan as the isolation substrate and
  the home of the model-driven "does init work" task.
- 2026-07-10 — Hardened after two-agent review: false dependency clause on
  matrix CLI-invocation facts dropped (runner verifies invocations itself),
  citation attribution corrected to Böckeler.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice; both that review and an independent
  external one ranked evals top-two.

## Decisions

- 2026-07-11 — Full eval discipline from the start, not a demo: pass-rate
  metrics over isolated multi-trial runs with reference-solution-validated
  graders. A two-task one-shot bank would misrepresent non-deterministic
  behavior as a point result — the exact failure mode Anthropic's guidance
  warns against.
- 2026-07-10 — Measurement before more components: every later addition
  must be provable with this machinery.

## Next action

After plans-machinery and install/update-verification ship: design the
`TASK.md` format (suite/polarity tags, executable checks first, rubric
fallback) and the per-trial isolation + transcript layout, then record the
first reference solution.
