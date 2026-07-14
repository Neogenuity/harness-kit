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
   are either *generated pointer stubs* (skills AND agent personas — both
   produced by `scripts/sync-agent-skills.sh`, in each provider's dialect:
   `.codex` agent stubs are TOML, the rest Markdown) or *hand-written thin
   pointers* (cursor rules) that carry only the harness-required frontmatter
   plus a "Canonical source: docs/..." line. Frontmatter is copied from the
   canonical file because the `description` is the activation/routing
   trigger — tuning it in `docs/` must propagate to every harness.

3. **Behavior lives in portable executables, not harness config.** Hooks are
   plain bash scripts in `scripts/hooks/` that read the event JSON on stdin
   and tolerate every harness's field layout. Per-provider hook configs
   (`.claude/settings.json`, `.cursor/hooks.json`, `.codex/hooks.json`) are
   one-line wirings; an OpenCode plugin shim is the documented fourth path,
   but the kit ships no shim template yet (descoped 2026-07-13), so OpenCode
   is not hook-wired. This keeps policy identical across harnesses and
   testable in isolation.

4. **Drift is a CI failure, not a code-review hope.** `scripts/check-harness.sh`
   fails the build when a stub is hand-edited, a canonical skill changes
   without a re-sync, a stub is missing from a provider dir, an AGENTS.md
   link goes dead, or a hook regression test breaks. The pattern survives
   only because divergence is mechanically impossible to merge.

5. **Guards are layered, fail open, and guard the harness itself.**
   Secret-file reads are denied both by the portable hook (works in every
   harness, symlink- and case-aware; patterns single-sourced in
   `harness.conf`) and by the harness's native permission deny list (works
   even when hooks don't fire, e.g. some subagent contexts) —
   `check-harness.sh` fails when the two drift apart. The mechanism is
   protected from the agent too: `guard-config.sh` denies edits to hook
   scripts, machinery, and lint configs, and the manifest checksum
   verification in CI catches whatever the hook can't see. Advisory checks
   (project invariants) warn the agent exactly once and never hard-block —
   the enforcing gate is tests/CI.

6. **Verification is executable, and feedback lands at the fastest layer.**
   `scripts/verify.sh` is the one executable definition of "done"; AGENTS.md,
   CLAUDE.md, and skills point at it instead of listing commands, so the
   gates cannot drift across docs. Independent full gates can use its explicit
   parallel queue; serial gates retain cheap-first, fail-fast behavior. The same
   policy runs at three latencies:
   the post-edit hook feeds lint findings back within the turn
   (milliseconds), the advisory stop-hook can run `verify.sh --fast`
   (seconds), CI runs everything (minutes). Agents can't ignore a failing
   gate the way they ignore prose.

7. **Observability closes the loop.** Every deny, advisory, and lint finding
   appends one JSON line to `.harness/log.jsonl` (git-ignored). The audit
   workflow summarizes it: a guard that fires repeatedly on the same path is
   the signal for what to engineer away permanently — tighten a pattern, add
   a lint rule, write the convention doc.

**Hooks are feedback; the sandbox is enforcement.** Pre-tool interception is a
*guardrail, not a boundary* — an agent can usually reach the same effect
through another supported tool path, so the provider matrix labels interception
exactly that way. The kit leans on hooks for fast, in-turn *feedback* (deny a
secret read, feed a lint finding back, advise once) and on the harness's native
permission/trust layers plus the CI manifest check as the layers that actually
hold. *Enforcement* proper — OS-level sandboxing, network-egress control,
filesystem scoping — is a platform capability the kit's job is to **configure**,
not reimplement. The hostile-input and risky-output guidance now ships as
convention docs (installed at `docs/conventions/untrusted-content.md` and
`docs/conventions/risky-actions.md`); the advanced per-provider enforcement
surface is scoped in the queued `docs/plans/execution-sandbox-profiles.md`.

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
  harness.conf                 # shared tailoring surface (providers, paths,
                               #   secret patterns, log toggle)     [tailored]
  verify.sh                    # executable "done": ordered quality gates
                               #   (--fast subset for the stop-hook) [tailored]
  sync-agent-skills.sh         # stub + skill-resource mirror generator
                               #   (+ --check mode, orphan detection)
  check-harness.sh             # CI drift gate + manifest integrity + doctor
  .harness-manifest            # kit version + checksums (upgrade + CI integrity)
  hooks/
    lib.sh                     # stdin parsing, deny, feedback, advise-once, hook_log
    format.sh                  # post-edit format + lint feedback  [tailored]
    guard-secrets.sh           # pre-read secret denial (patterns from harness.conf)
    guard-config.sh            # pre-edit mechanism/lint-config protection [tailored]
    guard-project-policy.sh    # advisory stop-hook invariants     [tailored]
    session-context.sh         # session-start orientation banner (branch,
                               #   recent commits, active plans)
    test-*.sh                  # regression tests, run by check-harness.sh
.harness/                      # hook event log (JSONL, git-ignored)
.claude/   settings.json (permissions + hook wiring), skills/ (stubs), agents/ (thin)
.cursor/   hooks.json, rules/*.mdc (thin), skills/ (stubs), agents/ (thin), mcp.json
.codex/    config.toml (MCP), hooks.json, agents/*.toml (thin)   # skills come from .agents/
.opencode/ skills/ (stubs), agents/ (thin) + opencode.json (MCP + native denies) at root   # hook shim documented, not shipped (descoped 2026-07-13)
.agents/   skills/ (stubs)          # cross-vendor standard; also read by Codex + OpenCode
```

## The three layers (what to copy vs. generate)

| Layer | Examples | Packaging treatment |
| --- | --- | --- |
| **Mechanism** | sync script, check script, lib.sh, hook tests | Copied verbatim; upgraded via manifest; integrity-checked in CI |
| **Policy** | quality gates (verify.sh), secret patterns, formatter/lint maps, protected paths, permission allowlist, plans dir | Templates with marked `TAILOR` blocks; filled at init; never auto-overwritten |
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

Skill *resource* directories (`references/`, `scripts/`, `assets/` per the
Agent Skills standard) are the deliberate exception: the generator mirrors
them verbatim next to each stub so harnesses that resolve resources relative
to the skill directory keep working, and `--check` pins the mirrors
recursively — full copies, but mechanically incapable of drifting.

This is also how **dynamic workflows** ride along: a workflow markdown file
distributed *inside* a skill's folder (its `references/` or the skill dir) is
mirrored to every provider stub by the same mechanism, so a skill can carry its
own step-by-step playbooks — invoked mid-task — with no extra wiring and no
drift.

## Upgrade model

At install, the kit writes `scripts/.harness-manifest`: the kit version plus
a sha256 per installed mechanism file, pinned AFTER init-time tailoring.
`check-harness.sh` verifies those checksums on every run, so any later edit
— agent, human, or merge — fails CI until its line is deliberately re-pinned.
A line suffixed ` # tailored` marks a deliberate local fork: its checksum is
**still** integrity-verified (a tailored file may not drift unnoticed — the
marker only exempts it from template *replacement*, not from pinning), but
`update` will only ever diff that file, never replace it. On `update`, files
whose checksum still matches the manifest are
upgraded in place; files that differ (or are marked tailored) get a diff
instead of an overwrite. Policy templates (TAILOR blocks) are always treated
as tailored after init.
