# Migration Playbooks

The harness landscape converges toward two open standards — hierarchical
`AGENTS.md` for instructions and Agent Skills (`SKILL.md` + `references/`,
`scripts/`, `assets/`) under `.agents/skills/` — and every provider that
adopts them natively makes part of this kit's shim layer unnecessary. That
is the design working as intended: the kit's job is to shrink. This file
records release-adoption and shim-sunset steps, so migration is a bounded
mechanism/policy/content decision rather than a rethink.

## v0.17.0 local-outcome and doc-garden adoption

For an install from v0.16 or earlier, keep mechanism, policy, and content
decisions separate:

1. Run update with the new kit's `install-lib.sh`. Its inventory adds
   `scripts/log-lib.sh`, `scripts/audit-log.sh`, `scripts/doc-garden.sh`, and
   their tests. It replaces a manifest-matching `scripts/hooks/lib.sh`; a
   changed copy gets a diff. Do not rewrite the existing mixed local log.
2. Treat `scripts/verify.sh` as tailored policy even when its old checksum is
   known. Review and explicitly approve the v2 gate-instrumentation diff. If it
   is declined, guard/reviewer data remains readable but gate trends are
   no-data/N/A.
3. Re-pin the approved mechanism/policy state and run the focused log, reducer,
   scanner, update, and harness tests.
4. Offer `docs/conventions/outcome-telemetry.md` and its AGENTS link as
   self-contained content; never point an installed repo back into the plugin.
5. Separately offer `docs/skills/doc-garden/SKILL.md`, its conditional AGENTS
   link, and regenerated stubs. Declining the skill is valid. Adoption grants no
   schedule, network probe, edit, commit, push, or PR authority.

A second update must be a no-op. Existing content and generated stubs are never
auto-added or overwritten; `hooks/lib.sh` and the new helpers follow manifest
checksums, while `verify.sh` stays diff-only.

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

**A provider ships native shell hooks** (watch: OpenCode, whose portable-hook
reuse would take the TS plugin shim — not shipped, descoped 2026-07-13):

1. Wire the same `scripts/hooks/*.sh` scripts in the provider's hook config
   per the provider matrix conventions (stdin JSON, exit 2 = deny).
2. Delete any hand-rolled shim (`.opencode/plugins/` for OpenCode); the kit
   ships none by default.
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

**A provider ships a plugin/marketplace distribution channel** (Codex gaining
`codex plugin marketplace add` was the first — kit 0.5.0): the distributed
plugin already lives at `plugins/harness-kit/`, so add the provider's manifest
beside the existing one — zero content duplication.

1. Re-verify the provider's plugin + marketplace schema against its primary
   docs and stamp the matrix **Distribution** row (ADR 004 discipline). The
   two providers rarely share a shape — Claude Code's marketplace
   `plugins[].source` is a flat `"./…"` string; Codex's is a nested object
   with required `policy`/`category` — so the two marketplace files are not
   copy-paste twins.
2. Add `plugins/harness-kit/.<provider>-plugin/plugin.json`
   (name/version/description + the provider's skills-path key), version equal
   to `VERSION`.
3. Add or extend the root marketplace file in the provider's convention
   (Codex: `.agents/plugins/marketplace.json`), its source pointing at
   `./plugins/harness-kit`.
4. Extend `check-packaging.sh` to validate the new manifest and marketplace
   entry — schema, name agreement, version == `VERSION`, a contained
   `./`-relative source path.
5. `bash scripts/verify.sh` green. Releases bump `VERSION` and every
   `plugin.json` version together (the packaging gate enforces equality); see
   ADR 007.

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
