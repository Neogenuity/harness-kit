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

7. **Runnable apps have one worktree-scoped control surface.** Application
   repos author `scripts/dev.sh up|health|seed|down` against the development
   runtime convention. Each recognized action emits one JSON v1 object, so a
   live-verification skill can start or reuse the app, reset deterministic data,
   find its logs/traces, and clean up without guessing stack-specific commands.
   The script is tailored project policy, manifest-pinned and diff-only; the kit
   ships a physical-worktree identity/port helper, not a generic `dev.sh`.
   Non-app repos omit the whole runtime bundle.

8. **Execution profiles are declared, provider-specific policy.** A repo adopts
   the stable floor one provider at a time through
   `EXECUTION_PROFILE_PROVIDERS`; an unset or empty declaration remains a valid
   unadopted harness. Semantic drift checks validate only declared providers
   and never infer adoption from surviving config files. The self-contained
   `docs/conventions/execution-profiles.md` records exact tuples, temp roots,
   local-runtime network availability and lifecycle limits, admin-only limits,
   and conditional validation prerequisites such as Python 3.11+ `tomllib` for
   complete Codex parsing.
   OpenCode's permission prompts
   are named honestly rather than presented as an OS or network sandbox.

9. **Observability closes the loop.** Denies, advisories, lint findings, and
   verification gate outcomes append JSON lines to `.harness/log.jsonl`
   (git-ignored). Exact five-key v1 review findings coexist with an eight-key
   `version: 2` event envelope; the deterministic `audit-log.sh` reducer owns
   rates, retries, repeated paths, review counts, eval drift, and explicit N/A
   states. A guard or gate that fails repeatedly is the signal for what to engineer away
   permanently. Attribution is explicit-only: absent session/provider/plan
   metadata remains unknown, and plan cycles or PRs are never invented from
   prose. Provider telemetry remains a separate stream with its own scope,
   schema, retention, and privacy controls; the kit installs no collector or
   automatic cross-stream join.

**Hooks are feedback; the sandbox is enforcement.** Pre-tool interception is a
*guardrail, not a boundary* — an agent can usually reach the same effect
through another supported tool path, so the provider matrix labels interception
exactly that way. The kit leans on hooks for fast, in-turn *feedback* (deny a
secret read, feed a lint finding back, advise once) and on the harness's native
permission/trust layers plus the CI manifest check as the layers that actually
hold. *Enforcement* proper — OS-level sandboxing, network-egress control,
filesystem scoping — is a platform capability the kit's job is to **configure**,
not reimplement. The hostile-input, risky-output, and adopted execution-profile
guidance ships as self-contained convention docs under `docs/conventions/`.
A devcontainer is an init-authored optional boundary from a confirmed image,
Dockerfile, or Compose source, never a placeholder template.

## Anatomy of an installed harness

