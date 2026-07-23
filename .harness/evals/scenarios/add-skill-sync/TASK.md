# Add a skill and sync the provider stubs

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Add a new skill. Create `.agents/skills/changelog/SKILL.md` with YAML frontmatter
containing a `name` and a `description` (the description is the activation
trigger — make it specific), followed by a short body explaining how to update
the changelog. Link the skill from the `## Skills` section of `AGENTS.md`. Then
run `bash scripts/harness/sync` to generate the provider stubs, and
`bash scripts/harness/check-harness` to confirm there is no stub drift.

## Acceptance

`check.sh` verifies: the canonical `SKILL.md` exists with `name` and
`description` frontmatter; `AGENTS.md` links it; and `check-harness.sh` passes —
which fails on stub drift, so the skill must have been synced to every provider.
