# Changelog

All notable changes to harness-kit. The version is defined in
`plugins/harness-kit/VERSION` and mirrored into both plugin manifests.

## 0.7.0 — 2026-07-11

Install/update verification — the kit's core product boundary (`init` / `update`)
was the only mechanism with no automated test; it now has a deterministic
fixture suite, and two *verified* integrity blind spots in the manifest
mechanism it exercises are closed.

- **Deterministic install/update mechanics extracted and tested.** New template
  `scripts/install-lib.sh` is the model-free core of init/update — pure
  filesystem functions (`harness_install_mechanism`, `harness_generate_manifest`,
  `harness_repin_manifest`, `harness_update_decision`, `harness_update_apply`,
  `harness_append_gitignore`) that the SKILL's `init`/`update` prose now calls
  instead of inlining shell. New template `scripts/test-install.sh` drives them
  against throwaway git fixtures: clean init, non-clobber floor (hand-written
  `AGENTS.md`/`settings.json` survive byte-for-byte), no-op update idempotence,
  mechanism upgrade, and `# tailored`-file preservation, plus a seeded
  deny-list drift case. The model-graded half of init/update (authoring quality,
  merge judgment) stays out of scope by design. **Migration:** `update` now
  manages `install-lib.sh` and `test-install.sh` like any other mechanism file;
  they are copied on init and pinned in the manifest.
- **`scripts/harness.conf` is now manifest-pinned** (verified finding). It is the
  single source for `SECRET_PATTERNS`, yet was pinned by neither the manifest
  producer nor `guard-config.sh` — so a narrowed `SECRET_PATTERNS` disarmed the
  secret guard for `id_rsa`/`*.pem`/`.env.*` while `check-harness.sh` stayed
  green. It is now enumerated by `harness_generate_manifest` (marked
  ` # tailored`, since its patterns are repo-specific), so an un-re-pinned edit
  fails CI like every other policy file. **Migration:** `update` gains a
  `harness.conf` line in the manifest; re-pin after tailoring `SECRET_PATTERNS`.
- **Manifest integrity hardened on three fronts** (verified findings, incl. a
  multi-model review round). `check-harness.sh` check #9 previously only verified
  the files the manifest *did* pin, so an adopted repo's manifest could be
  gutted by shell edit to disarm a guard while CI stayed green. Now, when
  `scripts/hooks/` is present: (a) a missing / emptied / all-malformed manifest
  is an ERROR, not a silent skip; (b) a nonempty malformed line no longer counts
  as a pin; and (c) **completeness** — every mechanism file on disk must be
  pinned (the expected set is derived from the filesystem, not the manifest), so
  *partial* pin deletion (un-pinning one guard while leaving others) is caught.
  A genuinely pre-adoption repo still passes.
- **Update mechanics corrected** (review round). `harness_update_apply` now (i)
  treats policy files (`verify.sh`, `harness.conf`, `format.sh`, `guard-secrets.sh`,
  `guard-project-policy.sh`) as diff-only even when pristine and unmarked — never
  auto-overwriting them (SKILL update step 3) — and (ii) installs mechanism files
  the new kit ships that an older install's manifest can't list, so a `0.6`→`0.7`
  upgrade actually picks up `install-lib.sh`/`test-install.sh`. `harness_repin_manifest`
  carries forward tailored pins the shipped producer doesn't emit (a repo's own
  local gates), so a re-pin never silently drops a project-added integrity pin.
- **`install-lib.sh` added to `guard-config.sh`'s protected paths** (mechanism,
  with a `test-guard-config.sh` case) and **check #6 skips only `test-install.sh`
  and `test-check-harness.sh` when nested** (via `HARNESS_NESTED_FIXTURE`, set by
  `test-install.sh`) so the fixture suite can run `check-harness.sh` inside a
  throwaway install without recursing — every other regression test, the guard
  behavioral checks included, still runs, so no single env var can switch off the
  regression layer.

## 0.6.0 — 2026-07-11

- **Plans machinery now ships.** The kit's docs promised a `docs/plans/`
  directory (`harness.conf` sets `PLANS_DIR`, `session-context.sh` announces
  it, `AGENTS.md` links its README) but no template shipped and `init` never
  authored one — a fresh harness referenced a directory that didn't exist. New
  templates `docs/plans/README.md` (lifecycle: queued → `active/` →
  `completed/`, theme-naming, the markdown-link honesty rule) and
  `docs/plans/_template.md` (the nine plan sections); `init` step 5 authors the
  README and creates `PLANS_DIR`, and `audit` flags a configured `PLANS_DIR`
  whose directory is missing. A throwaway
  [fixture recipe](plugins/harness-kit/skills/harness-kit/references/fixture-recipe.md)
  documents how to smoke-test `init` end-to-end.
- **GitHub Copilot + Gemini CLI added to the provider matrix** (both verified
  2026-07-11): Copilot reads `AGENTS.md` natively including nested files (plus
  `.github/copilot-instructions.md`); Gemini CLI reads it via a
  `.gemini/settings.json` `context.fileName` snippet. Both are
  instructions-only (no hook/skill/agent surface), so `init` step 6 gains two
  near-free wire steps.
