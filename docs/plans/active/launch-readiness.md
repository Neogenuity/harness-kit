# Launch readiness

Status: **active (partial)** — doc items 3–6 shipped in v0.13.0 (2026-07-13);
items 1 (demo), 2 (org move), 7 (public flip) remain maintainer actions

## Objective

Turn the launch — the point of the project — into tracked, scoped work with
acceptance criteria, instead of leaving it as unowned README checkboxes.

## Value

harness-kit is being built as an open-source artifact for career
positioning, and the launch is the deliverable, not an afterthought. Today
it is tracked only as two unchecked boxes in README.md's Status section —
invisible to the plans machinery this repo evangelizes (a plan with progress
and decision logs that survive context windows). A project that scaffolds
"in-repo plans instead of untracked checkboxes" for every repo it installs
into should not track its own launch as an untracked checkbox.

## Scope

1. **Demo recording of `init` on a fresh repo** — the README checklist item;
   record a walkthrough of the kit scaffolding a harness into a clean
   repository, start to finish. *Acceptance: a published recording (or
   asciinema-style capture) exists and is linked from README.md.*
2. **Move to the `neogenuity` org** — update install commands, CI badges, and
   marketplace references from the current owner to `neogenuity`, including
   `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`, and
   every README install snippet. *Acceptance: `grep -r` for the old org
   string across tracked files returns nothing outside of historical
   CHANGELOG entries; badges resolve against the new org.*
3. **Public-repo hygiene pass** — a secrets/hostnames sweep beyond the
   existing template-level checklist (this repo's own git history and
   config, not just the templates it ships), a LICENSE/CONTRIBUTING review,
   and an explicit decision on issue templates. *Acceptance: the sweep is
   documented as run with its findings (or "none found"); CONTRIBUTING
   exists and is current; the issue-template decision is recorded.*
4. **What 1.0 promises** — write an explicit "what 1.0 promises" section into
   [../../../README.md](../../../README.md), covering mechanism/update-contract stability
   guarantees and post-1.0 template semver discipline, so adopters know what
   changes are safe across upgrades before committing to the kit.
   *Acceptance: the section exists, is linked from README.md's Status
   section, and states concretely what does and doesn't break across a
   template version bump.*
5. **Security policy** — a root `SECURITY.md`: how to privately report a
   vulnerability in the shipped guard machinery, the expected response
   window, which versions receive fixes pre-1.0, and a pointer to the
   enforcement-layer honesty docs
   ([../../conventions/risky-actions.md](../../conventions/risky-actions.md)) so
   reports are triaged against the boundary the kit actually claims. A
   project whose pitch is agent-safety machinery shipped into other people's
   repos needs a disclosure path at launch. *Acceptance: `SECURITY.md` exists
   at the repo root, is linked from README.md and CONTRIBUTING.md, and
   GitHub's security-policy detection recognizes it.*
6. **Supported-platforms statement** — an explicit README line on the hook
   runtime posture: bash + jq on macOS / Linux / WSL / Git Bash; no
   native-Windows hook execution (Codex's `commandWindows` override and the
   Windows notes stay in the provider matrix). *Acceptance: README states the
   posture; no doc claims native-Windows hook support.*
7. **Flip the repository public** — the launch act itself, which every item
   above prepares for and none performs: switch the repository (at its
   post-item-2 home) from private to public, after the org move (item 2) and
   the hygiene sweep (item 3) land, then prove the outside-in path works.
   *Acceptance: the repo's GitHub visibility is public; the README install
   commands succeed from a clean environment with no collaborator access;
   CI badges render for logged-out visitors.*

## Out of scope

Any mechanism or template change needed to satisfy the stability guarantees
this plan documents — if the "what 1.0 promises" pass surfaces a gap between
documented and actual behavior, that gap becomes its own plan rather than
being fixed inline here.

## Dependencies

None hard: this plan touches no mechanism.
Originally sequenced loosely after reviewer-loop (Decision 2026-07-11);
superseded by the 2026-07-12 decision below — start immediately and
parallel-track the mechanism plans.

## Verification

README.md carries no unresolved launch checkboxes; the demo recording,
org-move grep, hygiene-pass note, and "what 1.0 promises" section are all
linkable and current; the repository's GitHub visibility is public and the
install path works from a cold clone; `bash scripts/check-harness.sh`
link-checks pass on every doc this plan touches.

## Progress

- 2026-07-13 — Post-v0.13.0 cross-review (Codex gpt-5.6-sol, claims
  independently re-verified in-repo, its headline hook-wiring hole reproduced
  empirically) landed two things here: the README Status-section links to
  this plan were dead — they pointed at `docs/plans/launch-readiness.md`,
  the pre-activation path, invisible to `check-harness.sh`'s link checker
  (which scans only `AGENTS.md` files and `docs/`) — fixed inline; and the
  review's six mechanism/assurance findings were scoped into a new queued
  plan, [../completed/v0.14.0-provider-wiring-assurance.md](../completed/v0.14.0-provider-wiring-assurance.md),
  per this plan's out-of-scope fence ("that gap becomes its own plan").
  Root-README link-checking itself stays with the queued doc-gardening plan.
