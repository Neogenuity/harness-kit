# Behavioral evals

The coherence checks (`check-harness.sh`, the hook tests, `test-install.sh`)
prove the harness is *internally consistent* — stubs synced, links live,
checksums honest. They do **not** prove it *works*: that a skill, convention
doc, or guard actually changes what an agent does. This directory is the layer
that measures behavior.

A single run is not a measurement. Agent behavior is non-deterministic, so every
task runs over **multiple independent trials**, each in a **fresh isolated
workspace**, and is scored by **pass rate**, not a lucky single result
(Anthropic, *Demystifying evals for AI agents*, validated 2026-07-11):

- **pass@k** — at least one of the k trials passed (can it ever do it?).
- **pass^k** — every one of the k trials passed (does it do it reliably?).

## Layout

```
docs/evals/
  README.md              # this file
  baselines.json         # recorded pass@k / pass^k per task+provider+model
  tasks/<slug>/
    TASK.md              # prompt + metadata (suite, polarity, provider, grade)
    setup.sh             # optional: seed workspace state before the agent runs
    check.sh             # REQUIRED grader: run in the post-agent workspace, exit 0 = pass
    reference/
      apply.sh           # the reference solution: makes check.sh pass (grader-validity proof)
      violate.sh         # negative tasks only: the forbidden shortcut, which check.sh must FAIL
  rubrics/<slug>.md      # optional: semantic (LLM-judge) criteria + a dated calibration note
```

## TASK.md format

```markdown
# <Task title>

- suite: capability | regression
- polarity: positive | negative
- provider: any | claude | codex        (default any)
- grade: check | check+verify           (default check)

## Prompt

<the exact instruction handed to the agent, verbatim>

## Acceptance

<prose describing what check.sh enforces — the executable check is the grader,
this prose documents it>
```

- **suite** — `capability` tasks legitimately sit **below** 100% (they measure
  what the agent can do; a low rate is data, not a failure). `regression` tasks
  are expected at/near **100%** — a drop is a real regression and
  `eval-harness.sh` exits non-zero on it. Keep a regression task trivially
  correct so that if it fails, the harness (not the task) is the suspect.
- **polarity** — `positive` asserts a behavior must happen; `negative` asserts
  one must **not** (the agent must not weaken a guard or edit a `# tailored`
  file to make a check pass). A negative task's `check.sh` passes only when the
  forbidden shortcut was avoided *and* the real goal met.
- **grade** — `check` runs only `check.sh`; `check+verify` additionally runs the
  workspace's `scripts/verify.sh`. Most tasks put the exact subset they need
  inside `check.sh` (faster than the full gate).

## Acceptance criteria are executable and agent-independent

The grader is `check.sh`, run against the workspace **after** the agent
finishes. It must be independent of any test the agent wrote during the task —
grade the end state (files present, links live, `check-harness.sh` green,
markers gone), never "the agent's own tests passed."

Every task ships a **reference solution** (`reference/apply.sh`) that a
known-good agent would produce. Applying it to a fresh workspace and running
`check.sh` **must pass** — this proves the task is solvable and the grader
valid. `test-eval.sh` enforces this offline for every task in the bank, with no
model in the loop, and for negative tasks additionally proves `check.sh` **fails**
on `reference/violate.sh` (a grader that can't catch the shortcut is false-green).

## Running

```bash
# One task, 3 independent trials, on a real model:
bash scripts/eval.sh add-convention-doc --provider claude --model haiku --trials 3
bash scripts/eval.sh add-convention-doc --provider codex  --model gpt-5.6-terra

# Plumbing / grader-validity check with NO model spend (runs the reference
# solution as a mock agent through the full pipeline):
bash scripts/eval.sh add-convention-doc --provider mock --trials 1

# Score the latest results against the baseline (fails on a regression-suite drop):
bash scripts/eval-harness.sh

# Record the current numbers as the baseline:
bash scripts/eval-harness.sh --update-baseline
```

Transcripts and per-trial logs land under `.harness/eval-results/<task>/<run>/`
(git-ignored). A full multi-model run costs real model calls — run it on a
schedule or after a harness change, never as a per-PR gate.

## Boundaries

- **`mock` is plumbing, not measurement.** It proves the pipeline and the
  grader; it says nothing about a real model. Baselines come only from live runs.
- **Semantic rubrics are advisory.** Executable `check.sh` is the default and
  needs no calibration. An LLM-as-judge `rubrics/<slug>.md` must carry a dated
  note confirming a human read a transcript sample and agreed with its verdicts
  (see `rubrics/_example.md`); re-run when the rubric or judged model changes.

The recorded bank and its baselines are the dogfood set for this repo. See the
task bank in `tasks/` and the current pass@k / pass^k numbers in
`baselines.json` (written by `eval-harness.sh --update-baseline`).
