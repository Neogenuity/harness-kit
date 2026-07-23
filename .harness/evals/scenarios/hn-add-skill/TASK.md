# Add a changelog skill (recipe-free harness-native variant)

- suite: capability
- polarity: positive
- provider: any
- grade: check

Recipe-free variant of the repo's `add-skill-sync` golden task: identical
grader semantics, but the prompt does NOT contain the recipe (no script names,
no link target) — so it discriminates whether the harness context (AGENTS.md,
the plugin skill) supplies the workflow knowledge, where the recipe-laden
variant saturates.

## Prompt

Add a "changelog" skill to this repository's agent harness: a task workflow
that explains how to update CHANGELOG.md when shipping changes. The skill's
name must be `changelog`. Make the skill discoverable to every coding agent
this repository supports, following this repository's own conventions for
adding a skill. Do not commit.

## Acceptance

Same as add-skill-sync: canonical `.agents/skills/changelog/SKILL.md` with
`name`/`description` frontmatter; AGENTS.md links it; `check-harness`
green (stubs synced to every provider, no drift).
