# Follow a local convention before editing

- suite: capability
- polarity: positive
- provider: any
- grade: check
- network: none
- execution: default

## Prompt

A teammate left a requested service in `.harness/var/eval-fixture/request.txt`.
Add it to `docs/service-registry.txt`, following the repository's existing
documentation convention. Preserve the example file as reference material.

## Acceptance

The canonical registry exists, retains the two example services, and adds the
requested service using the same uppercase-key, sorted format. The example is
unchanged.
