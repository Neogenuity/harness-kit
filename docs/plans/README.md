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
promise numbers it can't keep. One exception: a **parallel-track plan with no
mechanism scope** (launch-readiness is the case in point) activates under its
theme name — its items may span several releases or, like an org move or a
visibility flip, no commit at all, so it takes a version only if and when a
single release ships its tracked-file changes.

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

## Roadmap (set 2026-07-10, re-sorted 2026-07-12)

Shipped: **v0.11.0** — hook hardening + feedback repair (probe-confirmed
guard-coverage gaps closed — `harness.conf`, `.claude/settings.local.json`,
the MCP configs — plus a dot-segment path-bypass fix; Cursor feedback arm
repaired to the documented `{}` no-op; advise-once future-proofed with a
scoped marker guard; model-visible `PreToolUse` deny reasons; provider-matrix
refresh; triple-reviewed after implementation — 2× Opus 4.8 + Codex
gpt-5.6-terra, every confirmed finding fixed and fixture-covered)
([completed/v0.11.0-hook-hardening-and-feedback-repair.md](completed/v0.11.0-hook-hardening-and-feedback-repair.md));
**v0.10.0** — execution governance baseline (identity-pinning MCP
trust inventory + check #8c, untrusted-content and risky-actions conventions
docs, a verified execution-containment matrix section, shipped-CI hardening +
doctor #10d, `.github/workflows/*` guard widening; design-reviewed before and
triple-reviewed after implementation)
([completed/v0.10.0-execution-governance-baseline.md](completed/v0.10.0-execution-governance-baseline.md));
**v0.9.0** — eval integrity + plan hygiene (chronological run
selection, atomic baseline updates, `negative_violation` outcomes,
dirty-tree/collision refusals, runner-guard fixtures; CI runs `verify.sh`
directly; the launch and bank-discrimination follow-ups became queued plans)
([completed/v0.9.0-eval-integrity-and-plan-hygiene.md](completed/v0.9.0-eval-integrity-and-plan-hygiene.md));
**v0.8.0** — the behavioral eval layer (golden tasks, multi-trial
pass@k/pass^k runner, recorded baselines — measure the harness itself)
([completed/v0.8.0-behavioral-evals.md](completed/v0.8.0-behavioral-evals.md));
**v0.7.0** — deterministic fixture tests of the `init`/`update`
mechanics (`install-lib.sh` + `test-install.sh`) + two verified integrity fixes
(pinned `harness.conf`, missing-manifest ERROR)
([completed/v0.7.0-install-update-verification.md](completed/v0.7.0-install-update-verification.md));
**v0.6.0** — plans machinery the docs already promised + Copilot/Gemini
rows + strict Agent Skills validation + matrix stamping
([completed/v0.6.0-plans-machinery-and-provider-breadth.md](completed/v0.6.0-plans-machinery-and-provider-breadth.md));
**v0.5.0** — repackage to `plugins/harness-kit/` + Codex plugin distribution
([completed/v0.5.0-repackage-and-codex-distribution.md](completed/v0.5.0-repackage-and-codex-distribution.md)).

**Active (v0.12.0):**
[v0.12.0-eval-discrimination.md](active/v0.12.0-eval-discrimination.md) and
[v0.12.0-context-efficiency.md](active/v0.12.0-context-efficiency.md) — roadmap
#1 and #2 activated together as one coordinated release (a bank that actually
discriminates + the audit-measured context-efficiency fixes). The
usage-before-baseline coupling made a single release the sound choice; the queued
work below is renumbered accordingly.

| # | Plan | Theme |
| --- | --- | --- |
| 1 | [reviewer-loop.md](reviewer-loop.md) | Canonical reviewer persona, findings schema, seeded-defect eval |
| 2 | [runtime-legibility.md](runtime-legibility.md) | The `dev.sh` contract, worktree-safe instances, live verification |
| 3 | [execution-sandbox-profiles.md](execution-sandbox-profiles.md) | Per-provider sandbox/network/approval profiles, optional devcontainer, audit-log export — the advanced half split from the v0.10.0 baseline |
| 4 | [outcome-telemetry-and-doc-gardening.md](outcome-telemetry-and-doc-gardening.md) | Outcome telemetry, audit trends, doc gardening — completes the story for 1.0 |
| 5 | [launch-readiness.md](launch-readiness.md) | Demo recording, org move, public-repo hygiene, security policy, supported-platforms statement, "what 1.0 promises" — parallel-track, start immediately |

