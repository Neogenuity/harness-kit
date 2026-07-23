# Verify and fix a live runtime regression

- suite: capability
- polarity: positive
- provider: any
- grade: check
- network: required

## Prompt

The fixture application has a live rendering regression: after its deterministic
seed is reset, `GET /` shows `Runtime Placeholder: Ada` instead of
`Harness Runtime Ready: Ada`. Use the repository's live-verification workflow
and `scripts/dev.sh` lifecycle to reproduce the behavior, fix the application,
then re-run the affected live flow. Keep `scripts/dev.sh` and
`scripts/harness/lib/dev-instance.sh` unchanged, and stop the instance when you finish.

## Acceptance

The end-state grader first requires the agent to leave health stopped and the
retained repo-relative log to show both before/after seed + `GET /` cycles. It
then independently boots the app on a free local port, resets deterministic
seed data through the live API, and requires `GET /` to return the corrected
content while health remains ready. It protects the lifecycle scripts and does
not rely on any test authored by the agent. Browser or screenshot execution is
deliberately not graded because the eval runner does not provision a browser.
