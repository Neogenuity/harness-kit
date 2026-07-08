# The Harness Pattern

A standardized way to make one repository legible and safe for *every* AI
coding agent its contributors use — Claude Code, Cursor, Codex, OpenCode, and
whatever ships next — without maintaining N parallel configurations.

## Design principles

1. **Single source of truth in `docs/`.** All knowledge an agent needs —
   architecture, conventions, task workflows (skills), personas (agents) —
   lives in plain markdown under `docs/`, where humans also read and review
   it. Provider directories never hold original content.

2. **Provider shims are generated or thin.** Each harness needs files in its
   own dialect and location (`.claude/skills/`, `.cursor/rules/`, ...). Those
   are either *generated pointer stubs* (skills — produced by
   `scripts/sync-agent-skills.sh`) or *hand-written thin pointers* (agent
   personas, cursor rules) that carry only the harness-required frontmatter
   plus a "Canonical source: docs/..." line. Frontmatter is copied verbatim
   from the canonical file because the `description` is the activation
   trigger — tuning it in `docs/` must propagate to every harness.

3. **Behavior lives in portable executables, not harness config.** Hooks are
   plain bash scripts in `scripts/hooks/` that read the event JSON on stdin
   and tolerate every harness's field layout. Per-provider hook configs
   (`.claude/settings.json`, `.cursor/hooks.json`) are one-line wirings. This
   keeps policy identical across harnesses and testable in isolation.

4. **Drift is a CI failure, not a code-review hope.** `scripts/check-harness.sh`
   fails the build when a stub is hand-edited, a canonical skill changes
   without a re-sync, a stub is missing from a provider dir, an AGENTS.md
   link goes dead, or a hook regression test breaks. The pattern survives
   only because divergence is mechanically impossible to merge.

5. **Guards are layered and fail open.** Secret-file reads are denied both by
   the portable hook (works in every harness, symlink- and case-aware) and by
   the harness's native permission deny list (works even when hooks don't
   fire, e.g. some subagent contexts). Advisory checks (project invariants)
   warn the agent exactly once and never hard-block — the enforcing gate is
   tests/CI.

## Anatomy of an installed harness

```
AGENTS.md                      # table of contents; native instructions for Codex/OpenCode
CLAUDE.md                      # thin pointer to AGENTS.md + quality gates
docs/
  architecture/                # canonical architecture docs
  conventions/                 # one doc per topic agents get wrong
  skills/<slug>/SKILL.md       # canonical task workflows (frontmatter = trigger)
  agents/<name>.md             # canonical persona docs
  plans/                       # execution plans (surfaced by session-context.sh)
scripts/
  harness.conf                 # shared tailoring surface (providers, paths)
  sync-agent-skills.sh         # stub generator (+ --check mode, orphan detection)
  check-harness.sh             # CI drift gate
  .harness-manifest            # kit version + checksums (upgrade bookkeeping)
  hooks/
    lib.sh                     # stdin parsing, deny, advise-once protocol
    format.sh                  # post-edit formatter dispatch      [tailored]
    guard-secrets.sh           # pre-read secret denial            [tailored]
    guard-project-policy.sh    # advisory stop-hook invariants     [tailored]
    session-context.sh         # session-start orientation banner
    test-*.sh                  # regression tests, run by check-harness.sh
.claude/   settings.json (permissions + hook wiring), skills/ (stubs), agents/ (thin)
.cursor/   hooks.json, rules/*.mdc (thin), skills/ (stubs), agents/ (thin), mcp.json
.codex/    config.toml (MCP), skills/ (stubs)
.opencode/ skills/ (stubs)          + opencode.json (MCP) at root
.agents/   skills/ (stubs)          # emerging cross-vendor standard location
```

## The three layers (what to copy vs. generate)

| Layer | Examples | Packaging treatment |
| --- | --- | --- |
| **Mechanism** | sync script, check script, lib.sh, hook tests | Copied verbatim; upgraded via manifest |
| **Policy** | secret patterns, formatter map, permission allowlist, plans dir | Templates with marked `TAILOR` blocks; filled at init |
| **Content** | AGENTS.md, conventions, skills, personas, invariant checks | Authored per-project; kit provides skeletons + interview |

## Why stubs instead of symlinks or full copies

- Full copies drift — the moment two files can disagree, they will.
- Symlinks break on Windows checkouts, in some harness file readers, and in
  code review UIs.
- Generated stubs are real files (portable), tiny (reviewable), carry the
  verbatim frontmatter (correct activation), and are pinned to the generator
  output by CI (cannot drift).

The stub-size cap in `check-harness.sh` (25 lines) exists so full copies
cannot quietly reappear — any provider SKILL.md that grows past a pointer
fails the build.

## Upgrade model

At install, the kit writes `scripts/.harness-manifest`: the kit version plus
a sha256 per installed mechanism file. On `update`, files whose checksum
still matches the manifest are upgraded in place; files that differ were
tailored by the project, so the kit shows a diff instead of overwriting.
Policy templates (TAILOR blocks) are always treated as tailored after init.
