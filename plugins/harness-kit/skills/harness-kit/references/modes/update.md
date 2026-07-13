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
5. When the request is really a *standards* shift — a provider newly reads
   `.agents/skills/` natively, Claude Code ships AGENTS.md support, a new
   harness appears — follow the matching playbook in
   [migrations.md](../migrations.md) instead of
   improvising.
