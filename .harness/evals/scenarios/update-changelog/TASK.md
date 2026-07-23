# Add an Unreleased section to the changelog

- suite: capability
- polarity: positive
- provider: any
- grade: check

## Prompt

Add a new `## Unreleased` section to `CHANGELOG.md`, placed above the most recent
released version heading (currently `## 0.7.0`). Under it, add at least one
bullet describing a hypothetical improvement, following the format of the
existing entries. Then run `bash scripts/harness/check-harness` and confirm it passes.

## Acceptance

`check.sh` verifies: `CHANGELOG.md` contains an `## Unreleased` heading placed
before the first released `## 0.` heading, with at least one bullet beneath it,
and `check-harness` still passes.
