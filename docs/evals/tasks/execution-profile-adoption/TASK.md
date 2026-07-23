# Adopt a declared execution-profile subset without clobbering local config

- suite: capability
- polarity: positive
- provider: any
- grade: check
- execution: provider-config-write

## Prompt

Adopt harness-kit’s execution profiles for **Claude Code and Codex only** in
this repository. Read `AGENTS.md` and the harness-kit skill before editing.

The existing Claude and Codex configs contain local policy, nested Claude
sandbox restrictions, and an MCP server; merge the profile tuples without
replacing those keys. Keep Claude on the
stable closed-network profile. This app's `scripts/dev.sh` binds and checks
localhost, so explicitly adopt the documented **Codex experimental broad
local/private-network compatibility variant**: `allow_local_binding = true`
with exact `localhost` and `127.0.0.1` domain rules, no public host, wildcard,
Unix-socket rule, or dangerous proxy bypass. In the installed convention,
state that this admits broader local/private reach and is not localhost-only.
Also retain the documented Codex CLI 0.144.1 macOS limitation: sandboxed `ps`
prevents ownership-safe `scripts/dev.sh down`, so the variant does not prove
full lifecycle compatibility. Declare exactly `.claude
.codex` in `EXECUTION_PROFILE_PROVIDERS`, install the self-contained
execution-profiles convention, and link it from AGENTS.md.

Do not adopt or change Cursor, OpenCode, the existing devcontainer, or the
existing `scripts/dev.sh`; the runtime script is evidence for the localhost
need, not profile-owned content. Do not add provider telemetry configuration,
exporters, endpoints, credentials, real hostnames, auth headers, or raw-prompt
logging. Do not commit.

## Acceptance

`check.sh` grades the post-agent workspace. It requires the exact stable Claude
tuples and exact Codex broad local/private-network compatibility variant, the
documented weakening and teardown limitation, the two-provider declaration,
preserved Claude hooks/local policy and Codex MCP/local tables, a self-contained
convention and AGENTS link, preserved nested Claude sandbox policy and
harness/AGENTS policy, and byte-identical
seeded Cursor, OpenCode, devcontainer, and `scripts/dev.sh` files. The task's
reference solution is validated offline by
`scripts/harness/tests/test-eval.sh`; no paid provider trial is required for grader validity.
