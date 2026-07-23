# <Agent Name> Agent

<One paragraph: the persona's mission and when the main agent should delegate
to it. Keep the scope narrow — a persona that does everything is just the
main agent with extra steps.>

## Inputs

- <What the caller must provide: a diff, a module path, a failing test, ...>

## Checklist

<The ordered checks or steps the persona performs. This is the core of the
persona — make each item concrete and verifiable.>

1. <check>
2. <check>

## Output Format

<Exactly what the persona reports back: sections, severity levels, locations.
A fixed format makes the persona's results consumable by the calling agent.>

---

<!--
Provider wiring (not part of the canonical doc): give this doc `name`,
`description`, and `tools` frontmatter (the same shape SKILL.md uses — the
`description` is the routing signal the MAIN agent delegates on), then run
`bash scripts/harness/sync`. It GENERATES a pointer stub per provider in the
agent-stub set (derived from `HARNESS_PROVIDERS` via the capability table) in
that provider's dialect (`.claude/agents/<name>.md`,
`.cursor/agents/<name>.md`, `.opencode/agents/<name>.md`, and
`.codex/agents/<name>.toml`). Edit the frontmatter here, never a stub —
`check-harness` fails on any stub that drifts from the generator, is missing
from a declared provider, or orphans a deleted canonical persona:

---
name: <kebab-name>
description: <when the MAIN agent should delegate to this persona>
tools: <minimal tool list, e.g. Read, Grep, Glob, Bash>
---
-->
