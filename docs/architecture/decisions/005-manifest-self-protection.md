# ADR 005 — The harness protects itself from the agent it serves

**Status:** accepted (v0.2.0)

## Context

A guard an agent can edit is not a guard. When a lint rule or a hook blocks
an agent mid-task, the path of least resistance is to weaken the check —
agents do this without malice, and diffs that "fix" a guard config slip
through review. The harness mechanism (hooks, sync/check scripts, permission
files, CI wiring) needs protection *from its own primary user*.

## Decision

Two layers, because neither alone is sufficient:

1. **`guard-config.sh`** (pre-edit hook) denies agent edits to hook scripts,
   machinery, manifests, hook wiring, CI gates, and (tailored per repo) lint
   configs. Escape hatch for intentional maintenance:
   `HARNESS_ALLOW_MECHANISM_EDITS=1`.
2. **`scripts/.harness-manifest`** — sha256 per mechanism file, verified by
   `check-harness.sh` in CI. This catches what the hook can't see: `sed -i`
   via shell, edits from harnesses without pre-edit events (Cursor), or a
   human hand-edit. Any un-pinned change fails the build until its line is
   deliberately re-pinned; ` # tailored` marks a permanent local fork that
   update mode must diff, never replace.

## Consequences

- "Fix the code, not the check" is mechanical, not aspirational.
- Legitimate mechanism work carries ceremony (escape hatch + re-pin). The
  friction is small, deliberate, and logged.
- The manifest doubles as the upgrade contract (see
  [ADR 002](002-vendor-everything.md)): checksum-match means "the kit may
  replace this file", checksum-drift means "the project owns it now".

**Amended by [ADR 009](009-declarative-ship-manifest.md) (v0.21.0):** the
integrity manifest's role is unchanged, but its producer and update's
replace-vs-diff decision table now derive their file sets from the shipped
`scripts/kit-manifest` ship contract instead of hard-coded lists, and the
protected set grows to include the kit-manifest itself.
