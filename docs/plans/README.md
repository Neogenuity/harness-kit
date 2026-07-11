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

## Roadmap (set 2026-07-10, re-sorted 2026-07-11)

Shipped: **v0.6.0** — plans machinery the docs already promised + Copilot/Gemini
rows + strict Agent Skills validation + matrix stamping
([completed/v0.6.0-plans-machinery-and-provider-breadth.md](completed/v0.6.0-plans-machinery-and-provider-breadth.md));
**v0.5.0** — repackage to `plugins/harness-kit/` + Codex plugin distribution
([completed/v0.5.0-repackage-and-codex-distribution.md](completed/v0.5.0-repackage-and-codex-distribution.md)).

| # | Plan | Theme |
| --- | --- | --- |
| 1 | [install-update-verification.md](install-update-verification.md) | Deterministic fixture tests of `init`/`audit`/`update` — prove the core product boundary; + close two verified integrity blind spots (unpinned `harness.conf`, silently-skipped missing manifest) |
| 2 | [behavioral-evals.md](behavioral-evals.md) | Golden tasks, multi-trial pass@k/pass^k runner, baselines — measure the harness itself |
| 3 | [execution-governance.md](execution-governance.md) | Baseline: MCP trust inventory, untrusted-repo/prompt-injection guidance, CI hardening (advanced sandbox profiles trail #5) |
| 4 | [reviewer-loop.md](reviewer-loop.md) | Canonical reviewer persona, findings schema, seeded-defect eval |
| 5 | [runtime-legibility.md](runtime-legibility.md) | The `dev.sh` contract, worktree-safe instances, live verification |
| 6 | [outcome-telemetry-and-doc-gardening.md](outcome-telemetry-and-doc-gardening.md) | Outcome telemetry, audit trends, doc gardening — completes the story for 1.0 |

**Ordering rationale.** Claim-to-implementation gaps go first — plans
machinery closes the space between what the docs promise and what ships, then
install/update-verification puts the core product boundary (the `init`/`update`
workflow) under an automated deterministic test, the largest previously
unowned reliability gap. Measurement (behavioral evals) lands before every
component that must prove its value — the reviewer loop is validated by the
seeded-defect eval the evals plan makes possible. Execution governance's
*baseline* (guidance docs, MCP inventory, CI hardening — near-zero tailoring
cost) moves ahead of the reviewer and runtime work per current
combined-controls guidance, which treats containment as non-optional rather
than finishing work; its *advanced* per-provider sandbox profiles keep the
high tailoring cost that argues for a later slot and trail runtime-legibility
(shared `.devcontainer/` surface). Outcome telemetry is last because outcome
metrics are only worth collecting once gates, reviews, and evals emit
outcomes worth measuring.

The 2026-07-11 re-sort (new verification plan; governance baseline pulled
forward) followed a standards-coverage audit against current Anthropic and
OpenAI practice — see each plan's Progress log. A follow-up review the same day
added two *verified* self-protection findings (an unpinned `harness.conf`, a
silently-skipped missing manifest); both were reproduced in-repo and folded
into the already-#1 verification plan without changing the order.

Re-sorting is expected. Every harness component encodes an assumption about
what models can't do on their own, and those assumptions get stress-tested
on each model or provider shift — remove pieces that are no longer
load-bearing (<https://www.anthropic.com/engineering/harness-design-long-running-apps>,
validated 2026-07-10).

Each release cuts via [docs/skills/release/SKILL.md](../skills/release/SKILL.md).
