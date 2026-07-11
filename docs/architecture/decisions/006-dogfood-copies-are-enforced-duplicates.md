# ADR 006 — Dogfood copies are enforced duplicates, not references

**Status:** accepted (v0.3.0)

## Context

Every mechanism script — including the regression tests — exists twice: the
shipped template under `plugins/harness-kit/skills/harness-kit/templates/scripts/` and
this repo's installed copy under `scripts/`. The obvious de-duplications all
break something load-bearing. Root-only tests pointing at the plugin copies:
the tests are themselves shipped product (installed repos self-test via
`check-harness.sh` check #6), and the installed tests exercising the
*installed* hooks against the live `harness.conf` is exactly what catches
policy weakening. Symlinks: the root must be a byte-faithful example of what
`init` produces ([ADR 002](002-vendor-everything.md) — nothing references
the kit's install location). Generating templates *from* the root: three
root files are tailored for this repo and must never ship.

## Decision

Keep both copies, with a direction and a gate. The **templates are the
source of truth** — edit them first; the root install is downstream, rolled
forward by copy + manifest re-pin (the kit's own update mode).
`scripts/test-template-sync.sh` — root-only, never shipped — enforces the
relationship: every non-tailored mechanism file must be byte-identical to
its template twin, and every manifest-pinned file must still have a template
twin. It is named `test-*.sh` so check #6 runs it in CI and
`guard-config.sh` protects it, without touching any shipped mechanism.

## Consequences

- Editing mechanism still means touching two files plus a re-pin, but
  forgetting the roll-forward is now a CI failure that prints the exact
  commands — not a silently stale dogfood install.
- Tailored files (`# tailored` manifest lines) and `harness.conf` stay
  exempt: they legitimately diverge, and the release skill diffs them at
  release time instead.
- The duplication is the same pattern the kit installs everywhere — vendored
  copies with integrity pins ([ADR 005](005-manifest-self-protection.md)) —
  applied to the kit's own repo.
