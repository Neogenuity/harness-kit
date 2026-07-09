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
  indexed by an `AGENTS.md` table of contents (with a thin `CLAUDE.md`
  that `@AGENTS.md`-imports it).
- **An executable definition of "done"** — `scripts/verify.sh` holds the
  ordered quality gates; docs point at it instead of listing commands, and
  its `--fast` subset feeds the advisory stop-hook.
- **Generated provider stubs** — `scripts/sync-agent-skills.sh` renders
  pointer stubs into `.claude/.cursor/.opencode/.agents/skills/` (Codex
  reads `.agents/skills/` natively), copying frontmatter verbatim so
  activation triggers stay in sync, and mirroring skill resource dirs
  (`references/`, `scripts/`, `assets/`) per the Agent Skills standard.
- **Portable hooks** — `scripts/hooks/*.sh` read the hook event JSON on
  stdin and serve every harness: post-edit formatting *plus lint feedback
  the agent self-corrects on*, pre-read secret denial (symlink- and
  case-aware, patterns single-sourced in `harness.conf`), pre-edit
  protection of the harness mechanism and lint configs, an advisory
  stop-hook for project invariants (surfaces warnings exactly once, never
  hard-blocks), and a session-start orientation banner (branch, recent
  commits, active plans). Each guard ships with a regression test and logs
  denies/advisories to a git-ignored JSONL for the audit loop.
- **Shared permissions** — a Claude Code `settings.json` and OpenCode
  `permission` template mirroring the secret patterns; `check-harness.sh`
  fails when the native deny lists drift from the guard.
- **CI drift gate** — `scripts/check-harness.sh` fails the build on
  hand-edited stubs, stale syncs or resource mirrors, dead links anywhere in
  the knowledge base, non-executable hooks, failing hook tests, un-pinned
  edits to mechanism files (manifest checksums), or a native deny list
  missing a secret pattern — plus doctor warnings for silently-weakened
  setups (no jq, oversized AGENTS.md/skills).

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
    provider-matrix.md    per-harness file locations, hook events, payloads (cited)
    migrations.md         sunset playbooks as providers adopt the open standards
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

Private for now, v0.2.0. Provider matrix last validated against primary
harness docs 2026-07 (per-fact "verified" stamps + Sources section in the
matrix; notably Codex hooks are experimental/flag-gated, and Cursor has no
pre-edit event — the CI manifest check backstops guard-config there).
Before open-sourcing: add a LICENSE, re-verify the matrix (hook event names
are still evolving), and scrub any project-specific examples.
