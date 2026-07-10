# Reviewer/evaluator loop

Status: queued

## Objective

Ship an optional, canonical reviewer persona with a fixed findings schema —
the inferential half of the feedback system, running after the
deterministic gates pass.

## Value

The kit's feedback today is computational (lint, tests, drift checks).
Current practice pairs that with inferential review, and separating the
judge from the doer is the strongest documented lever: Anthropic reports
external evaluators catching what generators confidently miss
(<https://www.anthropic.com/engineering/harness-design-long-running-apps>,
validated 2026-07-10); Böckeler's taxonomy makes feedforward/feedback ×
computational/inferential the core grid (martinfowler.com, 2026-04,
validated 2026-07-10). The kit supports personas but leaves review entirely
bespoke — the usual first persona ("code-reviewer", per SKILL.md) should
ship, not be homework.

## Scope

1. **Canonical persona**: `templates/docs/agents/code-reviewer.md` — runs
   only after `verify.sh` passes (never duplicates deterministic findings);
   checks the four failure classes deterministic gates can't see:
   misunderstood scope, unnecessary features/over-engineering, brute-force
   fixes that mask causes, missing/weak tests.
2. **Findings schema**: fixed fields — severity, file:line, category,
   evidence, suggested fix. Machine-parseable: one JSON object per finding,
   appended to `.harness/log.jsonl` as v1-compatible `hook_log` lines. The
   schema is defined *here* and consumed later by the outcome-telemetry
   plan — never the reverse. Audit mode gains a simple findings count now;
   trend analysis stays in outcome-telemetry.
3. **Wiring**: thin stubs for all providers per the existing add-agent flow
   (`.claude/agents/`, `.cursor/agents/`, `.codex/agents/*.toml`,
   `.opencode/agents/`); non-blocking by default.
4. **Optional CI review**: a `templates/ci/` workflow wiring the persona as
   a PR reviewer (e.g. claude-code-action), with the repo's AGENTS.md in
   context; documented as opt-in with cost notes. Session→PR attribution
   convention (commit trailer) is documented here and only here — the
   outcome-telemetry plan consumes it.
5. **Seeded-defect eval** (uses the behavioral-evals machinery): plant N
   defects across the four failure classes in a fixture branch; record the
   reviewer's catch-rate as the baseline. *Acceptance: catch-rate
   demonstrated and recorded before the persona is documented as
   recommended.*

## Out of scope

Blocking review gates (advisory-first per ADR 001); multi-agent
planner/generator orchestration (harness-native features cover this;
document, don't rebuild); review of non-diff artifacts.

## Dependencies

The behavioral-evals machinery — the seeded-defect eval is the ship gate.

## Verification

Seeded-defect eval baseline recorded; persona stubs load in ≥2 providers;
findings parse as JSON into `.harness/log.jsonl`; `verify.sh` green.

## Progress

- 2026-07-10 — Hardened after two-agent review: findings log-line defined
  here as v1-compatible instead of depending on the outcome-telemetry
  schema two releases later; session→PR attribution deduplicated to this
  plan; citation attribution corrected to Böckeler.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-10 — Reviewer ships only with its eval: a reviewer that can't
  demonstrate catch-rate is scaffolding, not signal.

## Next action

After behavioral-evals ships: define the findings schema first (it
constrains the persona prompt), then the persona doc.
