# Execution Plans

Long-horizon work needs state that survives context windows: what is being
built, how far it got, what was decided, and what "done" means.
`scripts/harness/hooks/session-context.sh` announces every plan in `active/` at
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

## Roadmap (set 2026-07-10; restructure track added 2026-07-22)

Shipped: **v0.21.0** (2026-07-22) — declarative kit-manifest ship contract +
retired-file mechanism, Phase 1 of the
[standard-consumer-layout](standard-consumer-layout.md) umbrella plan, which
now owns the mechanism queue (Phases 2–6: adopter test descope,
`scripts/harness/` command surface, content/IA migration, single provider
declaration + generated adapters, launch acceptance) and gates the
launch-readiness public flip
([completed/v0.21.0-ship-manifest-and-retirement.md](completed/v0.21.0-ship-manifest-and-retirement.md));
**v0.19.0/v0.20.x** (2026-07-17/18) — Claude execution-profile
retry retention; the install-suite split (231s→46s) with root-only
provider-template validation; the SIGPIPE phantom-failure fixes swept through
checker and suites (see CHANGELOG.md); **v0.18.0** — fixture isolation: the shipped regression tests could run
their `git init`/`add`/`commit` in the **host repository** when `mktemp` failed,
because `cd ""` is a silent rc=0 no-op that defeats the `|| exit 1` guard that
looks like it catches it. Found by a launch-readiness review whose own
`verify.sh` runs reproduced it live on this repo's `main` — twice — which is why
the mechanism is pinned rather than theorized. 52 allocation sites guarded, every
consumption site `${VAR:?}`-hardened, the shipped `fixture-recipe.md` stopped
teaching the anti-pattern, three suites capped with `GIT_CEILING_DIRECTORIES`
(one had been passing vacuously), plus check #5b and a behavioral
`test-fixture-isolation.sh` verified to fail on v0.17.0 and pass here. The class
was invisible to both CI (hosted runners have a writable temp dir, so it never
fires there) and shellcheck (the variables are correctly quoted — that is what
makes `cd ""` well-formed)
([completed/v0.18.0-fixture-isolation.md](completed/v0.18.0-fixture-isolation.md));
**v0.17.0** — backward-compatible local outcome telemetry, fail-open
serial/parallel verification-gate events, deterministic mixed-log and eval
reduction, exact local session-trailer joins with honest lifecycle/PR N/A
states, plus the offline read-only doc-garden scanner and canonical skill.
Mechanism/content implementation was delegated to Terra/Luna, reciprocally
reviewed, dogfooded, and closed by a canonical reviewer with four confirmed
findings fixed and mutation-checked
([completed/v0.17.0-outcome-telemetry-and-doc-gardening.md](completed/v0.17.0-outcome-telemetry-and-doc-gardening.md));
**v0.16.0** — declared execution profiles (explicit per-provider
adoption for Claude Code, Cursor, Codex, and OpenCode; semantic drift checks;
an honestly labeled Codex local/private-network compatibility weakening;
authored devcontainer and provider-observability contracts; guarded
provider-config-write eval execution; and a Codex gpt-5.6-luna **2/3** adoption
baseline. Mechanism/content implementation was delegated to Terra/Luna,
reciprocally reviewed, and closed by an independent pre-commit review)
([completed/v0.16.0-execution-sandbox-profiles.md](completed/v0.16.0-execution-sandbox-profiles.md));
**v0.15.0** — runtime legibility (a universal worktree identity/port
helper; conditional, pinned `dev.sh up|health|seed|down` app contract; a
self-contained `verify-live` skill; surface-aware optional browser guidance;
app-aware init/update/audit adoption; a two-worktree HTTP fixture; and a Codex
gpt-5.6-luna **3/3** live-runtime eval. Mechanism/content implementation was
delegated to Terra/Luna workstreams and cross-reviewed in both directions)
([completed/v0.15.0-runtime-legibility.md](completed/v0.15.0-runtime-legibility.md));
**v0.14.0** — provider wiring assurance (the harness now *verifies* the
wiring it documents: a new `check-harness.sh` tuple check turns a hooks-deleted
`.claude/settings.json` from a false "coherent" into a specific per-guard
failure; agent stubs join skill stubs as generated-and-checked from canonical
frontmatter; the OpenCode/Cursor shim descoped with a dated rationale; init/update
gain a `jq` preflight and tested old-template recovery; a bare-vs-plugin-activated
eval baseline dimension, with the paid recordings deferred. Execution plan
reviewed by Codex gpt-5.6-sol — 6 findings folded pre-build; integrated diff by
gpt-5.6-terra; built in parallel Opus 4.8 + Sonnet 5 worktrees)
([completed/v0.14.0-provider-wiring-assurance.md](completed/v0.14.0-provider-wiring-assurance.md));
**v0.13.0** — reviewer loop + skill split (the canonical `code-reviewer`
persona with a v1-compatible findings schema and a seeded-defect catch-rate eval
recorded at claude/sonnet 5/5; the plugin `SKILL.md` split from a ~5.2k-token
monolith into a ~781-token router + per-mode `references/modes/`, shipped only
after a paired monolith-vs-split parity run held correctness 3/3=3/3 and
wall-clock no-worse; launch-readiness doc items — SECURITY.md, "what 1.0
promises", supported-platforms. Plan reviewed by Codex gpt-5.6-sol;
implementation by Opus 4.8 subagents, diff-reviewed by Codex gpt-5.6-terra)
([completed/v0.13.0-reviewer-loop.md](completed/v0.13.0-reviewer-loop.md),
[completed/v0.13.0-skill-split.md](completed/v0.13.0-skill-split.md));
**v0.12.0** — eval discrimination + context efficiency (roadmap #1+#2
as one coordinated release: the first four-model baseline matrix — Claude
haiku+sonnet, Codex gpt-5.6-terra+gpt-5.6-luna, 40 cells, per-cell dated,
spanning a cheap and a capable tier on both providers — two discriminating tasks
adopted, per-trial usage instrumentation, an opt-in scheduled eval cron, and
five context-efficiency audit fixes; the plugin skill-split deferred to a queued
plan behind a paired-parity gate)
([completed/v0.12.0-eval-discrimination.md](completed/v0.12.0-eval-discrimination.md),
[completed/v0.12.0-context-efficiency.md](completed/v0.12.0-context-efficiency.md));
**v0.11.0** — hook hardening + feedback repair (probe-confirmed
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

**Active:** [Launch readiness](active/launch-readiness.md) remains the parallel
maintainer track; its demo, org move, and public flip are still open.

The mechanism queue is empty after v0.18.0. New work enters as a
theme-named queued plan and takes a version only when activated. v0.18.0 was
unqueued and unplanned — it jumped straight to active because it was the one
defect class where the kit violated its own core promise (never damage the repo
it protects), it was reproduced on `main` rather than argued for, and its scope
was mechanism-only, displacing no dependency chain — the same profile that let
v0.11.0 jump the queue.

**Ordering rationale.** Claim-to-implementation gaps went first — plans
machinery (v0.6.0) closed the space between what the docs promise and what
ships, then install/update-verification (v0.7.0) put the core product boundary
(the `init`/`update` workflow) under an automated deterministic test, the
largest previously unowned reliability gap. The 2026-07-13 re-sort applies the
same logic: provider-wiring-assurance jumped to the head of the queue (now
active as v0.14.0) because
a post-v0.13.0 cross-review reproduced a claim-to-implementation gap in the
wiring itself — `check-harness.sh` reports a coherent harness with every
Claude Code hook deleted from `.claude/settings.json` — and its scope is
mostly mechanism checks that displace no dependency chain, the same profile
that let v0.11.0 jump the queue. With those shipped, measurement
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
per-provider sandbox profiles were split into their own plan and shipped as
[v0.16.0](completed/v0.16.0-execution-sandbox-profiles.md). Its high tailoring
cost kept it behind runtime-legibility, and it depends only on that plan's
`dev.sh` boot contract because runtime-legibility ships no devcontainer of its
own.
Outcome telemetry was last among the mechanism plans and shipped as v0.17.0
because outcome metrics are only worth collecting once gates, reviews, and
evals emit outcomes worth measuring. Launch-readiness parallel-tracks
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
[context-efficiency.md](completed/v0.12.0-context-efficiency.md) at #2 and left
eval-discrimination two validated donor tasks with recorded
discrimination-headroom cells (see both plans' Progress logs).

Re-sorting is expected. Every harness component encodes an assumption about
what models can't do on their own, and those assumptions get stress-tested
on each model or provider shift — remove pieces that are no longer
load-bearing (<https://www.anthropic.com/engineering/harness-design-long-running-apps>,
validated 2026-07-10).

Each release cuts via [.agents/skills/release/SKILL.md](../../.agents/skills/release/SKILL.md).
