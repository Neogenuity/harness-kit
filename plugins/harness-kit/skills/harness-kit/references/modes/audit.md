# Audit mode — grade an existing repo

Read [../pattern.md](../pattern.md) first if unread this session.

Grade an existing repo against the pattern. Check, in order: canonical
`docs/` presence (or content trapped in provider dirs / duplicated);
AGENTS.md as TOC with live links; skills canonical + stubs generated
everywhere `harness.conf` claims; hooks portable, executable, tested; native
permission deny list mirroring the secret guard; the configured `PLANS_DIR`
(`harness.conf`) resolving to a real directory (a dangling one makes
`session-context.sh` silently announce nothing) and `docs/plans/README.md`
present (AGENTS.md links it, so a missing README is a dead link); CI running
the drift gate; manifest present and passing its checksum
verification. Report the MCP trust-inventory state: servers configured across
the four MCP locations vs. `MCP_ALLOWED_SERVERS` coverage (or "no inventory
declared"), and whether the `docs/conventions/untrusted-content.md` and
`docs/conventions/risky-actions.md` governance docs are present or missing. If
a behavioral eval bank exists (`docs/evals/`), report its health too: number of golden tasks by suite (capability / regression) and
polarity, whether `test-eval.sh` passes (grader validity), and the age of
`docs/evals/baselines.json` — report the age of the OLDEST per-cell
`recorded` date across `tasks.*.runs.*.recorded` (falling back to the file's
top-level `recorded` for older baselines that predate per-cell dates); a
stale or absent baseline means the harness is unmeasured — recommend a
scheduled `eval-harness.sh` run. Then run
`scripts/check-harness.sh` and the hook tests if they exist. If `.harness/log.jsonl` exists, summarize it: deny / advise /
lint-findings counts by hook and by file — a repeatedly-denied path or a
warning surfaced every session is the next mistake to engineer away
(tighten a pattern, add a lint rule, write a convention doc). Output: a
table of pattern element → status (present / drifted / missing) with the
concrete fix for each, ordered by risk (secret exposure first, drift
second, missing content last), plus the log summary when available. Offer
to fix; don't fix unasked.
