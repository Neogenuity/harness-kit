---
name: harness-kit
description: >-
    Scaffolds and maintains a standardized cross-agent harness (Claude Code,
    Cursor, Codex, OpenCode, .agents) in any repository: a canonical docs/
    knowledge base, an executable quality-gate runner (verify.sh), generated
    provider skill stubs, provider-agnostic hook scripts with lint feedback
    and observability logging, shared permissions, and a CI drift gate with
    mechanism integrity checks. Activates when asked to set up or
    standardize an agent/AI harness in a repo, audit an existing harness,
    add a skill/subagent/hook to the harness, sync provider stubs, or
    upgrade/migrate harness machinery ("harness init", "harness audit").
---

# Harness Kit

Installs and maintains the harness pattern described in
[references/pattern.md](references/pattern.md): canonical content in `docs/`,
generated/thin provider shims, portable hooks, CI-gated drift checks. Read
that file first if you haven't in this session. Provider file locations and
event mappings live in [references/provider-matrix.md](references/provider-matrix.md).

Modes: **init** (scaffold a repo), **audit** (grade an existing repo),
**add-skill / add-agent / add-hook** (extend), **update** (upgrade machinery).
Pick the mode from the user's request; default to `audit` when a harness
already exists and the request is vague.

Everything the kit installs is **vendored into the target repo** — never
reference files inside this skill directory from a target repo's configs.
Teammates without the kit (and non-Claude harnesses) must get identical
behavior from the repo alone.

## init

