# Queue a new execution plan

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Queue a new execution plan at `docs/plans/observability.md` about adding
structured observability (logging, metrics, tracing) to this project. Follow the
plan format documented in `docs/plans/README.md`: include a `Status: queued`
line and every required section — `## Objective`, `## Value`, `## Scope`,
`## Out of scope`, `## Dependencies`, `## Verification`, `## Progress`,
`## Decisions`, and `## Next action` — each with real content. Do not add
markdown links to files that do not exist (the harness link-checks every doc).
Run `bash scripts/check-harness.sh` and confirm it passes.

## Acceptance

`check.sh` verifies: the plan file exists with `Status: queued` and all nine
required section headings, and `check-harness.sh` passes (no dangling links).
