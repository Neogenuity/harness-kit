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
Provider wiring (not part of the canonical doc): each harness that supports
subagents gets a thin stub with its own frontmatter pointing here, e.g.
.claude/agents/<name>.md:

---
name: <kebab-name>
description: <when the MAIN agent should delegate to this persona — this is
  the routing signal>
tools: <minimal tool list, e.g. Read, Grep, Glob, Bash>
---

# <Agent Name> Agent

Canonical source: `docs/agents/<name>.md`

Read that file first — it defines the checklist and required output format.
Then perform the requested task against it.
-->
