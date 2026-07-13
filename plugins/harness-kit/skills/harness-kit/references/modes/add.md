# Add mode — add a skill, agent, or hook

- **add-skill**: author `docs/skills/<slug>/SKILL.md` (template above; sweat
  the frontmatter description), link it from AGENTS.md, run
  `bash scripts/sync-agent-skills.sh`, run `check-harness.sh`, commit
  canonical + stubs together.
- **add-agent**: author `docs/agents/<name>.md` with `name`/`description`/
  `tools` frontmatter (the `description` is the routing signal), link from
  AGENTS.md, then run `bash scripts/sync-agent-skills.sh` — it GENERATES the
  provider stubs (`.claude/agents/`, `.cursor/agents/`, `.opencode/agents/` as
  Markdown; `.codex/agents/<name>.toml` as TOML) from that frontmatter. Run
  `check-harness.sh`, commit canonical + generated stubs together. Never
  hand-edit a stub; edit the canonical doc and re-sync.
- **add-hook**: write the script in `scripts/hooks/` sourcing `lib.sh`,
  following the conventions in `scripts/hooks/README.md` (fail open, exit 2
  to deny, `hook_advise_once` for stop-hooks). Add a `test-<name>.sh`
  regression script — a guard without a test is a future silent failure.
  Wire the event in each provider config per the provider matrix. Verify by
  piping sample payloads (both harness layouts) into the script.
