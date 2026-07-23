---
name: verify-live
description: >-
    Reproduces and verifies application behavior against the running local app,
    using the repository's dev runtime contract, deterministic seed data, and
    targeted logs or traces. Activates when changing UI or request behavior,
    fixing a live-only bug, smoke-testing an application flow, or when tests
    alone cannot prove the user-visible result.
---

# Verify Live Application Behavior

Use the real application to close the loop: establish a deterministic state,
reproduce before editing, observe the narrowest useful evidence, make the
change, and run the identical flow again. Unit tests remain necessary; they are
not a substitute for this live check.

## Preconditions and hard stops

1. Read `docs/runbooks/local-development.md` for this repo's runtime map.
2. Require executable `scripts/dev.sh` and `jq`. If the script is missing or
   non-executable, stop and report that the runtime contract is unavailable.
3. Treat each recognized action's stdout as protocol, not prose. It must be one
   compact JSON object on one line, with no other stdout, and must satisfy the
   JSON v1 schema below. Stop on invalid output or a contradictory exit/status;
   do not guess framework commands as a fallback.

The v1 object has exactly these required keys:

- `schema_version`: integer `1`
- `action`: `up`, `health`, `seed`, or `down`, matching the request
- `status`: `ready`, `seeded`, `stopped`, `unhealthy`, or `error`
- `instance`: the `scripts/harness/lib/dev-instance.sh suffix` output, matching
  `^h[0-9a-f]{12}$`
- `url`: string, possibly empty only when stopped or on error
- `logs`: nonempty repo-relative path string
- `traces`: repo-relative path string or the empty string
- `started`: boolean, true only when this `up` call launched the instance

A nonzero failure may add only a string `message`. Reject missing keys, wrong
types, extra keys, multiple JSON values, or absolute/artifact paths outside the
repo. Successful `up`/`health` are `ready`; successful `seed` is `seeded`;
successful `down` is `stopped`. `health` is the only action where `stopped` or
`unhealthy` is a valid nonzero result.

## Workflow

1. **Start or reuse the current-worktree instance.** Run
   `scripts/dev.sh up`, capture stdout and the exit code separately, validate
   the response, and require exit 0 with `action: "up"` and
   `status: "ready"`. Immediately record `started`, `instance`, `url`, `logs`,
   and `traces` from that object. The initial `started` value owns the cleanup
   decision for the entire task; never replace it with a later action's value.

2. **Reset to known data.** Run `scripts/dev.sh seed`, validate the response,
   and require exit 0 with `action: "seed"`, `status: "seeded"`, the same
   `instance`, and `started: false`. Seeding is an explicit action; `up` must
   not be treated as having seeded anything.

3. **Reproduce before editing.** Write down the shortest exact flow that shows
   the affected behavior: URL or endpoint, viewport or client when relevant,
   input/actions, and expected versus actual result. Execute it against the
   recorded `url` before touching code. If it does not reproduce, stop and
   report that fact instead of changing code against an assumption.

4. **Use the best already-available observation surface.** For UI behavior,
   prefer an existing browser or computer-use capability exposed by the
   current agent surface. Otherwise use the repo's already-configured
   Playwright CLI, Playwright tests, or browser MCP tools. Do not install a
   browser, extension, MCP server, skill, or package merely to complete this
   workflow, and never link installed repo content back to a harness/plugin
   cache. If none is available, exercise the same route with HTTP tools such as
   `curl` and explicitly report that visual behavior remains unverified.

5. **Inspect only targeted evidence.** Use the response's repo-relative
   `logs` path and, when nonempty, `traces` path. Search or tail the smallest
   time window and request/operation identifiers that cover the reproduction;
   do not dump entire logs or unrelated traces into context. Capture a
   before-change screenshot for a visual defect when the available surface
   supports it.

6. **Make the narrow change.** Preserve the recorded reproduction steps and
   seeded state. Add or update deterministic tests for the defect where the
   repo has an appropriate test layer.

7. **Run the identical live flow.** Confirm the instance is still ready with
   `scripts/dev.sh health`; validate exit 0, `action: "health"`,
   `status: "ready"`, the same `instance`, and `started: false`. Run
   `scripts/dev.sh seed` again, then repeat the same URL, inputs, actions,
   viewport/client, and targeted log/trace checks from steps 3–5. Capture the
   matching after-change screenshot when visual tooling exists. Do not quietly
   substitute a unit test or a different happy path for the failed flow.

8. **Run the repository gate.** Run `bash scripts/harness/verify` after the live
   behavior passes. Report the live flow, relevant evidence paths, test result,
   and any visual-verification limitation.

9. **Clean up only what this task started.** On success or an early failure
   after a valid `up` response, run `scripts/dev.sh down` only when the recorded
   initial `started` was `true`; validate exit 0 with `action: "down"`,
   `status: "stopped"`, the same `instance`, and `started: false`. If the
   initial `started` was `false`, leave the reused instance running. If `up`
   output was invalid and `started` could not be trusted, stop without calling
   `down`.

## Common mistakes

- Starting the framework directly bypasses worktree ownership, port collision,
  and cleanup semantics. Use only `scripts/dev.sh`.
- Treating `up` as a seed makes reproductions depend on old data. Call `seed`
  explicitly before both the before and after flows.
- Killing a process by port can stop another worktree or a user's service.
  Cleanup is `down`, and only when the initial `up` reported `started: true`.
- Calling a changed route once is not an identical rerun. Preserve the inputs,
  state, viewport/client, and evidence checks.
- An HTTP 200 does not prove layout or interaction. When no browser surface is
  available, say visual verification was not performed.
