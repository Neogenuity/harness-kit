# Execution sandbox profiles

Status: queued

## Objective

Ship the higher-tailoring-cost half of execution governance that the v0.10.0
baseline deferred: opt-in per-provider sandbox / network / approval profiles
(Claude Code, Codex, Cursor, OpenCode) with an optional `.devcontainer/`
template, plus provider audit-log / telemetry export pointers — each stamped
against live provider docs at edit time and kept honest by the kit's usual
drift checks, so a repo can move from the documented posture to enforced
profiles without the kit reimplementing any sandbox.

## Value

The v0.10.0 baseline
([completed/v0.10.0-execution-governance-baseline.md](completed/v0.10.0-execution-governance-baseline.md))
documented the safe-default posture and verified which native layer enforces
what (the provider matrix's Execution-containment section), but shipped no
per-provider *templates* that turn that posture on. Turning it on is real
per-project tailoring — sandbox settings, writable roots, network allowlists,
and approval policies differ per provider and per repo — which is exactly the
cost that argued for scheduling this after the near-zero-cost baseline. Current
practice treats sandbox + approvals + network policy + telemetry as one
combined control system (<https://openai.com/index/running-codex-safely/>,
validated 2026-07-10); this plan ships the configuration surface for it and the
export pointers for the telemetry half — never a collector, never an
enforcement engine of the kit's own.

## Scope

1. **Per-provider profiles** (opt-in templates + matrix rows, each stamped per
   ADR 004 at edit time): Claude Code `sandbox.*` settings (filesystem scoping,
   `network.allowedDomains`) plus an optional `.devcontainer/` template; Codex
   `sandbox_mode` / `approval_policy` / `[sandbox_workspace_write]` network
   config; Cursor `.cursor/sandbox.json` profile; OpenCode `permission`
   profiles. Workspace-only writes and network-default-deny, with documented
   loosening steps. *Acceptance: each profile installs cleanly per provider on
   the fixture recipe; every matrix row it cites is stamped; no template claims
   enforcement the matrix doesn't prove.*
2. **Audit-log export**: document the OTel / monitoring hooks each provider
   offers for agent telemetry and point `.harness/log.jsonl` consumers at them.
   No collector shipped. *Acceptance: the pointers resolve to live provider
   docs, stamped at edit time; `.harness/log.jsonl` consumers have a documented
   export path.*

## Out of scope

Reimplementing any sandbox (configure-don't-rebuild); CI secrets management;
org-level identity (document expectations only — provider-managed); the
documented default posture and the Execution-containment matrix section
(shipped in the v0.10.0 baseline); shipping a telemetry collector.

## Dependencies

The v0.10.0 baseline (the posture doc and the verified Execution-containment
matrix section these profiles turn on) and the plans-machinery fixture recipe
(used to prove each profile installs cleanly). **Corrected 2026-07-11:**
runtime-legibility ships a `dev.sh` **boot contract**, not a `.devcontainer/` —
so this plan owns its own optional `.devcontainer/` template and depends only
on that boot contract ([runtime-legibility.md](runtime-legibility.md), scope
item 1), not on any devcontainer from that plan. A matrix re-verification pass
at edit time is required — provider security surfaces move fast (ADR 004).

## Verification

Profiles install cleanly per provider on the plans-machinery fixture recipe;
every matrix row a profile cites carries a `verified YYYY-MM` stamp; no template
claims enforcement it doesn't have (reviewed against the matrix's
guardrail-not-boundary language); the audit-log-export pointers resolve to live
provider docs; `verify.sh` green.

## Progress

- 2026-07-11 — Split out of the execution-governance plan as its own queued
  plan when the v0.10.0 baseline (MCP inventory, untrusted-content +
  risky-actions convention docs, verified Execution-containment matrix section,
  CI hardening) was activated. Carries the original plan's advanced items 6-7
  (per-provider profiles, audit-log export), their dependencies, and their
  acceptance criteria (source:
  `git show v0.9.0:docs/plans/execution-governance.md`). Corrected the
  devcontainer dependency: runtime-legibility ships a `dev.sh` boot contract,
  not a `.devcontainer/`, so this plan owns its own optional devcontainer
  template and depends only on that boot contract.

## Decisions

- 2026-07-11 — **This plan owns its devcontainer**: the earlier "shared
  `.devcontainer/` surface" dependency was wrong — runtime-legibility's scope
  is a `dev.sh` boot contract plus a worktree-name helper, no devcontainer. The
  optional `.devcontainer/` template lives here, depending only on the boot
  contract.
- 2026-07-11 — **Baseline before profiles** (carried from the split): the
  zero-tailoring-cost posture doc + drift checks shipped first (v0.10.0); the
  expensive per-provider sandbox profiles keep their later slot.
- 2026-07-10 — **Configure-don't-rebuild** (from the source plan): the kit
  ships profiles and drift checks for platform enforcement, never its own
  enforcement.

## Next action

After runtime-legibility ships its `dev.sh` boot contract: draft the Claude
Code and Codex sandbox/network profiles first (their settings are the most
fully specified in the Execution-containment matrix section), then Cursor and
OpenCode, then the optional `.devcontainer/` template and the audit-log-export
pointers.