1. **Recon (before asking anything).** Detect: languages and build files
   (composer.json, package.json, pyproject.toml, go.mod, Cargo.toml);
   formatter/linter/test commands (from manifest scripts, Makefile, CI
   config); CI system (.github/workflows, .gitlab-ci.yml); existing agent
   config (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursor/`, `.codex/`,
   `.opencode/`, `.agents/`); secret-file patterns present (`.env*`,
   `auth.json`, key files); docs already written. If a partial harness
   exists, switch to a gap-filling variant of this flow — never overwrite
   hand-written content; migrate it toward `docs/` instead.

2. **Interview (only what recon can't answer).** Ask, ideally in one round:
   - Quality gates: the ordered commands that define "done" (recon proposes,
     user confirms). These are written into `scripts/verify.sh`, which is the
     single executable source for them — docs only point at it.
   - The millisecond-fast linter per file type for the post-edit feedback
     loop (`format.sh`'s second TAILOR map) — recon proposes from the
     toolchain; slow static analysis stays in `verify.sh`.
   - Which providers to wire beyond Claude Code + `AGENTS.md` (Cursor?
     Codex? OpenCode? `.agents`? — cheap to include, default to all five).
   - The 2-4 conventions worth a `docs/conventions/` doc (what do reviewers
     correct most often?).
   - The first 1-3 skills: recurring task shapes with a known recipe
     (e.g. "add an endpoint", "add a model").
   - One domain invariant for the advisory stop-hook, if any (the mistake
     that costs a review cycle every time — e.g. tenancy scoping, missing
     migration, unregistered route). Skippable; the hook ships as a no-op.
   - The 1-2 recurring tasks that *define success* in this repo ("add an
     endpoint", "add a model") — the seeds for the first behavioral eval golden
     tasks. Skippable; the eval bank starts empty and an empty bank is fine.

3. **Install mechanism** from `templates/scripts/` into `scripts/`:
   `harness.conf`, `install-lib.sh`, `sync-agent-skills.sh`, `check-harness.sh`,
   `test-check-harness.sh`, `test-install.sh`, `eval-lib.sh`, `eval.sh`,
   `eval-harness.sh`, `test-eval.sh`, `verify.sh`, and `hooks/` (all scripts +
   tests + README). `chmod +x scripts/hooks/*.sh scripts/*.sh`.
   `install-lib.sh` is the deterministic, model-free core of this flow —
   `harness_install_mechanism` copies exactly this set, and step 8's
   `harness_generate_manifest` and `update` mode both call it; `test-install.sh`
   is its fixture suite. Tailor `harness.conf` (providers, plans dir, secret
   patterns). Append `.harness/` to the repo's `.gitignore` — the hook
   observability log lives there.

4. **Tailor policy** in the marked `TAILOR` blocks:
   - `verify.sh`: write the interviewed quality gates as `gate` (fast:
     formatter/linter) and `full_gate` (typecheck, tests) lines, ordered
     cheapest-first. Keep the default `harness` gate.
   - `hooks/format.sh`: uncomment/add extension → formatter lines for the
     detected stack.
   - `harness.conf` `SECRET_PATTERNS` / `SECRET_ALLOW_PATTERNS`: extend for
     the repo's actual secret files — this is the single source
     (`guard-secrets.sh` enforces it, `check-harness.sh` verifies the native
     deny lists against it). Mirror additions into
     `hooks/test-guard-secrets.sh` cases.
   - `hooks/guard-config.sh`: extend `PROTECTED_PATHS` with the repo's
     linter/formatter configs — the files an agent could edit to make
     findings disappear. The harness mechanism is protected by default.
   - `hooks/guard-project-policy.sh`: implement the invariant check from the
     interview (follow the in-file example), or leave the no-op skeleton.

5. **Author content** (this is authoring, not copying — use the codebase):
   - `AGENTS.md` from `templates/AGENTS.md.tmpl`: fill every placeholder,
     delete sections that don't apply yet rather than leaving stubs.
   - `CLAUDE.md` from `templates/CLAUDE.md.tmpl` — a thin `@AGENTS.md`
     import plus a `verify.sh` pointer; the gates themselves live only in
     `scripts/verify.sh`.
   - `docs/conventions/<topic>.md` for each interviewed convention — short,
     example-driven, written from real code in the repo.
   - `docs/skills/<slug>/SKILL.md` per initial skill, following
     `templates/docs/skills/_example/SKILL.md`. Frontmatter descriptions are
     activation triggers — spend effort on them.
   - `docs/agents/<name>.md` personas only if a clear delegation need exists
     (code-reviewer is the usual first one); follow
     `templates/docs/agents/_example.md`, and add thin stubs in
     `.claude/agents/` (and `.cursor/agents/`) per the template's wiring
     comment.
   - `docs/plans/README.md` from `templates/docs/plans/README.md` (AGENTS.md
     links it, so `check-harness.sh` needs it to exist), and create the
     `PLANS_DIR` (`docs/plans/active/` by default) with a `.gitkeep` so
     `session-context.sh` has a directory to announce. Copy
     `templates/docs/plans/_template.md` alongside it; seed real plans only
     when there's long-horizon work to track (an empty queue is fine).
   - `docs/evals/` from `templates/docs/evals/` (`README.md` + `tasks/_template/`
     + `rubrics/_example.md`) — the behavioral eval bank. Author real golden
     tasks only for the recurring success-defining work named in the interview;
     an empty bank is fine, but if you ship none, delete the AGENTS.md Evals
     link so `check-harness.sh` doesn't dangle. Each task grades the *end state*
     via `check.sh` and ships a `reference/apply.sh` that `test-eval.sh` proves
     scores as a pass (and, for negative tasks, a `reference/violate.sh` it
     proves scores as a fail).

6. **Wire providers** (for each provider chosen in the interview):
   - Claude Code: `templates/providers/claude/settings.json` →
     `.claude/settings.json`. Extend `permissions.allow` with the quality-gate
     commands and `permissions.deny` with `Read(...)` entries covering every
     tailored `SECRET_PATTERNS` glob — `check-harness.sh` fails when the deny
     list misses one. Merge, don't clobber, an existing file.
   - Cursor: `templates/providers/cursor/hooks.json` → `.cursor/hooks.json`;
     one `.cursor/rules/<topic>.mdc` per convention doc from
     `templates/providers/cursor/rules/_example.mdc`.
   - Codex: `templates/providers/codex/hooks.json` → `.codex/hooks.json`
     (hooks are GA and on by default, but project-local configs load only
     when the project is trusted — see provider matrix). Codex payloads
     carry no file path: the guards parse apply_patch envelopes and
     token-scan shell commands via `lib.sh:hook_affected_files` — best
     effort, so keep Codex's native trust/permission layer as a second
     guard. `config.toml` only if MCP servers are needed. Skills come from
     `.agents/skills/` — no Codex skill dir.
   - OpenCode: `opencode.json` — its `permission.read` deny block mirrors
     `SECRET_PATTERNS` (keep the two in sync when tailoring; add `"mcp"`
     servers only if needed); optionally a TS plugin shim in
     `.opencode/plugins/` that shells out to the portable hooks (see provider
     matrix) — otherwise guards degrade to these native permissions + CI.
   - GitHub Copilot coding agent: nothing to wire — it reads `AGENTS.md`
     natively, including nested files (verified 2026-07-11). Optionally add a
     thin `.github/copilot-instructions.md` pointing at `AGENTS.md` for the
     completions surface. No skill/hook/agent dirs (see provider matrix).
   - Gemini CLI: write `.gemini/settings.json` with
     `{ "context": { "fileName": ["AGENTS.md", "GEMINI.md"] } }` so it loads the
     shared `AGENTS.md` (default reads `GEMINI.md` only; verified 2026-07-11).
   - Run `bash scripts/sync-agent-skills.sh` to generate all skill stubs.

7. **CI gate**: install `templates/ci/github-actions-harness-check.yml` as
   `.github/workflows/harness-check.yml` (or add the `check-harness.sh` step
   to existing CI; translate for other CI systems).

8. **Write the manifest** for upgrades *and* CI integrity — do this AFTER
   step 4, so the checksums pin the tailored state. `harness_generate_manifest`
   in `scripts/install-lib.sh` is the single producer; it pins the whole
   `scripts/hooks/` tree plus the top-level mechanism files (`harness.conf`,
   `install-lib.sh`, `sync-agent-skills.sh`, `check-harness.sh`,
   `test-check-harness.sh`, `test-install.sh`, `eval-lib.sh`, `eval.sh`,
   `eval-harness.sh`, `test-eval.sh`, `verify.sh`):
   ```bash
   . scripts/install-lib.sh
   harness_generate_manifest . <kit-version> > scripts/.harness-manifest
   ```
   (kit version = `version` in the kit's `.claude-plugin/plugin.json`).
   `check-harness.sh` verifies these checksums from now on, so every later
   edit must re-pin its line. Append ` # tailored` to a line when the project
   deliberately forks that file (update mode then only ever diffs it, never
   replaces it) — do this for the policy files step 4 tailors: `verify.sh`,
   `hooks/format.sh`, `hooks/guard-project-policy.sh`, and **`harness.conf`**.
   Pinning `harness.conf` is load-bearing: its `SECRET_PATTERNS` is the single
   source for the secret guard, so an un-re-pinned narrowing (which would
   silently disarm the guard) must fail CI like any other policy edit — shell
   edits are unscanned by design, so this manifest is their enforcing layer.

9. **Verify — do not skip**: `bash scripts/verify.sh` and
   `bash scripts/check-harness.sh` pass; each `scripts/hooks/test-*.sh`
   passes standalone; feed `guard-secrets.sh` a real payload for the repo's
   own `.env` and `guard-config.sh` one for `scripts/hooks/lib.sh`, confirm
   exit 2 for both; repeat both with Codex-shaped payloads (an apply_patch
   envelope in `tool_input.command` — crib the builders from
   `scripts/hooks/test-affected-files.sh`) and confirm exit 2 again;
   confirm every AGENTS.md link opens. Report results honestly, including
   anything left unwired. To rehearse the whole flow on a disposable repo
   first, follow [references/fixture-recipe.md](references/fixture-recipe.md).

## audit

Grade an existing repo against the pattern. Check, in order: canonical
`docs/` presence (or content trapped in provider dirs / duplicated);
AGENTS.md as TOC with live links; skills canonical + stubs generated
everywhere `harness.conf` claims; hooks portable, executable, tested; native
permission deny list mirroring the secret guard; the configured `PLANS_DIR`
(`harness.conf`) resolving to a real directory (a dangling one makes
`session-context.sh` silently announce nothing) and `docs/plans/README.md`
present (AGENTS.md links it, so a missing README is a dead link); CI running
the drift gate; manifest present and passing its checksum
verification. If a behavioral eval bank exists (`docs/evals/`), report its
health too: number of golden tasks by suite (capability / regression) and
polarity, whether `test-eval.sh` passes (grader validity), and the age of
`docs/evals/baselines.json` (stale or absent baselines mean the harness is
unmeasured — recommend a scheduled `eval-harness.sh` run). Then run
`scripts/check-harness.sh` and the hook tests if they exist. If `.harness/log.jsonl` exists, summarize it: deny / advise /
lint-findings counts by hook and by file — a repeatedly-denied path or a
warning surfaced every session is the next mistake to engineer away
(tighten a pattern, add a lint rule, write a convention doc). Output: a
table of pattern element → status (present / drifted / missing) with the
concrete fix for each, ordered by risk (secret exposure first, drift
second, missing content last), plus the log summary when available. Offer
to fix; don't fix unasked.

## add-skill / add-agent / add-hook

- **add-skill**: author `docs/skills/<slug>/SKILL.md` (template above; sweat
  the frontmatter description), link it from AGENTS.md, run
  `bash scripts/sync-agent-skills.sh`, run `check-harness.sh`, commit
  canonical + stubs together.
- **add-agent**: author `docs/agents/<name>.md`, add thin provider stubs
  (`.claude/agents/`, `.cursor/agents/`, `.opencode/agents/` as markdown;
  `.codex/agents/<name>.toml` with `developer_instructions` pointing at the
  canonical doc) with minimal frontmatter, link from AGENTS.md.
- **add-hook**: write the script in `scripts/hooks/` sourcing `lib.sh`,
  following the conventions in `scripts/hooks/README.md` (fail open, exit 2
  to deny, `hook_advise_once` for stop-hooks). Add a `test-<name>.sh`
  regression script — a guard without a test is a future silent failure.
  Wire the event in each provider config per the provider matrix. Verify by
  piping sample payloads (both harness layouts) into the script.

## update

1. Read the target's `scripts/.harness-manifest` (version + checksums). If
   missing, fall back to audit and offer to adopt the manifest.
2. For each mechanism file: checksum matches manifest → replace with the
   new kit version; differs, or its manifest line is marked ` # tailored` →
   the project owns it; show a diff of old-kit → new-kit and apply only
   what the user approves (the old kit's templates are recoverable from the
   kit repo's git tag matching the manifest header version — use them as
   the diff base for tailored files). `harness_update_apply` in
   `install-lib.sh` runs this decision deterministically
   (`harness_update_decision` classifies each line replace-vs-diff); it is the
   same code `test-install.sh` pins. Set `HARNESS_ALLOW_MECHANISM_EDITS=1`
   for the session if `guard-config.sh` is wired — upgrading the mechanism
   is the intended use of that escape hatch.
3. Never auto-overwrite policy files (`verify.sh`, `format.sh`,
   `guard-secrets.sh`, `guard-project-policy.sh`, `harness.conf`, provider
   configs) — diff only.
4. Rewrite the manifest with the new version/checksums — `harness_repin_manifest`
   in `install-lib.sh` regenerates it while preserving every ` # tailored`
   marker — then re-run `check-harness.sh` and all hook tests.
5. When the request is really a *standards* shift — a provider newly reads
   `.agents/skills/` natively, Claude Code ships AGENTS.md support, a new
   harness appears — follow the matching playbook in
   [references/migrations.md](references/migrations.md) instead of
   improvising.

## Rules that hold in every mode

- `docs/` is the single source of truth; never edit a generated stub by hand.
- Every guard hook gets a regression test wired into `check-harness.sh`.
- Hooks fail open; denial is exit 2; advisory stop-hooks never hard-block.
- Verify with the repo's own checks before declaring done, and report
  failures as failures.
