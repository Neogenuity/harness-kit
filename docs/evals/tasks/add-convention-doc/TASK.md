# Add a convention doc and link it from AGENTS.md

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Add a new convention document at `docs/conventions/error-handling.md` describing
how this project should handle and surface errors. Give it a top-level `# `
heading and at least a short paragraph of real guidance. Then link it from the
`## Conventions` section of `AGENTS.md` as a bullet, matching the style of the
existing entries. Finally, run `bash scripts/check-harness.sh` and make sure it
still passes.

## Acceptance

`check.sh` verifies: the doc exists with a `# ` heading and non-trivial prose;
`AGENTS.md` contains a live markdown link to it; and `check-harness.sh` passes
(which link-checks every AGENTS.md reference).
