# Launch readiness

Status: queued

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
   [../../README.md](../../README.md), covering mechanism/update-contract stability
   guarantees and post-1.0 template semver discipline, so adopters know what
   changes are safe across upgrades before committing to the kit.
   *Acceptance: the section exists, is linked from README.md's Status
   section, and states concretely what does and doesn't break across a
   template version bump.*
5. **Security policy** — a root `SECURITY.md`: how to privately report a
   vulnerability in the shipped guard machinery, the expected response
   window, which versions receive fixes pre-1.0, and a pointer to the
   enforcement-layer honesty docs
   ([../conventions/risky-actions.md](../conventions/risky-actions.md)) so
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
linkable and current; `bash scripts/check-harness.sh` link-checks pass on
every doc this plan touches.

## Progress

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