```
AGENTS.md                      # table of contents; native instructions for Codex/OpenCode
CLAUDE.md                      # thin pointer to AGENTS.md + quality gates
docs/
  architecture/                # canonical architecture docs
  conventions/                 # one doc per topic agents get wrong
    dev-runtime.md             # app-only dev.sh JSON/lifecycle contract [tailored]
    execution-profiles.md      # adopted provider floors + limits [tailored]
    outcome-telemetry.md       # mixed local-event schema + privacy/trend contract
  skills/                      # canonical task workflows (frontmatter = trigger)
    <slug>/SKILL.md
    doc-garden/SKILL.md        # optional offline doc-health workflow
    verify-live/SKILL.md       # app-only reproduce/observe/rerun workflow [tailored]
  agents/<name>.md             # canonical persona docs
  plans/                       # execution plans (surfaced by session-context.sh)
scripts/
  harness.conf                 # shared tailoring surface (providers, paths,
                               #   secret patterns, log toggle)     [tailored]
  verify.sh                    # executable "done": ordered quality gates
                               #   (--fast subset for the stop-hook) [tailored]
  dev.sh                       # app-only runtime adapter: up/health/seed/down
                               #   (authored per repo; no generic template) [tailored]
  dev-instance.sh              # physical-worktree suffix + port candidate helper
  log-lib.sh                   # fail-open v2 event writer helpers
  audit-log.sh                 # deterministic local outcome/eval reducer
  doc-garden.sh                # offline repository documentation scanner
  sync-agent-skills.sh         # stub + skill-resource mirror generator
                               #   (+ --check mode, orphan detection)
  check-harness.sh             # CI drift gate + manifest integrity + doctor
  kit-manifest                 # ship contract: layer per shipped path + retired set
  .harness-manifest            # kit version + checksums (upgrade + CI integrity)
  hooks/
    lib.sh                     # stdin parsing, deny, feedback, advise-once, hook_log
    format.sh                  # post-edit format + lint feedback (rules from harness.conf)
    guard-secrets.sh           # pre-read secret denial (patterns from harness.conf)
    guard-config.sh            # pre-edit mechanism/lint-config protection [tailored]
    guard-project-policy.sh    # advisory stop-hook invariants     [tailored]
    session-context.sh         # session-start orientation banner (branch,
                               #   recent commits, active plans)
    test-*.sh                  # regression tests, run by check-harness.sh
.harness/                      # local harness state (git-ignored)
  log.jsonl                    # mixed hook/review/verification outcome log
  dev/                         # app-only, worktree-scoped runtime state/logs/traces
.claude/   settings.json (permissions + hooks + optional declared profile), skills/, agents/
.cursor/   hooks.json, sandbox.json (optional declared profile), rules/, skills/, agents/, mcp.json
.codex/    config.toml (optional declared profile + MCP), hooks.json, agents/*.toml   # skills from .agents/
.opencode/ skills/, agents/ + opencode.json (MCP + native denies + optional declared permission profile)
.agents/   skills/ (stubs)          # cross-vendor standard; also read by Codex + OpenCode
```

## The three layers (what to copy vs. generate)

| Layer | Examples | Packaging treatment |
| --- | --- | --- |
| **Mechanism** | sync script, check script, lib.sh, hook tests, `dev-instance.sh` | Copied verbatim; upgraded via manifest; integrity-checked in CI |
| **Policy** | quality gates (verify.sh), secret patterns, formatter/lint maps and extra protected paths (harness.conf data), permission allowlist, plans dir; app-only authored `dev.sh` | Templates with marked `TAILOR` blocks, or repo-authored adapters where no generic mechanism can fit; pinned after init and never auto-overwritten |
| **Content** | AGENTS.md, conventions, skills, personas, invariant checks; app-only tailored runtime convention/skill | Authored or tailored per-project; kit provides skeletons + interview |

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
a sha256 per installed mechanism file, pinned AFTER init-time tailoring. In an
application repo it also pins the authored `scripts/dev.sh` with a
` # tailored` marker; the marker makes it diff-only, not exempt from integrity.
`check-harness.sh` verifies those checksums on every run, so any later edit
— agent, human, or merge — fails CI until its line is deliberately re-pinned.
A line suffixed ` # tailored` marks a deliberate local fork: its checksum is
**still** integrity-verified (a tailored file may not drift unnoticed — the
marker only exempts it from template *replacement*, not from pinning), but
`update` will only ever diff that file, never replace it. On `update`, files
whose checksum still matches the manifest are
upgraded in place; files that differ (or are marked tailored) get a diff
instead of an overwrite. Policy templates (TAILOR blocks) and authored policy
adapters are always treated as tailored after init. Update uses the NEW kit's
`templates/scripts/install-lib.sh` and its `kit-manifest` — the declarative
ship contract every file set derives from — to enumerate the new version's
mechanism: an old installed helper cannot discover files that did not exist
when it shipped. The kit-manifest's `retired` section lets update *remove* a
file the kit no longer ships, but only a pristine, untailored copy — drifted
or tailored copies are kept and reported, so retirement can never delete
local changes. New content such as the app-only convention and skill is
offered as an explicit opt-in and is never auto-added or overwritten.
