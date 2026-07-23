# ADR 002 — Vendor everything into the target repo

**Status:** accepted (v0.1.0)

## Context

A harness kit could stay resident: target repos reference hooks and scripts
inside the installed plugin, and updates propagate automatically. But a
repo's contributors do not share a toolchain — some use Claude Code with the
plugin, some use Cursor or Codex with no plugin infrastructure at all, and
CI has none of it. Any behavior that lives outside the repo exists only for
the subset of people who installed the kit.

## Decision

`init` **copies** everything into the target repo: hook scripts, the
sync/check/verify machinery, provider configs, templates-turned-content.
Nothing at runtime references the kit's install location. A plain `git
clone` gives every contributor — on any harness, or none — identical guards,
gates, and docs.

## Consequences

- Teammates and CI get the full harness for free; the kit is only needed to
  *install* or *upgrade*, never to *run*.
- Updates are no longer automatic — hence `scripts/harness/.harness-manifest`
  (see [ADR 005](005-manifest-self-protection.md)): checksums distinguish
  "still the kit's file, safe to replace" from "locally tailored, diff only".
- The vendored scripts must be dependency-light and portable (bash + jq,
  BSD/GNU tolerant), because they run on whatever machine clones the repo.
