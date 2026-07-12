# Changelog

All notable changes to harness-kit. The version is defined in
`plugins/harness-kit/VERSION` and mirrored into both plugin manifests.

## 0.11.0 — 2026-07-12

Hook hardening + feedback repair — the 2026-07-12 project review re-verified
the provider matrix against live docs and probed the installed guards with
real payloads, surfacing self-protection gaps and degraded feedback channels.
This release closes them. Mechanism-only; no new tailoring required. Scope was
triple-reviewed after implementation (2× Claude Opus 4.8 + Codex
gpt-5.6-terra); every confirmed finding was fixed and fixture-covered before
tagging.

- **Guard-coverage gaps closed.** `guard-config.sh`'s default `PROTECTED_PATHS`
  now also denies edits to `scripts/harness.conf` (the secret guard's pattern
  source), `.claude/settings.local.json` (can carry `disableAllHooks: true`;
  gitignored and unmanifested in the standard Claude Code setup, so no other
  layer caught it), and the three MCP configs the trust-inventory audit reads
  (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`). Post-init
  `harness.conf` tailoring rides the existing `HARNESS_ALLOW_MECHANISM_EDITS=1`
  escape hatch.
- **Path-normalization bypass fixed.** The guard now collapses `.`/`..`/`//`
  segments before matching, so a crafted `scripts/./harness.conf` or
  `scripts/../scripts/harness.conf` can no longer slip a protected path past
  the literal globs. (Case variants on a case-insensitive filesystem remain a
  documented guardrail limitation — the CI manifest check is the enforcing
  layer.)
- **Deny reasons are model-visible.** On a `PreToolUse` payload, `hook_deny`
  emits an exit-0 JSON `permissionDecision:deny` carrying the reason (parsed by
  Claude Code and Codex) instead of an exit-2 stderr the model may not see. The
  portable exit-2 deny stays as the fallback for every other layout and
  whenever JSON construction *or the stdout write* fails — a deny never fails
  open.
- **Cursor feedback arm repaired.** `afterFileEdit` documents no output field
  for feedback text and parses exit-0 stdout as JSON, so `hook_feedback` now
  emits the documented no-op (`{}`) on the Cursor layout instead of dead plain
  text; the finding still reaches `.harness/log.jsonl`.
- **Advise-once future-proofed.** A payload-independent marker guard
  (`.harness/stop-markers/`, keyed on session/conversation id + a warnings
  digest) keeps the stop advisory firing exactly once even if a future build
  drops the undocumented-but-still-sent `stop_hook_active` flag. The prune is
  scoped to the guard's own markers, so a user-pointed `HARNESS_STOP_MARKER_DIR`
  never loses unrelated files.
- **Provider matrix refreshed** with Cursor's grown hook surface
  (`beforeShellExecution`, `beforeMCPExecution`, generic
  `preToolUse`/`postToolUse`, per-hook `failClosed`), a recorded decision to
  defer wiring `guard-secrets.sh` to `beforeShellExecution` (its payload puts
  `command` top-level, which `hook_command_string` doesn't read), and restamped
  sources; `eval.sh`'s pinned CLI invocation restamped to Claude Code 2.1.207.

**Migration.** Update mode **replaces** `guard-config.sh` and `lib.sh` (both
non-tailored mechanism files) and adds `scripts/hooks/test-deny-reasons.sh`; it
**never touches** your tailored `harness.conf` or `verify.sh`. No config
changes are required. If you tailored `guard-config.sh`'s `PROTECTED_PATHS`
locally, re-apply your additions after updating — the file is replaced, not
diffed.

## 0.10.1 — 2026-07-12

CI fix — the `ci` workflow's "Hook templates are executable" check had failed
on every push to `main` since v0.8.0. The four eval-layer scripts added in
that release (`eval.sh`, `eval-lib.sh`, `eval-harness.sh`, `test-eval.sh`)
were committed to `plugins/harness-kit/skills/harness-kit/templates/scripts/`
without the executable bit, even though their identical-content counterparts
under the repo's own installed `scripts/` were correctly `+x`. No behavior or
template-layout change; mode bits only.

- `chmod +x` the four affected template files to match their `scripts/`
  counterparts and every sibling file in that directory.

## 0.10.0 — 2026-07-12

Execution governance baseline — the kit previously scaffolded knowledge,
gates, and evals but said nothing about *containment*: which MCP servers a
repo trusts, what an agent should do with hostile content, or whether the
shipped CI could be quietly repointed. Scope was design-reviewed before
implementation (Codex gpt-5.6-sol, 14 findings incorporated — most
materially: the MCP inventory pins expected *identity*, not just names) and
the implementation was triple-reviewed (2× Claude Opus 4.8 + Codex
gpt-5.6-terra, all SHIP-WITH-FIXES; every fix landed and is
fixture-covered).

- **MCP trust inventory (new check #8c).** `harness.conf` gains
  `MCP_ALLOWED_SERVERS` — one `<name> <expected-identity-substring>` line
  per allowed server. `check-harness.sh` extracts every *enabled* server
  from `.mcp.json`, `.cursor/mcp.json`, `opencode.json`, and
  `.codex/config.toml` (best-effort TOML scan; single- and double-quoted
  table names) and audits it: with no inventory declared, configured
  servers produce one adoption WARN; once the inventory is declared (even
  empty — the strict default), an uncovered server or one whose configured
  command/args/URL no longer contains its pinned substring is an **ERROR**.
  A name-only inventory line is itself an ERROR (an empty pin would match
  any identity). Unparseable configs and jq-absent machines get a loud
  "not audited" WARN — except trivially-empty maps (`"mcp": {}`), which
  stay silent via a dependency-free fast path. Disabled entries are
  skipped. **Migration:** update mode replaces `check-harness.sh`; add an
  `MCP_ALLOWED_SERVERS` block to your tailored `harness.conf` (the shipped
  template carries a commented example) — repos with no MCP configs see no
  change.
- **Untrusted-content + risky-actions conventions (shipped docs).** Two new
  template docs under `docs/conventions/`: `untrusted-content.md` (tool/
  repo/web/MCP output is data, not instructions; the untrusted-clone
  checklist; which containment layers actually *hold* under a hostile
  instruction, per provider — including that OpenCode ships no OS sandbox)
  and `risky-actions.md` (destructive-op policy and the safe-default
  posture, every wiring example labeled by its enforcement layer so hooks
  are never mistaken for boundaries). `AGENTS.md.tmpl` links both and its
  security checklist now says repo/tool/web/**MCP**.
- **Provider matrix: execution containment.** New verified section
  (sandbox, network policy, approval modes for Claude Code / Codex /
  Cursor / OpenCode, checked against vendor docs 2026-07-11) — the factual
  basis the conventions docs cite instead of asserting.
- **Shipped-CI hardening + guard widening (new doctor #10d).** The CI
  templates pin actions to full commit SHAs, declare `permissions:
  contents: read`, `timeout-minutes`, and `persist-credentials: false`;
  `check-harness.sh` gains doctor WARN #10d flagging any mutable
  (tag/branch) `uses:` ref in `.github/workflows/` (quoted refs
  unwrapped); `guard-config.sh` PROTECTED_PATHS broadens from the single
  harness-check workflow to `.github/workflows/*`. **Migration:** update
  mode replaces the guard and check; workflows are yours — re-apply the
  hardening from the template if you've tailored them.
- **Plans.** The governance plan's advanced half (per-provider sandbox
  profiles, devcontainer, audit-log export) split into its own queued plan
  ([docs/plans/execution-sandbox-profiles.md](docs/plans/execution-sandbox-profiles.md));
  completed plan at
  [docs/plans/completed/v0.10.0-execution-governance-baseline.md](docs/plans/completed/v0.10.0-execution-governance-baseline.md).

## 0.9.0 — 2026-07-11

Eval integrity and plans hygiene — a 2026-07-11 project review (findings
adversarially checked by a second model, Codex gpt-5.6-sol) found the v0.8.0
eval layer could silently mis-score, and found the launch and a saturated
task bank tracked nowhere the plans machinery could see.

- **Eval integrity fixes.** Latest-run selection in `eval-harness.sh` now
  picks by per-run `run_started_at` epoch (`max_by([(.run_started_at // 0),
  .run])`) instead of lexicographic run-id sort, so a custom `--run-id`
  can no longer permanently outrank a chronologically newer run; legacy
  result lines with no `run_started_at` still parse. `eval.sh` refuses to
  reuse a results directory that already has recorded results, and
  refuses to run against a dirty working tree (each trial clones committed
  `HEAD`) unless `--allow-dirty-head` is passed. Negative tasks gain a
  distinct `negative_violation` outcome via a `check.sh` exit-3 convention
  (exit 1 keeps meaning `task_failure`), and `eval-harness.sh` fails loudly
  on any `negative_violation` regardless of suite. `--update-baseline` now
  excludes `--provider mock` rows, refuses atomically unless every cell has
  exactly `--expected-trials` (default 3) trials, and writes each cell's
  `recorded` date from the run's own timestamp. Task metadata (`suite`,
  `polarity`, `provider`, `grade`) is now enum-validated at load time, and a
  `provider:` value gates a task off providers it doesn't target (`mock` is
  exempt). The default `--run-id` (when none is passed) changes from a bare
  UTC timestamp (`YYYYMMDD-HHMMSS`) to `TIMESTAMP-provider-model`, so two
  providers (or two models) launched in the same second no longer collide on
  a results dir — anything scripting against results-dir names by pattern
  should account for the new suffix. **Migration:** `update` mode replaces
  the four eval scripts as usual; the `results.jsonl` schema gains
  `run_started_at` and `outcome` fields (old lines keep parsing — legacy rows
  are outranked by any new, timestamped run). Negative-task graders should
  adopt exit 3 for a caught shortcut; a plain exit 1 still fails the task but
  records `task_failure`, which does not trigger the loud scorer failure
  path.
- **Plans, docs, and CI.** New active plan
  [docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md](docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md)
  tracks this work; two new queued plans,
  [docs/plans/eval-discrimination.md](docs/plans/active/v0.12.0-eval-discrimination.md)
  (a task bank that actually discriminates model behavior) and
  [docs/plans/launch-readiness.md](docs/plans/launch-readiness.md) (the
  launch, previously tracked only as README checkboxes), join the roadmap;
  `docs/plans/active/` is now tracked (a fresh clone previously lost the
  directory). `.github/workflows/ci.yml` now runs `bash scripts/verify.sh`
  directly instead of hand-reconstructing its steps, so a gate added to
  `verify.sh` can no longer silently drop out of CI. README's hardcoded
  `v0.6.0` claim is replaced with a pointer to `plugins/harness-kit/VERSION`,
  and the release skill gains a sweep step so this can't go stale again.

## 0.8.0 — 2026-07-11

Behavioral evals — the harness could prove it was *coherent* (drift, links,
checksums) but not that it *worked*. This release adds the layer that measures
whether the harness actually changes agent behavior: repo-specific golden tasks
run over multiple isolated trials, scored by pass@k / pass^k against recorded
baselines.

- **New eval mechanism** (`scripts/eval-lib.sh`, `eval.sh`, `eval-harness.sh`,
  `test-eval.sh`). `eval.sh <task> --provider <claude|codex|mock> --trials N`
  runs a golden task over N independent trials, each in a fresh isolated
  workspace (a throwaway `git clone`), captures a transcript per trial under
  `.harness/eval-results/` (git-ignored), and grades the end state with the
  task's `check.sh` (+ optional `verify.sh`). `eval-harness.sh` computes
  pass@k / pass^k per task and fails on a regression-suite drop vs
  `docs/evals/baselines.json`. `--provider mock` runs the reference solution
  through the whole pipeline for a zero-cost plumbing/grader-validity check.
- **`docs/evals/` convention + task bank.** `TASK.md` (suite: capability|
  regression, polarity: positive|negative), a `check.sh` grader independent of
  any agent-written test, and a `reference/apply.sh` proving the task solvable.
  Ships a `_template` task and a rubric+calibration-note example; this repo
  carries an 8-task dogfood bank spanning both suites and both polarities.
- **Grader validity is CI-enforced.** `test-eval.sh` (wired into `verify.sh`)
  proves, with no model in the loop, that every task's reference solution scores
  as a pass and every negative task's `reference/violate.sh` scores as a fail —
  a grader that can't catch the shortcut is caught here.
- **init/audit integration.** init interviews for the 1-2 success-defining tasks
  and scaffolds `docs/evals/`; audit reports task counts by suite/polarity,
  grader validity, and baseline age.
- **Migration.** `update` treats `eval-lib.sh` / `eval.sh` / `eval-harness.sh` /
  `test-eval.sh` as mechanism files: they are copied on init, added on upgrade
  from an older manifest, pinned in `.harness-manifest`, protected by
  `guard-config.sh`, and enumerated by `check-harness.sh`'s completeness check.
  No action needed — an existing harness picks them up on the next `update`.

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
