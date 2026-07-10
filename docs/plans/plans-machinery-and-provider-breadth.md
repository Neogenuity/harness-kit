# Plans machinery + provider breadth

Status: queued

## Objective

Ship the execution-plans machinery the kit's docs already promise, and add
the two highest-install-base providers (GitHub Copilot, Gemini CLI) to the
matrix.

## Value

This is the kit's clearest claim-to-implementation gap (validated
2026-07-10): `harness.conf` defines `PLANS_DIR`, `session-context.sh`
announces active plans, `AGENTS.md.tmpl` links `docs/plans/README.md`, and
pattern.md lists `plans/` in the installed anatomy — but no plans template
ships and init never authors one. A user following init ends up with a
harness that references a directory that doesn't exist. Closing it also
implements what Anthropic's long-running-agent guidance calls the necessary
layer beyond compaction: persistent progress + handoff artifacts
(<https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents>).

Copilot and Gemini CLI are near-free breadth: Copilot's coding agent reads
`AGENTS.md` natively — including nested files — since 2025-08
(<https://github.blog/changelog/2025-08-28-copilot-coding-agent-now-supports-agents-md-custom-instructions/>,
validated 2026-07-10); Gemini CLI reads it via the `context.fileName`
setting (<https://geminicli.com/docs/cli/gemini-md/>, validated 2026-07-10).

## Scope

1. **Plans templates**: `templates/docs/plans/README.md` (lifecycle:
   queued → `active/` → `completed/`; announced-at-session-start note;
   theme-naming rule for queued plans) and
   `templates/docs/plans/_template.md` with the required sections —
   Objective, Value, Scope w/ acceptance criteria, Out of scope,
   Dependencies, Verification, Progress, Decisions, Next action.
   *Acceptance: this repo's own `docs/plans/` conforms to the shipped
   template (dogfood).*
2. **init step**: SKILL.md step 5 authors `docs/plans/README.md` + the
   `active/` directory; audit mode flags a configured `PLANS_DIR` whose
   directory is missing. *Acceptance: init on the fixture recipe (scope
   item 6) produces a working plans dir; audit reports the gap when
   absent.*
3. **Plans checks** (mechanism change — template + tests + manifest
   re-pin):
   (a) The existing doc-link check already walks every `docs/**/*.md`,
   plans included — so "plan links must resolve" ships for free; document
   in the plans README template that honesty-critical repo references
   belong in markdown links, while prose/backtick mentions of future paths
   stay legal (queued plans name not-yet-existing files by design — an
   ERROR on non-link path mentions would fail every honest roadmap,
   including this one). This covers the commented "plans reference only
   existing paths" TAILOR example in `check-harness.sh`; nothing further
   to implement for it.
   (b) NEW advisory staleness check in the doctor section: WARN when an
   `active/` plan is missing a `Next action` section, or when its last
   commit (`git log -1 --format=%ct` — file mtime is checkout time in CI)
   is 30+ days old. Effective in local doctor runs; the shipped CI
   workflow uses a shallow checkout that can't see age — state that limit
   in the check's comment. *Acceptance: `test-check-harness.sh` covers the
   missing-Next-action case and the git-age case (skipping gracefully
   outside a git history); manifest re-pinned.*
4. **Provider matrix rows**: GitHub Copilot (instructions: native
   `AGENTS.md`, hierarchical; also reads `.github/copilot-instructions.md`;
   no hooks/skills dirs to wire) and Gemini CLI (instructions: `GEMINI.md`
   default, `AGENTS.md` via `context.fileName`; wire step = a
   `.gemini/settings.json` snippet). Re-verify both against primary docs at
   edit time and stamp per ADR 004. *Acceptance: matrix rows carry fresh
   verified-dates; init step 6 gains both wire steps.*
5. **Doc notes** (cheap, validated 2026-07-10): (a) dynamic workflows —
   workflow files distributed inside skill folders already ride the kit's
   skill-resource mirroring; say so in pattern.md/matrix
   (<https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code>);
   (b) one paragraph in pattern.md positioning hooks as *feedback* and
   OS-level sandboxing as *enforcement*, pointing at the
   execution-governance plan — the matrix already states that interception
   is "a guardrail, not a boundary".
6. **Fixture recipe**: a documented throwaway-fixture recipe (scratch git
   repo with a minimal manifest and one source file) in the kit's
   references, used by this plan's init verification and reused by later
   plans (evals, governance). Automated fresh-repo init tests in CI stay
   out of scope (deferred at the repackage release). *Acceptance:
   following the recipe verbatim yields a repo where init completes and
   `session-context.sh` announces a seeded plan.*

## Out of scope

Eval machinery (behavioral-evals plan); reviewer persona (reviewer-loop
plan); any sandbox/profile *implementation* (execution-governance plan —
only the positioning paragraph lands here).

## Dependencies

The repackage release (v0.5.0) merged — template paths move to
`plugins/harness-kit/`.

## Verification

`bash scripts/verify.sh` green; init dry-run on the scope-item-6 fixture
produces `docs/plans/` and announces it at session start; new check cases
pass standalone; matrix rows stamped.

## Progress

- 2026-07-10 — Hardened after two-agent review: TAILOR-comment claim
  corrected (only one commented example exists; the staleness check is
  new), path-check semantics pinned to markdown links only, staleness age
  defined via git log with the shallow-CI limit stated, fixture recipe
  promoted to an owned scope item, spliced matrix quote replaced with the
  verbatim heading.
- 2026-07-10 — Scoped from a coverage review against current
  harness-engineering practice.

## Decisions

- 2026-07-10 — Plans-before-evals: cheaper, closes a shipped-claim gap, and
  the roadmap itself dogfoods the format.

## Next action

After the repackage ships: draft `templates/docs/plans/_template.md` from
this repo's live plan format.