- 2026-07-13 — Workstream C (parallel-track, isolated worktree) landed items
  4–6 plus the CONTRIBUTING review, and closed out item 3's content-level
  sweep (the filename-level git-history sweep already covered by the
  2026-07-12 entry below):
  - **Item 3, content-level sweep**: grepped every tracked file outside
    `plugins/harness-kit/skills/harness-kit/templates/` (the shipped
    product, already covered by the template-level checklist) for
    AWS/GitHub/Slack token shapes, private-key headers, JWTs, Bearer
    tokens, and generic `key`/`secret`/`token`/`password` assignments —
    **none found**. IP-address and hostname sweep turned up only public
    provider-doc citations (openai.com, cursor.com, opencode.ai,
    martinfowler.com, agentskills.io, geminicli.com, arxiv.org) and the
    maintainer's own already-public `chase@neogenuity.com` (matches
    `.claude-plugin/marketplace.json`) — no internal/real hostnames.
    Filenames matching secret patterns (`guard-secrets.sh`,
    `test-guard-secrets.sh`, the `tmpl-secret-pattern` eval task) are the
    security tooling itself and its test fixtures, not leaked secrets;
    checked their contents directly — pattern names only, no real values.
    `git status --porcelain --ignored` showed nothing untracked or
    gitignored beyond `.DS_Store`/`.harness/`.
  - **Item 4**: added a "What 1.0 promises" section to
    [../../../README.md](../../../README.md#what-10-promises) — what a template
    version bump never touches (TAILOR blocks, tailored files, target-repo
    content, untouched mechanism files) and what each semver level means
    post-1.0 (patch/minor/major), linked from the Status section.
  - **Item 5**: added root `SECURITY.md` — private reporting (GitHub
    Security Advisories or email), scope grounded in
    [../../conventions/risky-actions.md](../../conventions/risky-actions.md) (advisory
    fail-open hooks are documented behavior, not a vulnerability), a
    best-effort response window, and a pre-1.0 supported-versions policy
    (latest tag only, no backports). Linked from README.md and
    CONTRIBUTING.md.
  - **Item 6**: added the supported-platforms line to README.md's Install
    section — bash + `jq` on macOS/Linux/WSL/Git Bash, no native-Windows
    hook execution, pointing at `provider-matrix.md` for Codex's
    `commandWindows` override rather than duplicating it.
  - **CONTRIBUTING review**: read end to end against current `verify.sh`
    gates and the ADRs; ground rules still accurate, no staleness found;
    added a Security section linking `SECURITY.md`.
  - Verified every relative link added in README.md/CONTRIBUTING.md/
    SECURITY.md resolves to an existing file (manual check — none of these
    three files are covered by `check-harness.sh`'s link checker, which
    only scans `AGENTS.md` files and `docs/`). `bash scripts/check-harness.sh`
    stays green (no mechanism touched).
  - Left untouched, as scoped: item 1 (demo recording), item 2 (org move),
    item 7 (flip repo public) — all user actions.
- 2026-07-12 — Cross-review (gpt-5.6-sol, claims independently re-verified
  in-repo) caught that the launch act itself — flipping the private repo
  public — was never a scope item: items 1–6 all prepare for the launch,
  none performs it. Added as item 7, sequenced after the org move and
  hygiene sweep, with an outside-in acceptance check (cold-clone install,
  logged-out badges). The same review re-confirmed the item-2 premise: the
  old org string currently appears in exactly one tracked file (README.md,
  6 occurrences).
- 2026-07-12 — Re-prioritized to start immediately (parallel-track) by the
  2026-07-12 project review; scope grew the security policy (item 5) and the
  supported-platforms statement (item 6) from the same review's
  launch-hygiene findings. The review also ran a filename-level git-history
  sweep (no secret-shaped filenames ever committed) — item 3's content-level
  sweep is still owed.
- 2026-07-11 — Scoped from the 2026-07-11 project review, which found the
  launch tracked only as README checkboxes with no acceptance criteria or
  progress log.

## Decisions

- 2026-07-12 — **Start now, don't wait for reviewer-loop** (supersedes the
  2026-07-11 sequencing decision): v0.10.0 is already a credible launch
  baseline — self-applied, CI-gated, eval-measured, governance-reviewed —
  and deferring the launch for a stronger pitch traded the project's point
  for polish. The reviewer persona strengthens the pitch whenever it ships;
  it gates nothing here.
- 2026-07-11 — Sequenced after reviewer-loop but not blocked on it: the
  launch pitch is stronger with a reviewer persona shipped, but nothing in
  this plan's scope requires it to exist first.

## Next action

Script the demo recording.
