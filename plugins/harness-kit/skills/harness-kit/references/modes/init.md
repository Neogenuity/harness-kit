# Init mode — scaffold a repo

Read [../pattern.md](../pattern.md) first if unread this session; provider file
locations and event mappings are in [../provider-matrix.md](../provider-matrix.md).

**Preflight — runtime prerequisites (before scaffolding anything).** Source the
NEW kit's `templates/scripts/harness/lib/install-lib.sh` and run
`harness_missing_prereqs`; name every tool it prints to the user *before*
installing the mechanism. The critical one is
**`jq`**: without it every guard hook fails OPEN (see the provider matrix), so
the whole in-turn feedback layer — secret-read denials, the format/lint loop,
the advisory stop-hook — is silently inert and only the native permission deny
lists stay live. `git`, `mktemp`, and a sha256 tool (`shasum`/`sha256sum`) are
the other prerequisites: `mktemp` (race-safe staging of every installed file)
and the sha256 tool (integrity pins) are **hard-gated** — the installer refuses
without them, `--allow-degraded` does not cover them; `git` (session banner +
Codex Git-root) merely degrades. If any are missing, get the user to ACKNOWLEDGE
scaffolding a harness whose feedback layer is degraded (better: install the dependency first)
— do not silently proceed. This is a name-and-acknowledge gate ONLY: it does
**not** change the guards' deliberate fail-open posture, and `check-harness`'s
doctor keeps WARNing on the same condition on every later run (check #10).

1. **Recon (before asking anything).** Detect: languages and build files
   (composer.json, package.json, pyproject.toml, go.mod, Cargo.toml);
   formatter/linter/test commands (from manifest scripts, Makefile, CI
   config); CI system (.github/workflows, .gitlab-ci.yml); existing agent
   config (`CLAUDE.md`, `AGENTS.md`, `.claude/`, `.cursor/`, `.codex/`,
   `.opencode/`, `.agents/`); MCP server configs (`.mcp.json`,
   `.cursor/mcp.json`, `opencode.json` `mcp`, `.codex/config.toml`
   `[mcp_servers.*]`); existing execution policy (`sandbox` in Claude settings,
   `.cursor/sandbox.json`, Codex sandbox/approval/network keys, OpenCode
   `permission`); any `.devcontainer/` plus the concrete image, Dockerfile, or
   Compose service it uses; secret-file patterns present (`.env*`,
   `auth.json`, key files); docs already written; existing `.harness/var/log.jsonl`,
   eval baselines/results, and documentation scheduling. Also classify the repo
   as an **application** (a local service/site/API with meaningful running state) or
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
     user confirms). These are written as declarations into
     `.harness/gates.conf`, which the kit-owned `scripts/harness/verify`
     runner executes — docs only point at the runner.
   - The millisecond-fast linter per file type for the post-edit feedback
     loop (`harness.conf`'s `FORMAT_RULES`/`LINT_RULES` data) — recon
     proposes from the toolchain; slow static analysis stays in the full
     gates of `.harness/gates.conf`.
   - Which providers to wire beyond Claude Code + `AGENTS.md` (Cursor?
     Codex? OpenCode? — cheap to include, default to all four:
     `HARNESS_PROVIDERS=".claude .cursor .codex .opencode"`). `.agents/skills/`
     is the canonical skills home every provider reads or is stubbed from — it
     is never itself a wired provider (`provider-caps` gives it no row and check
     `#8f` rejects it in `HARNESS_PROVIDERS`).
   - **Execution-profile adoption is a separate explicit choice.** For each
     wired provider, offer the stable tuple from
     `templates/docs/standards/execution-profiles.md`, name that provider's
     temp roots and enforcement limits, and ask which providers to declare.
     Existing config gets a proposed merge diff only. For an app, offer the
     experimental Codex broad local/private-network compatibility variant only
     when local command access is confirmed. State that it is not
     localhost-only and does not prove ownership-safe teardown. Report a strict
     repo-local localhost-only variant as unavailable on the observed Codex
     build, and do not broaden the other three providers to imitate one.
     Claude's credential tuple requires Claude
     Code 2.1.187 or later.
   - **Devcontainer adoption is another separate opt-in.** Offer it only when
     recon proved a real image, Dockerfile, or Compose source. Confirm the
     non-root user, mounts, ports, and explicit verification steps; if those
     cannot be proven, defer it. Never offer a placeholder container.
   - Each MCP server recon found: approve it (name + what it runs or connects
     to) or defer it. The approved set becomes the trust inventory (step 4);
     a deferred server is left out and will surface as drift until listed.
   - The 2-4 conventions worth a `docs/standards/` doc (what do reviewers
     correct most often?).
   - The first 1-3 skills: recurring task shapes with a known recipe
     (e.g. "add an endpoint", "add a model").
   - Offer the self-contained `doc-garden` skill. Adoption adds canonical
     content, its AGENTS link, and generated stubs; it does not authorize a
     schedule, external link probes, edits, commits, pushes, or PRs. Keep the
     default scan offline and read-only. A trusted existing scheduler may run it
     later with separately configured permissions.
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
   `harness_install_mechanism` from that NEW source's `install-lib.sh`. The
   file set comes from the source's `kit-manifest` — the declarative SHIP
   CONTRACT (one `<layer> <path>` line per shipped file: mechanism, policy,
   optional-policy, plus a retired section) that installs alongside the
   mechanism as `scripts/harness/kit-manifest`. Never copy from a hard-coded list;
   every installer/manifest/checker function derives its set from the
   kit-manifest, so a new shipped file is one added line. The shipped set
   includes `dev-instance.sh` (physical-worktree suffix and candidate-port
   derivation), `log-lib.sh` (fail-open v2 helpers), `audit-log.sh`
   (deterministic mixed-log/eval reduction), `doc-garden.sh` (offline
   documentation scanning), and their regression coverage as well as the
   config, install/sync/check/eval/verify, and hook machinery.
   (`harness_install_mechanism` marks the extensionless commands and every
   `*.sh` executable itself — no manual chmod pass).
   `lib/install-lib.sh` is the deterministic, model-free core of this flow —
   `harness_install_mechanism` copies exactly the set the kit-manifest
   declares, and step 8's `harness_generate_manifest` and `update` mode both
   flow through the same contract; the kit repo's maintainer-only
   `test-install-*.sh` suites are its fixture coverage, and the shipped
   `tests/test-harness-smoke.sh` is the adopter-side proof. Tailor
   `harness.conf` (providers, plans dir, secret patterns). Append
   `.harness/var/` to the repo's `.gitignore` — runtime state (the
   observability log, update baselines, eval results) lives there; the rest
   of `.harness/` (gates.conf, the project-policy hook) is committed.

