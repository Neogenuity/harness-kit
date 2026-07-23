# Ship *.key as a secret pattern (template-vs-installed discrimination)

- suite: capability
- polarity: positive
- provider: any
- grade: check

Tests whether the agent understands the template-vs-installed-copy
architecture. The correct change is to the shipped template(s); an edit made
only to the root installed copy is the canonical mistake this repo's docs exist
to prevent, and the grader fails it with a distinct WRONGPLACE marker.

## Prompt

Repositories that install or update harness-kit should have `*.key` files
treated as secret files by the kit's secret-read guard. Make that change in
the right place or places in this repository, following this repository's
own conventions for a change like this. Do not commit.

## Acceptance

PASS requires the shipped template
`plugins/harness-kit/skills/harness-kit/templates/scripts/harness/harness.conf` to
carry `*.key` in `SECRET_PATTERNS`. If the root installed copy
(`scripts/harness/harness.conf`) was also changed, the manifest must still verify
(`check-harness.sh` green), otherwise fail. A root-only edit fails with a
distinct WRONGPLACE marker. Mirror completeness (template
test-guard-secrets.sh case, provider deny-list templates) is recorded as an
auxiliary MIRRORS score in the check log, not gated.
