# Execution Plans

Long-horizon work needs state that survives context windows: what is being
built, how far it got, what was decided, and what "done" means.
`scripts/hooks/session-context.sh` announces every plan in `active/` at
session start, so a fresh session — or a subagent in a worktree — starts
oriented instead of re-deriving context.

In-repo plans with progress and decision logs are converged cross-vendor
practice (validated 2026-07-10): OpenAI's harness-engineering write-up
versions active plans, completed plans, and known debt inside the repo
(<https://openai.com/index/harness-engineering/>), and Anthropic's
long-running-agent guidance reaches the same conclusion — compaction alone
is insufficient; persistent progress artifacts and structured handoffs are
required
(<https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents>).

## Lifecycle

- `docs/plans/*.md` — **queued**: scoped and prioritized, not started.
- `docs/plans/active/` — **in execution**: announced every session start.
  Keep this to the one or two plans actually being worked.
- `docs/plans/completed/` — **shipped**: moved here (create the directory on
  first use) once the release is tagged and Verification is filled in with
  real evidence.

Move plans between states with `git mv` — never copy.

**Naming**: the active plan carries its release version (its scope pins that
version everywhere from `plugin.json` to the manifest header). Queued plans
are named by **theme** — versions are assigned when a plan moves to
`active/`, because the release skill assigns semver by what actually shipped
and interstitial releases happen (0.4.0 was one). A public roadmap shouldn't
promise numbers it can't keep.

## Plan format

Every plan carries these sections; a resuming session must be able to
continue from the file alone:

| Section | Answers |
| --- | --- |
| Objective | The outcome, in one paragraph |
| Value | Why this, why now, why in this order |
| Scope | Deliverables as a checklist, each with an acceptance criterion |
| Out of scope | What is deliberately deferred, so it isn't relitigated |
| Dependencies | What must exist or merge first |
| Verification | The evidence that will prove completion (commands, evals) |
| Progress | Dated running log, newest first |
| Decisions | Dated choices and their why |
| Next action | The single next step a resuming session takes |

Repo references that must stay honest belong in markdown links (the CI link
check walks every doc under `docs/`); prose and backtick mentions of
not-yet-existing paths are legal — queued plans name future files by design.

## Roadmap (set 2026-07-10)

| # | Plan | Theme |
| --- | --- | --- |
| 1 | [active/v0.5.0-repackage-and-codex-distribution.md](active/v0.5.0-repackage-and-codex-distribution.md) | Repackage to `plugins/harness-kit/`; Codex plugin distribution (next up) |
| 2 | [plans-machinery-and-provider-breadth.md](plans-machinery-and-provider-breadth.md) | Ship the plans machinery the docs already promise; Copilot + Gemini CLI rows |
| 3 | [behavioral-evals.md](behavioral-evals.md) | Golden tasks, eval runner, baselines — measure the harness itself |
| 4 | [reviewer-loop.md](reviewer-loop.md) | Canonical reviewer persona, findings schema, seeded-defect eval |
| 5 | [runtime-legibility.md](runtime-legibility.md) | The `dev.sh` contract, worktree-safe instances, live verification |
| 6 | [execution-governance.md](execution-governance.md) | Sandbox/network/approval profiles, MCP trust inventory |
| 7 | [outcome-telemetry-and-doc-gardening.md](outcome-telemetry-and-doc-gardening.md) | Outcome telemetry, audit trends, doc gardening — completes the story for 1.0 |

**Ordering rationale.** Scoped-and-locked work and claim-to-implementation
gaps go first (the repackage, then plans machinery): cheapest, and they
close the space between what the docs promise and what ships. Measurement
(behavioral evals) lands before every component that must prove its value —
the reviewer loop is validated by the seeded-defect eval the evals plan
makes possible. Runtime legibility and execution governance carry the
highest per-project tailoring cost, so they come after the cheap wins.
Outcome telemetry is last because outcome metrics are only worth collecting
once gates, reviews, and evals emit outcomes worth measuring.

Re-sorting is expected. Every harness component encodes an assumption about
what models can't do on their own, and those assumptions get stress-tested
on each model or provider shift — remove pieces that are no longer
load-bearing (<https://www.anthropic.com/engineering/harness-design-long-running-apps>,
validated 2026-07-10).

Each release cuts via [docs/skills/release/SKILL.md](../skills/release/SKILL.md).
