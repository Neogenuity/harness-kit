# Standard consumer layout (queued umbrella — phases activate individually)

**Status:** umbrella plan. Each phase below activates as its own versioned plan
in `active/` when work starts (per the lifecycle in [README.md](README.md));
this file holds the cross-phase rationale, ordering, and the target layout so
per-phase plans stay small. Supersedes
[adopter-test-descope.md](adopter-test-descope.md) (absorbed as Phase 2; its
retired-file prerequisite is Phase 1).

## Objective

Before the public flip, converge on **one** answer to "who owns this file and
what may update do to it," and ship a **standard consumer-repo layout** whose
ownership is legible from the path: kit-owned mechanism under `scripts/harness/`
(verb commands, sync-with-delete), repo-owned agent-operational policy under a
committed `.harness/` (policies, gates, templates, schemas, generated
adapters), canonical skills at `.agents/skills/`, and a human knowledge base
under `docs/` (standards, runbooks, plans, generated, references). The layout
is the trend-setting deliverable: there is no ecosystem standard yet, so 1.0's
layout must be final before any external adopter installs it.

## Value

Ownership is currently encoded five ways (three shell lists in
`install-lib.sh` plus a duplicate enumeration in `check-harness.sh` check #9c,
` # tailored` manifest markers, `TAILOR:` blocks inside shell bodies,
inconsistent rename conventions, four hand-curated provider lists in
`harness.conf`). Update mode cannot delete a file — which already forced a
manual workaround at v0.20.0 and blocks the adopter test descope. Every one of
these is cheap to fix with exactly one install (this repo) and impossible to
fix after launch without migration guides, grace windows, and compat shims.
Done now, each phase is a one-off re-pin of this repo; done later, each is a
breaking change multiplied by every adopter's tailored files.

## Scope

Phased; each phase is one minor release cut via
[the release skill](../skills/release/SKILL.md) and leaves `verify.sh` green.

- [x] **Phase 1 — declarative ship-manifest + retirement** — **shipped
  2026-07-22 as v0.21.0** (tag v0.21.0, 91aad35; see
  [completed/v0.21.0-ship-manifest-and-retirement.md](completed/v0.21.0-ship-manifest-and-retirement.md)). A shipped `kit-manifest` (plain text: layer, path, optional
  `dest=`, plus a `retired` section) becomes the single source for what ships
  and what layer owns it; `install-lib.sh` parses it instead of the three
  hard-coded lists; `harness_update_apply` gains `remove` for pristine,
  non-tailored retired files; check #9c derives its set from it. Acceptance:
  retirement fixtures (pristine-removed / drifted-kept / tailored-kept) pass;
  `scripts/test-install.sh` listed retired proves the v0.20.0 caveat is closed.
- [ ] **Phase 2 — adopter test descope + cleanups** (absorbs
  [adopter-test-descope.md](adopter-test-descope.md)). Conformance suites
  become maintainer-only; adopters get a small smoke suite; `dev.sh`'s three
  special cases collapse to one `optional-policy` manifest line; rename
  conventions become `dest=` data. Acceptance: a fixture updating from the
  Phase 1 layout removes the descoped suites cleanly and stays checker-green.
- [ ] **Phase 3 — mechanism re-home**: `scripts/harness/` extensionless verb
  commands (`bootstrap`, `verify`, `sync`, `check-instructions`, `check-docs`,
  `detect-drift`, `validate-plan`, `run-evals`) over shared `lib/`; mechanism
  hooks move to `scripts/harness/hooks/` with their tailorable parts extracted
  to `harness.conf`; `guard-project-policy.sh` moves to repo-owned
  `.harness/hooks/`; the verify runner reads a repo-owned `.harness/gates.conf`;
  runtime state moves to gitignored `.harness/var/`. Acceptance: provider hook
  configs, check #8d tuples, and provider-matrix stamps all reference the new
  paths; update-from-previous-layout fixture green; grep for old paths returns
  nothing.
