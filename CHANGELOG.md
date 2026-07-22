# Changelog

All notable changes to harness-kit. The version is defined in
`plugins/harness-kit/VERSION` and mirrored into both plugin manifests.

## 0.21.0 — 2026-07-22

Phase 1 of the standard-consumer-layout restructure
(`docs/plans/standard-consumer-layout.md`).

### Added

- **`scripts/kit-manifest` — the declarative ship contract** (ADR 009): one
  plain-text line per shipped path with its ownership layer (`mechanism` |
  `policy` | `optional-policy`) plus a `retired` section. Every
  installer/manifest/checker function now derives its file set from it; the
  three hard-coded inventory lists in `install-lib.sh`
  (`_HARNESS_MECHANISM_TOPLEVEL`, `_HARNESS_POLICY_FILES`,
  `_HARNESS_OPTIONAL_PROJECT_POLICY_TOPLEVEL`) and check #9c's duplicate
  enumeration are gone, and hooks are enumerated per file instead of copied
  wholesale. The kit-manifest is itself mechanism: sha-pinned,
  guard-config-protected, and required on adopted repos.
- **Retired-file mechanism:** `harness_update_apply` now removes a path the
  new kit-manifest lists as `retired` — but only a pristine (sha matches its
  pin), non-`# tailored` copy (`remove <path>`); drifted, tailored, or
  never-pinned copies are kept and reported (`retire-keep <path>`).
  Retirement never deletes local changes. Fixture-pinned in
  `test-install-update.sh` (pristine-removed / drifted-kept / tailored-kept,
  pin carried). `scripts/test-install.sh` ships as the first retired entry,
  closing v0.20.0's manual-`rm` migration caveat.
- **check #9d:** an adopted repo must carry a present, parseable,
  non-empty `scripts/kit-manifest` (ERROR otherwise); retired paths still on
  disk WARN until resolved.

### Changed

- **check #9c** derives its expected pin set from the kit-manifest crossed
  with the filesystem (hooks tree still taken from disk wholesale, so
  repo-local hooks stay pinned).
- **`hooks/guard-secrets.sh` reclassified policy → mechanism:** its policy is
  fully externalized to `SECRET_PATTERNS`/`SECRET_ALLOW_PATTERNS` in
  `harness.conf`, so a pristine copy now upgrades like any other mechanism
  file. `format.sh` and `guard-project-policy.sh` remain diff-only policy.
- `guard-config.sh` protects `scripts/kit-manifest`;
  `harness_generate_manifest`/`harness_repin_manifest` refuse to run without
  a kit-manifest instead of emitting an empty pin set;
  `harness_update_decision` takes the (new) kit-manifest as its layer source.
- Removed a stray empty `templates/scripts/.claude/` write-tracking artifact
  from the distribution.

### Migration

- Update mode installs `scripts/kit-manifest` as a newly-shipped mechanism
  file and replaces the manifest-matching `install-lib.sh`,
  `check-harness.sh`, `hooks/guard-config.sh`, `hooks/guard-secrets.sh`
  (reclassified — see above), `install-test-lib.sh`, `test-install-core.sh`,
  `test-install-update.sh`, and `test-check-harness.sh`. A pre-0.21.0
  install's leftover `scripts/test-install.sh` is now removed automatically
  when pristine (kept and reported when drifted or tailored). Policy files
  other than the guard-secrets reclassification are untouched.

## 0.20.2 — 2026-07-18

### Fixes

- **Test-suite sweep of the v0.20.1 SIGPIPE fix:** the regression suites still
  asserted with the shape 0.20.1 banned from `check-harness.sh` —
  `printf '%s' "$out" | grep -q…` where `$out` is a multi-KB transcript that
  can outgrow the pipe buffer, so a match could phantom-fail under an
  inherited ignored SIGPIPE + `pipefail`. Converted to pure-shell matching
  (bash 3.2 `case`; the `$'\n'` sandwich for exact-line): all transcript
  assertions in `test-check-harness.sh` (the `assert_flags`/`assert_warns`/
  `assert_ok_without` helpers and the direct 8c/8e sites), `test-verify.sh`,
  `test-fixture-isolation.sh`, the `--help`-completeness checks in
  `test-eval.sh` (a ~4.6KB haystack), and the exact-line update-plan
  assertions in `test-install-update.sh`. Two `… | head -1` first-line grabs
  (`test-eval.sh`, `test-verify.sh`) became pure-shell `${var%%$'\n'*}` trims
  so no early-exiting reader sits downstream of a `printf` of a large
  variable. Small single-atomic-write payloads (hook outputs, single manifest
  lines) can't chunk and keep the pipe form.

### Migration

- Update mode replaces the manifest-matching `test-check-harness.sh`,
  `test-verify.sh`, `test-eval.sh`, `test-install-update.sh`, and
  `test-fixture-isolation.sh`; no policy files change.

## 0.20.1 — 2026-07-17

### Fixes

