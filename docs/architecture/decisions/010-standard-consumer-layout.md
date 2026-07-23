# ADR 010 — Standard consumer layout: `scripts/harness/` mechanism, `.harness/` policy

**Status:** accepted (v0.23.0)

## Context

Through v0.22.0 the kit installed a flat `scripts/` tree: fifteen-plus
`*.sh` files (commands, libraries, and tests indistinguishable by name), a
`scripts/hooks/` directory mixing kit-owned guards with the repo-owned
project-policy hook, and a `verify.sh` whose single file carried both
kit-owned orchestration machinery and the repo's tailored gate list — so
every orchestration improvement shipped as a diff against a policy file the
update mode was forbidden to touch. `.harness/` was purely git-ignored
runtime state, leaving no committed home for repo-owned agent-operational
policy. No ecosystem standard existed for any of this; the kit's pre-launch
window was the one chance to set the layout without migration debt.

## Decision

The kit installs one standard consumer layout, in three ownership zones:

- **`scripts/harness/` — the kit-owned mechanism tree** (sha-pinned,
  replaced wholesale on update). Extensionless **verb commands** at its
  root — `bootstrap`, `verify`, `sync`, `check-harness`,
  `check-instructions`, `check-docs`, `detect-drift`, `validate-plan`,
  `run-evals` — over `lib/*.sh` (shared code, including the checker split
  into per-family `check-*.sh` scripts summed by the `check-harness`
  orchestrator), `hooks/*.sh` (mechanism guards only), `tests/` (the
  shipped regression floor), and both manifests (`kit-manifest`,
  `.harness-manifest`). Commands keep `.sh` off their names because they
  are the public interface; libraries keep it because they are files.
- **`.harness/` — the committed, repo-owned agent-operational layer**:
  `gates.conf` (the verify gate list as declarative data — `gate`, `full`,
  `parallel`, `parallel-each` lines run by the mechanism runner) and
  `hooks/guard-project-policy.sh` (project invariants are inherently
  shell). Runtime state moves under git-ignored **`.harness/var/`**
  (`log.jsonl`, `base/`, `eval-results/`, `dev/`, `stop-markers/`).
- **`scripts/` root — the repo's own space.** The kit claims only
  `scripts/harness/` and the optional authored `scripts/dev.sh`; everything
  else at `scripts/` belongs to the repo (in the kit repo itself: the
  maintainer-only conformance suites, kept as ` # tailored` retired forks).

This completes the mechanism/policy split ADR 009 started: update never
again diffs policy out of a shell body, because no shipped file carries
both. Hooks are split by **ownership, not provider**; `format.sh` and
`guard-config.sh` became pure mechanism by moving their tailorable parts
(`FORMAT_RULES`/`LINT_RULES`, `GUARD_PROTECTED_EXTRA`) into `harness.conf`
data. `guard-config.sh`'s protected set collapses to `scripts/harness/*`
plus the repo-owned enforcement-layer policy files. The old flat paths are
`retired` kit-manifest entries — ADR 009's retirement contract IS the
migration (`harness_update_apply` also migrates the integrity manifest's
location and the installer narrows a pre-v0.23.0 `.harness/` gitignore line
to `.harness/var/`).

Two deliberate adaptations from the community layout proposal that seeded
this: no separate `.harness/workflows/` system (canonical skills are the
one workflow standard — shipping two would fork it), and generated
per-provider adapters/`schemas` land in later phases (ADR 011 territory),
not here.

## Consequences

- Adopters see one obvious surface: `bash scripts/harness/<verb>`. Docs and
  instruction files point at commands, never at library files.
- The verify runner upgrades like any mechanism file; a repo's gates are
  data that survives every update untouched. The runner's
  `HARNESS_VERIFY_PRELUDE` seam keeps its internals testable without
  editing the shipped file.
- `.harness/gates.conf` and `.harness/hooks/*` are committed policy — they
  are guard-protected and integrity-pinned exactly like `harness.conf`,
  because an agent that can edit the gate list can fake a green verify.
- Everything under `scripts/harness/` is pinned from the filesystem
  wholesale (check #9c), so a repo-local addition to the kit tree must be
  pinned too; the maintainer repo's own suites live outside it and are
  protected via `GUARD_PROTECTED_EXTRA` instead.
- Pre-v0.23.0 installs migrate through the normal update path; the
  `test-install-update.sh` case (l) pins the whole sequence (manifest
  migrate, flat-path retirement, tree install, gitignore narrowing).