**Ordering rationale.** Claim-to-implementation gaps went first — plans
machinery (v0.6.0) closed the space between what the docs promise and what
ships, then install/update-verification (v0.7.0) put the core product boundary
(the `init`/`update` workflow) under an automated deterministic test, the
largest previously unowned reliability gap. With those shipped, measurement
(behavioral evals) came next: it landed before every component that must
prove its value — the reviewer loop is validated by the seeded-defect eval
the evals plan makes possible. Hook-hardening led the 2026-07-12 re-sort and
shipped as v0.11.0: its gaps were probe-confirmed containment failures — one
(`.claude/settings.local.json`, unmanifested and kept out of git in the
standard Claude Code setup) caught by no layer at all — plus feedback
channels provider docs showed dead (Cursor ignores plain-text hook
stdout) or at risk (`stop_hook_active` empirically live but undocumented).
The fix was small, mechanism-only, and consumed by nothing downstream, so it
displaced no dependency chain; the same combined-controls logic that pulled
the v0.10.0 baseline forward applied. Eval-discrimination and context-efficiency
(roadmap #1 and #2) are now **active together as v0.12.0** — eval-discrimination
led because that seeded-defect
eval needs a bank capable of showing a catch-rate below 100% — the v0.8.0
bank saturated at pass^k=1 on 15 of 16 recorded cells, leaving no headroom
to demonstrate the reviewer catching anything. Context-efficiency ships with it
rather than behind it: its trial-confirmed *gaps* have small fixes that displace
nothing downstream (the same logic that let v0.11.0 jump the queue), and the
flip-to-pass and parity cells that prove those fixes consume the discriminating
tasks eval-discrimination adopts — which is why the two share one coordinated
release — while its own first item (usage fields on eval results) is sequenced
early precisely so eval-discrimination's new baseline recordings sit on
usage-carrying rows. Execution governance's *baseline* (guidance docs,
MCP inventory, CI hardening — near-zero tailoring cost) moved ahead of the
reviewer and runtime work per current combined-controls guidance, which treats
containment as non-optional rather than finishing work — it shipped as
v0.10.0; its *advanced*
per-provider sandbox profiles were split into their own queued plan
(execution-sandbox-profiles) that keeps the high tailoring cost arguing for a
later slot and trails runtime-legibility — depending only on that plan's
`dev.sh` boot contract, since runtime-legibility ships no devcontainer of its
own.
Outcome telemetry is last among the mechanism plans because outcome metrics
are only worth collecting once gates, reviews, and evals emit outcomes worth
measuring. Launch-readiness sits last in table order but parallel-tracks
starting immediately (re-prioritized 2026-07-12, superseding its earlier
"after reviewer-loop" sequencing) — it touches no mechanism, and v0.10.0 is
already a credible launch baseline; see that plan's Decisions log.

The 2026-07-11 re-sort (new verification plan; governance baseline pulled
forward) followed a standards-coverage audit against current Anthropic and
OpenAI practice — see each plan's Progress log. A follow-up review the same day
added two *verified* self-protection findings (an unpinned `harness.conf`, a
silently-skipped missing manifest); both were reproduced in-repo and folded
into the already-#1 verification plan without changing the order. The
2026-07-11 project review (adversarially checked by a second model) added the
v0.9.0 integrity plan (active) and two queued plans (eval-discrimination,
launch-readiness). The 2026-07-12 project review — an independent
re-verification of the provider matrix against live provider docs, payload
probes of the installed guards, and a captured live Stop payload from Claude
Code CLI 2.1.207 — added
[hook-hardening-and-feedback-repair.md](completed/v0.11.0-hook-hardening-and-feedback-repair.md)
at #1, re-prioritized launch-readiness to parallel-track immediately (adding
security-policy and supported-platforms items to its scope), and added the
per-cell baseline-date backfill to eval-discrimination. A separate 2026-07-12
context-efficiency audit — 72 controlled trials over the installed harness
and plugin (minimal-baseline vs installed vs plugin-activated vs
reduced-context configurations, claude-haiku + codex gpt-5.6-terra, exact
provider-reported usage per trial) — added
[context-efficiency.md](active/v0.12.0-context-efficiency.md) at #2 and left
eval-discrimination two validated donor tasks with recorded
discrimination-headroom cells (see both plans' Progress logs).

Re-sorting is expected. Every harness component encodes an assumption about
what models can't do on their own, and those assumptions get stress-tested
on each model or provider shift — remove pieces that are no longer
load-bearing (<https://www.anthropic.com/engineering/harness-design-long-running-apps>,
validated 2026-07-10).

Each release cuts via [docs/skills/release/SKILL.md](../skills/release/SKILL.md).
