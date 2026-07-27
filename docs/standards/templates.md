# Editing the shipped templates

Rules for changing anything under `plugins/harness-kit/skills/harness-kit/templates/` —
the code this kit installs into other people's repositories. Reviewers
correct these most often; the advisory stop-hook and CI enforce the
mechanical ones.

## Every guard ships with a regression test

A new or changed hook under `templates/scripts/harness/hooks/` gets a matching
`test-<name>.sh` in `templates/scripts/harness/tests/`, runnable standalone.
Put it there and nowhere else: the gate that runs these is a `parallel-each`
over `templates/scripts/harness/tests/test-*.sh` (and, for adopters,
`scripts/harness/tests/test-*.sh`), so a test written beside the hook is a test
no gate ever globs — the silent failure this rule exists to prevent. A guard
without a test is a
future silent failure — the hook will break on some payload shape and nobody
will notice, because hooks fail open by design. CI runs every template test;
the stop-hook warns when a template change touches no test.

**Where the test lives depends on who needs to run it.** A shipped test beside
the mechanism is the default, and the only option for anything an adopter's
own floor must keep honest. But the install/update machinery
(`lib/install-lib.sh`) and the checker libraries (`lib/check-doctor.sh` and
its siblings) are covered by the maintainer suites at the repo root —
`scripts/test-install-core.sh`, `scripts/test-check-harness.sh` — because
v0.29.0 deliberately descoped the adopter floor to keep it fast, and shipping
these would reverse that. Adding a root-suite case satisfies this rule; the
stop hook searches the whole working tree for the accompanying `test-*.sh`, so
it does not care which of the two homes you used. This repo's own tailored
policy hook is itself covered that way, by `scripts/test-project-policy.sh` —
the shipped `test-guard-project-policy.sh` runs against whichever tailored
hook a checkout provides, so it can only assert what every install shares.

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

## Formatter-parseable content needs a formatter-ignore entry

Adding prose or any other formatter-parseable content to the checksum-pinned
mechanism tree needs a matching exclusion in an adopter-side repo-wide
formatter (`prettier --write .` and similar), or that formatter will rewrite
the file and break the integrity pin. `harness_append_formatterignore` in
`install-lib.sh` automates exactly one of these: writing the marked block to
**prettier's** `.prettierignore`. It is not a general remedy — biome excludes
via an ordered `!` negation in `files.includes`/`formatter.includes`, dprint
via its own `excludes` list, pre-commit via a top-level or per-hook
`exclude:` regex, and none of these mechanisms are interchangeable with
`.prettierignore` or with each other. For any formatter other than prettier,
the adopter adds the equivalent exclusion by hand; `check-harness` doctor
check #10e (best-effort, WARN-only) names the missing kit-owned path(s) for
whichever tool it detects configured, so the gap keeps surfacing instead of
going silent.

**Ignore entries must reach nested checkouts.** Every exclusion mechanism in
that set is path-anchored: `.prettierignore` follows gitignore matching, where
a pattern containing a slash before its end matches the repo-root copy only,
and biome/dprint/pre-commit patterns anchor the same way. A repo holding a
second checkout of itself — Claude Code's `.claude/worktrees/<name>/`, a
submodule, a vendored copy — therefore has its kit-owned files reformatted
despite a correct-looking root exclusion. In the worktree case Claude Code
hides the directory via `.git/info/exclude`, which no formatter reads; a repo
that *also* lists it in `.gitignore` is already spared under prettier, which
does read that file, so the exposure depends on the repo. So the
block `harness_append_formatterignore` writes lists `.claude/worktrees/`
itself and spells every kit-owned entry `**/`-prefixed (matched at any depth
including the root — a superset of the plain form, not a substitute for it).
Anything added to that block follows the same rule, and #10e's warnings carry
the nested-checkout hint for the tools it can only name, not fix.

Generated byte-exact artifacts (provider skill/agent stubs, wiring adapters)
are the sharper case regardless of formatter: they have no `# tailored`
escape hatch, so a formatter fighting `sync` there is a deadlock, not a
re-pin chore — `sync` regenerates the bytes the formatter rejects, and the
formatter produces the bytes `sync --check` rejects.

**Accepted limitation: canonical sources sit outside the ignore block.**
Neither `.prettierignore` nor doctor check #10e's other-formatter guidance
covers the canonical sources stub generation reads from (`.agents/skills/`,
`.harness/agents/`) — only the generated stub directories are listed. A
formatter that rewrites a canonical file (e.g. reindenting a YAML frontmatter
block scalar) changes the derived stub content and fails `sync --check` in
CI until a human re-runs `sync`. That is churn, not a deadlock: `sync`
regenerates the stubs from the rewritten canonical file and `--check` passes
again, with no byte-exact fight to reconcile. A 4-space-to-2-space
frontmatter normalization elsewhere in this template set is a point fix for
exactly one instance of that class (prettier's default YAML block-scalar
reindent); it does not cover prose reflow or any other future prettier
normalization of canonical sources. An adopter who hits this either re-runs
`sync` and commits the result, or adds `.agents/skills/` and
`.harness/agents/` to their own ignore/exclude configuration.

## Secret patterns are single-sourced

`SECRET_PATTERNS` in `harness.conf` drives the read guard; the provider
deny-list templates (`providers/claude/settings.json`, opencode
`permission.read`) must mirror it, and every addition gets a
`test-guard-secrets.sh` case. `check-harness` verifies the mirrors in
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

A behavior change in shipped mechanism bumps the kit version before release:
`plugins/harness-kit/VERSION` is the single source of truth, mirrored into
both `plugins/harness-kit/.claude-plugin/plugin.json` and
`plugins/harness-kit/.codex-plugin/plugin.json`
([.agents/skills/release/SKILL.md](../../.agents/skills/release/SKILL.md)) —
installed repos pin mechanism by checksum, and update mode uses the version
to know what changed.
