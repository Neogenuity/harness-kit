# Changelog

All notable changes to harness-kit. Versions refer to
`plugin/.claude-plugin/plugin.json`.

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
