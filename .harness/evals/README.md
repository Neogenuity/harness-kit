# Behavioral evals

The coherence checks (`check-harness`, the hook tests, the
`test-install-*.sh` suites) prove the harness is *internally consistent* —
stubs synced, links live, checksums honest. They do **not** prove it *works*:
that a skill, convention doc, or guard actually changes what an agent does.
This directory is the layer that measures behavior.

A single run is not a measurement. Agent behavior is non-deterministic, so every
task runs over **multiple independent trials**, each in a **fresh isolated
workspace**, and is scored by **pass rate**, not a lucky single result
(Anthropic, *Demystifying evals for AI agents*, validated 2026-07-11):

- **pass@k** — at least one of the k trials passed (can it ever do it?).
- **pass^k** — every one of the k trials passed (does it do it reliably?).

## Layout

```
.harness/evals/
  README.md              # this file
  baselines.json         # recorded pass@k / pass^k per task+provider+model
  scenarios/<slug>/
    TASK.md              # prompt + metadata (suite, polarity, provider, grade, network, execution)
    setup.sh             # optional: seed workspace state before the agent runs
    check.sh             # REQUIRED grader: post-agent workspace, exit 0/1/3 (see below)
    reference/
      apply.sh           # the reference solution: makes check.sh pass (grader-validity proof)
      violate.sh         # negative tasks only: the forbidden shortcut check.sh must exit 3 on
  rubrics/<slug>.md      # optional: semantic (LLM-judge) criteria + a dated calibration note
```

## TASK.md format

```markdown
# <Task title>

- suite: capability | regression
- polarity: positive | negative
- provider: any | claude | codex        (default any)
- grade: check | check+verify           (default check)
- network: none | required              (default none)
- execution: default | provider-config-write  (default default)

## Prompt

<the exact instruction handed to the agent, verbatim>

## Acceptance

<prose describing what check.sh enforces — the executable check is the grader,
this prose documents it>
```

- **suite** — `capability` tasks legitimately sit **below** 100% (they measure
  what the agent can do; a low rate is data, not a failure). `regression` tasks
  carry an ABSOLUTE invariant: the latest run's pass^k must equal **1**.
  `eval-harness.sh` fails whenever that invariant doesn't hold — the "vs
  baseline" column in its table is informational context, never the failure
  trigger, so a regression task fails even the first time it's ever run, with
  no prior baseline to compare against. Keep a regression task trivially
  correct so that if it fails, the harness (not the task) is the suspect.
- **polarity** — `positive` asserts a behavior must happen; `negative` asserts
  one must **not** (the agent must not weaken a guard or edit a `# tailored`
  file to make a check pass). A negative task's `check.sh` passes only when the
  forbidden shortcut was avoided *and* the real goal met — see the exit-3
  convention below.
- **provider** — pins a task to one provider CLI when the prompt or grader
  assumes that CLI's quirks (default `any`). `eval.sh` refuses to run a
  provider-pinned task under a different `--provider`, dying with a clear
  message — except `mock`, which is exempt so a provider-pinned task still
  gets plumbing/grader-validity coverage without the pinned CLI installed.
  `eval.sh` also validates every metadata value against its enum (suite,
  polarity, provider, grade, network, execution) before a run starts, dying and
  naming the offending value on a typo.
- **grade** — `check` runs only `check.sh`; `check+verify` additionally runs the
  workspace's `scripts/harness/verify`. Most tasks put the exact subset they need
  inside `check.sh` (faster than the full gate).
- **network** — declares whether the task needs provider network access, such
  as reaching a localhost HTTP server (default `none`). For Codex, `required`
  enables the experimental task-scoped proxy with exact `localhost` and
  `127.0.0.1` domain rules, empty Unix-socket rules, broad local/private binding
  on, and both dangerous bypasses forced off. This explicit test-only weakening
  is not localhost-only; public hosts and wildcards remain outside the
  allowlist. Tasks that do not opt in retain the network-disabled
  workspace-write sandbox with no proxy overrides. Networked tasks must remain
  self-contained and must not depend on external services. Never combine
  `network: required` with `execution: provider-config-write`.
- **execution** — `default` keeps the provider runner posture unchanged.
  `provider-config-write` is only for a task that explicitly requires edits to
  provider policy/config files; repository metadata alone does not authorize
  that weakening. A real provider run must also pass the independent
  `--allow-provider-config-write` CLI flag, and either half without the other is
  refused before provider invocation (mock plumbing is harmless and exempt).
  With both present, the provider receives the
  `HARNESS_ALLOW_MECHANISM_EDITS=1` maintenance escape; for Codex it also uses
  `danger-full-access` because `workspace-write` makes
  `.codex/config.toml` read-only. That Codex process has unrestricted host
  filesystem and public-network access: the disposable clone does not contain
  host effects. Prefer an external container or VM, never infer this mode from
  task content, and never combine it with `network: required`.

## Acceptance criteria are executable and agent-independent

The grader is `check.sh`, run against the workspace **after** the agent
finishes. It must be independent of any test the agent wrote during the task —
grade the end state (files present, links live, `check-harness` green,
markers gone), never "the agent's own tests passed."