4. **Tailor policy** in the marked `TAILOR` blocks:
   - `.harness/gates.conf`: write the interviewed quality gates as one
     declaration per line — `gate` (fast: formatter/linter, runs in both
     modes), `full` (serial typecheck/tests), `parallel` (independent
     typecheck/tests), or `parallel-each` (one gate per glob-matched file).
     Keep serial gates cheapest-first and keep the default `harness` gate
     (`bash scripts/harness/check-harness`) and the shipped-test
     `parallel-each`. Only parallelize gates that do not consume one
     another's outputs or share mutable fixtures; a `full` gate is also a
     barrier for parallel gates declared before it. The RUNNER
     (`scripts/harness/verify`) is kit-owned mechanism — it emits the v2
     gate events (name, mode, outcome, exit code, integer duration, never
     command output) itself, so gate policy and orchestration can no longer
     drift apart.
   - `harness.conf` `FORMAT_RULES` / `LINT_RULES`: one
     `<glob[|glob...]>=<command>` line per formatter / fast linter for the
     detected stack (the format hook is mechanism; its policy is this data).
     `GUARD_PROTECTED_EXTRA`: the repo's lint/formatter configs an agent
     could edit to make findings disappear.
   - `harness.conf` `SECRET_PATTERNS` / `SECRET_ALLOW_PATTERNS`: extend for
     the repo's actual secret files — this is the single source
     (`guard-secrets.sh` enforces it, `check-harness` verifies the native
     deny lists against it). Mirror additions into
     `tests/test-guard-secrets.sh` cases.
   - `harness.conf` `MCP_ALLOWED_SERVERS`: one
     `<name> <identity-substring>` per line for each server approved in the
     interview — the substring is matched fixed-string against the server's
     configured command+args or URL. `check-harness` ERRORs on a
     configured server missing from the inventory or whose identity drifted;
     leave it set-but-empty to assert "no MCP servers" strictly.
   - `harness.conf` `HARNESS_PROVIDERS`: the single declaration of the provider
     dirs you wire in steps 5–6 (ADR 011). The kit capability table
     (`scripts/harness/lib/provider-caps`) derives the per-facet sets from it —
     skill stubs (providers that don't read `.agents/skills/` natively; `.codex`
     does, so it gets none), agent stubs (all four dialects), and the hook-wired
     subset (`.claude .cursor .codex`; OpenCode is descoped — no bash hook shim)
     whose config `check-harness` validates tuple-by-tuple. `check-harness`
     validates the derived sets and the declaration itself; a declared provider
     missing its config/stubs is an ERROR, and an unknown entry is a loud `#8f`
     diagnostic. Set to `""` to wire no providers. The per-facet override knobs
     (`PROVIDERS`/`HOOK_WIRED_PROVIDERS`/`AGENT_PROVIDERS`, commented in the
     template) are only for the rare case where one facet must differ from the
     derivation.
   - `harness.conf` `EXECUTION_PROFILE_PROVIDERS`: NOT derived from
     `HARNESS_PROVIDERS` (ADR 011 — a strict runtime floor must never be imposed
     as a side effect of naming a provider). Set it to exactly the
     provider subset explicitly confirmed in step 2. Unset/empty means
     unadopted; never infer this declaration from configs that happen to exist.
     A declared provider makes its accepted profile a semantic drift gate:
     fixed stable tuples, with only the accepted Codex experimental broad
     local/private-network compatibility disjunction as an alternative.
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
     `templates/docs/runbooks/local-development.md`: `up|health|seed|down`, one
     compact JSON v1 object and no other stdout for every recognized action,
     worktree ownership under `.harness/var/dev/`, deterministic explicit seeding,
     and repo-relative log/trace paths. Use `scripts/harness/lib/dev-instance.sh suffix`
     for the `^h[0-9a-f]{12}$` instance and `port <base> <span> [namespace]`
     for the candidate unless `HARNESS_DEV_PORT` is set. A foreign occupied
     port is an error — never reuse or kill its process. Mark `dev.sh`
     executable. Non-app repos do not get this file.