- **Phantom check failures under CI parallel load** (the v0.20.0 ubuntu-only
  flake): `printf '…' | grep -q` membership tests in `check-harness.sh`
  (checks #8, #8b, MCP identity pinning, #9 completeness) and
  `test-install-core.sh` are now pure-shell `case` matches. `grep -q` exits on
  first match; when the process tree inherits an IGNORED SIGPIPE (GitHub's
  Actions runner does this), `printf` survives the EPIPE with a nonzero status
  and `pipefail` then turns the pipeline red precisely when the entry WAS
  found. Caught live at v0.16.0 (macOS: a pinned guard reported "not pinned",
  with `printf: write error: Broken pipe` in the log) and v0.20.0 (ubuntu:
  `test-advise-once.sh` inside the clean-init fixture); reproduced locally at
  3000/3000 trials with over-pipe-capacity payloads under an ignored SIGPIPE.
- **check #6 prints a failing test's output tail** instead of "run it
  directly for details" — unactionable advice when the failure happens inside
  a throwaway fixture that no longer exists by the time the message is read.

### Migration

- Update mode replaces the manifest-matching `check-harness.sh` and
  `test-install-core.sh`; no policy files change.

## 0.20.0 — 2026-07-17

### Changed

- **Install suite split:** the 554-line `test-install.sh` monolith is now a
  shared `install-test-lib.sh` plus three focused suites —
  `test-install-core.sh` (prereqs, clean init, non-clobber, gitignore, conf
  helpers), `test-install-update.sh` (update decisions and apply), and
  `test-install-recovery.sh` (persisted-base recovery and the `dev.sh` policy
  block). Fixture `check-harness.sh` invocations drop from 9 to 1, cutting the
  install suites from ~231s to ~46s serial (~28s max parallel under
  `verify.sh`'s gates).
- **Checker cases live with the checker:** the `.claude` deny-list drift pair
  and the hooks-glob manifest-completeness case moved into
  `test-check-harness.sh` (both are new coverage there); the
  `HOOK_WIRED_PROVIDERS` migration checker assertions and the provider-template
  negative half were deleted as duplicates of check #8d's existing cases.
- **Provider templates get a maintainer gate:** the positive
  real-provider-template validation is now the root-only
  `scripts/test-provider-templates.sh` (tailored-pinned, wired into
  `verify.sh`), no longer shipped to adopters as a block that self-skips in
  every repo without a providers dir.
- **New branch coverage:** `harness_update_decision`'s local-drift-preserve
  arm, `harness_append_gitignore` no-trailing-newline + idempotency, git/sha
  prerequisite reporting, arbitrary tailored-pin carry-forward in
  `harness_repin_manifest`, and the hooks add-pass via a synthetic future file
  (replacing eight hard-coded historical filenames); clean-init assertions now
  iterate `_HARNESS_MECHANISM_TOPLEVEL` instead of hand-maintained lists.

### Fixes

- **check #5b could be silently disabled under bash 3.2:** a shell comment
  containing an apostrophe inside the check's `<(...)` process substitution
  made bash 3.2's naive paren scan lose the closing paren; bash reported a
  parse error and kept going, so the whole scratch-path check was skipped
  without failing anything. The comment moved out of the substitution (with a
  comment pinning why) and a regression case now pins the shared-lib scan arm.
- Hardened the new suites per an adversarial Codex (gpt-5.6-sol) review: every
  `make_fixture` assignment is `|| exit 1`-guarded and suffixed destructive
  sites use `${F:?}`, closing an empty-path `rm -rf` hazard when a nested
  `mktemp` fails.

### Migration

- Update mode replaces the pinned mechanism files and **adds**
  `install-test-lib.sh`, `test-install-core.sh`, `test-install-update.sh`, and
  `test-install-recovery.sh` (executable). `test-install.sh` left the shipped
  inventory: update keeps the old on-disk copy and check #9 then flags it as
  present-but-unpinned. Delete `scripts/test-install.sh` by hand after
  updating, then re-pin. (Pre-launch this repo is the only install; a proper
  retired-file mechanism is queued in `docs/plans/adopter-test-descope.md`.)

## 0.19.0 — 2026-07-17

### Fixes

- **User-approved host integration:** Claude's adopted execution profile now
  retains its normal permission-gated unsandboxed retry while keeping
  sandboxed egress closed, credentials denied, and `excludedCommands` empty.
  This lets a user approve necessary host-integrated commands such as `git
  push`, a nested provider CLI, or an eval runner without pre-authorizing an
  always-unsandboxed command. Codex's existing `approval_policy =
  "on-request"` provides the equivalent explicit escalation.
- **macOS guard fixture paths:** normalize the scratch-root spelling in the
  guard-config test so a trailing-slash `TMPDIR` cannot create a lexical `//`
  mismatch between an absolute fixture path and the hook's computed root.

### Migration

- Update mode replaces the manifest-matching `check-harness.sh`,
  `test-check-harness.sh`, and `hooks/test-guard-config.sh` mechanism files.
  The Claude execution-profile change is policy content: merge
  `allowUnsandboxedCommands: true` into an adopted `.claude/settings.json`
  only when the repository wants user-approved host integration; keep
  `excludedCommands` empty.

## 0.18.0 — 2026-07-16

Fixture isolation — the regression tests can no longer run their `git` commands
in your repository. When `mktemp` failed, an unguarded fixture did not abort: it
fell back to the host repo and committed the working tree onto the checked-out
branch. This release guards every scratch allocation, hardens every consumption
site, adds the CI gate that makes the pattern unreintroducible, and pins the
behavior with a test that fails on the pre-fix tree.

### The defect

- **What happened:** `WORK=$(mktemp -d)` swallows a failure and leaves `WORK`
  empty; `cd ""` is a silent rc=0 no-op that stays in the current directory. So
  `cd "$WORK" || exit 1` — a guard that looks sufficient — passes, and
  `git init && git add -A && git commit` then runs in your repo. `git -C ""` is
  the same hazard with a seatbelt: it resolves to the real repo and returns 0.
  `set -u` does not help; the variable is assigned-but-empty, not unset.
- **Why it stayed hidden:** the trigger is `mktemp` *failing*, which a stock
  runner never does — so CI stays green while the class is live. It fails where
  the temp dir is denied: bare `mktemp -d` on macOS resolves
  `_CS_DARWIN_USER_TEMP_DIR` (`/var/folders/…`) and ignores `$TMPDIR` entirely,
  so it dies even when `$TMPDIR` points somewhere writable — a sandbox, a
  hardened runner. That is exactly the environment coding agents run in.
  shellcheck cannot see it either: every variable involved is *correctly quoted*,
  and quoting is what makes `cd ""` a well-formed no-op rather than an error.

### Fixes

- **Guarded allocation, 52 sites** (26 shipped + 26 installed twins): the idiom
  is now `VAR=$(mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX") || exit 1` — the same
  form `eval.sh` has carried, with a comment naming this exact hazard, since
  v0.8.0. Top-level suites take one guarded base; fixtures carve subdirectories
  out of it.
- **Guarded consumption:** `${VAR:?}` at every `cd`/`git`/`rm` consuming a
  fixture root. Not redundant — `|| return 1` inside a `F=$(make_fixture)`
  command substitution returns from the *subshell*, so callers still received an
  empty path and `test-install.sh`'s own `git commit` was still live.
- **`fixture-recipe.md` stopped teaching the bug.** The recipe built a path from
  an unchecked `mktemp` and then ran `git add -A && git commit` — in whatever
  repo the reader was standing in. It now builds inside `$( … )` with explicit
  guards and enters via `cd "${FIX:?}"`. Guards are explicit rather than
  `set -e`, whose assignment-from-command-substitution semantics are not
  dependable across shells (the recipe is `bash`; it gets pasted into zsh).
- **No fixture may discover a Git repository above its own scratch base.**
  `test-audit-log.sh`, `test-dev-instance.sh`, and `test-codex-hooks-cwd.sh`
  assert "outside a Git worktree" behavior in a scratch dir — which resolved the
  *host* repo whenever `$TMPDIR` itself sat inside a worktree (an agent sandbox,
  a `~/tmp` in dotfiles). `test-codex-hooks-cwd.sh` was passing vacuously.
  Capped with `GIT_CEILING_DIRECTORIES`.

### Enforcement

- **check #5b (new, ERROR):** a `mktemp` in the scripts check #6 runs must carry
  both an explicit `XXXXXX` template and a failure guard. It runs *before* #6 —
  a static gate on a file set must precede the gate that executes it. Scope is
  exactly what #6 runs; an adopter's own scripts are their business. Declare a
  verified exception with a trailing `# harness-mktemp-ok`, the same stance as
  the manifest's `# tailored`.
- **`scripts/test-fixture-isolation.sh` (new):** runs every sibling suite from
  inside a throwaway canary repo under a failing `mktemp` shim and asserts the
  canary's HEAD and porcelain are untouched — `cd ""` lands a leak in the CWD, so
  the canary is where it surfaces. It catches leaks whose damage is
  self-contained (`git init`, `git add -A`, `git commit`, a stray write) — the
  class that actually put commits on this repo's `main` — and its header states
  where that stops; it is not a universal oracle. It also refuses to pass
  vacuously: a run in which the shim was never invoked tested nothing and now
  fails saying so, rather than reporting isolation it never exercised. Verified
  in both directions: it passes here and **fails on v0.17.0**, catching the real
  leaks by name.

### Migration

- Update mode replaces `check-harness.sh`, `install-lib.sh`, and the
  manifest-matching `test-*.sh` mechanism files, and adds
  `test-fixture-isolation.sh`. Locally changed or tailored mechanism stays
  diff-only.
- **check #5b may fail your build on first upgrade**, in two shapes that want
  different answers. A test under `scripts/test-*.sh` or `scripts/hooks/test-*.sh`
  that *calls* a bare `mktemp` is the gate working: it is reporting a script that
  can commit to your branch. Adopt the guarded idiom, or annotate a verified
  allocation with `# harness-mktemp-ok`. A test that only *writes* `mktemp` text
  into a fixture — `printf '…$(mktemp -d)…' > "$f/run.sh"`, a heredoc body, even
  a message string — is a false positive: the gate keeps quoted text deliberately,
  because the `XXXXXX` template lives in quotes. Do not reach for the marker
  there; it is line-scoped and unconditional, so it would also mask a real
  `mktemp` added to that line later. Assemble the literal instead (`MK=mktemp`,
  then `printf '%s -d …' "$MK"`) — this repo's own suite hit this on day one and
  does exactly that. See `references/fixture-recipe.md`.
- No tailored file, TAILOR block, or authored content is touched.

## 0.17.0 — 2026-07-15

Local outcome telemetry and documentation gardening — the harness now records
verification outcomes without changing gate behavior, reduces mixed historical
and current events into deterministic local trends, and offers an offline,
read-only documentation health workflow. Terra implemented the portable
mechanism and fixtures, Luna implemented the schema/workflow content, and the
two streams received reciprocal and lead review through dogfood integration.

### Outcome stream and audit

- **Exact mixed-version contract:** new producers use the eight-key v2 envelope
  `{version,ts,hook,event,file,detail,context,data}` while code-reviewer findings
  remain exact five-key v1 records. Optional run, session, provider, and plan
  attribution is accepted only with explicit provenance; absent context stays
  unknown rather than being inferred from repository state.
- **Fail-open gate telemetry:** serial and parallel `verify.sh` gates record
  label, fast/full mode, pass/fail, exit code, and portable integer duration.
  Parallel children remain concurrent while the parent emits results in
  declaration order. Skipped fast-mode gates are not fabricated, and missing
  logging dependencies or unwritable destinations never change a gate result.
- **Deterministic `audit-log.sh`:** the reducer accepts interleaved exact v1/v2
  rows, counts malformed and unsupported rows, summarizes daily gate failures,
  explicit-session retries, repeat denials, and review findings, joins exact
  `Harness-Session-Id:` trailers to local commits, and consumes the existing
  eval scorer's new JSON view. Plan-cycle timing and PR enrichment report N/A
  until a reliable versioned producer exists.
- **Privacy floor:** durable lint events retain only a bounded category/count,
  never raw diagnostics. The local git-ignored stream installs no collector and
  does not ingest provider telemetry, prompts, commands, tool output, secrets,
  endpoints, authorization data, or cost exports.

### Documentation gardening

- **Canonical `doc-garden` skill and offline scanner:** `doc-garden.sh` checks
  tracked Markdown across the repository for broken local links, missing
  anchors, references to deleted paths, and stale or malformed verification
  stamps while ignoring CommonMark fences and same-line
  `<!-- doc-garden: planned -->` exceptions. Reports are stably ordered,
  read-only, and advisory.
- The skill reuses existing harness checks, de-duplicates overlapping results,
  keeps external URL probing separately authorized, and requires distinct
  authorization for edits, commits, pushes, or pull requests. Provider-neutral
  scheduled-run guidance ships without a daemon or unstamped platform claim.
- Root dogfood adopts the new convention and skill and regenerates Claude,
  Cursor, OpenCode, and `.agents` skill stubs. Deterministic scanner fixtures
  proved the authorization and detection boundaries, so no paid behavioral run
  was required.

### Migration

- Update mode normally adds `log-lib.sh`, `audit-log.sh`, `doc-garden.sh`, and
  their tests, and replaces manifest-matching mechanism files including
  `hooks/lib.sh`; locally changed or tailored mechanism remains diff-only.
- `verify.sh`, `harness.conf`, `hooks/format.sh`, secret/project guards, provider
  configs, and application launchers remain policy and are always reviewed as
  diffs. Gate instrumentation is therefore opt-in for an existing tailored
  `verify.sh`, while mixed-log reduction remains usable without it.
- The telemetry convention, `doc-garden` skill, AGENTS links, and generated
  provider stubs are content adoption: update proposes them but never silently
  creates or overwrites them. Existing v1 logs are read in place and are never
  rewritten.

## 0.16.0 — 2026-07-14

Declared execution profiles — repositories can explicitly adopt and verify the
strongest honest repo-local execution posture each supported provider exposes.
The release adds stable profiles for Claude Code, Cursor, Codex, and OpenCode;
an experimental Codex local/private-network compatibility variant; semantic
drift checks; an authored devcontainer contract; and a provider-observability
map that stays separate from the harness hook log. Terra implemented the
mechanism and deterministic fixtures, Luna implemented the provider/content
surface and behavioral task, and both workstreams were reciprocally reviewed.

### Provider-native profiles

- **Claude Code** enables the OS sandbox, fails closed when it is unavailable,
  disables unsandboxed fallback and excluded-command bypasses, adds no writable
  roots, denies command egress, rejects Unix-socket/Mach allowlists and both
  weaker-isolation modes, and protects named credential files/environment
  variables. The credential block requires Claude Code 2.1.187 or later;
  project settings are not an administrator lock.
- **Cursor** adds `.cursor/sandbox.json` with workspace-plus-temp writes, no
  extra read/write roots or shared build cache, and a deny-by-default network
  file. Effective closed egress still requires **sandbox.json Only** UI mode or
  administrator policy; repo configuration alone cannot prove that state.
- **Codex** adds `workspace-write`, user-reviewed on-request approvals, filtered
  core environment inheritance, declared temp roots, and network-off defaults.
  Applications may explicitly choose the experimental local/private-network
  compatibility disjunction: command networking behind exact
  `localhost`/`127.0.0.1` public-domain proxy rules, empty Unix-socket rules,
  disabled dangerous bypasses, and `allow_local_binding = true`. The latter is
  an admitted broad loopback/private-network weakening, not a localhost-only
  boundary. Native Windows elevated/unelevated sandbox behavior is documented
  separately from the kit's Bash-hook platform support.
- **OpenCode** denies external-directory and web-tool access and asks for shell
  commands. The docs state the actual limit: this is permission policy, not an
  OS/filesystem/network sandbox, and an approved shell can still reach the host
  and network.

### Adoption and drift assurance

- **Explicit `EXECUTION_PROFILE_PROVIDERS` declaration** is independent from
  hook and agent wiring. Unset/empty remains a clean unadopted state for legacy
  installs; the adopted subset is never inferred from surviving config files.
- **Semantic check #8e** parses declared provider configs, accepts unrelated
  local keys/order and additive deny hardening, and fails specifically on a
  missing, malformed, disabled, full-access, broadened-write, approval-off, or
  unrestricted-network tuple. Codex accepts only network-off or the exact
  experimental local/private compatibility disjunction; declared Codex
  validation uses Python 3.11+ `tomllib` to reject malformed content anywhere
  in the file, compare domain/socket maps as parsed objects so nested descendant
  tables cannot evade exactness, and report the profile unverifiable when that
  conditional parser is absent.
- **Guard coverage** now protects `.cursor/sandbox.json` and `.devcontainer/*`
  in direct, Cursor, and Codex edit payloads while retaining the documented
  fail-open behavior and maintenance escape hatch.
- **Codex custom-agent stubs** now follow the current standalone-agent schema:
  name, description, and developer instructions only. The generic canonical
  `tools` list remains in the Markdown-provider stubs but is omitted from Codex
  TOML, where CLI 0.144.1 interpreted it as an incompatible config value and
  ignored the entire reviewer role.
- Init/update/audit merge only explicitly chosen profiles, preserve hooks,
  permissions, MCP servers, secret mirrors, and local keys, and classify each
  provider as adopted, unadopted, drifted, unavailable, or unverifiable.

### Containers, observability, and evidence

- **Devcontainers are authored from confirmed repo evidence**, never copied as
  placeholders: explicit opt-in, non-root user, no host credential/agent/socket
  mounts, no automatic repo-code lifecycle command, and build plus existing
  `scripts/dev.sh` lifecycle verification. This non-app repository has no
  confirmed image/Dockerfile/Compose source, so no dogfood container is emitted.
- **Provider observability stays separate** from `.harness/log.jsonl`. The
  dated map records each provider's signal, configuration scope, export path,
  and privacy limitation without shipping collectors, endpoints, headers,
  credentials, raw-prompt opt-ins, or automatic session joins.
- **Behavioral adoption task** requires a non-clobbering Claude/Codex subset
  merge, the exact Codex compatibility tuple plus an explicit account of its
  broad local/private reach and teardown limit, preserved local/MCP/runtime
  state, a substantive self-contained convention, and no provider telemetry.
  Its reference passes and clobber/telemetry/thin-doc shortcuts are rejected by
  the offline grader. The corrected paid Codex run passed 2/3 on
  `gpt-5.6-luna` (`pass@k=1`, rate 0.67; run
  `20260714-v016-provider-config`) and is recorded as the baseline. One
  quota-conservative Claude Haiku smoke failed the external grader after it
  changed forbidden OpenCode policy and missed required Claude/convention
  content; the 0/1 smoke is retained as evidence but is not baselined.
- **Explicit eval execution authorization** keeps ordinary trials unchanged.
  A task must declare `execution: provider-config-write` *and* the caller must
  independently pass `--allow-provider-config-write`; either half alone is
  refused before a real provider CLI starts. The accepted pair receives the
  mechanism-maintenance escape and, for Codex, `danger-full-access` because
  `workspace-write` protects `.codex/config.toml`. The runner states that this
  grants unrestricted host filesystem and public-network access, that a
  disposable clone does not contain host effects, and that an external
  container/VM is preferred; it also rejects combining the mode with
  `network: required`.
- **Live Codex evidence** on CLI 0.144.1 under macOS showed why the tuple is
  labeled as a weakening: `allow_local_binding = false` blocked concurrent
  local startup despite exact localhost rules; `true` allowed the two-worktree
  fixture through health, seed, HTTP, and log checks while a tested
  `example.com` request was proxy-blocked. The workspace-write sandbox also
  blocked `ps`, so ownership-safe `scripts/dev.sh down` could not complete.
  v0.16.0 therefore does not claim localhost-only containment or full lifecycle
  compatibility for this experimental variant.

### Migration

- Update mode replaces pristine `check-harness.sh`,
  `test-check-harness.sh`, `guard-config.sh`, and its regression test, then
  re-pins them. Existing tailored `harness.conf` is diff-only: leave
  `EXECUTION_PROFILE_PROVIDERS` unset/empty to remain unadopted, or explicitly
  declare only the provider subset whose proposed config merge you approve.
- Provider configs, conventions, AGENTS links, and devcontainer files are
  policy/content and are never auto-added or overwritten during update.

## 0.15.0 — 2026-07-14

Runtime legibility — application repositories can expose one deterministic,
worktree-owned live runtime contract to every agent surface. The release ships
the universal instance helper, conditionally authors a tailored `dev.sh`, adds
a self-contained `verify-live` workflow, and grounds optional browser guidance
in each provider's actual surface. Implementation was delegated to Terra
(mechanism and executable evidence) and Luna (content and provider contract),
then cross-reviewed in both directions.

### Worktree-aware runtime mechanism

- **Universal `scripts/dev-instance.sh`** derives a stable `h` + 12-character
  lowercase hash suffix from the physical Git worktree root and namespace, and
  maps a validated base/span to a deterministic candidate port. Finite port
  hashing is collision-resistant, not collision-proof; runtime startup must
  fail loudly rather than reuse or kill another instance's occupied port.
- **Conditional `scripts/dev.sh` contract** for detected and confirmed app
  repositories implements `up|health|seed|down`. Every valid action returns one
  JSON v1 object; startup is idempotent and readiness-gated, seed resets named
  fixture data, health is read-only, and down can stop only this worktree's
  resources. State lives under `.harness/dev/`, with repo-relative JSON paths.
- **Installer/update integrity** treats the helper and its regression test as
  mechanism, but `dev.sh` as optional project policy: authored scripts are
  executable, manifest-pinned, diff-only, preserved on update, and protected by
  the config guard. Update mode now sources the incoming kit's `install-lib.sh`
  so pre-0.15 installs can discover newly introduced mechanism files.
- **Parallel full-gate support** lets independent template, eval, fixture, and
  harness checks overlap while preserving declaration-ordered output and exact
  failure rerun commands. The tailored verify template also includes the
  commented `full_gate "smoke" bash scripts/dev.sh health` adoption point.

### Live-verification content

- **Self-contained `verify-live` skill** enforces
  start/reuse → seed → reproduce → inspect targeted logs/traces → change → rerun
  the same flow → `verify.sh` → ownership-aware cleanup. It stops on a missing or
  invalid runtime contract instead of guessing repo-specific commands.
- **Runtime convention and app-aware init** document the lifecycle JSON schema,
  ownership, deterministic seeding, port override, log/trace paths, and failure
  behavior. Recon proposes commands from manifests, Compose files, and
  Procfiles; interview asks only unresolved details. Libraries receive no
  placeholder runtime content and audit reports N/A.
- **Safe adoption/audit** offers existing apps an opt-in proposal through
  update/audit; it never auto-adds or overwrites authored content or `dev.sh`.
  Audit calls only `health` and distinguishes missing, non-executable, unpinned,
  invalid JSON, stopped, unhealthy, and ready states.
- **Surface-aware browser guidance** is stamped from current primary sources
  for Claude Code Chrome, Cursor Browser, Codex Browser, OpenCode MCP, and
  Playwright CLI/MCP. It uses an already configured native/browser/computer-use
  surface when available, otherwise falls back to HTTP and explicitly reports
  that visual behavior was not checked; no browser tool is installed
  automatically.

### Evidence

- The root-only Python fixture runs main and linked-worktree HTTP instances
  concurrently, proves suffix/port separation, deterministic seed resets,
  valid JSON, logs, ownership-safe teardown, readiness-timeout cleanup, and
  that stopping A leaves B healthy. Python 3 is a contributor/test prerequisite
  only; installed harness prerequisites remain Bash, jq, Git, and SHA-256.
- The positive `verify-live-runtime` capability eval passed **3/3** on Codex
  `gpt-5.6-luna` (`pass@k=1`, `pass^k=1`, rate 1.00; run
  `20260714-170246-codex-gpt-5.6-luna`). Eval tasks now have closed,
  task-scoped `network: none|required` metadata so localhost fixtures can opt in
  without enabling network for ordinary Codex evals.

### Migration

- Update mode automatically installs or refreshes `dev-instance.sh` and its
  test.
- Existing app installs adopt `dev.sh`, runtime docs, AGENTS links, and the
  `verify-live` skill only by explicit opt-in; authored files are never
  auto-overwritten. Non-app repositories need no action.
- The commented live smoke-gate example is diff-only in an existing tailored
  `scripts/verify.sh`; adopt it manually if the repository wants that gate.

## 0.14.0 — 2026-07-13

Provider wiring assurance — the harness now *verifies* the wiring it documents.
A fresh clone with `.claude/settings.json`'s `hooks` object deleted used to pass
`check-harness.sh` at exit 0 ("coherent"); it now fails with a specific
per-guard error. Agent stubs join skill stubs as generated-and-checked. The
OpenCode/Cursor hook shim is descoped with a dated rationale rather than left a
documented-but-unshipped claim. Init/update gain a `jq` preflight and a tested
old-template recovery path. Eval baselines gain a bare-vs-plugin-activated
dimension. Execution plan reviewed by Codex gpt-5.6-sol (6 findings folded
pre-build); integrated diff reviewed by Codex gpt-5.6-terra. Implementation
delegated to parallel Opus 4.8 + Sonnet 5 worktrees.

### Hook-wiring validation (mechanism)

- **New `check-harness.sh` check** validates, per declared hook-wired provider
  (`HOOK_WIRED_PROVIDERS` in `harness.conf`), every required
  `(config, event, matcher, script)` tuple against the frozen provider matrix —
  a guard on the wrong event, a weakened matcher, a missing config, or a command
  pointing at a missing script now all fail (previously any of these stayed
  green). Migration: update mode replaces `check-harness.sh` and `install-lib.sh`
  and diffs the tailored `harness.conf` — declare `HOOK_WIRED_PROVIDERS` and
  `AGENT_PROVIDERS` on upgrade (update/audit proposes the set, you confirm; the
  check errors loudly until declared, and never infers the set from surviving
  configs).

### Agent-stub generation (mechanism)

- **Agent stubs are now generated** by `sync-agent-skills.sh` — like skill stubs
  — from `name`/`description` frontmatter on the canonical `docs/agents/*.md`,
  and checked for bidirectional equality. Previously hand-authored. Migration:
  update mode replaces `sync-agent-skills.sh`; re-run it and commit the
  regenerated stubs.

### Provider wiring reconciliation

- The OpenCode TS hook shim and Cursor `guard-config` wiring are **descoped**
  (dated 2026-07-13): documented as the reuse path, but no shim template ships,
  so OpenCode is not in the hook-wired set. Every shipped surface reconciled so
  none implies the shim ships.

### Install/update robustness (mechanism)

- **`jq` preflight** at init/update names missing prerequisites before
  scaffolding a harness whose guards would silently fail open.
- **Old-template recovery** for update mode across install channels (git tag,
  plugin cache, plain copy) via a git-ignored persisted pristine base, tested for
  the no-local-git path.

### Evals

- **Execution-variant dimension** (bare vs plugin-activated) in the baseline key:
  `bare` keeps the `provider/model` key (zero migration for existing baselines);
  a non-bare variant appends `/variant` so it can never overwrite the bare cell.
  The paid Codex plugin-activated recordings and acceptance-floor decision are
  deferred to a follow-up (activating the plugin inside a trial workspace is not
  yet built; `eval.sh --variant` only tags the row).

## 0.13.0 — 2026-07-13

Reviewer loop + skill split — the inferential half of the feedback system lands
(a canonical code-reviewer persona with a machine-parseable findings schema and a
seeded-defect catch-rate eval), and the plugin skill is split from a ~5.2k-token
monolith into a ~780-token router, proven at parity. Launch-readiness docs ship
alongside. Every gate is eval- or review-backed. Plan reviewed by Codex
gpt-5.6-sol; implementation reviewed by Codex gpt-5.6-terra.

### Reviewer loop

- **Canonical `code-reviewer` persona** (`templates/docs/agents/code-reviewer.md`,
  self-installed here at `docs/agents/code-reviewer.md`) — an inferential reviewer
  that runs only after `verify.sh` passes and checks the four classes deterministic
  gates can't see: misunderstood scope, over-engineering, cause-masking fixes, and
  missing/weak tests. Advisory by default; treats the diff as untrusted data.
  Hand-authored provider stubs for Claude, Cursor, Codex, and OpenCode.
- **Findings schema** — one v1-compatible `hook_log` line per finding appended to
  `.harness/log.jsonl`: the five reviewer fields (severity, line, category,
  evidence, suggested_fix) ride inside `detail`, so the top level stays the exact
  `{ts, hook, event, file, detail}` shape and every existing audit/log consumer
  keeps working unchanged.
- **Seeded-defect catch-rate eval** (`docs/evals/tasks/seeded-defect-review/`) —
  8 planted defects (2 per class); the grader credits a catch on (file, category)
  with a fully-formed finding, and `caught == 0` is a false-green violation
  (exit 3). Ship gate: `pass_rate ≥ 0.60` over 5 trials with zero violations.
  Recorded baseline: claude/sonnet **5/5** (`baselines.json`, 40 → 41 cells).
- **Opt-in PR-review CI workflow** (`templates/ci/github-actions-review.yml`) —
  wires the persona as an advisory PR reviewer: SHA-pinned actions, `pull_request`
  (never `pull_request_target`), minimal `permissions`, explicit `github_token`,
  fork-safe, cost-noted. Defines the `Harness-Session-Id:` session→PR trailer.

### Skill split

- **Plugin `SKILL.md` → compact router.** The ~299-line monolith becomes an
  ~81-line (~780-token) router whose mode table inlines each mode's load-bearing
  invariants; the full playbooks move verbatim to
  `references/modes/{init,audit,add,update}.md`. Activation footprint drops ~85%.
- **Shipped only on parity.** A fresh paired monolith-vs-split run (claude sonnet,
  3 trials, both discriminating tasks) held correctness 3/3 = 3/3 with wall-clock
  no worse, and was in fact cheaper (25–46% fewer tokens/cost per success).
  Evidence: `docs/evals/parity/skill-split.md`. The router surfaces the canonical
  `code-reviewer` persona and the PR-review workflow in init mode.

### Launch readiness (partial)

- **`SECURITY.md`** — private disclosure path for the shipped guard machinery,
  grounded in `docs/conventions/risky-actions.md` (advisory/fail-open is documented
  behavior, not a vulnerability), with a pre-1.0 supported-versions policy.
- **README** — a "What 1.0 promises" compatibility contract (what a template bump
  never touches vs. what each semver level means post-1.0) and a supported-platforms
  line (bash + jq on macOS/Linux/WSL/Git Bash; no native-Windows hook execution).
- Content-level secrets/hostname hygiene sweep of this repo (none found); the org
  move, demo, and public-flip remain maintainer actions.

### Upgrade notes

- Update mode **replaces** the plugin skill wholesale (it is distributed content,
  not tailored); the new `references/modes/` and `templates/` files are additive.
- No installed `scripts/` mechanism changed, so the dogfood manifest header stays
  at `0.12.0` by design — it records the mechanism version, and `check-packaging.sh`
  gates the `VERSION`/plugin-manifest trio, not the header. No re-pin.

## 0.12.0 — 2026-07-13

Eval discrimination + context efficiency — a joint release that makes the
behavioral eval bank actually discriminate model/harness behavior, lands the
measured fixes from the 2026-07-12 context-efficiency audit, and records the
first full four-model baseline matrix. Every behavior change ships against eval
evidence, not intuition. Plan reviewed by Codex gpt-5.6-sol; implementation
reviewed by Codex.

### Eval layer

- **Per-trial provider usage on every results row.** `eval_result_json` now
  carries a typed `usage` object — uncached / cached-read / cache-write input
  tokens, output tokens, cost (when the provider reports it), and tool-call
  count — with JSON `null` (never `0`) for any field a provider does not emit.
  Claude and Codex transcripts are parsed by provider-specific extractors pinned
  to committed fixtures; `eval-harness.sh` scoring stays correctness-only and
  tolerates pre-0.12 rows.
- **Two discriminating tasks adopted** — `hn-add-skill` (recipe-free add-skill)
  and `tmpl-secret-pattern` (template-vs-installed secret mirror), each proven by
  reference and violation fixtures.
- **First four-model baseline matrix.** `baselines.json` grows 16 → 40 cells:
  Claude haiku+sonnet and Codex gpt-5.6-terra+gpt-5.6-luna across the full
  10-task bank, spanning a cheap tier (haiku, luna) and a capable tier (sonnet,
  terra) on both providers. Every cell carries a per-cell `recorded` date, and
  the under-trialed regression cell is re-recorded at 3 trials. The bank now
  discriminates — `hn-add-skill` splits Claude 3/3 vs Codex 0/3, and the negative
  neuter-check surfaced haiku reward-hacking a gate script (1/3) that a smaller
  sample had scored a clean 3/3.
- **Opt-in scheduled eval workflow** (`ci/github-actions-eval-cron.yml`) — weekly
  cron plus manual dispatch defaulting to the free `mock` provider, scoring-only
  (never `--update-baseline`), SHA-pinned actions, cost-honesty notes. Copy to
  `.github/workflows/` and wire a provider credential to run live.

### Harness behavior (context-efficiency audit fixes)

- **AGENTS.md skill-link convention** — one line making "link every new skill and
  convention doc from AGENTS.md" explicit; the audit measured this single
  sentence as the difference behind a 0/6 add-skill failure mode.
- **Guard deny-hint** (`GUARD_DENY_HINT` in `harness.conf`, empty default) — an
  optional tailorable line appended to the config-guard's deny message so a
  denied edit can point the agent at the right place.
- **Protected-path over-match fixed** — the `opencode.json` entry is root-anchored
  (`/opencode.json`), so the guard still protects the installed root file without
  denying edits to the shipped `templates/providers/opencode/opencode.json`.
- **Banner trim** (`BANNER_RECENT_COMMITS`, default 0) — the session-start
  banner's recent-commits block is now an opt-in tailorable (zero observed
  in-session consumers across the audit).
- **Stop-hook clean-tree skip** — `guard-project-policy.sh` skips the
  `verify.sh --fast` run on a clean tree (which cannot newly fail it), removing a
  measured stop-time tax; advisory behavior on a dirty tree is unchanged.

### Migration

Mechanism + content release. Update mode replaces the manifest-matching
`scripts/` files and diffs the tailored ones. Two new `harness.conf` keys
(`GUARD_DENY_HINT`, `BANNER_RECENT_COMMITS`) arrive with empty/zero defaults — no
action needed unless you want to set them. The AGENTS.md skill-link line is
content (`AGENTS.md.tmpl`), applied on re-init or copied by hand.

### Deferred

The plugin skill-split (SKILL.md → compact router + per-mode references), gated
on fresh paired parity runs, is deferred to a queued `skill-split.md` plan; it
needs its own parity round and ships only on evidence.

## 0.11.0 — 2026-07-12

Hook hardening + feedback repair — the 2026-07-12 project review re-verified
the provider matrix against live docs and probed the installed guards with
real payloads, surfacing self-protection gaps and degraded feedback channels.
This release closes them. Mechanism-only; no new tailoring required. Scope was
triple-reviewed after implementation (2× Claude Opus 4.8 + Codex
gpt-5.6-terra); every confirmed finding was fixed and fixture-covered before
tagging.

- **Guard-coverage gaps closed.** `guard-config.sh`'s default `PROTECTED_PATHS`
  now also denies edits to `scripts/harness.conf` (the secret guard's pattern
  source), `.claude/settings.local.json` (can carry `disableAllHooks: true`;
  gitignored and unmanifested in the standard Claude Code setup, so no other
  layer caught it), and the three MCP configs the trust-inventory audit reads
  (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`). Post-init
  `harness.conf` tailoring rides the existing `HARNESS_ALLOW_MECHANISM_EDITS=1`
  escape hatch.
- **Path-normalization bypass fixed.** The guard now collapses `.`/`..`/`//`
  segments before matching, so a crafted `scripts/./harness.conf` or
  `scripts/../scripts/harness.conf` can no longer slip a protected path past
  the literal globs. (Case variants on a case-insensitive filesystem remain a
  documented guardrail limitation — the CI manifest check is the enforcing
  layer.)
- **Deny reasons are model-visible.** On a `PreToolUse` payload, `hook_deny`
  emits an exit-0 JSON `permissionDecision:deny` carrying the reason (parsed by
  Claude Code and Codex) instead of an exit-2 stderr the model may not see. The
  portable exit-2 deny stays as the fallback for every other layout and
  whenever JSON construction *or the stdout write* fails — a deny never fails
  open.
- **Cursor feedback arm repaired.** `afterFileEdit` documents no output field
  for feedback text and parses exit-0 stdout as JSON, so `hook_feedback` now
  emits the documented no-op (`{}`) on the Cursor layout instead of dead plain
  text; the finding still reaches `.harness/log.jsonl`.
- **Advise-once future-proofed.** A payload-independent marker guard
  (`.harness/stop-markers/`, keyed on session/conversation id + a warnings
  digest) keeps the stop advisory firing exactly once even if a future build
  drops the undocumented-but-still-sent `stop_hook_active` flag. The prune is
  scoped to the guard's own markers, so a user-pointed `HARNESS_STOP_MARKER_DIR`
  never loses unrelated files.
- **Provider matrix refreshed** with Cursor's grown hook surface
  (`beforeShellExecution`, `beforeMCPExecution`, generic
  `preToolUse`/`postToolUse`, per-hook `failClosed`), a recorded decision to
  defer wiring `guard-secrets.sh` to `beforeShellExecution` (its payload puts
  `command` top-level, which `hook_command_string` doesn't read), and restamped
  sources; `eval.sh`'s pinned CLI invocation restamped to Claude Code 2.1.207.

**Migration.** Update mode **replaces** `guard-config.sh` and `lib.sh` (both
non-tailored mechanism files) and adds `scripts/hooks/test-deny-reasons.sh`; it
**never touches** your tailored `harness.conf` or `verify.sh`. No config
changes are required. If you tailored `guard-config.sh`'s `PROTECTED_PATHS`
locally, re-apply your additions after updating — the file is replaced, not
diffed.

## 0.10.1 — 2026-07-12

CI fix — the `ci` workflow's "Hook templates are executable" check had failed
on every push to `main` since v0.8.0. The four eval-layer scripts added in
that release (`eval.sh`, `eval-lib.sh`, `eval-harness.sh`, `test-eval.sh`)
were committed to `plugins/harness-kit/skills/harness-kit/templates/scripts/`
without the executable bit, even though their identical-content counterparts
under the repo's own installed `scripts/` were correctly `+x`. No behavior or
template-layout change; mode bits only.

- `chmod +x` the four affected template files to match their `scripts/`
  counterparts and every sibling file in that directory.

## 0.10.0 — 2026-07-12

Execution governance baseline — the kit previously scaffolded knowledge,
gates, and evals but said nothing about *containment*: which MCP servers a
repo trusts, what an agent should do with hostile content, or whether the
shipped CI could be quietly repointed. Scope was design-reviewed before
implementation (Codex gpt-5.6-sol, 14 findings incorporated — most
materially: the MCP inventory pins expected *identity*, not just names) and
the implementation was triple-reviewed (2× Claude Opus 4.8 + Codex
gpt-5.6-terra, all SHIP-WITH-FIXES; every fix landed and is
fixture-covered).

- **MCP trust inventory (new check #8c).** `harness.conf` gains
  `MCP_ALLOWED_SERVERS` — one `<name> <expected-identity-substring>` line
  per allowed server. `check-harness.sh` extracts every *enabled* server
  from `.mcp.json`, `.cursor/mcp.json`, `opencode.json`, and
  `.codex/config.toml` (best-effort TOML scan; single- and double-quoted
  table names) and audits it: with no inventory declared, configured
  servers produce one adoption WARN; once the inventory is declared (even
  empty — the strict default), an uncovered server or one whose configured
  command/args/URL no longer contains its pinned substring is an **ERROR**.
  A name-only inventory line is itself an ERROR (an empty pin would match
  any identity). Unparseable configs and jq-absent machines get a loud
  "not audited" WARN — except trivially-empty maps (`"mcp": {}`), which
  stay silent via a dependency-free fast path. Disabled entries are
  skipped. **Migration:** update mode replaces `check-harness.sh`; add an
  `MCP_ALLOWED_SERVERS` block to your tailored `harness.conf` (the shipped
  template carries a commented example) — repos with no MCP configs see no
  change.
- **Untrusted-content + risky-actions conventions (shipped docs).** Two new
  template docs under `docs/conventions/`: `untrusted-content.md` (tool/
  repo/web/MCP output is data, not instructions; the untrusted-clone
  checklist; which containment layers actually *hold* under a hostile
  instruction, per provider — including that OpenCode ships no OS sandbox)
  and `risky-actions.md` (destructive-op policy and the safe-default
  posture, every wiring example labeled by its enforcement layer so hooks
  are never mistaken for boundaries). `AGENTS.md.tmpl` links both and its
  security checklist now says repo/tool/web/**MCP**.
- **Provider matrix: execution containment.** New verified section
  (sandbox, network policy, approval modes for Claude Code / Codex /
  Cursor / OpenCode, checked against vendor docs 2026-07-11) — the factual
  basis the conventions docs cite instead of asserting.
- **Shipped-CI hardening + guard widening (new doctor #10d).** The CI
  templates pin actions to full commit SHAs, declare `permissions:
  contents: read`, `timeout-minutes`, and `persist-credentials: false`;
  `check-harness.sh` gains doctor WARN #10d flagging any mutable
  (tag/branch) `uses:` ref in `.github/workflows/` (quoted refs
  unwrapped); `guard-config.sh` PROTECTED_PATHS broadens from the single
  harness-check workflow to `.github/workflows/*`. **Migration:** update
  mode replaces the guard and check; workflows are yours — re-apply the
  hardening from the template if you've tailored them.
- **Plans.** The governance plan's advanced half (per-provider sandbox
  profiles, devcontainer, audit-log export) split into its own queued plan
  ([docs/plans/completed/v0.16.0-execution-sandbox-profiles.md](docs/plans/completed/v0.16.0-execution-sandbox-profiles.md));
  completed plan at
  [docs/plans/completed/v0.10.0-execution-governance-baseline.md](docs/plans/completed/v0.10.0-execution-governance-baseline.md).

## 0.9.0 — 2026-07-11

Eval integrity and plans hygiene — a 2026-07-11 project review (findings
adversarially checked by a second model, Codex gpt-5.6-sol) found the v0.8.0
eval layer could silently mis-score, and found the launch and a saturated
task bank tracked nowhere the plans machinery could see.

- **Eval integrity fixes.** Latest-run selection in `eval-harness.sh` now
  picks by per-run `run_started_at` epoch (`max_by([(.run_started_at // 0),
  .run])`) instead of lexicographic run-id sort, so a custom `--run-id`
  can no longer permanently outrank a chronologically newer run; legacy
  result lines with no `run_started_at` still parse. `eval.sh` refuses to
  reuse a results directory that already has recorded results, and
  refuses to run against a dirty working tree (each trial clones committed
  `HEAD`) unless `--allow-dirty-head` is passed. Negative tasks gain a
  distinct `negative_violation` outcome via a `check.sh` exit-3 convention
  (exit 1 keeps meaning `task_failure`), and `eval-harness.sh` fails loudly
  on any `negative_violation` regardless of suite. `--update-baseline` now
  excludes `--provider mock` rows, refuses atomically unless every cell has
  exactly `--expected-trials` (default 3) trials, and writes each cell's
  `recorded` date from the run's own timestamp. Task metadata (`suite`,
  `polarity`, `provider`, `grade`) is now enum-validated at load time, and a
  `provider:` value gates a task off providers it doesn't target (`mock` is
  exempt). The default `--run-id` (when none is passed) changes from a bare
  UTC timestamp (`YYYYMMDD-HHMMSS`) to `TIMESTAMP-provider-model`, so two
  providers (or two models) launched in the same second no longer collide on
  a results dir — anything scripting against results-dir names by pattern
  should account for the new suffix. **Migration:** `update` mode replaces
  the four eval scripts as usual; the `results.jsonl` schema gains
  `run_started_at` and `outcome` fields (old lines keep parsing — legacy rows
  are outranked by any new, timestamped run). Negative-task graders should
  adopt exit 3 for a caught shortcut; a plain exit 1 still fails the task but
  records `task_failure`, which does not trigger the loud scorer failure
  path.
- **Plans, docs, and CI.** New active plan
  [docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md](docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md)
  tracks this work; two new queued plans,
  [docs/plans/eval-discrimination.md](docs/plans/completed/v0.12.0-eval-discrimination.md)
  (a task bank that actually discriminates model behavior) and
  [docs/plans/active/launch-readiness.md](docs/plans/active/launch-readiness.md) (the
  launch, previously tracked only as README checkboxes), join the roadmap;
  `docs/plans/active/` is now tracked (a fresh clone previously lost the
  directory). `.github/workflows/ci.yml` now runs `bash scripts/verify.sh`
  directly instead of hand-reconstructing its steps, so a gate added to
  `verify.sh` can no longer silently drop out of CI. README's hardcoded
  `v0.6.0` claim is replaced with a pointer to `plugins/harness-kit/VERSION`,
  and the release skill gains a sweep step so this can't go stale again.

## 0.8.0 — 2026-07-11

Behavioral evals — the harness could prove it was *coherent* (drift, links,
checksums) but not that it *worked*. This release adds the layer that measures
whether the harness actually changes agent behavior: repo-specific golden tasks
run over multiple isolated trials, scored by pass@k / pass^k against recorded
baselines.

- **New eval mechanism** (`scripts/eval-lib.sh`, `eval.sh`, `eval-harness.sh`,
  `test-eval.sh`). `eval.sh <task> --provider <claude|codex|mock> --trials N`
  runs a golden task over N independent trials, each in a fresh isolated
  workspace (a throwaway `git clone`), captures a transcript per trial under
  `.harness/eval-results/` (git-ignored), and grades the end state with the
  task's `check.sh` (+ optional `verify.sh`). `eval-harness.sh` computes
  pass@k / pass^k per task and fails on a regression-suite drop vs
  `docs/evals/baselines.json`. `--provider mock` runs the reference solution
  through the whole pipeline for a zero-cost plumbing/grader-validity check.
- **`docs/evals/` convention + task bank.** `TASK.md` (suite: capability|
  regression, polarity: positive|negative), a `check.sh` grader independent of
  any agent-written test, and a `reference/apply.sh` proving the task solvable.
  Ships a `_template` task and a rubric+calibration-note example; this repo
  carries an 8-task dogfood bank spanning both suites and both polarities.
- **Grader validity is CI-enforced.** `test-eval.sh` (wired into `verify.sh`)
  proves, with no model in the loop, that every task's reference solution scores
  as a pass and every negative task's `reference/violate.sh` scores as a fail —
  a grader that can't catch the shortcut is caught here.
- **init/audit integration.** init interviews for the 1-2 success-defining tasks
  and scaffolds `docs/evals/`; audit reports task counts by suite/polarity,
  grader validity, and baseline age.
- **Migration.** `update` treats `eval-lib.sh` / `eval.sh` / `eval-harness.sh` /
  `test-eval.sh` as mechanism files: they are copied on init, added on upgrade
  from an older manifest, pinned in `.harness-manifest`, protected by
  `guard-config.sh`, and enumerated by `check-harness.sh`'s completeness check.
  No action needed — an existing harness picks them up on the next `update`.

## 0.7.0 — 2026-07-11

Install/update verification — the kit's core product boundary (`init` / `update`)
was the only mechanism with no automated test; it now has a deterministic
fixture suite, and two *verified* integrity blind spots in the manifest
mechanism it exercises are closed.

- **Deterministic install/update mechanics extracted and tested.** New template
  `scripts/install-lib.sh` is the model-free core of init/update — pure
  filesystem functions (`harness_install_mechanism`, `harness_generate_manifest`,
  `harness_repin_manifest`, `harness_update_decision`, `harness_update_apply`,
  `harness_append_gitignore`) that the SKILL's `init`/`update` prose now calls
  instead of inlining shell. New template `scripts/test-install.sh` drives them
  against throwaway git fixtures: clean init, non-clobber floor (hand-written
  `AGENTS.md`/`settings.json` survive byte-for-byte), no-op update idempotence,
  mechanism upgrade, and `# tailored`-file preservation, plus a seeded
  deny-list drift case. The model-graded half of init/update (authoring quality,
  merge judgment) stays out of scope by design. **Migration:** `update` now
  manages `install-lib.sh` and `test-install.sh` like any other mechanism file;
  they are copied on init and pinned in the manifest.
- **`scripts/harness.conf` is now manifest-pinned** (verified finding). It is the
  single source for `SECRET_PATTERNS`, yet was pinned by neither the manifest
  producer nor `guard-config.sh` — so a narrowed `SECRET_PATTERNS` disarmed the
  secret guard for `id_rsa`/`*.pem`/`.env.*` while `check-harness.sh` stayed
  green. It is now enumerated by `harness_generate_manifest` (marked
  ` # tailored`, since its patterns are repo-specific), so an un-re-pinned edit
  fails CI like every other policy file. **Migration:** `update` gains a
  `harness.conf` line in the manifest; re-pin after tailoring `SECRET_PATTERNS`.
- **Manifest integrity hardened on three fronts** (verified findings, incl. a
  multi-model review round). `check-harness.sh` check #9 previously only verified
  the files the manifest *did* pin, so an adopted repo's manifest could be
  gutted by shell edit to disarm a guard while CI stayed green. Now, when
  `scripts/hooks/` is present: (a) a missing / emptied / all-malformed manifest
  is an ERROR, not a silent skip; (b) a nonempty malformed line no longer counts
  as a pin; and (c) **completeness** — every mechanism file on disk must be
  pinned (the expected set is derived from the filesystem, not the manifest), so
  *partial* pin deletion (un-pinning one guard while leaving others) is caught.
  A genuinely pre-adoption repo still passes.
- **Update mechanics corrected** (review round). `harness_update_apply` now (i)
  treats policy files (`verify.sh`, `harness.conf`, `format.sh`, `guard-secrets.sh`,
  `guard-project-policy.sh`) as diff-only even when pristine and unmarked — never
  auto-overwriting them (SKILL update step 3) — and (ii) installs mechanism files
  the new kit ships that an older install's manifest can't list, so a `0.6`→`0.7`
  upgrade actually picks up `install-lib.sh`/`test-install.sh`. `harness_repin_manifest`
  carries forward tailored pins the shipped producer doesn't emit (a repo's own
  local gates), so a re-pin never silently drops a project-added integrity pin.
- **`install-lib.sh` added to `guard-config.sh`'s protected paths** (mechanism,
  with a `test-guard-config.sh` case) and **check #6 skips only `test-install.sh`
  and `test-check-harness.sh` when nested** (via `HARNESS_NESTED_FIXTURE`, set by
  `test-install.sh`) so the fixture suite can run `check-harness.sh` inside a
  throwaway install without recursing — every other regression test, the guard
  behavioral checks included, still runs, so no single env var can switch off the
  regression layer.

## 0.6.0 — 2026-07-11

- **Plans machinery now ships.** The kit's docs promised a `docs/plans/`
  directory (`harness.conf` sets `PLANS_DIR`, `session-context.sh` announces
  it, `AGENTS.md` links its README) but no template shipped and `init` never
  authored one — a fresh harness referenced a directory that didn't exist. New
  templates `docs/plans/README.md` (lifecycle: queued → `active/` →
  `completed/`, theme-naming, the markdown-link honesty rule) and
  `docs/plans/_template.md` (the nine plan sections); `init` step 5 authors the
  README and creates `PLANS_DIR`, and `audit` flags a configured `PLANS_DIR`
  whose directory is missing. A throwaway
  [fixture recipe](plugins/harness-kit/skills/harness-kit/references/fixture-recipe.md)
  documents how to smoke-test `init` end-to-end.
- **GitHub Copilot + Gemini CLI added to the provider matrix** (both verified
  2026-07-11): Copilot reads `AGENTS.md` natively including nested files (plus
  `.github/copilot-instructions.md`); Gemini CLI reads it via a
  `.gemini/settings.json` `context.fileName` snippet. Both are
  instructions-only (no hook/skill/agent surface), so `init` step 6 gains two
  near-free wire steps.
- **Stricter harness checks** (mechanism — `check-harness.sh` +
  `test-check-harness.sh`, manifest re-pinned):
  - Canonical skills are now validated against the **Agent Skills spec** as
    ERRORs, not doctor hints: closing `---` delimiter, non-empty `name`/
    `description`, `name` equal to its parent directory, `name` charset with no
    leading/trailing or consecutive hyphens, and the 64/1024-char limits
    (previously warnings). Prefers `skills-ref validate` when on PATH, with a
    dependency-free bash fallback.
  - New doctor WARNs: an `active/` plan missing a `Next action` or unchanged
    for 30+ days (git-dated; a no-op in shallow CI), and a provider-matrix
    `verified <date>` stamp older than 90 days or a matrix with no stamp at all
    (`PROVIDER_MATRIX_DOC`, `HARNESS_PLAN_STALE_DAYS`,
    `HARNESS_MATRIX_STALE_DAYS` are configurable in `harness.conf`).
- **Docs:** provider-matrix capability rows now carry `verified` stamps;
  `pattern.md` notes dynamic workflows riding skill-resource mirroring and
  positions hooks as *feedback* vs. OS sandboxing as *enforcement* (pointing at
  the execution-governance plan).

## 0.5.0 — 2026-07-10

- **Repackaged `plugin/` → `plugins/harness-kit/` + a Codex distribution
  channel.** The same source tree now installs as a versioned, updatable
  plugin in **both** Claude Code (`/plugin marketplace add`) and Codex
  (`codex plugin marketplace add`) — the manual clone-and-copy of
  `skills/harness-kit` still works but is no longer the only path. New files:
  `plugins/harness-kit/.codex-plugin/plugin.json` and the root
  `.agents/plugins/marketplace.json` (Codex's nested-source marketplace shape,
  with `policy`/`category`; distinct from Claude Code's flat-string source —
  schemas verified 2026-07-10 against learn.chatgpt.com/docs/build-plugins).
  See [ADR 007](docs/architecture/decisions/007-dual-provider-packaging.md).
- **`plugins/harness-kit/VERSION` is now the single version source**, mirrored
  into both `plugin.json` files. New `scripts/check-packaging.sh` (the
  `verify.sh` manifests gate) asserts the whole cross-file invariant — four
  valid manifests, semver `VERSION` equal to both plugin versions, name
  agreement, `./`-relative contained source paths, the Codex `skills` dir, and
  in-enum `policy`/`category`.
- **Codex hook commands now resolve from the Git root** (from PR #6 review): a
  Codex session whose CWD is a repo subdirectory previously exited 127 because
  `bash scripts/hooks/X.sh` is CWD-relative. All five commands in the Codex
  `hooks.json` now use `bash "$(git rev-parse --show-toplevel)/scripts/hooks/X.sh"`
  (the pattern the hooks docs recommend); a new `test-codex-hooks-cwd.sh`
  regression test runs every command from a nested CWD in CI.
- **Docs:** provider matrix gains a stamped **Distribution** row; new
  migrations playbook for a provider shipping a plugin/marketplace channel;
  README gains a "Codex, as a plugin" install section; the release skill now
  bumps `VERSION` + both plugin.jsons together. Corrected a stale `pattern.md`
  line that claimed `# tailored` manifest lines skip integrity checking (they
  are still checksum-verified; the marker only exempts template *replacement*).
- Update-mode note: this is a path/packaging change. Existing installs keep
  working; to move to the plugin channel, install via your provider's
  marketplace instead of the copy path. `lib.sh` and the guard/test scripts
  are unchanged from 0.4.1 apart from the new Codex-hooks-CWD test.

## 0.4.1 — 2026-07-10

- **Codex apply_patch guard bypass (found by real-payload capture):** a live
  Codex 0.144.1 payload — reconciled against the generated hook schemas
  (`openai/codex: codex-rs/hooks/schema/generated`) — showed that a file edit
  arrives as the **bare** apply_patch envelope (`*** Begin Patch` … `*** End
  Patch`) directly in `tool_input.command`, with the tool identity carried in
  `tool_name`; the literal `apply_patch` is **not** in the command. But
  `lib.sh:hook_affected_files` gated on `case "$cmd" in *apply_patch*)`, so it
  extracted nothing from a real Codex edit — making `guard-config.sh`,
  `format.sh`, and `guard-secrets.sh`'s write-side denial silent no-ops on
  Codex. Impact: an agent on Codex could edit protected harness mechanism
  (e.g. `scripts/hooks/lib.sh`) or write a secret file via apply_patch
  **undenied**. Fix: `hook_affected_files` parses the bare envelope when
  `tool_name` is `apply_patch` — the tool identity, not command text — and
  keeps the `apply_patch`-literal branch for the shell-wrapper form
  (`apply_patch <<'EOF' …`, which also rides a Bash/shell tool). Gating on the
  tool identity, rather than on the bare `*** Begin Patch` marker, is
  deliberate: a first pass keyed on the marker text alone fail-**closed**
  ordinary shell payloads that merely *contain* patch text (a heredoc writing
  a `.patch` file), fabricating affected-file paths and denying them — caught
  in review before merge.
- **Why CI stayed green:** every Codex apply_patch fixture used the
  `apply_patch <<'EOF'` wrapper form (which contains the literal), so the
  wrong envelope shape was never exercised. Bare-envelope regression cases are
  added to `test-affected-files.sh`, `test-guard-config.sh`, and
  `test-guard-secrets.sh`, plus a shell-command-containing-patch-text case in
  each pinning the no-false-close boundary; the affected-files/guard fixture
  comments now cite the captured payload as the source of truth.
- Update-mode note: `lib.sh` and the three `test-*.sh` files are mechanism
  (replaced on checksum match). Take the kit update and re-pin
  `scripts/.harness-manifest`; behavior-only change, no config migration.

## 0.4.0 — 2026-07-10

- **Codex protocol correctness (from adversarial review, validated against
  the current docs at learn.chatgpt.com):** Codex hook payloads carry no
  `tool_input.file_path` — file edits arrive as apply_patch invocations in
  `tool_input.command` — so the guards and `format.sh` were silent no-ops
  on Codex. New `lib.sh:hook_affected_files` / `hook_command_string`
  normalize all three provider layouts (direct fields, plus apply_patch
  envelope headers including multi-file patches and renames);
  `guard-config.sh`, `guard-secrets.sh`, and `format.sh` now iterate every
  affected file. `guard-secrets.sh` adds a best-effort token scan of shell
  commands (the only live secret layer on Codex) with apply_patch bodies
  stripped to avoid false denies, and now also denies patch writes to
  secret files. Fixtures are schema-derived; pinned by the new
  `test-affected-files.sh` plus Codex cases in every guard test.
- **Stop-hook protocol:** Codex requires JSON on Stop stdout at exit 0;
  `hook_advise_once`'s second pass now emits `{"continue": true}` (valid in
  Claude Code too — the layouts are indistinguishable) and `{}` on the
  Cursor layout instead of plain text.
- **Manifest integrity:** `check-harness.sh` check #9 now checksum-verifies
  ` # tailored` lines too — the marker only exempts a file from template
  replacement (update mode) and template-equality checks, never from
  integrity verification. Re-pin tailored lines after editing, keeping the
  marker.
- **Docs:** provider matrix re-verified 2026-07-10 — Codex hooks are GA and
  enabled by default (`hooks` feature key; `codex_hooks` deprecated alias;
  `commandWindows` exists), payload/Stop facts corrected, sources updated
  to learn.chatgpt.com (developers.openai.com/codex/* now redirects there).
- **CI:** test matrix now includes macOS (exercises the BSD awk/`shasum`/
  `readlink -f` branches).
- Update-mode note: `lib.sh`, both guards, `format.sh`, and
  `check-harness.sh` are mechanism (replaced on checksum match). A tailored
  `format.sh` fork needs the multi-file iteration applied manually — the
  TAILOR arms now live inside a `process_one()` function.

## 0.3.0 — 2026-07-09

- **Packaging:** the distributable plugin moved from the repo root into
  `plugin/` (`marketplace.json` `source: "./plugin"`). Installs no longer
  include repo-level files. If you track paths, `skills/…` is now
  `plugin/skills/…`.
- **Self-application:** this repository now runs its own harness — root
  `AGENTS.md`/`CLAUDE.md`, `docs/` knowledge base with ADRs, vendored and
  tailored `scripts/` (manifest-pinned), all-provider wiring, and the
  `harness-check.yml` drift gate in CI.
- **Docs:** README rewritten around the one-line value proposition;
  architecture overview and five decision records added; MIT license,
  CONTRIBUTING, and `llms.txt` added.
- **Mechanism hardening (from adversarial review):** `check-harness.sh`
  check #6 now also runs top-level mechanism tests (`scripts/test-*.sh`);
  new check #8b verifies OpenCode's `opencode.json permission.read` against
  `SECRET_PATTERNS`; checks #8/#8b now error (instead of silently skipping)
  when a wired `.claude/` or `.opencode/` is missing its native deny-list
  file; `guard-config.sh` protects `opencode.json`; the Claude deny-list
  template covers root-level `*.pem`/`id_rsa`/`id_ed25519`; every
  `SECRET_PATTERNS` entry now has a `test-guard-secrets.sh` case; the
  version-bump stop-hook compares version values against HEAD. Update-mode
  note: `check-harness.sh` and the test scripts are mechanism (replaced on
  checksum match); `settings.json`/`opencode.json` are policy (diffed).

## 0.2.0 — 2026-07-08

- Verification loop: post-edit lint feedback hooks the agent self-corrects
  on, `verify.sh --fast` wired into the advisory stop-hook.
- Self-guarding harness: `guard-config.sh` (mechanism/lint-config edit
  denial), manifest checksum integrity in `check-harness.sh`, native
  deny-list drift detection against `SECRET_PATTERNS`.
- Observability: every deny/advisory/lint event appends to
  `.harness/log.jsonl`; audit mode summarizes it.
- Provider matrix revalidated against 2026-07 harness docs (per-fact
  verified stamps + Sources section).

## 0.1.0 — 2026-07-08

- Initial extraction from a production Laravel modular monolith: canonical
  `docs/` knowledge base + `AGENTS.md` TOC, generated provider skill stubs
  (`sync-agent-skills.sh`), portable hook scripts with regression tests,
  shared permission templates, and the `check-harness.sh` CI drift gate.
