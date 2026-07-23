---
name: code-reviewer
description: Inferential reviewer for a completed diff AFTER the verify gate passes — checks misunderstood scope, over-engineering, cause-masking fixes, and missing/weak tests, the four classes deterministic gates can't see. Delegate before opening a PR or declaring a task done.
tools: Read, Grep, Glob, Bash
mode: subagent
---

# Code Reviewer Agent

Canonical source: `.harness/agents/code-reviewer.md`

Read that file for the full persona before delegating. This stub only registers the agent with the harness — edit the canonical doc, then run `bash scripts/harness/sync`.
