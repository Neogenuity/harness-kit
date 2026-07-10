# Migration Playbooks

The harness landscape converges toward two open standards — hierarchical
`AGENTS.md` for instructions and Agent Skills (`SKILL.md` + `references/`,
`scripts/`, `assets/`) under `.agents/skills/` — and every provider that
adopts them natively makes part of this kit's shim layer unnecessary. That
is the design working as intended: the kit's job is to shrink. This file
records the sunset trigger and the exact steps for each shim, so migration
is a config change, not a rethink.

## Per-provider sunset playbooks

**A provider starts reading `.agents/skills/` natively** (already true for
Codex and OpenCode):

1. Remove the provider's dir from `PROVIDERS` in `scripts/harness.conf`.
2. Delete `<provider>/skills/` (the sync's orphan check will demand this
   anyway).
3. `bash scripts/sync-agent-skills.sh && bash scripts/check-harness.sh`,
   commit stubs + conf together.

**Claude Code ships native `AGENTS.md` loading**
(anthropics/claude-code#34235):

1. Delete `CLAUDE.md` (today just an `@AGENTS.md` import + a verify.sh
   pointer; move any Claude-only lines into AGENTS.md or drop them).
2. Keep `.claude/settings.json` — permissions and hook wiring are separate
   concerns and stay.

**A provider ships native shell hooks** (watch: OpenCode, which today needs
the TS plugin shim):

1. Wire the same `scripts/hooks/*.sh` scripts in the provider's hook config
   per the provider matrix conventions (stdin JSON, exit 2 = deny).
2. Delete the shim (`.opencode/plugins/` for OpenCode).
3. Re-verify payload shapes by piping the provider's real payloads through
   the scripts; extend `lib.sh:hook_affected_files` if a new layout appears.

**Codex hooks graduate from experimental to GA** (happened mid-2026: hooks
are enabled by default, `hooks` is the canonical feature key with
`codex_hooks` a deprecated alias, and the docs moved to
<https://learn.chatgpt.com/docs/hooks>): on installs older than kit 0.4.0,
remove any `[features] codex_hooks = true` line from `.codex/config.toml`
and take the kit update — 0.4.0 also taught the guards Codex's real payload
shape (no file-path field; apply_patch envelopes in `tool_input.command`)
and the Stop hook's JSON-on-exit-0 contract. Re-verify event names and
exit-code semantics against the docs before updating the "verified" stamps.

**A new harness appears**: add its dirs to the matrix first (instructions /
skills / subagents / hooks / permissions / MCP), then: `PROVIDERS` gets its
skills dir only if it doesn't read `.agents/skills/`; hooks wire to the
existing portable scripts; teach `lib.sh:hook_affected_files` its payload
layout if novel; add its native secret-deny config mirroring
`harness.conf:SECRET_PATTERNS`.

## The end state

When every supported harness reads `.agents/skills/` natively, flip the
canonical location and retire the mirror step entirely:

1. `git mv docs/skills .agents/skills` (history preserved).
2. Set `CANONICAL_SKILLS=".agents/skills"` and shrink `PROVIDERS` to the
   dirs still needing stubs (possibly none).
3. Update AGENTS.md links; run the sync + check.

At that point the kit degrades gracefully into what was always the durable
core: the canonical `docs/` knowledge base, the portable hooks with their
tests, `verify.sh`, and the CI drift gate.

## Rules that keep migrations safe

- Never migrate and upgrade in the same commit — do the kit `update` first,
  then the migration, so diffs stay attributable.
- Every step above ends with `bash scripts/check-harness.sh` green before
  commit; the drift gate is exactly the machinery that makes these moves
  cheap.
- Re-pin `scripts/.harness-manifest` when a migration edits mechanism files.
