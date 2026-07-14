# Contributing

Thanks for looking under the hood. This repo runs the harness it ships, so
contributing here *is* using the product — the guards and gates you hit are
the ones users get.

Contributors also need Python 3 for this repository's root-only live-runtime
fixture. Python is not an installed-harness prerequisite: shipped harnesses
continue to require only Bash, `jq`, Git, and a SHA-256 tool.

## Ground rules

1. **`bash scripts/verify.sh` must pass** before any PR: shellcheck
   (warning severity) on every script, JSON-valid manifests, the template
   regression tests, and the harness drift gate.
2. **Template changes ship with a test.** Anything under
   `plugins/harness-kit/skills/harness-kit/templates/scripts/` is code that gets
   installed into other people's repos — a new or changed guard hook gets a
   `test-<name>.sh` beside it. The advisory stop-hook will remind you; CI
   will insist. See [docs/conventions/templates.md](docs/conventions/templates.md).
3. **Never hand-edit generated stubs** (`.claude/skills/`, `.cursor/skills/`,
   `.opencode/skills/`, `.agents/skills/`). Edit the canonical file under
   `docs/skills/`, run `bash scripts/sync-agent-skills.sh`, commit both.
4. **Provider-matrix facts need receipts.** A load-bearing claim you add or
   change in `provider-matrix.md` (a harness's file locations, hook events,
   payloads) carries a `verified YYYY-MM` stamp, cross-referenced to the
   file's Sources section — for the fact you touched, no stamp means no merge.
   Unverified facts are marked, not dressed up as confirmed.
5. **Root `scripts/` is an installed copy**, pinned by
   `scripts/.harness-manifest`. Improve the template first; roll it into the
   installation via the kit's update mode and re-pin. Editing the installed
   copy directly trips `guard-config.sh` and the CI manifest check — by
   design.

## Working on this repo with a coding agent

Start at [AGENTS.md](AGENTS.md) (your agent will, automatically, on most
harnesses). The hooks are live: secret reads are denied, mechanism edits are
blocked without `HARNESS_ALLOW_MECHANISM_EDITS=1`, and lint findings come
back to the agent after each edit.

## Releases

Maintainer-driven, via [docs/skills/release/SKILL.md](docs/skills/release/SKILL.md).

## Security

Found a vulnerability in a shipped guard or gate, rather than a bug in this
PR? Don't open a public issue — see [SECURITY.md](SECURITY.md) for how to
report it privately.
