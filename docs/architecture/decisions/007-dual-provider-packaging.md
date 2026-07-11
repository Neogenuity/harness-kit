# ADR 007 — Dual-provider packaging: one plugin tree, two manifests, a neutral VERSION

**Status:** accepted (v0.5.0)

## Context

The distributed plugin lives under `plugins/harness-kit/` and, as of v0.5.0,
installs as a versioned, updatable plugin in **both** Claude Code and Codex —
not just the old manual clone-and-copy of `skills/harness-kit`. The two
providers read different files and, crucially, do **not** share a marketplace
shape:

- **Claude Code** reads `.claude-plugin/marketplace.json` (a `plugins[]` entry
  whose `source` is a flat `"./…"` string) and the plugin's
  `.claude-plugin/plugin.json`.
- **Codex** reads `.agents/plugins/marketplace.json` (a `plugins[]` entry
  whose `source` is a nested object `{ "source": "local", "path": "./…" }`,
  with required `policy.installation`, `policy.authentication`, and `category`,
  plus a top-level `interface.displayName`) and the plugin's
  `.codex-plugin/plugin.json` (`name`/`version`/`description`, `skills`).

A single generated marketplace file cannot serve both. And with a version
string now living in two plugin manifests, they can silently drift apart.

## Decision

Check **both** provider manifests into the tree verbatim, side by side under
`plugins/harness-kit/` (`.claude-plugin/` and `.codex-plugin/`), with a root
marketplace file in each provider's own convention. Introduce
`plugins/harness-kit/VERSION` as the **single neutral version source**; every
`plugin.json` `version` must equal it. A tailored, root-only gate
(`scripts/check-packaging.sh`, run by `verify.sh`'s manifests gate) enforces
the whole invariant: four valid JSON manifests, a semver `VERSION`, both
plugin versions equal to it, name agreement across all manifests, `./`-relative
contained source paths that exist, the Codex `skills` dir resolving inside the
plugin root, in-enum `policy`/`category` fields, and each marketplace entry
resolving to a manifest at `VERSION`. The provider schemas are re-verified
against primary docs and stamped in the provider matrix's **Distribution** row
([ADR 004](004-provider-matrix-verification.md)).

## Consequences

- Adding a future provider's channel is a bounded playbook (see
  `references/migrations.md`): add its `plugin.json`, add/extend its
  marketplace file, extend `check-packaging.sh`, re-stamp the matrix — no
  content duplication, since all providers point at the one `plugins/harness-kit/`.
- A version bump is now three edits (`VERSION` + two `plugin.json`s) kept
  honest by the gate, so the release skill sets them together rather than
  relying on discipline.
- `check-packaging.sh` is dogfood/release machinery specific to this repo's
  layout, so it is root-only and tailored — the same exemption
  `test-template-sync.sh` takes ([ADR 006](006-dogfood-copies-are-enforced-duplicates.md)).
- Two marketplace files is more surface than one, but it is the honest cost
  of two providers whose contracts genuinely differ; the alternative (a
  generator) would hide a schema divergence the gate is designed to surface.
