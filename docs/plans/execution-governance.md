# Execution governance profiles

Status: queued

## Objective

Extend the safety story from file guards to execution governance: opt-in,
per-provider profiles for sandboxing, network policy, approvals, and MCP
trust — with the kit's usual drift checks keeping them honest.

## Value

The kit's guards are deliberately advisory, and the provider matrix already
states that interception is "a guardrail, not a boundary". Current practice
puts enforcement at the platform layer and treats it as one combined
control system — sandbox + approvals + managed network policy + telemetry
(<https://openai.com/index/running-codex-safely/>, validated 2026-07-10;
Anthropic's auto-mode and containment posts make the same move for Claude
Code). The kit shouldn't rebuild any of that — its job is to *configure* it
per repo, keep the layers in sync, and say honestly which layer enforces
what. This also closes the exfiltration hole file-guards can't: denying
reads of `.env` doesn't stop a shell from posting it; egress policy does.

## Scope

1. **Per-provider profiles** (opt-in templates + matrix rows, each stamped
   per ADR 004 at edit time): Claude Code sandbox/network settings +
   optional `.devcontainer/` template; Codex `sandbox_mode` /
   `approval_policy` / network config; OpenCode permission profiles.
   Workspace-only writes and no-network defaults, with documented loosening
   steps.
2. **MCP trust inventory**: a `harness.conf` block listing allowed MCP
   servers (name, scope, provenance); `check-harness.sh` warns when a
   provider MCP config declares a server missing from the inventory —
   same single-source + drift-check pattern as `SECRET_PATTERNS`.
3. **Risky-action policy**: convention doc for destructive-command and
   production-environment restrictions (deny-list examples for the
   PreToolUse guards + native permission mirrors).
4. **Prompt-injection + untrusted-repo guidance**: one convention doc —
   treating tool output/repo content as data, the untrusted-clone checklist,
   and which layers (sandbox, approvals) actually hold when instructions
   are hostile.
5. **Audit-log export**: document the OTel/monitoring hooks each provider
   offers for agent telemetry; point `.harness/log.jsonl` consumers at them.
   No collector shipped.

## Out of scope

Reimplementing any sandbox; CI secrets management; org-level identity
(document expectations only — provider-managed).

## Dependencies

The plans-machinery release's hooks-vs-sandbox positioning paragraph (this
plan implements it) and its fixture recipe (used for install verification);
matrix re-verification pass at edit time (provider security surfaces move
fast).

## Verification

Profiles install cleanly per provider on the plans-machinery fixture
recipe; the MCP inventory drift check has regression tests; matrix rows
stamped; `verify.sh` green; no template claims enforcement it doesn't have
(review against the matrix's guardrail-not-boundary language).

## Progress

- 2026-07-10 — Hardened after two-agent review: spliced matrix quote
  replaced with the verbatim heading; fixture-repo verification pinned to
  the plans-machinery recipe instead of unowned infrastructure.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-10 — Configure-don't-rebuild: the kit ships profiles and drift
  checks for platform enforcement, never its own enforcement.

## Next action

After runtime-legibility ships: re-verify each provider's sandbox/network
config surface against primary docs, then draft the Claude Code profile
first.