- [ ] **Phase 4 — content/IA migration**: committed `.harness/` layer
  (policies, templates, schemas, evals, agents), docs IA (standards, runbooks,
  product/generated/references skeletons, PLANS.md, root ARCHITECTURE.md),
  canonical skills to `.agents/skills/` (ADR 003 amended — stubs still
  generated for providers that don't read `.agents/`). Acceptance: link
  checker, stub checks, and eval machinery all pass against the new tree;
  this repo's own docs migrated identically.
- [ ] **Phase 5 — single provider declaration + generated adapters**: kit-owned
  provider capability table; adopters declare one `HARNESS_PROVIDERS`; `sync`
  generates per-provider adapter summaries in `.harness/adapters/` and the
  secret-deny mirrors (`SECRET_PATTERNS` → Claude/OpenCode native denies) with
  semantic `--check`. Acceptance: the four legacy lists demote to explicit
  overrides; checks #8/#8b/#8d/#8e gate on the derived sets; generated mirrors
  drift-checked.
- [ ] **Phase 6 — acceptance + launch unblock**: fresh-repo `bootstrap`
  end-to-end on a throwaway repo (doubles as the launch demo recording), eval
  grader validity, then the public flip in
  [launch-readiness](active/launch-readiness.md) proceeds.

## Out of scope

- Compat shims or old-path symlinks — pre-1.0 with one install; the Phase 1
  retirement contract **is** the migration mechanism.
- A second workflow system (the example layout's `.harness/workflows/`) —
  `.agents/skills/` is the one workflow standard; workflow topics become
  candidate shipped skills later.
- Splitting into multiple plugins, or any ADR 007 packaging change.
- YAML/TOML/JSON for `kit-manifest` or the provider table — ADR 002's
  bash-3.2 + no-jq parse floor stands (jq only where a subcommand writes JSON).
- Inferring any provider set from disk — declarations stay explicit; only the
  *derived* facts move from adopter homework to kit data.

## Dependencies

Phase 1 blocks everything (retirement is how later phases move/drop files).
Phases 2–5 are strictly ordered as numbered; Phase 6 needs all prior. The
public flip in [launch-readiness](active/launch-readiness.md) is gated on
Phase 6; launch-readiness's other items (demo script, org move) proceed in
parallel.

## Verification

Per phase: templates edited first, rolled into the root install, manifest
re-pinned, `bash scripts/verify.sh` green, release tagged. Every
layout-changing phase adds an update-from-previous-release fixture to the
install suites asserting the checker stays green across the move. Phase 6's
fresh-repo `bootstrap` is the end-to-end proof.

## Progress

- 2026-07-22 — **Phase 1 shipped as v0.21.0** (tag v0.21.0, 91aad35): ship
  contract + retirement mechanism live, all suites and the full gate green;
  the v0.20.0 manual-`rm` caveat is now a regression test. Phase 2 (adopter
  test descope) is next.
- 2026-07-22 — Umbrella plan authored from the approved restructure design
  (three parallel codebase explorations + plan review; user decisions
  recorded below). Phase 1 activated as v0.21.0.

## Decisions

- 2026-07-22 — **Full six-phase scope; the restructure gates the public
  flip** (user decision). Layout ships final; no adopter ever migrates.
- 2026-07-22 — **Canonical skills move to `.agents/skills/`** (user decision):
  the emerging cross-provider standard location becomes the source; Codex
  reads it natively; stubs remain generated for `.claude`/`.cursor`/`.opencode`.
- 2026-07-22 — **Verify splits into kit-owned runner + repo-owned declarative
  gate config** (user decision); same extraction applies to hook TAILOR
  content, completing the mechanism/policy separation so updates never diff
  policy out of shell bodies.
- 2026-07-22 — **`.harness/` becomes the committed agent-operational layer**;
  runtime state (log, base snapshots, eval results) moves under gitignored
  `.harness/var/`. Chosen over renaming the runtime dir: the target layout's
  `.harness/` name is the standard being set.
- 2026-07-22 — **Hooks split by ownership, not provider**: mechanism hooks
  ship in the kit dir with policy extracted to config; only
  `guard-project-policy.sh` (project invariants, inherently shell) stays
  repo-owned. Provider configs rewritten once, pre-launch — the frozen #8d
  tuple tables ship from the kit, so contract and configs change together.

## Next action

Execute Phase 2 per [active/v0.22.0-adopter-test-descope.md](active/v0.22.0-adopter-test-descope.md)
(Phase 1 shipped — see
[completed/v0.21.0-ship-manifest-and-retirement.md](completed/v0.21.0-ship-manifest-and-retirement.md)).