- **Stricter harness checks** (mechanism — `check-harness.sh` +
  `test-check-harness.sh`, manifest re-pinned):
  - Canonical skills are now validated against the **Agent Skills spec** as
    ERRORs, not doctor hints: closing `---` delimiter, non-empty `name`/
    `description`, `name` equal to its parent directory, `name` charset with no
    leading/trailing or consecutive hyphens, and the 64/1024-char limits
    (previously warnings). Prefers `skills-ref validate` when on PATH, with a
    dependency-free bash fallback.
  - New doctor WARNs: an `active/` plan missing a `Next action` or unchanged
    for 30+ days (git-dated; a no-op in shallow CI), and a provider-matrix
    `verified <date>` stamp older than 90 days or a matrix with no stamp at all
    (`PROVIDER_MATRIX_DOC`, `HARNESS_PLAN_STALE_DAYS`,
    `HARNESS_MATRIX_STALE_DAYS` are configurable in `harness.conf`).
- **Docs:** provider-matrix capability rows now carry `verified` stamps;
  `pattern.md` notes dynamic workflows riding skill-resource mirroring and
  positions hooks as *feedback* vs. OS sandboxing as *enforcement* (pointing at
  the execution-governance plan).

## 0.5.0 — 2026-07-10

- **Repackaged `plugin/` → `plugins/harness-kit/` + a Codex distribution
  channel.** The same source tree now installs as a versioned, updatable
  plugin in **both** Claude Code (`/plugin marketplace add`) and Codex
  (`codex plugin marketplace add`) — the manual clone-and-copy of
  `skills/harness-kit` still works but is no longer the only path. New files:
  `plugins/harness-kit/.codex-plugin/plugin.json` and the root
  `.agents/plugins/marketplace.json` (Codex's nested-source marketplace shape,
  with `policy`/`category`; distinct from Claude Code's flat-string source —
  schemas verified 2026-07-10 against learn.chatgpt.com/docs/build-plugins).
  See [ADR 007](docs/architecture/decisions/007-dual-provider-packaging.md).
- **`plugins/harness-kit/VERSION` is now the single version source**, mirrored
  into both `plugin.json` files. New `scripts/check-packaging.sh` (the
  `verify.sh` manifests gate) asserts the whole cross-file invariant — four
  valid manifests, semver `VERSION` equal to both plugin versions, name
  agreement, `./`-relative contained source paths, the Codex `skills` dir, and
  in-enum `policy`/`category`.
- **Codex hook commands now resolve from the Git root** (from PR #6 review): a
  Codex session whose CWD is a repo subdirectory previously exited 127 because
  `bash scripts/hooks/X.sh` is CWD-relative. All five commands in the Codex
  `hooks.json` now use `bash "$(git rev-parse --show-toplevel)/scripts/hooks/X.sh"`
  (the pattern the hooks docs recommend); a new `test-codex-hooks-cwd.sh`
  regression test runs every command from a nested CWD in CI.
- **Docs:** provider matrix gains a stamped **Distribution** row; new
  migrations playbook for a provider shipping a plugin/marketplace channel;
  README gains a "Codex, as a plugin" install section; the release skill now
  bumps `VERSION` + both plugin.jsons together. Corrected a stale `pattern.md`
  line that claimed `# tailored` manifest lines skip integrity checking (they
  are still checksum-verified; the marker only exempts template *replacement*).
- Update-mode note: this is a path/packaging change. Existing installs keep
  working; to move to the plugin channel, install via your provider's
  marketplace instead of the copy path. `lib.sh` and the guard/test scripts
  are unchanged from 0.4.1 apart from the new Codex-hooks-CWD test.

## 0.4.1 — 2026-07-10

- **Codex apply_patch guard bypass (found by real-payload capture):** a live
  Codex 0.144.1 payload — reconciled against the generated hook schemas
  (`openai/codex: codex-rs/hooks/schema/generated`) — showed that a file edit
  arrives as the **bare** apply_patch envelope (`*** Begin Patch` … `*** End
  Patch`) directly in `tool_input.command`, with the tool identity carried in
  `tool_name`; the literal `apply_patch` is **not** in the command. But
  `lib.sh:hook_affected_files` gated on `case "$cmd" in *apply_patch*)`, so it
  extracted nothing from a real Codex edit — making `guard-config.sh`,
  `format.sh`, and `guard-secrets.sh`'s write-side denial silent no-ops on
  Codex. Impact: an agent on Codex could edit protected harness mechanism
  (e.g. `scripts/hooks/lib.sh`) or write a secret file via apply_patch
  **undenied**. Fix: `hook_affected_files` parses the bare envelope when
  `tool_name` is `apply_patch` — the tool identity, not command text — and
  keeps the `apply_patch`-literal branch for the shell-wrapper form
  (`apply_patch <<'EOF' …`, which also rides a Bash/shell tool). Gating on the
  tool identity, rather than on the bare `*** Begin Patch` marker, is
  deliberate: a first pass keyed on the marker text alone fail-**closed**
  ordinary shell payloads that merely *contain* patch text (a heredoc writing
  a `.patch` file), fabricating affected-file paths and denying them — caught
  in review before merge.
- **Why CI stayed green:** every Codex apply_patch fixture used the
  `apply_patch <<'EOF'` wrapper form (which contains the literal), so the
  wrong envelope shape was never exercised. Bare-envelope regression cases are
  added to `test-affected-files.sh`, `test-guard-config.sh`, and
  `test-guard-secrets.sh`, plus a shell-command-containing-patch-text case in
  each pinning the no-false-close boundary; the affected-files/guard fixture
  comments now cite the captured payload as the source of truth.
- Update-mode note: `lib.sh` and the three `test-*.sh` files are mechanism
  (replaced on checksum match). Take the kit update and re-pin
  `scripts/.harness-manifest`; behavior-only change, no config migration.

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