5. **Author content** (this is authoring, not copying — use the codebase):
   - `AGENTS.md` from `templates/AGENTS.md.tmpl`: fill every placeholder,
     delete sections that don't apply yet rather than leaving stubs.
   - `CLAUDE.md` from `templates/CLAUDE.md.tmpl` — a thin `@AGENTS.md`
     import plus a `scripts/harness/verify` pointer; the gate list itself
     lives only in `.harness/gates.conf`.
   - `docs/standards/<topic>.md` for each interviewed convention — short,
     example-driven, written from real code in the repo.
   - `.harness/policies/security.md` and
     `.harness/policies/changes.md` from `templates/docs/policies/` —
     copy, then tailor: set the risky-actions default posture to the repo's
     real defaults, delete inapplicable sections (production environment, MCP)
     and, for the enforcement facts, keep only what the wired providers' rows
     in the provider matrix prove.
   - Copy `templates/docs/standards/outcome-telemetry.md` to
     `docs/standards/outcome-telemetry.md` and keep its AGENTS link. It is the
     self-contained exact v1/v2, provenance, privacy, reducer, and N/A contract
     for the local mechanism installed in step 3. Do not replace it with a link
     into this plugin or combine it with provider observability.
   - **Adopted execution profiles or devcontainer:** copy
     `templates/docs/standards/execution-profiles.md` into
     `docs/standards/execution-profiles.md` after at least one provider
     profile is adopted **or** the devcontainer is separately adopted. Tailor
     it to the confirmed provider subset, any named weakening, and/or the
     authored devcontainer, then keep its conditional AGENTS link. The
     installed file is self-contained: never point it back into this skill.
     Repos adopting neither boundary omit the file and link. Devcontainer-only
     adoption does not add an `EXECUTION_PROFILE_PROVIDERS` declaration.
   - **Application repos only:** copy
     `templates/docs/runbooks/local-development.md` to
     `docs/runbooks/local-development.md` and tailor its runtime map; copy the
     self-contained `templates/docs/skills/verify-live/SKILL.md` to
     `.agents/skills/verify-live/SKILL.md`. Add both conditional links from the
     AGENTS template. Never point either file at this skill/plugin directory.
     Non-app repos omit the files and links.
   - If the user adopted doc gardening, copy
     `templates/docs/skills/doc-garden/SKILL.md` to
     `.agents/skills/doc-garden/SKILL.md`, keep its conditional AGENTS link, and
     generate its provider stubs in step 6. Otherwise remove the link and create
     no canonical/stub files.
   - `.agents/skills/<slug>/SKILL.md` per initial skill, following
     `templates/docs/skills/_example/SKILL.md`. Frontmatter descriptions are
     activation triggers — spend effort on them.
   - `.harness/agents/<name>.md` personas only if a clear delegation need exists.
     `code-reviewer` is the recommended first one and **ships canonical** as
     `templates/docs/agents/code-reviewer.md` — an inferential reviewer that
     runs after `scripts/harness/verify` passes, checks the four classes gates can't see,
     and emits v1-compatible `hook_log` findings to `.harness/var/log.jsonl` (its
     catch-rate is gated by the `seeded-defect-review` eval). Follow that
     template (or `templates/docs/agents/_example.md` for a bespoke persona) —
     give the canonical doc `name`/`description`/`tools` frontmatter; the
     provider stubs (`.claude/agents/`, `.cursor/agents/`, `.opencode/agents/`
     as Markdown, `.codex/agents/<name>.toml` as TOML) are GENERATED from it by
     `scripts/harness/sync` in step 6 — never hand-authored.
   - `docs/plans/PLANS.md` from `templates/docs/plans/PLANS.md` (AGENTS.md
     links it, so `check-harness` needs it to exist), and create the
     `PLANS_DIR` (`docs/plans/active/` by default) with a `.gitkeep` so
     `session-context.sh` has a directory to announce. Copy
     `templates/docs/templates/execution-plan.md` to `.harness/templates/`; seed real plans only
     when there's long-horizon work to track (an empty queue is fine).
   - `.harness/evals/` from `templates/docs/evals/` (`README.md` + `scenarios/_template/`
     + `rubrics/_example.md`) — the behavioral eval bank. Author real golden
     tasks only for the recurring success-defining work named in the interview;
     an empty bank is fine, but if you ship none, delete the AGENTS.md Evals
     link so `check-harness` doesn't dangle. Each task grades the *end state*
     via `check.sh` and ships a `reference/apply.sh` that `test-eval.sh` proves
     scores as a pass (and, for negative tasks, a `reference/violate.sh` it
     proves scores as a fail).

