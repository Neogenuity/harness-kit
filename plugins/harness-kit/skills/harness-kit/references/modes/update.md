# Update mode — upgrade harness machinery

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
6. When the request is really a *standards* shift — a provider newly reads
   `.agents/skills/` natively, Claude Code ships AGENTS.md support, a new
   harness appears — follow the matching playbook in
   [migrations.md](../migrations.md) instead of
   improvising.
