# Changelog

All notable changes to harness-kit. Versions refer to
`plugin/.claude-plugin/plugin.json`.

## 0.4.0 — 2026-07-10

- **Codex protocol correctness (from adversarial review, validated against
  the current docs at learn.chatgpt.com):** Codex hook payloads carry no
  `tool_input.file_path` — file edits arrive as apply_patch invocations in
  `tool_input.command` — so the guards and `format.sh` were silent no-ops
  on Codex. New `lib.sh:hook_affected_files` / `hook_command_string`
  normalize all three provider layouts (direct fields, plus apply_patch
  envelope headers including multi-file patches and renames);
  `guard-config.sh`, `guard-secrets.sh`, and `format.sh` now iterate every
  affected file. `guard-secrets.sh` adds a best-effort token scan of shell
  commands (the only live secret layer on Codex) with apply_patch bodies
  stripped to avoid false denies, and now also denies patch writes to
  secret files. Fixtures are schema-derived; pinned by the new
  `test-affected-files.sh` plus Codex cases in every guard test.
- **Stop-hook protocol:** Codex requires JSON on Stop stdout at exit 0;
  `hook_advise_once`'s second pass now emits `{"continue": true}` (valid in
  Claude Code too — the layouts are indistinguishable) and `{}` on the
  Cursor layout instead of plain text.
- **Manifest integrity:** `check-harness.sh` check #9 now checksum-verifies
  ` # tailored` lines too — the marker only exempts a file from template
  replacement (update mode) and template-equality checks, never from
  integrity verification. Re-pin tailored lines after editing, keeping the
  marker.
- **Docs:** provider matrix re-verified 2026-07-10 — Codex hooks are GA and
  enabled by default (`hooks` feature key; `codex_hooks` deprecated alias;
  `commandWindows` exists), payload/Stop facts corrected, sources updated
  to learn.chatgpt.com (developers.openai.com/codex/* now redirects there).
- **CI:** test matrix now includes macOS (exercises the BSD awk/`shasum`/
  `readlink -f` branches).
- Update-mode note: `lib.sh`, both guards, `format.sh`, and
  `check-harness.sh` are mechanism (replaced on checksum match). A tailored
  `format.sh` fork needs the multi-file iteration applied manually — the
  TAILOR arms now live inside a `process_one()` function.

## 0.3.0 — 2026-07-09

- **Packaging:** the distributable plugin moved from the repo root into
  `plugin/` (`marketplace.json` `source: "./plugin"`). Installs no longer
  include repo-level files. If you track paths, `skills/…` is now
  `plugin/skills/…`.
- **Self-application:** this repository now runs its own harness — root
  `AGENTS.md`/`CLAUDE.md`, `docs/` knowledge base with ADRs, vendored and
  tailored `scripts/` (manifest-pinned), all-provider wiring, and the
  `harness-check.yml` drift gate in CI.
- **Docs:** README rewritten around the one-line value proposition;
  architecture overview and five decision records added; MIT license,
  CONTRIBUTING, and `llms.txt` added.
- **Mechanism hardening (from adversarial review):** `check-harness.sh`
  check #6 now also runs top-level mechanism tests (`scripts/test-*.sh`);
  new check #8b verifies OpenCode's `opencode.json permission.read` against
  `SECRET_PATTERNS`; checks #8/#8b now error (instead of silently skipping)
  when a wired `.claude/` or `.opencode/` is missing its native deny-list
  file; `guard-config.sh` protects `opencode.json`; the Claude deny-list
  template covers root-level `*.pem`/`id_rsa`/`id_ed25519`; every
  `SECRET_PATTERNS` entry now has a `test-guard-secrets.sh` case; the
  version-bump stop-hook compares version values against HEAD. Update-mode
  note: `check-harness.sh` and the test scripts are mechanism (replaced on
  checksum match); `settings.json`/`opencode.json` are policy (diffed).

## 0.2.0 — 2026-07-08

- Verification loop: post-edit lint feedback hooks the agent self-corrects
  on, `verify.sh --fast` wired into the advisory stop-hook.
- Self-guarding harness: `guard-config.sh` (mechanism/lint-config edit
  denial), manifest checksum integrity in `check-harness.sh`, native
  deny-list drift detection against `SECRET_PATTERNS`.
- Observability: every deny/advisory/lint event appends to
  `.harness/log.jsonl`; audit mode summarizes it.
- Provider matrix revalidated against 2026-07 harness docs (per-fact
  verified stamps + Sources section).

## 0.1.0 — 2026-07-08

- Initial extraction from a production Laravel modular monolith: canonical
  `docs/` knowledge base + `AGENTS.md` TOC, generated provider skill stubs
  (`sync-agent-skills.sh`), portable hook scripts with regression tests,
  shared permission templates, and the `check-harness.sh` CI drift gate.
