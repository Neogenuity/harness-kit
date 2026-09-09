# Behavioral evals

The harness coherence checks (`check-harness`, the hook tests) prove the
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
.harness/evals/
  README.md              # this file
  baselines.json         # recorded pass@k / pass^k per task+provider+model
  scenarios/<slug>/
    TASK.md              # prompt + metadata (suite, polarity, provider, grade, network, execution)
    setup.sh             # optional: seed workspace state before the agent runs
    check.sh             # REQUIRED grader: post-agent workspace, exit 0/1/3 (see below)
    reference/
      apply.sh           # reference solution: makes check.sh pass (grader-validity proof)
      violate.sh         # negative tasks only: the forbidden shortcut check.sh must exit 3 on
      precheck.sh        # optional: host prerequisites; exit 1 SKIPs this task's validity check
  rubrics/<slug>.md      # optional: semantic (LLM-judge) criteria + a dated calibration note
```

Copy `scenarios/_template/` to `scenarios/<your-slug>/` and fill it in. Pick 1–3 tasks
that capture what "the agent did the job right" means *in this repo* — the
recurring changes your reviewers care about most.

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

<prose documenting what check.sh enforces>
```

- **suite** — `capability` tasks legitimately sit **below** 100% (a low rate is
  data, not a failure). `regression` tasks carry an ABSOLUTE invariant: latest
  pass^k must equal **1** — `eval-harness.sh` fails whenever that's not true,
  independent of any baseline comparison (the table's "vs baseline" column is
  informational only). Keep a regression task trivially correct, so a failure
  implicates the harness, not the task.
- **polarity** — `positive` asserts a behavior must happen; `negative` asserts
  one must **not** (e.g. the agent must not weaken a guard or edit a
  `# tailored` file to make a check pass). A negative `check.sh` passes only when
  the shortcut was avoided *and* the goal met — see the exit-3 convention below.
- **provider** — pins a task to one provider CLI (default `any`); `eval.sh`
  refuses to run a pinned task under a different `--provider` (mock is
  exempt). All six metadata fields are validated against their enum before a
  run starts; a typo dies loudly instead of silently changing scoring.
- **grade** — `check` runs only `check.sh`; `check+verify` also runs the
  workspace's `scripts/harness/verify`. If a `check+verify` task's workspace has
  no `scripts/harness/verify`, that is a **grader error** that aborts the run —
  not a skip and never a pass. The task declared that `check.sh` alone does not
  score it, so grading on `check.sh` alone would record a false success for
  exactly the trial that deleted or renamed the gate it was meant to satisfy.
- **network** — declares whether a task needs to reach a localhost service
  (default `none`). For Codex, `required` enables the experimental task-scoped
  proxy with exact `localhost` and `127.0.0.1` domain rules, empty Unix-socket
  rules, broad local/private binding on, and both dangerous bypasses forced
  off. This explicit test-only weakening is not localhost-only; public hosts
  and wildcards remain outside the allowlist. Tasks that do not opt in keep
  command network access disabled and receive no proxy overrides. Never combine
  `network: required` with `execution: provider-config-write`.
- **execution** — `default` keeps the provider runner posture unchanged.
  `provider-config-write` is only for a task that explicitly requires edits to
  provider policy/config files; metadata declares eligibility but does not
  authorize the weakening. Every non-mock run also requires the explicit
  `--allow-provider-config-write` CLI flag. The runner then sets
  `HARNESS_ALLOW_MECHANISM_EDITS=1`; for Codex it uses `danger-full-access`
  because `workspace-write` makes `.codex/config.toml` read-only. That grants
  unrestricted host filesystem access and public network access: the
  disposable trial clone does not contain effects elsewhere on the host.
  Prefer an external container or VM for real runs. Mock validation is harmless
  and exempt from the extra flag. Never infer this mode from task content,
  describe it as workspace-only containment, or combine it with
  `network: required`.

## Graders are executable and agent-independent

The grader is `check.sh`, run against the workspace after the agent finishes. It
must grade the end state (files present, links live, markers gone), never "the
agent's own tests passed." Every task ships a reference solution
(`reference/apply.sh`); applying it to a fresh workspace and running `check.sh`
**must pass** — proof the task is solvable and the grader valid.
`scripts/harness/tests/test-eval-graders.sh` enforces this offline for every task
in the bank, and additionally proves each negative task's
`reference/violate*.sh` **scores `violation`** and each `reference/wrongplace*.sh`
is rejected. It runs in the shipped floor (the `harness-test` gate), and no-ops
when the bank is empty — so the cost appears only once this repo authors tasks.

A task whose reference solution needs more of the host than a POSIX shell and
git — a live dev server, a language runtime, a bindable port — declares that in
an optional **`reference/precheck.sh`**:

- **exit 0** — this host can run the task; the full validity check proceeds.
- **exit 1** — it cannot; print a one-line reason on stdout and the task's
  validity check is **skipped**, counted and named, rather than failed.
