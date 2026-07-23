# Add mode — add a skill, agent, or hook

- **add-skill**: author `.agents/skills/<slug>/SKILL.md` (template above; sweat
  the frontmatter description), link it from AGENTS.md, run
  `bash scripts/harness/sync`, run `check-harness`, commit
  canonical + stubs together.
- **add-agent**: author `.harness/agents/<name>.md` with `name`/`description`/
  `tools` frontmatter (the `description` is the routing signal), link from
  AGENTS.md, then run `bash scripts/harness/sync` — it GENERATES the
  provider stubs (`.claude/agents/`, `.cursor/agents/`, `.opencode/agents/` as
  Markdown; `.codex/agents/<name>.toml` as TOML) from that frontmatter. Run
  `check-harness`, commit canonical + generated stubs together. Never
  hand-edit a stub; edit the canonical doc and re-sync.
- **add-hook**: a custom hook is repo-owned policy, so it lives in
  `.harness/hooks/<name>.sh` — **not** the kit-owned `scripts/harness/hooks/`
  mechanism tree. A hook dropped in the mechanism tree is unpinned mechanism
  that completeness check #9c rejects (every file under `scripts/harness/` must
  be manifest-pinned), and it squats a path the kit owns — a future version that
  ships a file there would collide with your local one. `.harness/hooks/` is the
  repo-owned home the update flow never touches unless you declare it. Source the
  portable library by its tree-relative path,
  `. "$(dirname "$0")/../../scripts/harness/hooks/lib.sh" 2>/dev/null || exit 0`
  (exactly as `.harness/hooks/guard-project-policy.sh` does — the path is
  `.harness/hooks/` → repo root → `scripts/harness/hooks/lib.sh`), and follow the
  conventions in `scripts/harness/hooks/README.md` (fail open, exit 2 to deny,
  `hook_advise_once` for stop-hooks). Wire the event in each provider config per
  the provider matrix. Add a `test-<name>.sh` regression beside the hook and run
  it as a gate in `.harness/gates.conf` — a guard without a test is a future
  silent failure. Verify by piping sample payloads (both harness layouts) into
  the script and confirming it actually sources `lib.sh` (a wrong relative path
  fails open to a silent no-op). For an enforcement hook the agent must not be
  able to neuter, pin it in `scripts/harness/.harness-manifest` as a
  ` # tailored` line (re-pin carries it forward) and add it to
  `GUARD_PROTECTED_EXTRA`.