6. **Wire providers** (for each provider chosen in the interview):
   - Claude Code: merge the `permissions` and `hooks` subtrees from
     `templates/providers/claude/settings.json` into `.claude/settings.json`.
     Extend `permissions.allow` with the quality-gate
     commands and `permissions.deny` with `Read(...)` entries covering every
     tailored `SECRET_PATTERNS` glob — `check-harness` fails when the deny
     list misses one. When `.claude` is in `EXECUTION_PROFILE_PROVIDERS`, merge
     the template's `sandbox` object too; otherwise omit that optional subtree
     even on a fresh install. Stop if the installed Claude Code is older than
     2.1.187. Merge, don't clobber, an existing file.
   - Cursor: `templates/providers/cursor/hooks.json` → `.cursor/hooks.json`;
     one `.cursor/rules/<topic>.mdc` per convention doc from
     `templates/providers/cursor/rules/_example.mdc`. When `.cursor` is
     declared for execution profiles, merge
     `templates/providers/cursor/sandbox.json` into
     `.cursor/sandbox.json`; say that effective closed egress also needs the
     **sandbox.json Only** UI mode or admin policy.
   - Codex: `templates/providers/codex/hooks.json` → `.codex/hooks.json`
     (hooks are GA and on by default, but project-local configs load only
     when the project is trusted — see provider matrix). Codex payloads
     carry no file path: the guards parse apply_patch envelopes and
     token-scan shell commands via `lib.sh:hook_affected_files` — best
     effort, so keep Codex's native trust/permission layer as a second
     guard. Install or merge `config.toml` when MCP servers are needed **or**
     `.codex` is declared for execution profiles. Preserve every existing MCP
     table; every new `[mcp_servers.*]` server gets a matching
     `MCP_ALLOWED_SERVERS` line (step 4). For an MCP-only, unadopted install,
     write only the MCP tables/comments and omit the active profile keys from
     the combined template. Before declaring `.codex`, require Python 3.11+
     with `tomllib` (`python3 -I -c 'import tomllib'`); otherwise report the
     profile as unverifiable and leave it undeclared. The local/private-network
     compatibility variant is explicit and experimental, keeps exact
     localhost/127.0.0.1 domain rules, and requires broad local binding; it is
     not localhost-only or full runtime-lifecycle compatibility. Skills come
     from `.agents/skills/` — no Codex skill dir.
   - OpenCode: `opencode.json` — its `permission.read` deny block mirrors
     `SECRET_PATTERNS` (keep the two in sync when tailoring; add `"mcp"`
     servers only if needed — each also gets an `MCP_ALLOWED_SERVERS` line,
     step 4). The base install omits the template's other permission fields.
     When `.opencode` is declared for execution profiles, merge the
     `external_directory`, `bash`, `webfetch`, and `websearch` permission
     tuples; state that they are prompts/denials, not an OS/network sandbox.
     No hook shim ships (descoped 2026-07-13): a TS plugin shim in
     `.opencode/plugins/` shelling out to the portable hooks is the documented
     path (see provider matrix), but the kit provides no template for it, so
     OpenCode is left out of `HOOK_WIRED_PROVIDERS` and its guards degrade to
     these native permissions + CI — the intended backstop, not a gap to fill
     by hand.
   - GitHub Copilot coding agent: nothing to wire — it reads `AGENTS.md`
     natively, including nested files (verified 2026-07-11). Copy
     `templates/github-copilot-instructions.md.tmpl` to
     `.github/copilot-instructions.md` (kit-manifest content entry) so the
     completions surface gets the same thin pointer. No skill/hook/agent
     dirs (see provider matrix).
   - Gemini CLI: copy `templates/GEMINI.md.tmpl` to `GEMINI.md` (content
     entry), and write `.gemini/settings.json` with
     `{ "context": { "fileName": ["AGENTS.md", "GEMINI.md"] } }` so it loads the
     shared `AGENTS.md` (default reads `GEMINI.md` only; verified 2026-07-11).
   - Run `bash scripts/harness/sync` to generate all skill AND agent
     stubs (agent stubs come from each `.harness/agents/*.md` frontmatter into every
     `AGENT_PROVIDERS` dir). In app repos this generates the `verify-live`
     provider stubs only after the canonical skill and AGENTS link exist.

   **Optional devcontainer, after provider wiring:** author
   `.devcontainer/devcontainer.json` only from the confirmed source in step 2.
   Preserve every existing devcontainer file and show a proposed diff. Require
   a non-root user; mount no host credentials, SSH/GPG agent, or container-engine
   socket; and do not auto-run repo code in lifecycle hooks. Build it before
   acceptance. For an app, explicitly exercise the existing `scripts/dev.sh`
   contract inside the container instead of creating another launcher. Even
   when no provider profile is adopted, copy/tailor the combined
   `execution-profiles.md` convention and keep its AGENTS link for this
   devcontainer boundary.

