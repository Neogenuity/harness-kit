# Update mode — upgrade harness machinery

**Preflight — runtime prerequisites (before touching the install).** Resolve
`<new_src_scripts>` to the NEW kit's `templates/scripts/` directory, source
`<new_src_scripts>/install-lib.sh`, and run `harness_missing_prereqs`; surface
anything it prints. Do **not** source the target repo's old
`scripts/harness/lib/install-lib.sh` for update decisions: it cannot enumerate mechanism
files introduced after that version. `jq` is the critical prerequisite —
without it every guard hook fails OPEN, so
an upgraded harness's feedback layer stays inert until `jq` is installed; `git`
and a sha256 tool (`shasum`/`sha256sum`) are the other hard dependencies. Name
any that are missing and have the user ACKNOWLEDGE (or install them) before
proceeding. Detection only — the guards' fail-open posture is unchanged and
`check-harness`'s doctor keeps WARNing on the same condition (check #10).

1. Read the target's `scripts/harness/.harness-manifest` (version + checksums). If
   missing, fall back to audit and offer to adopt the manifest.
2. Use the NEW kit's `kit-manifest` (read through the NEW `install-lib.sh`'s
   `harness_update_apply`) as the inventory; never reconstruct
   the new version's file set from the old manifest or an old hard-coded list.
   Checksum matches manifest → replace with the
   new kit version; differs, or its manifest line is marked ` # tailored` →
   the project owns it; show a diff of old-kit → new-kit and apply only
   what the user approves (recover the old kit's templates per the channel
   matrix below, and use them as the diff base for tailored files).
   `harness_update_apply` from the NEW `install-lib.sh` runs this decision
   deterministically (`harness_update_decision` classifies each line
   replace-vs-diff against the NEW kit-manifest's layers); it is the same code
   `test-install-update.sh` pins. Set
   `HARNESS_ALLOW_MECHANISM_EDITS=1` for the session if `guard-config.sh` is
   wired — upgrading the mechanism is the intended use of that escape hatch.

   **Layout migration (pre-v0.23.0 installs).** `harness_update_apply`
   itself migrates the integrity manifest from `scripts/.harness-manifest`
   to `scripts/harness/.harness-manifest` (reported `migrate ...`), retires
   the old flat paths, and installs the `scripts/harness/` tree. After the
   apply, run `harness_append_gitignore <repo_root>` — it narrows a
   pre-v0.23.0 `.harness/` ignore line to `.harness/var/` (gates.conf and
   the policy hook are committed now) — and move the repo's runtime state
   under `.harness/var/` (`log.jsonl`, `base/`, `eval-results/`, `dev/`).
   Tailored policy CONTENT moves as approved diffs, not automatically: the
   old `verify.sh` gate block becomes `.harness/gates.conf` declarations,
   `scripts/harness.conf` content moves to `scripts/harness/harness.conf`,
   and a tailored `scripts/hooks/guard-project-policy.sh` moves to
   `.harness/hooks/`. Their old copies are retire-keep until resolved.

   **Retired paths.** The NEW kit-manifest's `retired` section names files the
   kit no longer ships. `harness_update_apply` removes an installed copy only
   when it is pristine (sha still matches its pin) and not ` # tailored`, and
   reports `remove <path>`; a drifted or tailored copy is kept and reported
   `retire-keep <path>` — surface those to the user for manual review
   (check-harness #9d keeps WARNing until they are resolved). Retirement must
   never delete local changes.

   For older inventories, newly introduced files
   (`log-lib.sh`, `audit-log.sh`, `doc-garden.sh`, their regression tests, and
   `kit-manifest` itself for pre-v0.21.0 installs) are
   normal mechanism additions. A manifest-matching `hooks/lib.sh` is pristine
   mechanism and may be replaced with the newer version; a locally changed
   copy remains diff-only under the checksum rule. Never make the old inventory
   enumerate these files by hand.

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
   reproduces the version's templates from `.harness/var/base/<version>/scripts/`
   with NO git and NO network — it is the code `test-install-recovery.sh`
   pins for the no-local-git channel. init writes that snapshot at install
   time and step 4
   refreshes it after each update. It returns non-zero when the base is missing
   (e.g. a teammate's fresh clone, where the git-ignored base was never checked
   out); fall back to the git-tag or upstream-fetch channels, or — as a last
   resort — diff the tailored file against the NEW template only and say so.
   Never present a silent empty diff.
3. Never auto-overwrite policy files (the kit-manifest's policy and
   optional-policy layers: `.harness/gates.conf`,
   `.harness/hooks/guard-project-policy.sh`, `harness.conf`, an app repo's
   authored `dev.sh` — plus provider
   configs, `.cursor/sandbox.json`, and `.devcontainer/*`, which are never
   pinned) — diff only. (`guard-secrets.sh` is mechanism since v0.21.0 and
   `format.sh` since v0.23.0: their policy lives entirely in `harness.conf` —
   `SECRET_PATTERNS`, `FORMAT_RULES`/`LINT_RULES`, `GUARD_PROTECTED_EXTRA` —
   so a pristine copy upgrades like any other mechanism file. A pre-v0.23.0
   install's tailored `format.sh` case arms migrate into `harness.conf`
   rules as part of the update diff.) Never auto-add or
   overwrite content files, including conventions, skills, AGENTS links, and
   generated stubs; mechanism update and content adoption are separate acts.
   The verify RUNNER is mechanism since v0.23.0 (a pristine copy upgrades
   automatically); the repo's gate list stays tailored policy in
   `.harness/gates.conf` — a pre-v0.23.0 install's tailored `verify.sh` gate
   block migrates into gates.conf declarations as part of the update diff,
   applied only with explicit approval. Installing the reducer/writer
   helpers alone does not prove gate outcomes are emitted; if that migration
   is declined, audit reports gate trends as no-data/N/A while continuing to
   read existing v1 hook/reviewer lines.
4. Rewrite the manifest with the new version/checksums — `harness_repin_manifest`
   in `install-lib.sh` regenerates it while preserving every ` # tailored`
   marker — then persist the new templates as the NEXT update's diff base with
   `harness_persist_base <new_src_scripts> <repo_root> <new_version>` (prune the
   superseded `.harness/var/base/<old_version>/`), and re-run `check-harness` and
   all hook tests.
5. **Migrate to the single provider declaration if an older install lacks it.**
   Since v0.25.0 the wiring sets derive from one `HARNESS_PROVIDERS` declaration
   through the kit capability table (ADR 011); `harness.conf` is diff-only here,
   so the line never appears on its own. If `HARNESS_PROVIDERS` is absent
   (`harness_conf_declared` in `install-lib.sh` reports it) but the install
   carries the legacy explicit lists, those lists still validate as overrides —
   nothing breaks — but PROPOSE consolidating to
   `HARNESS_PROVIDERS="<the providers this repo wires>"` (the union of the legacy
   sets) and ask the user to CONFIRM, then optionally remove the now-redundant
   `PROVIDERS`/`HOOK_WIRED_PROVIDERS`/`AGENT_PROVIDERS` lines that equal the
   derivation. A genuinely pre-declaration install (none of the sets present) is
   the same loud diagnostic as before until `HARNESS_PROVIDERS` is confirmed.
   Never infer the set from whichever configs/stubs survive on disk: a config
   deleted before the upgrade is indistinguishable from a provider never wired,
   so adopting survivors would silently bless a deletion — surface any resulting
   declared-but-missing config as the ERROR it is. Record the confirmed value
   with `harness_conf_declare` (idempotent — a second update neither duplicates
   the line nor resets an edited value), then re-pin the manifest so the new
   `harness.conf` checksum is captured. `EXECUTION_PROFILE_PROVIDERS` stays a
   separate opt-in (never derived) — see the paragraph below.

   `EXECUTION_PROFILE_PROVIDERS` is different because profiles are optional.
   If it is absent, leave it unset and report **unadopted**; never infer
   adoption from provider configs already on disk. Offer the stable tuples
   after mechanism update, and declare only the provider subset the user
   explicitly confirms. An empty declaration is also valid.
   Before declaring `.codex`, verify Python 3.11+ `tomllib` with
   `python3 -I -c 'import tomllib'`; without a complete TOML parser, classify
   that profile as unverifiable and do not adopt it.
6. **Offer existing application repos explicit runtime adoption.** Use init's
   app detection and recon to propose boot, health, deterministic seed/reset,
   port, log, and trace mappings. Non-app repos report N/A. For an app without
   the bundle, explain that new kit mechanism now supplies
   `scripts/harness/lib/dev-instance.sh`, but take no content action unless the user opts
   in. On opt-in only: author (never template-copy) executable
   `scripts/dev.sh`; copy and tailor `docs/runbooks/local-development.md` and
   `.agents/skills/verify-live/SKILL.md`; add their conditional AGENTS links; run
   `scripts/harness/sync`; and manifest-pin `dev.sh` with
   ` # tailored`. If any of these files already exists, preserve it and show a
   proposed diff — never silently replace local content. Re-run the v1 contract
   checks and manifest/stub checks after approved adoption.
7. **Offer execution profiles and devcontainer adoption as separate content
   changes.** Read `templates/docs/standards/execution-profiles.md`, compare
   each wired provider's existing config tuple-by-tuple, and present a merge
   diff for only the providers the user chooses. Preserve hooks, MCP servers,
   permission rules, secret-deny mirrors, and unknown local keys. Never replace
   a whole config. Copy/tailor the self-contained convention and add its AGENTS
   link after at least one provider is declared **or** the devcontainer is
   separately adopted; run the semantic checks. Claude's credential profile
   requires Claude Code 2.1.187 or later.

   Offer an authored `.devcontainer/devcontainer.json` only when recon confirms
   a real image, Dockerfile, or Compose source and the user separately opts in.
   Preserve existing `.devcontainer/` content, use a non-root user, mount no
   host credentials or container-engine socket, auto-run no repo code, build
   the result, and use an existing app's `scripts/dev.sh` inside the container.
   A devcontainer-only adoption still installs/tailors the combined convention
   and its AGENTS link, without adding a provider declaration.
   Otherwise defer it explicitly; there is no placeholder template to copy.
8. **Offer outcome-telemetry and doc-garden content separately.** Never rewrite
   `.harness/var/log.jsonl`; v1 and v2 lines intentionally coexist. Offer the
   self-contained `templates/docs/standards/outcome-telemetry.md` plus its
   AGENTS link after the v2 mechanism update. Separately offer
   `templates/docs/skills/doc-garden/SKILL.md`, its conditional AGENTS link, and
   regenerated provider stubs. Preserve any existing convention/skill and show
   a proposed diff. Declining either content change is valid and does not remove
   the newly installed helpers. Doc-garden adoption authorizes only its offline,
   read-only report; schedules, external probes, edits, commits, pushes, and PRs
   remain separate choices.
9. When the request is really a *standards* shift — a provider newly reads
   `.agents/skills/` natively, Claude Code ships AGENTS.md support, a new
   harness appears — follow the matching playbook in
   [migrations.md](../migrations.md) instead of
   improvising.
