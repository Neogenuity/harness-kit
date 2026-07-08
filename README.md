# harness-kit

A portable kit for standing up a **standardized, cross-agent harness** in any
repository — one canonical knowledge base that Claude Code, Cursor, Codex,
OpenCode, and `.agents`-standard tools all consume, with provider-agnostic
hooks, generated skill stubs, shared permissions, and a CI drift gate.

Extracted and generalized from a production Laravel modular monolith where
the pattern is exercised daily across multiple harnesses.

## What it installs into a target repo

- **`docs/` as single source of truth** — architecture, conventions,
  skills (`docs/skills/<slug>/SKILL.md`), agent personas (`docs/agents/`),
  indexed by an `AGENTS.md` table of contents (with a thin `CLAUDE.md`).
- **Generated provider stubs** — `scripts/sync-agent-skills.sh` renders
  pointer stubs into `.claude/.cursor/.codex/.opencode/.agents/skills/`,
  copying frontmatter verbatim so activation triggers stay in sync.
- **Portable hooks** — `scripts/hooks/*.sh` read the hook event JSON on
  stdin and serve every harness: post-edit formatting, pre-read secret
  denial (symlink- and case-aware), an advisory stop-hook for project
  invariants (surfaces warnings exactly once, never hard-blocks), and a
  session-start orientation banner. Each guard ships with a regression test.
- **Shared permissions** — a Claude Code `settings.json` template pairing the
  secret-read hook with a native deny list, plus a quality-gate allowlist.
- **CI drift gate** — `scripts/check-harness.sh` fails the build on
  hand-edited stubs, stale syncs, dead AGENTS.md links, non-executable
  hooks, or failing hook tests.

The kit **vendors everything into the target repo**: nothing at runtime
depends on this kit being installed, so teammates on any harness get
identical behavior from a plain clone.

## Layout

```
.claude-plugin/           plugin + marketplace manifests
skills/harness-kit/
  SKILL.md                the skill: init / audit / add-* / update workflows
  references/
    pattern.md            the architecture and its rationale
    provider-matrix.md    per-harness file locations, hook events, payloads
  templates/
    AGENTS.md.tmpl, CLAUDE.md.tmpl
    docs/                 skill + agent authoring templates
    scripts/              the vendored machinery (sync, check, hooks, tests)
    providers/            claude / cursor / codex / opencode config shims
    ci/                   GitHub Actions drift-gate job
```

## Install

**As a Claude Code plugin** (recommended — versioned, updatable):

```
/plugin marketplace add riotCode/harness-kit
/plugin install harness-kit@harness-kit
```

**As a personal skill** (no plugin infrastructure):

```bash
cp -R skills/harness-kit ~/.claude/skills/harness-kit
```

## Use

In any repo: *"set up the agent harness"* (init), *"audit the agent
harness"* (audit), *"add a harness skill for X"*, or *"upgrade the harness
machinery"* (update). The skill intentionally interviews before writing:
quality gates, conventions worth documenting, first skills, and the one
domain invariant worth an advisory stop-hook.

## Status

Private for now. Before open-sourcing: add a LICENSE, re-verify the provider
matrix against current harness docs (hook event names are still evolving),
and scrub any project-specific examples.
