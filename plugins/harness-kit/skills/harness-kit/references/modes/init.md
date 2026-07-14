# Init mode — scaffold a repo

Read [../pattern.md](../pattern.md) first if unread this session; provider file
locations and event mappings are in [../provider-matrix.md](../provider-matrix.md).

**Preflight — runtime prerequisites (before scaffolding anything).** Source the
NEW kit's `templates/scripts/install-lib.sh` and run
`harness_missing_prereqs`; name every tool it prints to the user *before*
installing the mechanism. The critical one is
**`jq`**: without it every guard hook fails OPEN (see the provider matrix), so
the whole in-turn feedback layer — secret-read denials, the format/lint loop,
the advisory stop-hook — is silently inert and only the native permission deny
lists stay live. `git` and a sha256 tool (`shasum`/`sha256sum`) are the other
hard dependencies. If any are missing, get the user to ACKNOWLEDGE scaffolding a
harness whose feedback layer is degraded (better: install the dependency first)
— do not silently proceed. This is a name-and-acknowledge gate ONLY: it does
**not** change the guards' deliberate fail-open posture, and `check-harness.sh`'s
doctor keeps WARNing on the same condition on every later run (check #10).

1. **Recon (before asking anything).** Detect: languages and build files
   (composer.json, package.json, pyproject.toml, go.mod, Cargo.toml);
   formatter/linter/test commands (from manifest scripts, Makefile, CI
   config); CI system (.github/workflows, .gitlab-ci.yml); existing agent
   config (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursor/`, `.codex/`,
   `.opencode/`, `.agents/`); MCP server configs (`.mcp.json`,
   `.cursor/mcp.json`, `opencode.json` `mcp`, `.codex/config.toml`
   `[mcp_servers.*]`); secret-file patterns present (`.env*`,
   `auth.json`, key files); docs already written. Also classify the repo as an
   **application** (a local service/site/API with meaningful running state) or
   **non-app** (library, docs, static data, or another repo with no running app
   to exercise). For an app, inspect manifest `dev`/`start`/`serve` scripts,
   Compose services and healthchecks, Procfiles, framework entrypoints,
   existing smoke tests, and artifact configuration. Propose all six runtime
   mappings before asking: boot, readiness/health, deterministic seed/reset,
   port injection/allocation, repo-relative logs, and repo-relative traces (or
   no traces). Carry only genuinely unresolved classification or mapping facts
   into the interview. If a partial harness exists, switch to a gap-filling
   variant of this flow — never overwrite hand-written content; migrate it
   toward `docs/` instead.

2. **Interview (only what recon can't answer).** Ask, ideally in one round:
   - Quality gates: the ordered commands that define "done" (recon proposes,
     user confirms). These are written into `scripts/verify.sh`, which is the
     single executable source for them — docs only point at it.
   - The millisecond-fast linter per file type for the post-edit feedback
     loop (`format.sh`'s second TAILOR map) — recon proposes from the
     toolchain; slow static analysis stays in `verify.sh`.
   - Which providers to wire beyond Claude Code + `AGENTS.md` (Cursor?
     Codex? OpenCode? `.agents`? — cheap to include, default to all five).
   - Each MCP server recon found: approve it (name + what it runs or connects
     to) or defer it. The approved set becomes the trust inventory (step 4);
     a deferred server is left out and will surface as drift until listed.
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
   - **Application repos only:** always present the detected app classification
     and proposed six-field runtime map, then require one explicit confirmation
     to adopt the runtime bundle before authoring anything. Ask detailed
     follow-ups only for mappings recon could not prove. A deterministic
     seed/reset is required for adoption; do not disguise a best-effort
     additive seed as a reset. Confirm a candidate port base/span and optional
     namespace while preserving `HARNESS_DEV_PORT` as the explicit override.
     Non-app repos skip every runtime question, leave no placeholders, and
     record runtime support as N/A.

3. **Install mechanism** from `templates/scripts/` into `scripts/` with
   `harness_install_mechanism` from that NEW source's `install-lib.sh`. Let the
   new helper enumerate its own file set instead of copying an old hard-coded
   list; the set includes `dev-instance.sh` (physical-worktree suffix and
   candidate-port derivation) and its regression coverage as well as the
   config, install/sync/check/eval/verify, and hook machinery.
   `chmod +x scripts/hooks/*.sh scripts/*.sh`.
   `install-lib.sh` is the deterministic, model-free core of this flow —
   `harness_install_mechanism` copies exactly this set, and step 8's
   `harness_generate_manifest` and `update` mode both call it; `test-install.sh`
   is its fixture suite. Tailor `harness.conf` (providers, plans dir, secret
   patterns). Append `.harness/` to the repo's `.gitignore` — the hook
   observability log lives there.

4. **Tailor policy** in the marked `TAILOR` blocks:
   - `verify.sh`: write the interviewed quality gates as `gate` (fast:
     formatter/linter), `full_gate` (serial typecheck/tests), or
     `parallel_full_gate` (independent typecheck/tests) lines. Keep serial gates
     cheapest-first and keep the default `harness` gate. Only parallelize gates
     that do not consume one another's outputs or share mutable fixtures.
   - `hooks/format.sh`: uncomment/add extension → formatter lines for the
     detected stack.
   - `harness.conf` `SECRET_PATTERNS` / `SECRET_ALLOW_PATTERNS`: extend for
     the repo's actual secret files — this is the single source
     (`guard-secrets.sh` enforces it, `check-harness.sh` verifies the native
     deny lists against it). Mirror additions into
     `hooks/test-guard-secrets.sh` cases.
   - `harness.conf` `MCP_ALLOWED_SERVERS`: one
     `<name> <identity-substring>` per line for each server approved in the
     interview — the substring is matched fixed-string against the server's
     configured command+args or URL. `check-harness.sh` ERRORs on a
     configured server missing from the inventory or whose identity drifted;
     leave it set-but-empty to assert "no MCP servers" strictly.
   - `harness.conf` `HOOK_WIRED_PROVIDERS` / `AGENT_PROVIDERS`: set each to the
     providers you actually wire in steps 5–6. `HOOK_WIRED_PROVIDERS` is the
     hook-wired subset (`.claude .cursor .codex`; OpenCode is descoped — no bash
     hook shim) whose hook config `check-harness.sh` validates tuple-by-tuple;
     `AGENT_PROVIDERS` is the set that receives generated agent stubs
     (`.claude .cursor .codex .opencode`). A declared provider missing its
     config/stubs is an ERROR; leaving either UNSET on an adopted harness is a
     loud diagnostic. Drop a provider from the set if you don't wire it (set to
     `""` for none).
   - `hooks/guard-config.sh`: extend `PROTECTED_PATHS` with the repo's
     linter/formatter configs — the files an agent could edit to make
     findings disappear. The harness mechanism is protected by default, now
     including `harness.conf`, `.claude/settings.local.json`, and the MCP
     configs (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`);
     post-init `harness.conf` edits (new `SECRET_PATTERNS`,
     `MCP_ALLOWED_SERVERS` entries) use the same
     `HARNESS_ALLOW_MECHANISM_EDITS=1` escape hatch as any other
     protected-file maintenance.
   - `hooks/guard-project-policy.sh`: implement the invariant check from the
     interview (follow the in-file example), or leave the no-op skeleton.
   - **Application repos only — author `scripts/dev.sh`; do not copy a generic
     template.** Implement the confirmed runtime map against
     `templates/docs/conventions/dev-runtime.md`: `up|health|seed|down`, one
     compact JSON v1 object and no other stdout for every recognized action,
     worktree ownership under `.harness/dev/`, deterministic explicit seeding,
     and repo-relative log/trace paths. Use `scripts/dev-instance.sh suffix`
     for the `^h[0-9a-f]{12}$` instance and `port <base> <span> [namespace]`
     for the candidate unless `HARNESS_DEV_PORT` is set. A foreign occupied
     port is an error — never reuse or kill its process. Mark `dev.sh`
     executable. Non-app repos do not get this file.

5. **Author content** (this is authoring, not copying — use the codebase):
   - `AGENTS.md` from `templates/AGENTS.md.tmpl`: fill every placeholder,
     delete sections that don't apply yet rather than leaving stubs.
   - `CLAUDE.md` from `templates/CLAUDE.md.tmpl` — a thin `@AGENTS.md`
     import plus a `verify.sh` pointer; the gates themselves live only in
     `scripts/verify.sh`.
   - `docs/conventions/<topic>.md` for each interviewed convention — short,
     example-driven, written from real code in the repo.
   - `docs/conventions/untrusted-content.md` and
     `docs/conventions/risky-actions.md` from `templates/docs/conventions/` —
     copy, then tailor: set the risky-actions default posture to the repo's
     real defaults, delete inapplicable sections (production environment, MCP)
     and, for the enforcement facts, keep only what the wired providers' rows
     in the provider matrix prove.
   - **Application repos only:** copy
     `templates/docs/conventions/dev-runtime.md` to
     `docs/conventions/dev-runtime.md` and tailor its runtime map; copy the
     self-contained `templates/docs/skills/verify-live/SKILL.md` to
     `docs/skills/verify-live/SKILL.md`. Add both conditional links from the
     AGENTS template. Never point either file at this skill/plugin directory.
     Non-app repos omit the files and links.
   - `docs/skills/<slug>/SKILL.md` per initial skill, following
     `templates/docs/skills/_example/SKILL.md`. Frontmatter descriptions are
     activation triggers — spend effort on them.
   - `docs/agents/<name>.md` personas only if a clear delegation need exists.
     `code-reviewer` is the recommended first one and **ships canonical** as
     `templates/docs/agents/code-reviewer.md` — an inferential reviewer that
     runs after `verify.sh` passes, checks the four classes gates can't see,
     and emits v1-compatible `hook_log` findings to `.harness/log.jsonl` (its
     catch-rate is gated by the `seeded-defect-review` eval). Follow that
     template (or `templates/docs/agents/_example.md` for a bespoke persona) —
     give the canonical doc `name`/`description`/`tools` frontmatter; the
     provider stubs (`.claude/agents/`, `.cursor/agents/`, `.opencode/agents/`
     as Markdown, `.codex/agents/<name>.toml` as TOML) are GENERATED from it by
     `sync-agent-skills.sh` in step 6 — never hand-authored.
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
     guard. `config.toml` only if MCP servers are needed — and every server
     added to `[mcp_servers.*]` gets a matching `MCP_ALLOWED_SERVERS` line
     (step 4). Skills come from `.agents/skills/` — no Codex skill dir.
   - OpenCode: `opencode.json` — its `permission.read` deny block mirrors
     `SECRET_PATTERNS` (keep the two in sync when tailoring; add `"mcp"`
     servers only if needed — each also gets an `MCP_ALLOWED_SERVERS` line,
     step 4). No hook shim ships (descoped 2026-07-13): a TS plugin shim in
     `.opencode/plugins/` shelling out to the portable hooks is the documented
     path (see provider matrix), but the kit provides no template for it, so
     OpenCode is left out of `HOOK_WIRED_PROVIDERS` and its guards degrade to
     these native permissions + CI — the intended backstop, not a gap to fill
     by hand.
   - GitHub Copilot coding agent: nothing to wire — it reads `AGENTS.md`
     natively, including nested files (verified 2026-07-11). Optionally add a
     thin `.github/copilot-instructions.md` pointing at `AGENTS.md` for the
     completions surface. No skill/hook/agent dirs (see provider matrix).
   - Gemini CLI: write `.gemini/settings.json` with
     `{ "context": { "fileName": ["AGENTS.md", "GEMINI.md"] } }` so it loads the
     shared `AGENTS.md` (default reads `GEMINI.md` only; verified 2026-07-11).
   - Run `bash scripts/sync-agent-skills.sh` to generate all skill AND agent
     stubs (agent stubs come from each `docs/agents/*.md` frontmatter into every
     `AGENT_PROVIDERS` dir). In app repos this generates the `verify-live`
     provider stubs only after the canonical skill and AGENTS link exist.

7. **CI gate**: install `templates/ci/github-actions-harness-check.yml` as
   `.github/workflows/harness-check.yml` (or add the `check-harness.sh` step
   to existing CI; translate for other CI systems). If the `code-reviewer`
   persona is wired, optionally add `templates/ci/github-actions-review.yml`
   (the persona as a PR reviewer — SHA-pinned, `pull_request` not
   `pull_request_target`, minimal permissions; opt-in, cost notes in its
   header).

8. **Write the manifest** for upgrades *and* CI integrity — do this AFTER all
   policy tailoring and conditional app authoring, so the checksums pin the
   tailored state. `harness_generate_manifest`
   in `scripts/install-lib.sh` is the single producer; it pins the whole
   `scripts/hooks/` tree plus the top-level files enumerated by the NEW
   installer, including `dev-instance.sh`; in an app repo it also pins the
   authored `dev.sh`:
   ```bash
   . scripts/install-lib.sh
   harness_generate_manifest . <kit-version> > scripts/.harness-manifest
   # Persist the pristine templates as update mode's channel-independent diff
   # base — recoverable with NO local git (plugin/copied installs need not keep
   # .git; see update.md). <src-templates-scripts> is the kit templates/scripts
   # dir this install copied from.
   harness_persist_base <src-templates-scripts> . <kit-version>
   ```
   (kit version = `version` in the kit's `.claude-plugin/plugin.json`).
   `check-harness.sh` verifies these checksums from now on, so every later
   edit must re-pin its line. Append ` # tailored` to a line when the project
   deliberately forks that file (update mode then only ever diffs it, never
   replaces it) — do this for the policy files step 4 tailors: `verify.sh`,
   `hooks/format.sh`, `hooks/guard-project-policy.sh`, and **`harness.conf`**.
   In an app repo, append ` # tailored` to the `dev.sh` manifest line too; it is
   authored project policy and has no kit template to replace it from.
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
   confirm every AGENTS.md link opens. For an app repo, validate every
   `dev.sh` action's single-object JSON schema and lifecycle: `up` waits ready
   without seeding and records whether it started; `seed` resets known data;
   `health` is read-only and exits zero iff ready; `down` stops only this
   worktree and is idempotent. Exercise cleanup only if that validation's
   initial `up` reported `started: true`. Report results honestly, including
   anything left unwired. To rehearse the whole flow on a disposable repo
   first, follow [fixture-recipe.md](../fixture-recipe.md).
