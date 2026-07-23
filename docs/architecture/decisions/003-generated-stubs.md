# ADR 003 — Generated pointer stubs, not symlinks or copies

**Status:** accepted (v0.1.0); amended v0.24.0 — canonical home moved from
`docs/skills/` to `.agents/skills/`

## Context

Every harness wants skills in its own directory (`.claude/skills/`,
`.cursor/skills/`, `.opencode/skills/`, `.agents/skills/`). The canonical
content lives once — originally in `docs/skills/`, beside the rest of the
knowledge base. Three ways to bridge: full copies, symlinks, or generated
stubs.

## Decision

`scripts/harness/sync` generates **tiny pointer stubs** — verbatim
frontmatter (the `description` is the activation trigger, so it must stay
identical everywhere) plus a `Canonical source: ...` line — and CI pins
stubs to the generator's exact output.

- Full copies drift: the moment two files can disagree, they will.
- Symlinks break on Windows checkouts, in some harness file readers, and in
  review UIs.
- Stubs are real files (portable), tiny (reviewable), and mechanically
  incapable of drifting because `check-harness` fails the build on any
  hand-edit, missing stub, or stale sync.

A 25-line stub-size cap prevents full copies from quietly reappearing. Skill
*resource* directories (`references/`, `scripts/`, `assets/`) are the
deliberate exception — mirrored verbatim so relative-path resolution works,
but pinned recursively by `--check`.

### Amendment (v0.24.0, standard-consumer-layout Phase 4)

The canonical home moves from `docs/skills/` to **`.agents/skills/`** — the
emerging cross-vendor standard location, which Codex (and compatible tools)
read natively. `.agents` therefore leaves the stub `PROVIDERS` set: the
canonical files ARE its content, and generating a stub over the canonical
home would overwrite the source with a pointer to itself. Stubs continue to
be generated for `.claude/`, `.cursor/`, and `.opencode/`
(`CANONICAL_SKILLS` remains the override knob). Everything else in this ADR
— stub shape, size cap, resource mirroring, CI pinning — is unchanged.

## Consequences

- Editing a canonical skill requires re-running the sync — forgetting is a
  CI failure, not silent staleness.
- Generated files live in the repo (reviewable diffs) at the cost of some
  checked-in redundancy.
- Since v0.24.0, a repo whose tools all read `.agents/skills/` natively can
  set `PROVIDERS=""` and carry zero stubs — the sunset path
  the migrations playbook always described, now the default direction.
