# harness-kit

**One canonical knowledge base for every coding agent — Claude Code, Cursor,
Codex, OpenCode — with CI that fails when it drifts.**

[![ci](https://github.com/riotCode/harness-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/riotCode/harness-kit/actions/workflows/ci.yml)
[![harness-check](https://github.com/riotCode/harness-kit/actions/workflows/harness-check.yml/badge.svg)](https://github.com/riotCode/harness-kit/actions/workflows/harness-check.yml)

A **harness** is everything that surrounds the model when an agent works in
your repo: the docs it's fed, the skills it can activate, the hooks that
guard and give feedback, the permissions, the quality gates. Every agent
vendor wants those in its own dialect and directory — so teams end up with
N parallel configurations that disagree within a month, and agents that
confidently act on the stale one. harness-kit scaffolds one canonical,
enforced harness instead:

```mermaid
flowchart LR
    D["docs/<br/>one canonical knowledge base<br/>(architecture, conventions, skills)"]
    V["scripts/verify.sh<br/>executable definition of done"]
    G["generated stubs<br/>.claude/ .cursor/ .opencode/ .agents/"]
    H["portable hooks<br/>guards + lint feedback, any harness"]
    CI["check-harness.sh (CI)<br/>drift is a build failure"]
    D -->|sync-agent-skills.sh| G
    D --> V
    H --> CI
    G --> CI
    V --> CI
```

## This repo runs on itself

The root of this repository is a live installation of the kit — the same
`AGENTS.md`, `docs/`, vendored `scripts/`, provider wiring, and CI drift
gate it installs into your repo, produced by its own `init` flow. Browse it
as the example: start at [AGENTS.md](AGENTS.md), then
[docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) for
how the pieces fit and
[docs/architecture/decisions/](docs/architecture/decisions/README.md) for
why they look the way they do. Only [plugin/](plugin/) ships to users;
everything else is the dogfood.

## What it installs into a target repo

- **`docs/` as the single source of truth** — architecture, conventions,
  skills, personas, indexed by an `AGENTS.md` table of contents (with a thin
  `CLAUDE.md` importing it).
- **An executable definition of "done"** — `scripts/verify.sh` holds the
  ordered quality gates; docs point at it instead of listing commands.
- **Generated provider stubs** — pointer stubs rendered into
  `.claude/.cursor/.opencode/.agents/skills/` with frontmatter copied
  verbatim, so activation triggers stay in sync everywhere.
- **Portable hooks** — plain bash, reading each harness's event JSON:
  post-edit lint feedback the agent self-corrects on, pre-read secret
  denial, pre-edit protection of the harness mechanism itself, an advisory
  stop-hook for project invariants (warns once, never hard-blocks), and a
  session-start orientation banner. Every guard ships with a regression
  test and logs to a git-ignored JSONL for the audit loop.
- **Shared permissions** — native deny lists mirroring the secret patterns;
  CI fails when the two layers drift apart.
- **A CI drift gate** — hand-edited stubs, stale syncs, dead doc links,
  non-executable hooks, failing hook tests, or un-pinned edits to mechanism
  files (manifest checksums) all fail the build.

Everything is **vendored into the target repo**: nothing at runtime depends
on the kit being installed, so teammates on any harness — or none — get
identical behavior from a plain clone. The full pattern and its rationale:
[pattern.md](plugin/skills/harness-kit/references/pattern.md); per-provider
file locations and hook events (key facts carrying verification stamps, with
a Sources section to re-check against):
[provider-matrix.md](plugin/skills/harness-kit/references/provider-matrix.md).

## Install

**As a Claude Code plugin** (recommended — versioned, updatable):

```
/plugin marketplace add riotCode/harness-kit
/plugin install harness-kit@harness-kit
```

**As a personal skill** (no plugin infrastructure):

```bash
cp -R plugin/skills/harness-kit ~/.claude/skills/harness-kit
```

## Use

In any repo: *"set up the agent harness"* (init), *"audit the agent
harness"* (audit), *"add a harness skill for X"*, or *"upgrade the harness
machinery"* (update). The skill intentionally interviews before writing:
quality gates, conventions worth documenting, first skills, and the one
domain invariant worth an advisory stop-hook.

## Layout

```
.claude-plugin/marketplace.json   marketplace manifest (points at plugin/)
plugin/                           what ships: plugin manifest + the skill
  skills/harness-kit/             SKILL.md, references/, templates/
AGENTS.md, CLAUDE.md, docs/,      this repo's own installed harness
scripts/, .claude/ .cursor/ ...   (see "This repo runs on itself")
```

## Status

v0.3.0, extracted and generalized from a production Laravel modular
monolith where the pattern is exercised daily across multiple harnesses.
Pre-launch checklist:

- [x] MIT license
- [x] Self-application (this repo runs its own harness, CI-gated)
- [ ] Re-verify the provider matrix against current harness docs (hook
      event names are still evolving; last validated 2026-07)
- [ ] Demo recording of `init` on a fresh repo
- [ ] Move to the `neogenuity` org and update install commands

## License

[MIT](LICENSE)
