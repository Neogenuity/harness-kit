# Runtime legibility

Status: queued

## Objective

Make the *running application* operable and observable by an agent: boot per
worktree, seed deterministic data, expose logs/health, and ship a
live-verification skill — so behavioral confidence stops ending at green
unit tests.

## Value

Green unit tests are a weak behavioral sensor for UI, distributed-system,
and performance work. Current practice closes the loop against the live
app: OpenAI made their app bootable per git worktree with an ephemeral local
observability stack (logs/metrics/traces) per instance
(<https://openai.com/index/harness-engineering/>, validated 2026-07-10 via
InfoQ 2026-02); Anthropic's evaluator drives the page itself — navigating,
screenshotting, checking endpoints and database state
(<https://www.anthropic.com/engineering/harness-design-long-running-apps>).
The kit discovers build commands at init but nothing makes the app
*runnable* by an agent.

## Scope

1. **The `dev.sh` contract** (convention, not template): a convention doc
   specifying the interface — `dev.sh up|health|down`, worktree-suffix
   derivation for ports/db/cache names so parallel agents don't collide,
   and a deterministic seed step. The only shipped *mechanism* is a small
   helper for worktree-derived names; the script body belongs to the
   target repo. *Acceptance: a documented contract a skill can rely on
   blind, plus the helper with a regression test.*
2. **Live-verification skill**: `templates/docs/skills/verify-live/SKILL.md`
   — the reproduce → observe → change → re-run loop; drive the affected
   flow, not just tests; browser/screenshot steps for UI surfaces; where to
   find logs/traces for the booted instance.
3. **Matrix: browser tooling pointers** — a stamped note on the
   browser-driving options per provider (e.g. Playwright MCP, native
   browser tools), re-verified against primary docs at edit time per
   ADR 004. The matrix carries no such facts today; this plan adds them
   because the verify-live skill needs something to point at.
4. **verify.sh example**: a commented `full_gate "smoke" bash scripts/dev.sh health`
   pattern showing where live checks slot into the gate order.
5. **init integration**: interview asks for the boot/health commands; recon
   proposes from docker-compose/Procfile/manifest scripts. Audit reports
   whether a runnable contract exists.
6. **Fixture app**: a minimal bootable web app (extending the
   plans-machinery fixture recipe) defined as a test asset with its own
   acceptance criterion — this repo is bash + markdown, so the contract
   can only be exercised for real on an app-shaped fixture.

## Out of scope

Shipping any observability stack (compose files for Grafana etc. — point,
don't vendor); performance benchmarking; provider browser-tool
reimplementation.

## Dependencies

The behavioral-evals runner (used to exercise the contract end-to-end on
the fixture app). The fixture app itself is this plan's own scope item 6 —
no earlier plan provides it.

## Verification

On the scope-item-6 fixture app: an agent boots two worktree instances
concurrently without collision; the verify-live skill drives one flow
end-to-end; `verify.sh` green.

## Progress

- 2026-07-10 — Hardened after two-agent review: `dev.sh` demoted from
  all-TAILOR script template to contract-plus-helper (a template the kit
  can never upgrade carries no mechanism); fixture app promoted to an owned
  scope item instead of a phantom dependency on the evals plan; matrix
  browser-tooling pointers moved from Dependencies into scope.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-10 — Contract over stack, and contract over template: the kit
  standardizes the `dev.sh` interface and ships only the worktree-name
  helper as mechanism — never the infrastructure, never an all-TAILOR
  script body.

## Next action

After reviewer-loop ships: draft the `dev.sh` contract doc and the
worktree-suffix helper.
