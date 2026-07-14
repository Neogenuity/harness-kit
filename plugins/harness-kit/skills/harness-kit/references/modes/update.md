# Update mode — upgrade harness machinery

**Preflight — runtime prerequisites (before touching the install).** Resolve
`<new_src_scripts>` to the NEW kit's `templates/scripts/` directory, source
`<new_src_scripts>/install-lib.sh`, and run `harness_missing_prereqs`; surface
anything it prints. Do **not** source the target repo's old
`scripts/install-lib.sh` for update decisions: it cannot enumerate mechanism
files introduced after that version. `jq` is the critical prerequisite —
without it every guard hook fails OPEN, so
an upgraded harness's feedback layer stays inert until `jq` is installed; `git`
and a sha256 tool (`shasum`/`sha256sum`) are the other hard dependencies. Name
any that are missing and have the user ACKNOWLEDGE (or install them) before
proceeding. Detection only — the guards' fail-open posture is unchanged and
`check-harness.sh`'s doctor keeps WARNing on the same condition (check #10).

1. Read the target's `scripts/.harness-manifest` (version + checksums). If
   missing, fall back to audit and offer to adopt the manifest.
2. Use the NEW `install-lib.sh`'s `harness_update_apply` inventory for each
   mechanism file; never reconstruct
   the new version's file set from the old manifest or an old hard-coded list.
   Checksum matches manifest → replace with the
   new kit version; differs, or its manifest line is marked ` # tailored` →
   the project owns it; show a diff of old-kit → new-kit and apply only
   what the user approves (recover the old kit's templates per the channel
   matrix below, and use them as the diff base for tailored files).
   `harness_update_apply` from the NEW `install-lib.sh` runs this decision
   deterministically (`harness_update_decision` classifies each line
   replace-vs-diff); it is the same code `test-install.sh` pins. Set
   `HARNESS_ALLOW_MECHANISM_EDITS=1` for the session if `guard-config.sh` is
   wired — upgrading the mechanism is the intended use of that escape hatch.

   **Recovering the old templates (the diff base) — per install channel.** The
   diff needs the OLD kit version's templates, where the version is the manifest
   header (`harness_manifest_version` in `install-lib.sh`). How to obtain them
   depends on how the kit was installed:
   - **git checkout of the kit** (dev, or clone-and-copy from a git working
     tree): read them straight from the kit repo at the matching tag —
     `git show v<version>:plugins/harness-kit/skills/harness-kit/templates/scripts/<f>`.
     No persistence needed.
   - **plugin install** (Claude/Codex plugin cache): the cache holds only
     `plugins/harness-kit/` and need not retain `.git`. Recover from the
     persisted base (below); if it is absent, fetch tag `v<version>` from the
     declared upstream repo (the marketplace `source`) once it is reachable and
     public.
   - **copied install without `.git`**: neither a local tag nor the kit source
     is on hand, so the persisted base is the only path.
   The **channel-independent** path is the locally-persisted base:
   `harness_recover_old_templates <repo_root> <out_dir>` (`install-lib.sh`)
   reproduces the version's templates from `.harness/base/<version>/scripts/`
   with NO git and NO network — it is the code `test-install.sh` pins for the
   no-local-git channel. init writes that snapshot at install time and step 4
   refreshes it after each update. It returns non-zero when the base is missing
   (e.g. a teammate's fresh clone, where the git-ignored base was never checked
   out); fall back to the git-tag or upstream-fetch channels, or — as a last
   resort — diff the tailored file against the NEW template only and say so.
   Never present a silent empty diff.
3. Never auto-overwrite policy files (`verify.sh`, `format.sh`,
   `guard-secrets.sh`, `guard-project-policy.sh`, `harness.conf`, provider
   configs, or an app repo's authored `dev.sh`) — diff only. Never auto-add or
   overwrite content files, including conventions, skills, AGENTS links, and
   generated stubs; mechanism update and content adoption are separate acts.
4. Rewrite the manifest with the new version/checksums — `harness_repin_manifest`
   in `install-lib.sh` regenerates it while preserving every ` # tailored`
   marker — then persist the new templates as the NEXT update's diff base with
   `harness_persist_base <new_src_scripts> <repo_root> <new_version>` (prune the
   superseded `.harness/base/<old_version>/`), and re-run `check-harness.sh` and
   all hook tests.
5. **Migrate the declared provider sets if a pre-v0.14 install lacks them.**
   `check-harness.sh` now fails when an adopted harness leaves
   `HOOK_WIRED_PROVIDERS` (semantic hook-wiring validation) or `AGENT_PROVIDERS`
   (agent-stub coherence) undeclared, and `harness.conf` is diff-only here so the
   lines never appear on their own. If either is absent (`harness_conf_declared`
   in `install-lib.sh` reports it), PROPOSE the default sets —
   `HOOK_WIRED_PROVIDERS=".claude .cursor .codex"`,
   `AGENT_PROVIDERS=".claude .cursor .codex .opencode"` — narrowed to the
   providers this repo actually wired, and ask the user to CONFIRM. Never infer
   the set from whichever configs/stubs survive on disk: a config deleted before
   the upgrade is indistinguishable from a provider never wired, so adopting
   survivors would silently bless a deletion — surface any resulting
   declared-but-missing config as the ERROR it is. Record the confirmed value
   with `harness_conf_declare` (idempotent — a second update neither duplicates
   the line nor resets an edited value), then re-pin the manifest so the new
   `harness.conf` checksum is captured.
6. **Offer existing application repos explicit runtime adoption.** Use init's
   app detection and recon to propose boot, health, deterministic seed/reset,
   port, log, and trace mappings. Non-app repos report N/A. For an app without
   the bundle, explain that new kit mechanism now supplies
   `scripts/dev-instance.sh`, but take no content action unless the user opts
   in. On opt-in only: author (never template-copy) executable
   `scripts/dev.sh`; copy and tailor `docs/conventions/dev-runtime.md` and
   `docs/skills/verify-live/SKILL.md`; add their conditional AGENTS links; run
   `scripts/sync-agent-skills.sh`; and manifest-pin `dev.sh` with
   ` # tailored`. If any of these files already exists, preserve it and show a
   proposed diff — never silently replace local content. Re-run the v1 contract
   checks and manifest/stub checks after approved adoption.
7. When the request is really a *standards* shift — a provider newly reads
   `.agents/skills/` natively, Claude Code ships AGENTS.md support, a new
   harness appears — follow the matching playbook in
   [migrations.md](../migrations.md) instead of
   improvising.
