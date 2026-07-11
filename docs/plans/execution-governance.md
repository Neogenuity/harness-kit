# Execution governance profiles

Status: queued

## Objective

Extend the safety story from file guards to execution governance: a
pull-forward-eligible baseline (MCP trust inventory, untrusted-repo/prompt-
injection and risky-action guidance, a documented safe-default posture, CI
supply-chain hardening) plus later opt-in per-provider profiles for
sandboxing, network policy, and approvals — with the kit's usual drift checks
keeping them honest.

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

**Sequencing (moved up 2026-07-11).** A standards-coverage audit flagged
that leaving *all* execution containment until the roadmap's tail leaves the
exfiltration hole and the hostile-repo/prompt-injection posture open behind
four other plans, while OpenAI treats these controls as a non-optional
combined system rather than finishing work. The response splits this plan:
the **minimal baseline** below (MCP inventory, risky-action + untrusted-repo
guidance, CI hardening, a documented default posture) is pure documentation
and single-source drift checks — near-zero per-project tailoring cost — so it
moves ahead of the reviewer-loop and runtime-legibility plans. The **advanced
profiles** (per-provider sandbox/network templates, devcontainers, audit-log
export) keep the high tailoring cost the original ordering rationale cited
and stay later; they can split into their own plan if the baseline ships
first.

## Scope

### Minimal baseline (pull-forward-eligible)

1. **MCP trust inventory**: a `harness.conf` block listing allowed MCP
   servers (name, scope, provenance); `check-harness.sh` warns when a
   provider MCP config declares a server missing from the inventory —
   same single-source + drift-check pattern as `SECRET_PATTERNS`.
2. **Risky-action policy**: convention doc for destructive-command and
   production-environment restrictions (deny-list examples for the
   PreToolUse guards + native permission mirrors).
3. **Prompt-injection + untrusted-repo guidance**: one convention doc —
   treating tool output/repo content as data, the untrusted-clone checklist,
   and which layers (sandbox, approvals) actually hold when instructions
   are hostile. Implements the plans-machinery hooks-vs-sandbox positioning
   paragraph as a full doc.
4. **Documented default posture**: state the recommended safe defaults
   (workspace-only writes, no-network-by-default, approvals on for
   destructive actions) as prose in the convention doc, with the loosening
   steps — no per-provider template yet, just the posture a repo should aim
   for and which native layer enforces each part.
5. **CI-template hardening**: the kit installs
   `templates/ci/github-actions-harness-check.yml` into other repos, so it
   should model secure CI defaults (a coverage audit, 2026-07-11, found it
   uses a mutable `actions/checkout@v4`, declares no `permissions`, and sets
   no `timeout-minutes`). Harden it: SHA-pin third-party actions, add
   `permissions: contents: read`, add `timeout-minutes`, and
   `persist-credentials: false` on checkout. Mirror the change into this
   repo's own `.github/workflows/`. *Acceptance: the shipped template and the
   repo's workflows pin actions to a SHA and declare least-privilege
   permissions; a pin-freshness note is added so the SHA is maintained.*

### Advanced profiles (higher tailoring cost — stays later)

These two items block on the runtime-legibility plan's devcontainer/boot
work, so a resuming session should not attempt them in-line here: when the
baseline (items 1–5) ships, split items 6–7 into their own queued plan
slotted after runtime-legibility.

6. **Per-provider profiles** (opt-in templates + matrix rows, each stamped
   per ADR 004 at edit time): Claude Code sandbox/network settings +
   optional `.devcontainer/` template; Codex `sandbox_mode` /
   `approval_policy` / network config; OpenCode permission profiles.
   Workspace-only writes and no-network defaults, with documented loosening
   steps.
7. **Audit-log export**: document the OTel/monitoring hooks each provider
   offers for agent telemetry; point `.harness/log.jsonl` consumers at them.
   No collector shipped.

## Out of scope

Reimplementing any sandbox; CI secrets management; org-level identity
(document expectations only — provider-managed).

## Dependencies

The plans-machinery release's hooks-vs-sandbox positioning paragraph (this
plan implements it) and its fixture recipe (used for install verification);
matrix re-verification pass at edit time (provider security surfaces move
fast). The baseline depends only on plans-machinery; the advanced profiles
additionally want the runtime-legibility devcontainer/boot work to land
first (shared `.devcontainer/` surface).

## Verification

Baseline: the MCP inventory drift check has regression tests; the shipped CI
template and this repo's workflows SHA-pin actions and declare
least-privilege `permissions`; the untrusted-repo/risky-action convention
doc links resolve; `verify.sh` green. Advanced: profiles install cleanly per
provider on the plans-machinery fixture recipe; matrix rows stamped; no
template claims enforcement it doesn't have (review against the matrix's
guardrail-not-boundary language).

## Progress

- 2026-07-11 — Split into a pull-forward-eligible baseline (MCP inventory,
  risky-action + untrusted-repo guidance, documented default posture, CI
  hardening) and later advanced profiles, after a standards-coverage audit
  (2026-07-11) argued execution containment was scheduled too late per
  OpenAI's combined-controls framing. Moved ahead of reviewer-loop and
  runtime-legibility in the roadmap; folded in the CI-template supply-chain
  hardening finding (mutable `actions/checkout`, no `permissions`/timeout).
- 2026-07-10 — Hardened after two-agent review: spliced matrix quote
  replaced with the verbatim heading; fixture-repo verification pinned to
  the plans-machinery recipe instead of unowned infrastructure.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-11 — Baseline before profiles: the zero-tailoring-cost pieces
  (guidance docs, MCP inventory, CI hardening) close the hostile-repo and
  supply-chain gaps immediately; the expensive per-provider sandbox profiles
  keep their later slot. Honors both the audit's "don't schedule containment
  last" and the roadmap's "highest tailoring cost goes late".
- 2026-07-10 — Configure-don't-rebuild: the kit ships profiles and drift
  checks for platform enforcement, never its own enforcement.

## Next action

After plans-machinery ships: draft the untrusted-repo/prompt-injection +
risky-action convention doc and the MCP trust inventory drift check
(baseline), and harden the CI template. The advanced per-provider profiles
wait until after runtime-legibility (shared `.devcontainer/` surface).