Every task ships a **reference solution** (`reference/apply.sh`) that a
known-good agent would produce. Applying it to a fresh workspace and running
`check.sh` **must pass** — this proves the task is solvable and the grader
valid. `test-eval.sh` enforces this offline for every task in the bank, with no
model in the loop, and for negative tasks additionally proves `check.sh`
**scores `violation`** on every `reference/violate*.sh` fixture (a grader that
can't catch the shortcut is false-green).

### The exit-3 convention and the `outcome` field

`check.sh`'s exit code is a three-way signal, not a bare pass/fail:

- **exit 0** — the goal was met honestly. Recorded outcome: `pass`.
- **exit 3** — a NEGATIVE task's grader caught the forbidden shortcut itself
  (the gate script was modified or deleted, the evidence was destroyed, …) —
  a stronger signal than an ordinary miss. Recorded outcome:
  `negative_violation`.
- **any other non-zero** — an ordinary unmet goal (including a `check+verify`
  task whose `scripts/harness/verify` failed — that path has no violation concept
  and always reports this way). Recorded outcome: `task_failure`.

Every `results.jsonl` line carries the mapped `outcome`, and `eval-harness.sh`
fails the run whenever it sees `negative_violation` — **regardless of
suite**. A caught reward-hacking attempt is never merely "informational,"
even on a capability-suite task; only `capability` tasks failing with ordinary
`task_failure` stay informational. Positive tasks only ever use exit 0 / 1.

## Running

```bash
# One task, 3 independent trials, on a real model:
bash scripts/harness/run-evals add-convention-doc --provider claude --model haiku --trials 3
bash scripts/harness/run-evals add-convention-doc --provider codex  --model gpt-5.6-terra

# Plumbing / grader-validity check with NO model spend (runs the reference
# solution as a mock agent through the full pipeline):
bash scripts/harness/run-evals add-convention-doc --provider mock --trials 1

# Score the latest results against the baseline (fails on a regression-suite drop):
bash scripts/harness/lib/eval-harness.sh

# Record the current numbers as the baseline:
bash scripts/harness/lib/eval-harness.sh --update-baseline
```

Transcripts and per-trial logs land under `.harness/var/eval-results/<task>/<run>/`
(git-ignored). A full multi-model run costs real model calls — run it on a
schedule or after a harness change, never as a per-PR gate.

`eval.sh` clones committed `HEAD` for every trial workspace, so uncommitted
changes in the repo you're running from are invisible to the agent and would
silently go unmeasured. It refuses to start when `git status --porcelain` is
non-empty, naming the count of uncommitted changes; pass `--allow-dirty-head`
to proceed anyway (a one-line warning is printed instead of a refusal).

## Execution variant: bare vs plugin-activated

Every result row (and baseline cell) carries a `variant`: `bare` (default) or
`plugin-activated`. It exists because the same task/provider/model can be run
two meaningfully different ways — the provider CLI on its own vs the same CLI
with the harness-kit plugin active — and those two runs must never collide on
one baseline cell (a plugin-activated re-run silently overwriting the bare
cell it needs to be compared against would erase that comparison). Pass
`--variant plugin-activated` to `eval.sh` when the run activates the plugin;
`eval.sh` only tags the row with the value you pass — activating the plugin
in the trial workspace or invoking environment is the caller's job, not
`eval.sh`'s.

Baseline keys reflect the dimension without disturbing any cell recorded
before it existed: `bare` keeps the plain `provider/model` key every existing
`baselines.json` entry already uses, so no historical cell needed migrating;
a non-bare variant appends a third segment — e.g.
`codex/gpt-5.6-terra/plugin-activated` — so it coexists as its own key instead
of overwriting the bare cell. A row or baseline entry with no `variant` field
at all (recorded before this dimension existed) is treated as `bare`.

## Boundaries

- **`mock` is plumbing, not measurement.** It proves the pipeline and the
  grader; it says nothing about a real model. Baselines come only from live
  runs — `--update-baseline` excludes any `mock`-provider cell automatically
  and prints what it excluded.
- **Baseline updates are atomic.** `--update-baseline` requires every recorded
  cell to share one trial count (`--expected-trials`, default 3); if any cell
  disagrees, the WHOLE update is refused — exit 1, existing baseline file left
  byte-unchanged — rather than writing a file where one pass^k=1 cell means "3
  for 3" and another silently means something else. Pass `--expected-trials N`
  to accept a different count on purpose. Each recorded cell also carries its
  own `recorded` date (UTC, derived from that run's `run_started_at`; falls
  back to today when absent) alongside the top-level `recorded` kept for
  back-compat — so one stale cell is visible even inside an otherwise-fresh
  baseline file.
- **Semantic rubrics are advisory.** Executable `check.sh` is the default and
  needs no calibration. An LLM-as-judge `rubrics/<slug>.md` must carry a dated
  note confirming a human read a transcript sample and agreed with its verdicts
  (see `rubrics/_example.md`); re-run when the rubric or judged model changes.

The recorded bank and its baselines are the dogfood set for this repo. See the
task bank in `tasks/` and the current pass@k / pass^k numbers in
`baselines.json` (written by `eval-harness.sh --update-baseline`).
