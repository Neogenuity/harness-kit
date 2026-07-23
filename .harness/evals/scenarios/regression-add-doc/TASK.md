# Add a plain doc (regression anchor)

- suite: regression
- polarity: positive
- provider: any
- grade: check

## Prompt

Add a file `docs/notes/scratch.md` containing a single short paragraph of prose
on any topic. Then run `bash scripts/harness/check-harness` and confirm it passes.

## Acceptance

`check.sh` verifies the file exists with real prose and `check-harness`
passes. This is a trivially correct change: if a model ever fails it, suspect the
harness (a guard wrongly blocking a plain doc write), not the task.