- **any other status** — the precheck itself is broken (a shell syntax error,
  a missing interpreter), and that is reported as a FAILURE. This narrows the
  hole rather than closing it: plenty of ordinary failures exit 1 by accident,
  so write the probe so its own breakage is distinguishable from a real
  decline — catch the specific error that means "unavailable" and let anything
  else fall through to a non-1 status.

Keep the prerequisite in the task, not in the runner: the task knows whether it
needs Python, Node, or a database; the shipped floor must not. The probe is not
a second grader — a host that passes it still runs the full
reference-scores-pass check.

`check.sh`'s exit code is a three-way convention: **0** = pass; **3** = a
negative task's grader caught the forbidden shortcut itself (recorded outcome
`negative_violation` — stronger than an ordinary miss); any other non-zero =
an ordinary unmet goal (`task_failure`). `eval-harness.sh` fails the run on
any `negative_violation`, regardless of suite.

## Running

```bash
bash scripts/harness/run-evals <slug> --provider claude --model <m> --trials 3   # live
bash scripts/harness/run-evals <slug> --provider mock  --trials 1                # plumbing (no model)
bash scripts/harness/lib/eval-harness.sh                    # score latest vs baseline (fails on a regression/violation)
bash scripts/harness/lib/eval-harness.sh --update-baseline  # record current numbers
bash scripts/harness/eval-author new <slug>                 # excluded _draft- scaffold
bash scripts/harness/eval-author finalize <slug>            # validate grader/reference, then activate
bash scripts/harness/observe import --provider claude --transcript <path> [--diff <path>]
```

Transcripts land under `.harness/var/eval-results/` (git-ignored). A full run costs
real model calls — schedule it or run after a harness change, never per-PR.
`mock` proves the pipeline and the grader; it is not a measurement of any model.

Claude and Codex trials also produce `trace.jsonl`, a versioned provider-neutral
projection of file, command, and tool events, plus a `trajectory` object on the
result row. The deterministic fields flag instruction discovery order, test and
verification execution, failed-command recovery, repeated reads/commands, and
modified files. They are observational evidence only: `eval-harness.sh` does
not use traces or trajectory metrics to decide task outcomes, regression state,
or baselines. Instruction-discovery fields are positive-evidence metrics: they
are nullable when the trace has no direct successful instruction-read event,
because shell or provider-internal reads may be unobservable. Unknown is never
scored as failure. Raw transcripts and normalized traces remain local under
`.harness/var/` and may contain repository paths or command text.

`eval-author` always creates an underscore-prefixed draft from the shipped
mechanism template and marks it `.harness-eval-draft`. The runner rejects both
underscore names and marker-bearing directories, even when named explicitly.
After replacing every `HARNESS_EVAL_TODO`, use `eval-author finalize <slug>`:
it activates the task only after the reference solution passes the independent
grader-validity suite. `observe feedback` records a local good/bad label, and
`observe promote <run-id> <slug>` attaches path-redacted trajectory metrics to
a new draft. Raw transcript text, run identity, and modified-file paths stay
under `.harness/var/`. Use `observe show <run-id>` before promotion.

`observe import --diff <path>` optionally records the run's **outcome diff**.
The file is copied verbatim to `<run>/diff.patch` beside the transcript, and the
run metadata (now `version: 2`) gains `diff_present`, `diff_files_changed`, and
`diff_files_changed_source`. The source names how the count was reached, because
the diff shapes are not interchangeable: `git-diff-headers` counts `diff --git`
lines, and `unified-target-headers` is the fallback `+++` count for a plain
`diff -u` — approximate, since added content beginning `++ ` inflates it. A file
carrying neither header shape — an empty diff, or operator-supplied prose — is
still accepted and recorded as present with zero files, labelled
`no-recognized-headers` so the record never names a counting method that did not
apply. An unreadable `--diff` path, a directory, or an empty value all fail
before any run directory is staged. `observe show` reports the same three facts
as a top-level `diff` block, and reports a pre-`version: 2` run as absent and
uncounted. Like the transcript, the diff is raw local evidence that can carry
secrets and private paths, so `promote` never copies it into a draft scenario —
drafts get committed. `--diff` is accepted by `import` alone.

A ready-made **opt-in scheduled workflow** ships with the kit and installs as
`.github/workflows/eval-cron.yml`: a weekly cron plus a manual dispatch that
DEFAULTS to the free `mock` provider, scoring-only
(it never runs `--update-baseline`), with transcripts uploaded as an artifact.
Wire your provider CLI + credential secret and scope the matrix before enabling
live runs — the header comment walks through it.

`eval.sh` clones committed HEAD per trial, so it refuses to run against a dirty
tree (uncommitted changes would go unmeasured) unless you pass
`--allow-dirty-head`.

`--update-baseline` excludes `mock`-provider cells, refuses the whole update
atomically if any cell's trial count differs from `--expected-trials` (default
3), and records a per-cell `recorded` date (derived from that run's
timestamp) alongside the top-level date.

Semantic `rubrics/<slug>.md` (LLM-as-judge) are advisory and must carry a dated
calibration note (see `rubrics/_example.md`); executable `check.sh` is the
default and needs none.
