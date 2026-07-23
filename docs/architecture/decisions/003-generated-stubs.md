# ADR 003 — Generated pointer stubs, not symlinks or copies

**Status:** accepted (v0.1.0)

## Context

Every harness wants skills in its own directory (`.claude/skills/`,
`.cursor/skills/`, `.opencode/skills/`, `.agents/skills/`). The canonical
content lives once, in `docs/skills/`. Three ways to bridge: full copies,
symlinks, or generated stubs.

## Decision

`scripts/harness/sync` generates **tiny pointer stubs** — verbatim
frontmatter (the `description` is the activation trigger, so it must stay
identical everywhere) plus a `Canonical source: docs/skills/...` line — and
CI pins stubs to the generator's exact output.

- Full copies drift: the moment two files can disagree, they will.
- Symlinks break on Windows checkouts, in some harness file readers, and in
  review UIs.
- Stubs are real files (portable), tiny (reviewable), and mechanically
  incapable of drifting because `check-harness.sh` fails the build on any
  hand-edit, missing stub, or stale sync.

A 25-line stub-size cap prevents full copies from quietly reappearing. Skill
*resource* directories (`references/`, `scripts/`, `assets/`) are the
deliberate exception — mirrored verbatim so relative-path resolution works,
but pinned recursively by `--check`.

## Consequences

- Editing a canonical skill requires re-running the sync — forgetting is a
  CI failure, not silent staleness.
- Generated files live in the repo (reviewable diffs) at the cost of some
  checked-in redundancy.
