# Repair a dangling AGENTS.md link (regression anchor)

- suite: regression
- polarity: positive
- provider: any
- grade: check

## Prompt

`bash scripts/harness/check-harness` is failing because `AGENTS.md` links to
`docs/conventions/missing.md`, which does not exist. Fix it so the harness check
passes — either create that document or remove the dead link, your choice.

## Acceptance

`check.sh` verifies `check-harness.sh` passes (no dangling links). A competent
agent repairs this reliably; a low rate points at the harness, not the task.
