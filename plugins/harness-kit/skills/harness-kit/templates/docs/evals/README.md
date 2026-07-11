# Behavioral evals

The harness coherence checks (`check-harness.sh`, the hook tests) prove the
harness is *internally consistent*. They do not prove it *works* — that a skill,
convention doc, or guard actually changes what an agent does. This directory is
where you measure behavior.

A single run is not a measurement. Agent behavior is non-deterministic, so every
task runs over **multiple independent trials**, each in a **fresh isolated
workspace**, scored by **pass rate**:

- **pass@k** — at least one of k trials passed (can it ever do it?).
- **pass^k** — every one of k trials passed (does it do it reliably?).

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
      apply.sh           # reference solution: makes check.sh pass (grader-validity proof)
      violate.sh         # negative tasks only: the forbidden shortcut check.sh must FAIL
  rubrics/<slug>.md      # optional: semantic (LLM-judge) criteria + a dated calibration note
```

Copy `tasks/_template/` to `tasks/<your-slug>/` and fill it in. Pick 1–3 tasks
that capture what "the agent did the job right" means *in this repo* — the
recurring changes your reviewers care about most.

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

<prose documenting what check.sh enforces>
```

- **suite** — `capability` tasks legitimately sit **below** 100% (a low rate is
  data, not a failure). `regression` tasks are expected at/near **100%**; a drop
  is a real regression and `eval-harness.sh` exits non-zero on it. Keep a
  regression task trivially correct, so a failure implicates the harness, not
  the task.
- **polarity** — `positive` asserts a behavior must happen; `negative` asserts
  one must **not** (e.g. the agent must not weaken a guard or edit a
  `# tailored` file to make a check pass). A negative `check.sh` passes only when
  the shortcut was avoided *and* the goal met.
- **grade** — `check` runs only `check.sh`; `check+verify` also runs the
  workspace's `scripts/verify.sh`.

## Graders are executable and agent-independent

The grader is `check.sh`, run against the workspace after the agent finishes. It
must grade the end state (files present, links live, markers gone), never "the
agent's own tests passed." Every task ships a reference solution
(`reference/apply.sh`); applying it to a fresh workspace and running `check.sh`
**must pass** — proof the task is solvable and the grader valid. `test-eval.sh`
enforces this offline for every task, and additionally proves each negative
task's `reference/violate.sh` **fails** the grader.

## Running

```bash
bash scripts/eval.sh <slug> --provider claude --model <m> --trials 3   # live
bash scripts/eval.sh <slug> --provider mock  --trials 1                # plumbing (no model)
bash scripts/eval-harness.sh                    # score latest vs baseline (fails on regression drop)
bash scripts/eval-harness.sh --update-baseline  # record current numbers
```

Transcripts land under `.harness/eval-results/` (git-ignored). A full run costs
real model calls — schedule it or run after a harness change, never per-PR.
`mock` proves the pipeline and the grader; it is not a measurement of any model.

Semantic `rubrics/<slug>.md` (LLM-as-judge) are advisory and must carry a dated
calibration note (see `rubrics/_example.md`); executable `check.sh` is the
default and needs none.
