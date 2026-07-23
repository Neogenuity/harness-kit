# Editing the shipped templates

Rules for changing anything under `plugins/harness-kit/skills/harness-kit/templates/` —
the code this kit installs into other people's repositories. Reviewers
correct these most often; the advisory stop-hook and CI enforce the
mechanical ones.

## Every guard ships with a regression test

A new or changed hook under `templates/scripts/harness/hooks/` gets a matching
`test-<name>.sh` beside it, runnable standalone. A guard without a test is a
future silent failure — the hook will break on some payload shape and nobody
will notice, because hooks fail open by design. CI runs every template test;
the stop-hook warns when a template change touches no test.

## Hooks fail open, deny with exit 2, and tolerate every payload layout

- Any missing dependency (jq, git), empty stdin, or unknown JSON shape must
  `exit 0` — never break a contributor's agent turn.
- Denial is `hook_deny` (exit 2) with a reason that names the guard script
  and the escape hatch.
- Read event fields through `lib.sh` helpers (`hook_affected_files`,
  `hook_command_string`, …), never with a layout assumed from one harness.
  Cursor puts `file_path` at the top level; Claude Code nests it under
  `tool_input`; Codex sends no file path at all — affected files hide in
  the `tool_input.command` apply_patch envelope.

## Policy is TAILOR blocks; mechanism is everything else

Anything a target repo must customize lives inside a marked
`# -- TAILOR: ... --` block with commented examples; everything outside the
blocks is mechanism, replaced wholesale on upgrade. Never make a target repo
edit mechanism lines — if a customization point is missing, add a TAILOR
block or a `harness.conf` variable, don't tell users to fork the script.

## Secret patterns are single-sourced

`SECRET_PATTERNS` in `harness.conf` drives the read guard; the provider
deny-list templates (`providers/claude/settings.json`, opencode
`permission.read`) must mirror it, and every addition gets a
`test-guard-secrets.sh` case. `check-harness.sh` verifies the mirrors in
installed repos — keep the templates consistent so fresh installs start
consistent.

## Provider-matrix facts need a verified stamp

When you add or change a load-bearing statement in
`references/provider-matrix.md` (file locations, hook events, payload shapes),
give it a `verified YYYY-MM` stamp cross-referenced to the file's Sources
section (see
[ADR 004](../architecture/decisions/004-provider-matrix-verification.md)) —
for the fact you touched, no stamp means no merge. Unstable facts
(experimental, flag-gated) say so.

## Shell style

`shellcheck -x --severity=warning` clean (info/style notices are acceptable —
TAILOR blocks keep commented arms next to live code). BSD/GNU portable:
macOS ships BSD grep/awk, CI runs GNU. Bash + jq are the only assumed
universal dependencies, and jq's absence must degrade, not crash. Optional
adopted features may add a narrowly documented conditional prerequisite;
declared Codex execution-profile validation, for example, requires Python 3.11+
`tomllib` and reports the profile unverifiable when the parser is unavailable.

## Version discipline

A behavior change in shipped mechanism bumps `plugins/harness-kit/.claude-plugin/plugin.json`
before release ([.agents/skills/release/SKILL.md](../../.agents/skills/release/SKILL.md)) —
installed repos pin mechanism by checksum, and update mode uses the version
to know what changed.