7. **CI gate**: install `templates/ci/github-actions-harness-check.yml` at
   its declared destination (`.github/workflows/harness-check.yml` — the
   template→destination rename map is the kit-manifest's `content` layer
   `dest=` entries, the same file step 3 installed; read renames from there,
   don't restate them). Or add the `check-harness` step
   to existing CI; translate for other CI systems. If the `code-reviewer`
   persona is wired, optionally add `templates/ci/github-actions-review.yml`
   at its declared destination (the persona as a PR reviewer — SHA-pinned,
   `pull_request` not
   `pull_request_target`, minimal permissions; opt-in, cost notes in its
   header).

8. **Write the manifest** for upgrades *and* CI integrity — do this AFTER all
   policy tailoring and conditional app authoring, so the checksums pin the
   tailored state. `harness_generate_manifest`
   in `scripts/harness/lib/install-lib.sh` is the single producer; it pins the whole
   `scripts/harness/hooks/` tree plus the top-level files enumerated by the NEW
   installer, including `dev-instance.sh`; in an app repo it also pins the
   authored `dev.sh`:
   ```bash
   . scripts/harness/lib/install-lib.sh
   harness_generate_manifest . <kit-version> > scripts/harness/.harness-manifest
   # Persist the pristine templates as update mode's channel-independent diff
   # base — recoverable with NO local git (plugin/copied installs need not keep
   # .git; see update.md). <src-templates-scripts> is the kit templates/scripts
   # dir this install copied from.
   harness_persist_base <src-templates-scripts> . <kit-version>
   ```
   (kit version = `version` in the kit's `.claude-plugin/plugin.json`).
   `check-harness` verifies these checksums from now on, so every later
   edit must re-pin its line. Append ` # tailored` to a line when the project
   deliberately forks that file (update mode then only ever diffs it, never
   replaces it) — do this for the policy files step 4 tailors:
   `.harness/gates.conf`, `.harness/hooks/guard-project-policy.sh`, and
   **`harness.conf`**.
   In an app repo, append ` # tailored` to the `dev.sh` manifest line too; it is
   authored project policy and has no kit template to replace it from.
   Pinning `harness.conf` is load-bearing: its `SECRET_PATTERNS` is the single
   source for the secret guard, so an un-re-pinned narrowing (which would
   silently disarm the guard) must fail CI like any other policy edit — shell
   edits are unscanned by design, so this manifest is their enforcing layer.

9. **Verify — do not skip**: before the verify runner can create the real local log,
   prove the no-data path against an explicitly absent fixture:

   ```bash
   [ ! -e .harness/init-no-data-check.absent.jsonl ] && \
     bash scripts/harness/lib/audit-log.sh --log .harness/init-no-data-check.absent.jsonl --format table
   ```

   Confirm it reports
   `log.status: no_data`, zero parser counters, empty gate/retry/deny sections,
   and review count zero. Git/eval sections remain independently derived. Then
   require `bash scripts/harness/verify` and `bash scripts/harness/check-harness` to pass;
   each `scripts/harness/hooks/test-*.sh` passes standalone; run `bash scripts/harness/tests/test-log.sh`,
   `bash scripts/harness/tests/test-audit-log.sh`, and `bash scripts/harness/tests/test-doc-garden.sh`
   directly; feed `guard-secrets.sh` a real payload for the repo's
   own `.env` and `guard-config.sh` one for `scripts/harness/hooks/lib.sh`, confirm
   exit 2 for both; repeat both with Codex-shaped payloads (an apply_patch
   envelope in `tool_input.command` — crib the builders from
   `scripts/harness/tests/test-affected-files.sh`) and confirm exit 2 again;
   confirm every AGENTS.md link opens. If doc-garden was adopted, run its
   default offline report and confirm it made no changes. For an app repo,
   validate every
   `dev.sh` action's single-object JSON schema and lifecycle: `up` waits ready
   without seeding and records whether it started; `seed` resets known data;
   `health` is read-only and exits zero iff ready; `down` stops only this
   worktree and is idempotent. Exercise cleanup only if that validation's
   initial `up` reported `started: true`. Report results honestly, including
   anything left unwired. For each declared execution profile, run the semantic
   checks and report effective-policy caveats (especially Cursor UI/admin scope
   and OpenCode's missing OS boundary). If a devcontainer was adopted, build it
   and run the confirmed gates inside it before reporting success. To rehearse
   the whole flow on a disposable repo
   first, follow [fixture-recipe.md](../fixture-recipe.md).
