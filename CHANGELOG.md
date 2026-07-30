# Changelog

All notable changes to harness-kit. The version is defined in
`plugins/harness-kit/VERSION` and mirrored into both plugin manifests.

## 0.41.0 — 2026-07-30

Windows / Git Bash portability. Every fix here came from one adopter running
the kit on Git Bash, on surfaces no CI job could see — so the release also adds
the CI job that can see them.

All changed files are mechanism-layer: update mode **replaces** them when your
copy still matches its pin, and diffs any you have marked `# tailored`. No
policy-layer file changed, so nothing needs a manual merge.

### Fixed

- **A Windows clone could not install the kit at all.** The repo shipped no
  `.gitattributes`, and Git for Windows defaults to `core.autocrlf=true`, so an
  ordinary clone rewrote every shipped script and the `kit-manifest` ship
  contract to CRLF; `bootstrap install` then died before copying anything. The
  8 blank separator lines become lone-CR records, which both `awk`'s `NF` and
  bash `read` treat as a non-blank field, and 99 of 117 shippable entries pick
  up a trailing CR on their path. `.gitattributes` now pins `* text=auto
  eol=lf` with basename tripwires for the files whose parsers break first, and
  `harness_validate_ship_contract` probes for CR and names *that* as the cause
  once, instead of emitting ~100 bogus `unknown layer` findings that all point
  at the manifest's content when the fault is the checkout. (#27)

- **Binary-mode sha256 pins made drift reports lie and update silently do
  nothing.** Git Bash and Cygwin default both `shasum` and `sha256sum` to
  binary mode, writing `<sha> *<path>` rather than the documented
  `<sha>  <path>`. The `*` lands in field 2 at every manifest reader, so pinned
  paths resolve to nothing — one adopter's 10 real drift findings became 122
  failures. Two further consequences the report did not cover, both reproduced
  against fixtures first: re-pin dropped **every** `# tailored` marker (the one
  thing keeping update mode from overwriting a deliberate fork), and update's
  replace loop fell through to `keep` for every entry — a silent no-op that
  still exited 0. The writer now normalizes the marker, and all eight reader
  sites tolerate it. (#25)

- **Shipped tests asserted on fixtures Windows cannot build.** Five cases
  across four suites failed for environmental reasons, and presented as
  product defects: `FAIL: symlink notes.md->[secret] denied — expected exit 2,
  got 0` reads as the secret guard admitting a symlink to a secret, when in
  fact MSYS `ln -s` had copied the file and the guard correctly evaluated an
  ordinary one. PATH shims no longer need symlinks at all (they are `exec`
  wrapper files, so those cases now *run* on Git Bash rather than skip), and
  genuinely symlink-dependent fixtures capability-probe and `SKIP`. Skips are
  counted and named in every suite summary — a skipped case can no longer hide
  behind `PASSED`. (#26)

- **`verify --fast` accepted a `gates.conf` that `verify` refused.** Given a
  `# inputs` token matching no files, full mode exited 1 with a FAIL while
  `--fast` printed the identical diagnostic to stderr and exited 0 with "OK:
  all quality gates passed (fast)". Validation had been skipped under `--fast`
  for cost, on the belief that `--fast` runs no annotated gate — but gate-kind
  gates run in both modes and may carry an annotation. The config checks are
  now split from the hashing and run in every mode: 0.036s against the 6.05s of
  hashing they replace. Deleting the prescan's discarded key computation also
  takes a warm `--changed` run on this repo from 93.8s to 84.6s. A bare
  `@tool:` is now rejected too — unlike `@tool:absent-binary`, it can never
  resolve anywhere. (#23)

- **`audit-log.sh --format table` is now robust to a CRLF-emitting jq.** jq's
  Windows build opens stdout in TEXT mode, so every line it prints ends CRLF.
  Command substitution strips the LF and leaves the CR, which lands MID-ROW in
  the assembled table (`status=available<CR> v1=1<CR> …`), and a terminal then
  renders the row overwritten from column 0. The text branch normalizes every
  interpolated value; the `--format json` branch is untouched, since a CR there
  is insignificant JSON whitespace and a blanket strip could reach inside string
  values.

  This is **hardening, not a diagnosed fix**. It was written while chasing the
  one Git Bash failure in the shipped `test-audit-log.sh`, whose printed table
  looks byte-identical to its golden — but that cause is still unknown, and a
  CRLF-emitting jq is *not* it: under one, nine other shipped suites fail too
  (`test-affected-files.sh` 13 cases, `test-guard-secrets.sh` 28, …) and all
  nine pass on that runner. The earlier `core.autocrlf` suspicion is likewise
  unconfirmed — forcing `autocrlf=true` on a POSIX host does not reproduce it,
  which rules that path out without promoting any other. The suite now dumps
  `od -c` for both sides on failure so the next Git Bash run reports the actual
  bytes, and it stays excluded from the Windows floor until they are read.

- **Broken-pipe noise on stderr could fail an unrelated gate.** `harness_kit_is_diff_only`
  returned out of a `while read` loop fed by a process substitution, closing the
  pipe while the producer was still writing. On a runner that hands down an
  *ignored* SIGPIPE (GitHub Actions does), the producer's `printf` survives the
  EPIPE and reports `write error: Broken pipe` instead of dying silently. The
  volume is scheduling-dependent, so it varied run to run and turned the
  install-update gate red on ubuntu while macOS stayed green. The reader now
  drains.

### Added

- **CI covers the adopter floor on Windows / Git Bash.** Deliberately not a
  third leg of the existing matrix: that job runs the full `verify`, whose
  eval, live-runtime and prettier-backed gates assume a POSIX toolchain the kit
  has never claimed on Windows, and a red-and-ignored job teaches nothing. This
  one covers what the kit *does* claim — the floor an adopter's own
  `gates.conf` runs, needing only git, jq and a sha256 tool. One step per
  issue, so a regression names itself. It also gives
  `scripts/harness/tests/` its first behavioral coverage anywhere: `.harness/gates.conf`
  globs only the templates tree, so the installed copies were verified as bytes
  and executed nowhere. One suite (`test-audit-log.sh`) remains excluded by name
  and printed as a `GAP:` line, with its cause still open; every other shipped
  suite passes, and cases whose *fixture* the platform cannot build report
  `SKIP:` with a reason and are summed in the job output.

- **`verify` now re-emits `SKIP:` lines from a gate that PASSED.** A passing
  gate's stdout was captured and discarded, so a suite that skipped a case for a
  missing platform capability reported it to nobody — the operator saw only
  `ok:   <label>`. Every shipped suite counts and names its skips precisely so a
  narrowed run is visible, and the only consumer that ever read them was the
  Windows CI step. That made "the skip is counted, so coverage loss cannot hide"
  true on one runner and false under `verify` itself.

- **Eval tasks can declare their host prerequisites (`reference/precheck.sh`).**
  A task whose reference solution needs more than a POSIX shell and git — a
  live dev server, a language runtime, a bindable port — exits non-zero from
  this optional script with a one-line reason, and `test-eval-graders.sh` skips
  that task's grader-validity check instead of failing it. The skip is counted
  and its reason printed, so a precheck that always declines cannot quietly
  retire its own task's coverage. Deliberately per-task rather than TASK.md
  metadata: this repo's `verify-live-runtime` needs `python3` and a loopback
  bind because *its* fixture app is Python, and the shipped floor must stay
  agnostic about what any one task's runtime is. Without it the suite reported
  `reference/apply.sh errored`, which reads as a broken grader when the real
  answer was that Git for Windows bundles no python.

- **`test-verify.sh` capability-probes the `0644 -> 0600` cache case.** On a
  platform that does not record a non-exec-bit permission change, there is
  nothing for the `--changed` key to move on, so the case `SKIP`s with its
  reason instead of failing. The probe declines on both candidate causes — no
  usable `stat` dialect, or a chmod that does not stick — so a failure that
  survives it is a real defect. This is what lets the suite run on the Windows
  floor at all; excluding the whole file had also dropped the only coverage of
  the `# inputs` mode-consistency regression above.

## 0.40.1 — 2026-07-27

### Fixed

- **The shipped `tests/test-verify.sh` failed 13 of its own assertions under
  any CI runner.** GitHub Actions (and most runners) export `CI=true`, and
  v0.40.0's runner deliberately refuses `--changed` there — correctly, since the
  cache is writable by the same agent whose work verify gates. But the suite
  drives `--changed` directly to exercise the memoization, so it inherited that
  refusal and every `--changed` case failed with `rc=64`. The suite now `unset
  CI`s at the top and the one case that asserts the refusal sets `CI=true` for
  its own invocation, so both branches stay covered. Local runs passed because
  a developer shell has no `CI` set; the shipped floor is exactly where that
  divergence is invisible until it reaches a runner. Verified by running the
  suite, `check-harness`, and a full `verify` with `CI=true` before release.

## 0.40.0 — 2026-07-27

### Added

- **`verify --changed` skips a gate only on proof that its declared inputs are
  byte-identical to its last passing run.** Measured on this repo: a warm run
  goes from **326s to 81s**, matching the ablation ceiling (removing those
  gates outright gives 67s from a 243s baseline). Inputs are declared as a
  COMMENT directive in `.harness/gates.conf`, so the format stays compatible
  both ways — an older runner skips `#` lines and therefore *runs* the gate,
  the fail-closed direction, where a new gate kind would have been a hard parse
  error:

  ```
  # inputs <gate-label> <file|dir|glob|@git-head|@tool:name>...
  ```

  This is memoization on a digest, never relevance guessed from a diff: a stale
  path-to-gate map is a silent skip, and a silent skip is a fake green verify.
  The key covers the whole gate list (so a kind change, a reorder, or a new
  neighbour invalidates), the runner itself via `$0` (which subsumes a
  hand-maintained cache-format version), the sorted inventory of files *and*
  directories (an empty directory is invisible to a content hash), per-file
  executable bits (so is `chmod`, and check #5 fails on a lost one), and any
  `@git-head` / `@tool:` material. `@git-head` exists because a gate whose
  workspaces clone committed HEAD would otherwise be keyed on a working tree it
  never reads.

  Fail-closed throughout: a token matching nothing, an annotation naming no
  declared gate, a duplicate annotation, an unknown `@directive`, or a symlink
  in a resolved set all fail the run *before* the first gate executes; a
  missing sha256 tool, an unreadable input, or an unwritable cache runs the
  gate. A failing gate is never recorded. The digest is recomputed after the
  command and written only if unchanged, which narrows the window in which the
  agent being gated edits the files a 190-second gate declared, and gives "a
  gate that mutates its own declared inputs is never cached" for free. It does
  not close that window completely: an input changed and reverted mid-run (ABA)
  hashes the same before and after. That residue is accepted — `--changed` is a
  local mode and CI runs the full set.

  The cache is content-addressed under the git-ignored `.harness/var/gate-cache/`,
  written on a pass in *every* mode so ordinary full runs warm it, and read only
  under `--changed`. Because it is writable by the same agent whose work verify
  gates, `--changed` refuses to run under `CI=true`, and `--fast --changed` is a
  usage error rather than a silent winner. Skips announce themselves and emit no
  telemetry event; a gate that *runs* under `--changed` reports `mode: "full"`,
  so `lib/audit-log.sh`'s enum and daily roll-up need no schema change.

  The key also covers the ambient environment (`PATH`, `TMPDIR`, locale, and the
  whole `HARNESS_*`/`EVAL_*` namespace), because this release's other half
  establishes that an exported variable can hollow out a gate — memoizing a
  verdict without recording the environment that produced it would reintroduce
  exactly that class.

  Ships **inert**: `.harness/gates.conf` is diff-only policy, so no existing
  install gains an annotation without an explicit edit.

  Three review rounds (the repo's `code-reviewer`, an adversarial false-green
  hunt, and Codex) found five reproduced false greens in the first cut, all
  fixed before release and each now pinned by a regression case: duplicate gate
  labels sharing one key so a passing twin warmed it for a failing one; keys
  reused from the prescan instead of recomputed at the hit test; `printf ...
  "$(cmd)" || return 1` guards that tested `printf` and so never fired, silently
  dropping the runner from its own key; a second word-split of an already
  pathname-expanded token, which hashed a same-named decoy while a declared path
  containing a space stayed invisible; and an unreadable file that `find` counted
  but the hasher skipped, yielding a stable key that no longer described those
  bytes. `tests/test-verify.sh` grew from 25 to 47 assertions.

  Two guards were also *relaxed* on review: a symlink or a newline-containing
  path under a declared token is no longer a hard failure but simply unprovable
  (the gate runs), because failing the mandatory full verify over an ordinary
  source tree would let the optimization break the primary command.

### Fixed

- **Six gates could report `ok:` having done no work at all.** `EVAL_TEST_QUICK`,
  `EVAL_TASKS_DIR`, and `HARNESS_NESTED_FIXTURE` are honored by the suites as
  recursion breakers and fast-loop knobs, but a gate is the TOP of a run, never
  a nested one — so one variable exported in a developer's shell silently turned
  the install suites, `provider-templates`, `evals`, and `eval-graders` into
  vacuous passes. Measured: `HARNESS_NESTED_FIXTURE=1 bash
  scripts/test-install-recovery.sh` exits 0 in 0s where the suite does 18s of
  real work. Each gate command now clears its own hatch with `env -u`, which is
  safe because every suite re-exports the breaker for its children after the
  entry check, and which makes the outcome independent of ambient environment by
  construction rather than by hoping nobody exports it. New root-only
  `scripts/test-gate-env-hygiene.sh` derives the hatches by scanning the suites
  rather than hard-coding them, so a hatch added to a new suite fails the gate
  until its declaration clears it.

## 0.39.0 — 2026-07-27

### Fixed

- **Every installed file and directory landed with private modes — scripts
  `0711`, data files `0600`, directories umask-dependent — breaking container
  and multi-uid gate runs.** `_harness_copy_shipped` stages each shipped file
  with `mktemp` (mode 0600) and copies content in with plain `cp`, which
  preserves the *destination's* mode, so the source's mode never applied. Git
  tracks only the executable bit, so committed trees and fresh clones look
  normal — the defect lived purely in installed working copies, on every init
  and every update, and bit exactly where the kit's own guidance sends people:
  a non-root user in the documented containerized gate run cannot *read* a
  `0711` script (bash needs read to execute a script file), and a `0600`
  `kit-manifest` fails the drift checks for a reason that has nothing to do
  with drift. Installed modes are now an explicit ship-contract property,
  umask-independent end to end: files are normalized to `644` after the copy
  (deliberately not `cp -p`, so adopters never inherit how the kit's checkout
  was cloned), executables get absolute `755` (symbolic `+x` is umask-masked —
  under `umask 077` it yielded `744`), and a new `_harness_mkdir_installed`
  helper creates missing directory components at `755` atomically
  (`mkdir -m`), refuses symlinked components by name, and touches **only
  directories it creates** — an adopter's pre-existing directory modes are
  theirs. Wired at all four sites that create installed-tree directories,
  including both update-apply paths. A new maintainer-suite case installs
  under `umask 077` and asserts the octal mode of every shipped file and
  directory, so the contract is pinned, not assumed. (#20)

- **test-check-loops.sh could not tell "the rule holds" from "the scan is
  broken."** The structural scanner — the guard added for the here-doc
  fail-open class (#15) — discarded awk's exit status and sent its stderr to
  /dev/null, so a broken scan program produced empty output for every file and
  the test printed `ok:` having scanned nothing: the same fail-open shape it
  exists to stamp out, one level up. A scanner failure is now a loud per-file
  FAIL carrying awk's stderr; each of the five glob roots is guarded
  individually (a root that fails to resolve or contributes zero shell files
  is a named FAIL — an empty `$(cd ...)` result used to silently rewrite the
  glob and the surviving roots kept the counter positive); an unreadable swept
  file is a named FAIL instead of being mistaken for a non-shell file; and
  five exact-line positive-control fixtures pin every scanner rule — the
  done-heredoc loop, the single-read form (the historical miss), the
  line-continued redirect, and marker adjacency (a marker outside the reader's
  own comment block does not excuse it). The structural `ok` is withheld on
  any scan error, read error, empty root, or zero-file sweep: an empty finding
  list is not evidence unless every root was actually swept. (#21)

- **Two test-sync-adapters.sh assertions could pass without exercising what
  they claim.** The negative "deadlock scenario" case accepted *any*
  `sync --check` failure as proof the stripped blank line was re-flagged — an
  unbuilt fixture or a failed mutation produced the same nonzero exit and the
  same green line. Every setup step is now gated, `--check` must be clean
  *before* the mutation, and the mutation is verified to have actually removed
  the blank line, so the final nonzero exit is attributable to the one byte
  the case changed. And the prettier "byte-for-byte" comparison ran through
  command substitution, which strips trailing newlines from both sides —
  blinding it to the likeliest formatter delta. It now compares files with
  `cmp -s`, which is what byte-for-byte meant all along. (#22)

- **Maintainer install suite: three of its own checks could not fail.** The
  mktemp preflight was brace-nested inside the sha256 check's else-branch and
  silently never ran without a sha256 tool on PATH; the clean-init inventory
  loop read the kit-manifest from a wrong path, inspected zero files, and
  still printed both its `ok` lines (its counter counted one blank printf
  line); and the new mode case initially trusted `stat -f` output that GNU
  stat pollutes (breaking Linux CI unreadably) and derived its full-count
  floor from the helper under test. All four closed: the preflight is
  unconditional, inventory counters count inspected paths against full-count
  floors plus per-layer sentinel membership, and `mode_of` shape-validates
  every probe. Maintainer-only files — adopters are unaffected.

### Migration

- Update mode replaces `scripts/harness/lib/install-lib.sh`,
  `scripts/harness/tests/test-check-loops.sh`, and
  `scripts/harness/tests/test-sync-adapters.sh` when pristine (diffed when
  tailored). Working-copy file modes repair themselves on the next
  init/update run; no manual chmod needed.

## 0.38.0 — 2026-07-26

### Fixed

- **Check #10e stayed silent for biome and dprint configs scoped by file
  extension — the exact configs it exists to catch.** The check collapses every
  manifest-pinned path into the two directories nearly everything funnels
  through (`scripts/harness`, `.harness`) and compares include patterns against
  those strings. Both matchers strip a leading `**/` and trailing glob noise
  first, so an include of `**/*.md` reduces to `*.md`, which can never
  string-match a bare directory name. Every kit path then read as "the
  formatter does not reach this", and the branch emitted nothing — while
  dprint or biome would in fact rewrite the checksum-pinned
  `scripts/harness/hooks/README.md` and every generated `.harness/adapters/*.md`
  and provider `SKILL.md` stub, breaking the integrity pin and hard-failing
  `check-harness`'s drift check on an otherwise clean tree.

  The collapse is only sound for prefix-style **ignore** matching, where a
  missed match fails toward an extra warning — noise, which this check
  deliberately prefers. On an **include** side the same miss fails toward
  silence, the one direction it cannot afford. Include-side matching now also
  asks whether a pattern reaches any representative *descendant file* under a
  kit path: formatter-parseable manifest pins serve as their own
  representatives, and the generated directories the manifest cannot see get
  synthesized stand-ins, so the answer stays correct in a repo whose stubs are
  not generated yet. Directory-shaped includes keep matching exactly as before,
  ordered `!` negations still exclude as before, and the warning still names
  the collapsed kit path — that is what a reader adds to their config. The
  prettier branch is unchanged; `.prettierignore` matching was never affected.

- **A pre-commit formatter hook silenced #10e merely by carrying a `files:`
  key, even when that key still matched kit files.** The scan treated the
  presence of the key as proof the hook was scoped away from kit-owned paths,
  so `files: \.md$` — which matches every pinned and generated Markdown file
  pre-commit would hand it — skipped the entire coverage check. This
  contradicted the check's own stated rule that when coverage cannot be proven
  it warns with hedged wording rather than assuming safety. The scan now
  extracts each formatter hook's pattern and probes it against representative
  kit file paths: a pattern that reaches one falls through to the coverage
  logic with hedged wording naming the probe as best-effort, a pattern that
  reaches none is genuinely scoped and stays silent (`files: ^src/` does not
  warn), and a pattern this scan cannot recover or the local `grep -E` cannot
  parse warns that it could not be evaluated. Per-hook block attribution is
  unchanged, so an unrelated hook's `files:` still cannot suppress a warning
  for a different, actually-unscoped formatter hook.

  Quoted patterns are decoded the way the YAML loader would, because the
  quoting style changes the regex: a double-quoted scalar processes escapes
  before pre-commit ever sees it, so `files: "\\.md$"` **is** the regex
  `\.md$`, and probing the raw text instead tested a pattern matching no kit
  file — reintroducing the same silence through a different spelling. Single
  quotes stay literal apart from a doubled quote, and a double-quoted escape
  this scanner cannot decode (`\t`, `\n`, `\xNN`, a trailing lone backslash)
  is reported as unevaluable rather than guessed at.

### Changed

- **Update mode's manifest re-pin now points at `bootstrap repin`, and a
  version-less re-pin is a diagnosed error instead of a corrupt manifest.**
  `harness_repin_manifest` is a pure-stdout producer by design — it prints the
  regenerated manifest and writes nothing — but update mode's step 4 named the
  function as though it rewrote the file. Followed literally it exits 0,
  prints to the terminal, and leaves the old version header and now-stale
  checksums in place, which silently mis-classifies pristine files as drifted
  on the *next* upgrade. The obvious repair is also wrong: redirecting the
  function straight onto `.harness-manifest` truncates the very file it reads
  ` # tailored` markers back from, un-forking every tailored line. Both steps
  that re-pin now direct the reader to
  `bash <new_src>/harness/bootstrap repin <root> <version>`, which already
  existed — it validates both arguments, gates on a sha256 tool, and writes
  atomically via a temp file. The underlying function additionally rejects a
  missing or empty `<kit_version>` with a message naming the fix, rather than
  emitting a header with no version behind an exit code of 0.

## 0.37.0 — 2026-07-26

### Fixed

- **The opt-in prettier ignore block missed nested checkouts, so an adopter's
  format gate went red on a clean tree.** `.prettierignore` follows gitignore
  matching, where a pattern containing a slash before its end is anchored to
  the repo root — the block's `scripts/harness/` and `.harness/adapters/`
  matched the root copy and nothing else. Claude Code's worktree feature puts
  a full second checkout of the repo under `.claude/worktrees/<name>/` and
  hides it via `.git/info/exclude`, which prettier does not read. Prettier does
  read `.gitignore`, so a repo that also lists the directory there is already
  spared; in the repo where this was reported it was not, and `prettier --check .`
  descended into the nested copy, flagged the checksum-pinned and generated
  files there, and failed the adopter's format gate — and with it
  `bash scripts/harness/verify` — with nothing actually wrong in the tree.
  `harness_append_formatterignore` now excludes `.claude/worktrees/` (which
  also spares the nested copy of the adopter's *own* sources, inside which
  their own anchored entries silently stop applying) and writes every
  kit-owned entry in the depth-agnostic `**/` form, which gitignore matches at
  any depth **including** the root — a strict superset of the plain form it
  replaces, not a relocation of coverage, and the shape that covers submodules
  and vendored checkouts too.

  The `**/` forms are deliberately broad: `**/scripts/harness/` also excludes
  an unrelated `packages/app/scripts/harness/` an adopter happens to own, so a
  monorepo may find a directory of its own going unformatted. That trade is
  intentional — the cost is a few files a formatter skips, against a broken
  checksum pin and a red gate for the miss in the other direction — but if it
  is the wrong trade for a given repo, delete the `**/` lines and keep
  `.claude/worktrees/`, which alone covers the reported failure.

  **Existing installs need `bootstrap update --formatter-ignore` re-run.** The
  helper only ever appends the required lines it cannot find, so a re-run adds
  the new entries and leaves the already-present plain ones (harmless subsets)
  untouched — no hand-editing, and no second write on a repo already carrying
  the new block.

- **Hooks in `.harness/hooks/` wrote their telemetry and stop-markers outside
  the repository.** `scripts/harness/hooks/lib.sh` resolved the repo root as
  `dirname($0)/../../..`, and `$0` is the *calling* hook — correct for the
  kit's own guards at `scripts/harness/hooks/<name>.sh` (three levels below
  the root), one level too high for a tailored policy hook at
  `.harness/hooks/<name>.sh` (two levels below — the home ADR 010 documents).
  Those hooks resolved the repo's **parent**, so `hook_log` appended to a
  stray `<parent>/.harness/var/log.jsonl` and `hook_advise_once_seen` created
  `<parent>/.harness/var/stop-markers/`. Both writers fail open, so there was
  no symptom: outcome telemetry from the policy layer never reached the
  repo's own log and the audit workflow undercounted it, while every checkout
  sharing a parent — git worktrees most visibly — deduped stop advisories
  against one another, letting a sibling worktree swallow an advisory that
  had never been shown there. The root is now resolved once from `lib.sh`'s
  own `BASH_SOURCE` path, which removes the caller's depth from the
  calculation entirely; an unrecognized layout (a fixture that copies
  `lib.sh` somewhere flat) resolves to `lib.sh`'s own directory, so writes
  stay inside the fixture instead of climbing out of it. `HARNESS_LOG_FILE`
  and `HARNESS_STOP_MARKER_DIR` overrides are unchanged. Adopters with a
  tailored `.harness/hooks/` hook may have a stray `.harness/var/` directory
  beside their repository; it is safe to delete once its contents are no
  longer wanted.

- **`check-docs` no longer pulls nested worktrees into the doc-link gate.**
  Check #4's `AGENTS.md` scan walked the whole tree, so every live
  `.claude/worktrees/<name>/` checkout contributed its own `AGENTS.md`: a
  broken link in a branch someone else was still writing failed *this*
  checkout's gate, naming a path the reader was not editing and could not fix
  from where they stood, and the scan's cost multiplied by the worktree count.
  The find now prunes that directory (a `-prune`, not a result filter, so the
  walk actually stops).

- **Doctor check #10e now sees the same blind spot.** It recognizes a leading
  `**/` as coverage (without it the check would warn about a remedy the kit
  had just applied), names `.claude/worktrees` among the paths a formatter
  must not reach — but only when that directory exists, so a repo that has
  never made a worktree gains no new warning — and appends a nested-checkout
  hint to the prettier, biome, dprint, and pre-commit warnings alike, since
  every one of those exclusion mechanisms is path-anchored and none is
  interchangeable with `.prettierignore`.

## 0.36.0 — 2026-07-26

### Fixed

- **The here-doc fail-open is closed across every check family, not just
  `check-drift`** ([#15](https://github.com/Neogenuity/harness-kit/issues/15)).
  v0.34.0 fixed the three loops in `check-drift.sh` the issue named and recorded
  the other 19 as deferred; the promotion trigger fired the same day. Both
  first-adopter repos reproduced the failure live: in one,
  `lib/check-instructions.sh` emitted 11 `cannot create temp file for here
  document: Operation not permitted` errors — six of them from line 441, the
  **#8d hook-wiring validator** — and exited 0. That check is what proves the
  guards are wired at all, so a harness with its entire `hooks` object deleted
  passed. `check-drift.sh` printed `OK: drift checks passed` the same way.

  All 16 of those loops that run to completion now read through process
  substitution (no temp file, byte-identical input) and assert they actually
  consumed it, via a new shared `assert_loop_ran` in `lib/check-common.sh` that
  carries the whole rationale in one place: `check-instructions.sh` #7, #8c
  (inventory pins and per-server audit), #8d (tuple coverage and command
  resolvability) and #8g; `check-doctor.sh` #10e (kit-path collection, prettier,
  biome, dprint, pre-commit); `check-docs.sh` #10c; `install-lib.sh`
  (ship-contract duplicate reporting, and the `.prettierignore` heal — where a
  skipped loop reported success without writing the block it exists to write);
  and `eval-harness.sh`'s results table. The kit's own `test-install-core.sh`
  and `test-shipped-doc-refs.sh` had the same shape and printed `ok` / `all
  checks passed` without examining a single path; both now assert their scans
  ran.

  Adopters get their own coverage: a new shipped floor test,
  `scripts/harness/tests/test-check-loops.sh`, asserts that `assert_loop_ran`
  behaves, that a real family run with no writable `$TMPDIR` **and** no writable
  CWD does not go silent, and — the durable guard — that **every** surviving
  here-doc-fed reader carries a comment marking its retention deliberate. That
  last check is what stops the class from growing back one site at a time; it
  fails against the pre-fix tree listing all 20 unmarked sites (the 19 loops
  plus `verify`'s single `read`). It scans
  `lib/`, `hooks/`, `tests/` and the extensionless entry points, and matches
  single `read ... <<` as well as `done <<` — a narrower first cut, limited to
  `done <<` in `lib/` and `hooks/`, could not see the `verify` defect below.
  Files the repo owns (`# tailored`, or locally drifted from their pin) are
  reported as a note rather than failed, because update mode deliberately does
  not replace those: hard-failing there would be a demand no upgrade can
  satisfy. Three more cases in the maintainer suite pin the families end to end
  (#9c, #8d, #10e), and one covers the `.prettierignore` heal returning success
  without healing.

- **`verify` could blame your `gates.conf` for an unwritable temp dir.** The
  gate runner split each config line with `read -r kind label cmdstr <<LINE`.
  When that redirection fails all three fields stay empty, and the very next
  check reports `FAIL: malformed .harness/gates.conf line` — naming a
  well-formed line and exiting before a single gate runs. This is narrower than
  the fail-open class above (it fails *closed*, and `verify` chdirs to the repo
  root first, so the CWD fallback normally covers it — a read-only checkout plus
  an unwritable `$TMPDIR` is what it takes) but the diagnostic sends you to
  audit a config file that was never the problem. Now split with plain parameter
  expansion, which needs no temp file at all; verified field-for-field identical
  to `read` across every line of this repo's `gates.conf` and the whitespace
  edge cases.

  Five loops deliberately stay on here-docs: they `return` on the first match,
  where process substitution would expose the `printf` writer to the
  ignored-SIGPIPE phantom failure this repo hit twice. Every one of them fails
  **closed** — a lost redirection makes them report "not found" or run no
  formatter, never a false pass. Each site says so in a comment, and
  `docs/plans/tech-debt.md` records the class with a promotion trigger.

  **Migration:** update mode replaces `lib/check-common.sh`,
  `lib/check-instructions.sh`, `lib/check-doctor.sh`, `lib/check-docs.sh`,
  `lib/install-lib.sh`, `lib/eval-harness.sh`, `hooks/format.sh`, and `verify`,
  and adds `tests/test-check-loops.sh` to the shipped floor. No config change.

  If you have tailored (`# tailored`) or locally drifted any of those files,
  update keeps your copy — `harness_update_decision` returns `diff` for both
  cases — while still installing the new floor test. Your build will **not**
  break: the new test reports repo-owned files as a note rather than a failure,
  precisely because upgrading cannot fix a file the upgrade does not touch. You
  should still port the pattern by hand, and note that the helper it needs
  (`assert_loop_ran`) lives in `check-common.sh`, which may itself be in your
  not-replaced set. The failure this closes is silent by construction, so a
  tailored copy gives no outward sign of still having it.

## 0.35.0 — 2026-07-26

Stale shipped text, and the maintainer gate that should have caught it. Both
first adopters independently hand-corrected the same `AGENTS.md` sentence
before anyone reported it — that duplication is what surfaced the class. Every
prose fix here ships into adopting repos; none of them changes behaviour.

### Fixed

- **`AGENTS.md.tmpl` sent adopters to the wrong file to edit their gates.** It
  said the ordered gates live in `scripts/harness/verify` and to "edit the
  gates in that script, never here" — wrong since v0.23.0, when the gate list
  moved to `.harness/gates.conf` and `verify` became checksum-pinned mechanism.
  An adopter who followed the sentence either hit the config guard or edited
  the runner and broke their own integrity pin. It now names
  `.harness/gates.conf` as the gate list, the runner as mechanism, and
  `check-harness` (#9a) as what rejects a local edit to it.

- **The shipped `gates.conf` promised a floor entry retired two versions
  earlier.** Its comment described the installed floor as including "the
  install smoke test"; `test-harness-smoke.sh` left the shipped set in v0.29.0.
  It now names the floor that actually ships — hook behavioural tests, library
  and runtime suites, grader validity — and records the retirement.

- **Three further copies of those same two retirements, all shipped.**
  `references/modes/init.md` told adopters to check that each
  `scripts/harness/hooks/test-*.sh` passes standalone, from a directory that
  has held no tests since the v0.23.0 move to `scripts/harness/tests/`;
  `check-tests.sh`'s check #6 comment repeated the smoke claim and credited
  recursion control to the retired `test-harness-smoke.sh`, when the shipped
  floor's one nested-checker test is `test-eval-graders.sh`, which owns it by
  exporting `HARNESS_SKIP_TESTS_FAMILY` (`HARNESS_NESTED_FIXTURE` is read by no
  shipped mechanism at all); and `check-harness`'s own header said "CI and the
  smoke test call THIS".

- **`references/fixture-recipe.md` could not build a working fixture.** Its
  copy block still used the pre-v0.23.0 flat layout, installing the hooks where
  the checker does not look and omitting `lib/`, which `check-harness` sources.
  Corrected to the current layout, with an explicit note that this hand-copy
  exercises the hooks only — a fixture a checker can pass needs `init`. The
  same file's plan-seeding block lacked a `mkdir` for `.harness/templates`, so
  its `cp` failed; fixed.

- **`check-doctor.sh` mis-described an adopter's manifest** as "mostly
  `scripts/*.sh` entries". An installed manifest is essentially all
  `scripts/harness/**/*.sh`.

### Changed

- **The shipped-doc-refs gate sees glob citations, and can no longer pass
  without running.** Its token regex stopped dead at `*`, so
  `scripts/harness/tests/test-*.sh` extracted as nothing — which is why the
  `init.md` defect above survived the v0.23.0 relocation. Globs now resolve by
  matching at least one **regular** file (a directory named `test-x.sh` cannot
  satisfy a citation), and `${VAR}/scripts/…` no longer falls out of the
  pipeline unchecked. Literals are still read from the whole file, but globs
  are read from prose only — every line of a `.md`/`.tmpl`/`.conf`, comment
  lines only in a `.sh` — because a glob in shell code is a loop domain that is
  allowed to be empty by design, and demanding it match would push
  `doc-ref-ok:` annotations into shipped mechanism to satisfy a maintainer-only
  gate. The scanned set gains `templates/scripts/gates.conf`, the
  `templates/scripts/harness/` runners, the skill's `SKILL.md`, and this repo's
  own `.harness/gates.conf`.

- **That gate no longer fails open.** Both check loops were here-doc-fed — the
  issue-#15 class, where bash 3.2 puts the here-doc temp in `$TMPDIR`, falls
  back to CWD, and from an unwritable directory runs the loop body zero times
  while still exiting 0. They use process substitution now (neither loop breaks
  early, so there is no SIGPIPE hazard), and a counter assertion in each pass
  turns any future silent skip into a failure instead of a green result.

- **Contributor docs stopped misrouting guard tests.** `docs/standards/
  templates.md` and `CONTRIBUTING.md` said a guard's regression test goes
  "beside it" under `templates/scripts/harness/hooks/`. Every gate globs
  `.../harness/tests/test-*.sh`, so a test written beside the hook is a test no
  gate ever runs — exactly the silent failure that rule exists to prevent.

### Migration

- The mechanism files touched here (`check-harness`, `check-tests.sh`,
  `check-doctor.sh`) are **replaced** by update mode. Every changed line is a
  comment, so there is no behaviour change and no work beyond the normal
  update.
- `.harness/gates.conf` is a **policy** file — update mode never overwrites it.
  The corrected floor comment therefore arrives as a proposed diff to accept,
  not automatically. Adopters who never take it keep a stale comment and a
  correct gate list.


## 0.34.0 — 2026-07-26

Three defects found by running the kit against a large external repo and by an
outside report. Two made `doc-garden` unusable there — it could not finish, and
what it did report included false positives. The third let `check-drift` print
"OK" without having run its completeness check.

### Fixed

- **`doc-garden` no longer takes hours on a repo with a long deletion history.**
  The deleted-path-reference stage was `O(deleted paths × tracked .md files)`,
  re-listing the tracked Markdown set and re-reading every file once per
  deleted path — two `awk` spawns per pair, ~5ms each. On a repo with 6,179
  historical deletions and 146 Markdown files that is 902k pair scans, measured
  at over an hour; because the report only prints at the very end, a timeout
  yielded **no output at all**. The stage now builds the deleted set once and
  scans each file a single time against it, so cost tracks total documentation
  size instead of Git history. Findings are unchanged: for a backtick-free path
  the interior fields of a backtick split are exactly the substrings the old
  per-path search found, and the rare path that itself contains a backtick —
  invisible to that split — keeps the original literal search. Same 15 findings on this repo,
  23s → 7s; the shipped test pins the shape by asserting `ls-files` invocations
  do not scale with the deleted-path count.

- **`doc-garden` reported legitimate GitHub anchors as missing.** GitHub slugs a
  heading by lowercasing, deleting disallowed characters, and then turning
  **each** surviving space into its own hyphen. Runs are not collapsed, so
  `## Provider Portability: DigitalOcean ↔ AWS` anchors as
  `#provider-portability-digitalocean--aws` — the symbol goes, both spaces
  around it stay. `heading_has_anchor` collapsed the run to a single hyphen and
  reported every correct double-hyphen link as `missing-anchor`. It now
  hyphenates per space, and trims trailing heading whitespace first (CommonMark
  drops it before the slugger sees it) so the change cannot invent trailing
  hyphens.

- **`check-drift` could report success without running completeness check #9c**
  ([#15](https://github.com/Neogenuity/harness-kit/issues/15)). Bash backs a
  here-doc with a temp file; bash 3.2 puts it in `$TMPDIR` and falls back to the
  CWD. With neither writable the redirection fails, and under `set -uo pipefail`
  without `set -e` a failed redirection skips the entire compound command. That
  loop is #9c's only error source, so the script printed `OK: drift checks
  passed` and exited 0 for a repo with unpinned mechanism files on disk —
  reproduced against a fixture, not theorized. Checks #9c, #9d, and #9e now read
  through process substitution (no temp file, byte-identical input) and each
  asserts it actually consumed its input, so "the check could not run" is an
  ERROR instead of a silent pass.

  Note the same here-doc-fed loop shape remains at 19 other sites; they are
  recorded in `docs/plans/tech-debt.md` rather than converted here, because
  about half exit the loop early and process substitution would expose those to
  the ignored-SIGPIPE phantom failure this repo hit twice.

  **Migration:** update mode replaces `lib/check-drift.sh`. No config change.

## 0.33.0 — 2026-07-25

A repo-wide code formatter in an adopter repo rewrote the kit's checksum-pinned
and byte-exact generated files, hard-failing `check-harness` — and for generated
adapters it was a deadlock with no escape hatch. The kit now emits
formatter-stable bytes, can write prettier's ignore block on request, and warns
when a formatter it cannot configure is left pointed at kit-owned paths.

### Fixed

- **`.harness/adapters/*.md` no longer deadlock against a markdown formatter.**
  `render_adapter` emitted its `<!-- generated ... -->` comment immediately
  followed by a heading. Prettier always inserts a blank line between block
  nodes, so `sync` regenerated bytes the formatter rejected while the formatter
  produced bytes `sync --check` rejected — and generated files have no
  `# tailored` marker, so neither side could yield. The generator now emits the
  blank line itself.

  This removes the collision under prettier's **default** config only. The
  adapter body is hard-wrapped prose, so `proseWrap: "always"` reopens it; the
  ignore block below is the actual guarantee. Same reasoning that keeps
  `hooks/README.md` hand-authored rather than reformatted.

  **Migration:** update mode replaces `lib/sync-lib.sh`. Re-run
  `bash scripts/harness/sync` and commit the regenerated adapters — a one-time
  reformat, or `sync --check` reports all of them stale.

- **Skill-stub churn from YAML frontmatter.** The shipped `verify-live` and
  `_example` skill templates used 4-space folded scalars; prettier's YAML
  default is 2. A formatter run reindented the canonical file, desyncing every
  derived stub until the next `sync`. Both templates now ship 2-space.

  **Migration:** diff-only — these are `content`, never auto-replaced. Existing
  installs keep their copies; reindent if you run a formatter.

- **`sync --check`'s umbrella error named only skill stubs** while also covering
  agent stubs and generated adapters, sending readers to the wrong files.

### Added

- **`--formatter-ignore` on `bootstrap install` and `update` (opt-in).** Writes
  an idempotent marked block to `.prettierignore` covering the kit-owned
  mechanism tree and every generated stub directory. Never an unconditional
  repo-config mutation: init asks in the existing interview, update surfaces it
  in the diff, and `--dry-run` writes nothing. The `update` path matters most —
  it previously called no ignore helper at all, so pre-existing installs could
  not receive the block on upgrade.

  Scoped to prettier by design. It does **not** help biome, dprint, or
  pre-commit; their exclusion mechanisms are not interchangeable, and the docs
  now say so rather than implying an automated remedy.

- **Doctor check 10e (warning-only) — a repo-wide formatter that still reaches
  kit-owned paths.** Tool-specific guidance for prettier, biome, dprint, and
  pre-commit, since telling a biome user to edit `.prettierignore` is worse than
  silence. Derives its path set from the manifest, filtered to extensions a
  formatter can actually parse, so it never nags about shell files. Fails open
  and hedges rather than asserting coverage it could not verify.

- **`scripts/harness/tests/test-sync-adapters.sh`** — pins the adapter's blank
  separator and, when prettier is on `PATH`, asserts the generated bytes are a
  fixed point of it. Skips cleanly without prettier, so the gate never depends
  on npm. Ships via the existing `parallel-each` glob; no `gates.conf` change.

### Known limitations

- The ignore block covers generated stub directories but not their canonical
  sources (`.agents/skills/`, `.harness/agents/`). A formatter rewriting those
  desyncs derived stubs until `sync` is re-run — churn, not deadlock, since
  `sync` converges. Documented in `docs/standards/templates.md`.

## 0.32.0 — 2026-07-25

Adopters now receive the grader-validity proof their eval docs already promised
them, and the destructive-change policy stops describing a layer taxonomy that
0.31.0 made false. Resolves issues #13 and #14.

### Added

- **`scripts/harness/tests/test-eval-graders.sh` — grader validity now ships.**
  For every task in the repo's bank it proves, offline and with no model: the
  reference solution scores `pass`; every negative task's `reference/violate*.sh`
  scores `violation` (exit 3, not merely "some non-pass"); every
  `reference/wrongplace*.sh` is rejected. This was maintainer-only from 0.22.0
  while seven adopter-facing references still described it as active
  enforcement, so an adopter authoring a task got the documentation and not the
  mechanism — a grader that silently scores a violation as an ordinary miss
  stayed false-green forever. It runs in the shipped floor via the existing
  `parallel-each harness-test` glob, needs no `gates.conf` change, and gives
  `eval_apply_violation` a shipped caller for the first time.

  **Cost:** none on a fresh install. `eval_list_tasks` skips `_*` directories
  and the kit ships only `scenarios/_template`, so the bank is empty and the
  test no-ops. Once a repo authors tasks it is roughly 3.7s per task
  (measured: 13 tasks, 23 assertions, 48s), and `EVAL_TEST_QUICK=1` skips it.

- **`scripts/test-shipped-doc-refs.sh` (maintainer-only) — a gate for the
  failure class behind #13.** Shipped prose must not cite a script the kit does
  not ship, and this repo's own prose must not cite one that does not exist. The
  class is silent by construction: the kit repo keeps descoped suites at root,
  so a template citing one passes every check that looks at this tree. On its
  first run it found a fourth instance in `references/fixture-recipe.md`, which
  claimed the descoped install suites still ship.

### Fixed

- **`docs/policies/changes.md`: the three-layer taxonomy matched 0.30.x, not
  0.31.0.** Wiring `guard-secrets.sh` to `Bash` made two of its core claims
  false in the same release — that hooks are "file-edit scope only", and that
  native pre-action enforcement "is the only layer that stops a shell command".
  Neither held: the hook token-scans shell command text and denies before
  execution, while the native deny lists are `Read(...)`-scoped and never see
  `Bash`. A reader following the old text concluded that a native deny stops
  `cat <secret-file>` (it does not) and that the layer which *does* stop it
  needs no scrutiny — when in fact that layer is the fail-open, bypassable one.
  That inversion is exactly what the document exists to prevent. The template
  now also documents the basename false positive (an ordinary `grep -rn` or a
  `git commit -m` mentioning a secret filename is refused), scopes the CI
  backstop to kit mechanism files, and names OpenCode as having no hooks at all.
  Its TAILOR block now exempts **every** `execution-profiles.md` pointer, not
  just the closing one, matching `security.md`.

- **Seven shipped references to the retired `test-eval.sh` now point at the
  shipped test**, including `AGENTS.md.tmpl`, which cited
  `scripts/harness/tests/test-eval.sh` — a path that never existed anywhere —
  and wrote that claim into every adopting repo's canonical index.

### Changed

- **Grader validity runs once, not twice.** The loop was removed from the
  maintainer-only `scripts/test-eval.sh` (which keeps the eval-machinery
  conformance half) and given its own parallel gate, off `check-harness`'s
  serial path. Adopters are unaffected; the shipped `gates.conf` already sets
  `HARNESS_SKIP_TESTS_FAMILY=1` on its harness gate.

**Migration:** `test-eval-graders.sh` is a mechanism file — update mode installs
it automatically, and the shipped `gates.conf` glob picks it up with no edit. If
your repo has no golden tasks it does nothing. `docs/policies/changes.md` is a
`content` file authored at init and repo-owned afterward, so update mode will
not overwrite your copy: apply the taxonomy correction by hand if you want it.

## 0.31.1 — 2026-07-25

Stops `sync secrets` from reformatting the provider config it edits.

### Fixed

- **`sync secrets` preserves the target file's existing indentation.** It wrote
  jq's output straight back, and jq renders 2-space by default, so any change to
  `SECRET_PATTERNS` reindented the whole document — adding five patterns in
  v0.31.0 produced a 47-line diff in `opencode.json` of which only ~10 lines
  were the new deny keys. The kit installs into other people's repos, so that
  churn lands in an adopter's hand-formatted config, buries the
  security-relevant delta in review, and manufactures merge conflicts. The
  reconcile now reads the target's layout and matches it (`--indent N` for
  widths 1–7, `--tab`, `-c` for a single-line document; jq's default when there
  is no indented line to learn from, unchanged from before). Ensure-present +
  preserve semantics are untouched — nothing is ever removed, and the deny
  additions are asserted to still land.
- **`sync secrets` is now genuinely idempotent on a non-2-space file.** The
  write path decides whether to rewrite by comparing jq's rendering against the
  file's bytes, so a 4-space config never matched: every run rewrote it and
  reported `reconciled`. It now reports `already current` and leaves the file
  alone. **Migration:** none — but the first run after upgrading may still
  rewrite a config that v0.31.0 flattened, once, to restore your layout.
- This repo's own `opencode.json` is restored to the 4-space style v0.31.0
  flattened.

## 0.31.0 — 2026-07-25

Closes a secret-read gap on Claude Code's most-used tool, widens the default
secret patterns, and corrects a batch of shipped-template claims that
contradicted the code they described.

### Added

- **`Bash` joins the Claude Code `guard-secrets.sh` matcher** (`Read|Grep` →
  `Read|Grep|Bash`). The native deny list is `Read(...)`-scoped, so `cat .env`
  passed both the permission layer and the hook; the guard's shell-command
  token scan already existed (it is the live secret layer on Codex) but nothing
  routed Claude's `Bash` calls into it. **Migration:** the matcher lives in
  `.claude/settings.json`, which update mode DIFFS rather than replaces —
  approve the diff to adopt. Expect new denials: the scan matches on basename
  and never checks whether a token is a real path, so any command whose *text*
  names a secret file is refused, including commands that read nothing
  (`git commit -m "clarify .env handling"`). Rephrase, or leave `Bash` out of
  the matcher if your repo discusses secret filenames constantly.
- **Five more default `SECRET_PATTERNS`**: `id_ecdsa`, `id_dsa`,
  `.git-credentials`, `*.ppk`, `*.jks`. **Migration:** `harness.conf` is
  policy-layer, so update mode diffs it; after adopting, run
  `bash scripts/harness/sync secrets` to regenerate the native provider deny
  lists — `check-harness` #8/#8b flags the gap until you do.

### Fixed

- **`guard-secrets.sh` is ~4x faster per shell token** (~24ms → ~5.7ms; a
  124-token command went 3005ms → 787ms). It spawned `readlink`, two
  `basename`s and two `classify` subshells for every token on the command line
  — a cost Codex always paid and Claude Code would now pay too. Basenames use
  parameter expansion, `readlink` runs only for an actual symlink (for anything
  else it returns a normalized path with the same basename, so it cannot change
  the verdict), and the literal is classified only when it differs from the
  target. Coverage is unchanged: symlink laundering is still denied and the
  full case bank still passes.
- **The shipped provider templates now carry the full deny list.** Adding
  patterns updated the installed root configs but not
  `templates/providers/{claude,opencode}/`, so a *fresh* install began with a
  failing `check-harness`, and fresh OpenCode installs silently lacked the new
  native denies.
- **`harness.conf` told you to edit a sha256-pinned file, at a path that no
  longer exists.** It named `hooks/test-guard-secrets.sh` (the file moved to
  `tests/` in the v0.23.0 re-home) and omitted that editing it needs
  `HARNESS_ALLOW_MECHANISM_EDITS=1` plus a manifest re-pin.

### Changed

- **The `.env.example` contradiction is now documented rather than papered
  over.** `harness.conf` claimed allow patterns beat secret patterns; that
  holds in the hook, but the Claude mirror is deny-only by design (ADR 011), so
  the default `.env.*` pattern denies `.env.example` natively there.
  `harness.conf`, `hooks/README.md`, ADR 011 and the affected test labels now
  say so, and `test-sync-secrets.sh` pins the deny-only invariant executably
  instead of leaving it as prose in four files.
- `hooks/README.md` no longer calls the manifest "the backstop" unqualified
  where pre-edit hooks are absent: it pins kit mechanism files only, never
  `GUARD_PROTECTED_EXTRA` entries.
- `docs/policies/security.md`'s TAILOR block carries an explicit exemption from
  its own keep-verbatim rule for the `execution-profiles.md` pointers, which
  are dead links in a repo that declares no profile.
- Installed-path corrections in shipped templates: the evals README and all
  three CI workflow headers named kit-repo paths instead of their installed
  destinations, and the reviewer persona's untrusted-content link carried a
  label naming a file that does not exist.
- `provider-matrix.md`'s hook row records the `Read|Grep|Bash` tuple, and
  `guard-secrets.sh`'s own header no longer describes the token scan as
  Codex-only.

## 0.30.0 — 2026-07-25

Closes a false-pass hole in eval grading and corrects two guard/sandbox scope
claims that overstated what the harness actually enforces.

### Fixed

- **A `check+verify` eval task whose workspace lost `scripts/harness/verify` now
  fails as a grader error instead of silently scoring `pass`.** The verifier
  presence was guarded by a bare `[ -f ]` that skipped verification when the file
  was absent, so a trial that deleted or renamed the very gate it was supposed to
  satisfy could record a false success — and that success could be written to a
  baseline. `eval_grade` now returns 2 (grader error, aborts the run) in that
  case, matching the existing missing-`check.sh` behavior: a task whose promised
  grader is absent cannot be scored. No task in the shipped bank uses
  `check+verify`, so this was latent here but live for any adopter authoring one.
  **Migration:** update mode replaces `eval-lib.sh` and `eval.sh` outright
  (mechanism, not tailored). If you author `check+verify` tasks, a run that
  previously reported `pass` with a missing verifier will now abort and name the
  missing path.

### Changed

- **`guard-secrets.sh` now documents that its search coverage is narrower than
  its `Read|Grep` wiring implies.** Only a call that *names* a secret file is
  denied; a directory-scoped search — or one omitting its path, meaning "search
  the project" — is allowed by design, because denying those denies nearly every
  search an agent makes. The native deny list is `Read(...)`-scoped and does not
  close that path either, so a content-mode search can surface lines from a
  secret file it walked into. Behavior is unchanged; the pathless case now has a
  regression test alongside the directory case, so both edges are pinned as
  deliberate rather than one being accidental.
- **`eval.sh`'s header no longer implies default Claude trials are contained.**
  Containment is asymmetric: Codex default trials get an OS-enforced
  `--sandbox workspace-write` boundary, Claude trials get no equivalent, and
  `cd`-ing into the workspace is a cwd, not a boundary. The header now states
  this and records what the `provider-config-write` branch actually changes for
  Claude — `HARNESS_ALLOW_MECHANISM_EDITS=1` disarming the `guard-config.sh`
  PreToolUse hook, which runs regardless of permission mode — so the acknowledgement
  is not mistaken for a sandbox. Run Claude evals in a container or VM when host
  containment matters (see the v0.18.0 fixture-leak precedent).
- Eval-authoring docs (`docs/evals/README.md`) state the missing-verifier
  contract alongside the existing three-way `check.sh` exit-code convention.
- This repo's own `guard-project-policy.sh` pointed at `docs/skills/release/SKILL.md`,
  a path retired by the standard-consumer-layout restructure; corrected to
  `.agents/skills/release/SKILL.md`. Repo-local policy only — not shipped.

## 0.29.0 — 2026-07-24

Trims the adopter `verify` floor further by making the install-mechanics smoke
test maintainer-only again.

### Changed

- **`test-harness-smoke.sh` descoped from the shipped floor to a maintainer-only
  gate** (moved to `scripts/test-install-smoke.sh`, run here as
  `install-suite-smoke`, installing from the template ship artifact). On every
  adopter `verify` it re-installed the mechanism into a throwaway fixture and ran
  that fixture's checker (~30s — the shipped floor's pole), which is redundant
  with the manifest-integrity check (`check-drift`), the mechanism guard, and the
  shipped hook behavioral tests. Adopters' post-install proof is now those three.
  **Net adopter harness floor: ~35–50s → ~10–15s** (the new pole is the ~6s guard
  tests). **Migration:** the shipped-floor path is `retired` (update mode removes
  a pristine copy); the `kit-manifest` + `gates.conf` change is delivered as an
  update diff, so new installs get it by default and existing installs approve the
  diff. This reverses the v0.22.0 promotion of the smoke test into the shipped
  floor — adopters trade an end-to-end install check for the lighter floor.

## 0.28.0 — 2026-07-24

A `verify`-runtime optimization grounded in a two-model review (a gpt-5.6-sol
second opinion plus adversarial Codex passes over the diff, every claim
reproduced before acting). The `evals` gate — the dominant cost, and one that
grew ~8× with every test added to the floor — is cut by ~80% by removing
redundant re-execution of the test floor, and the update-mechanics suite is
split for parallelism. No coverage is dropped: the floor still runs once per
context, and two adversarial-review passes confirmed the skip preserves it.

### Changed

- **`check-tests.sh` gains an opt-in `HARNESS_SKIP_TESTS_FAMILY` skip.** When
  set to exactly `1`, check #6 (running every `scripts/harness/tests/test-*.sh`)
  is skipped while the cheap static checks #5 (exec-bit) and #5b (mktemp-hygiene)
  still run. The offline eval grader-validity loop (`test-eval.sh`) and the
  shipped harness gate set it, because the `parallel-each` gate already runs the
  floor once — eliminating the ~8 redundant nested re-runs of the whole floor per
  eval pass. Default unset = unchanged behavior, so a bare `check-harness` audit
  still runs everything. **Migration:** `check-tests.sh` is a mechanism file — a
  pristine copy is auto-replaced by update mode; the `gates.conf` harness-gate
  change is repo-owned policy, delivered as an update diff (new installs get the
  corrected default).
- **`evals` gate ~340–620s → ~58s** (measured on a committed tree) and it no
  longer grows with floor size. The skip takes effect only on committed code
  (eval workspaces `git clone` HEAD).
- **`test-install-update.sh` split into `test-install-update.sh` +
  `test-install-migrate.sh`**, run as two concurrent gates (the v0.20.0
  pattern): a ~105s serial suite becomes two ~50s halves.

### Added

- **`test-skip-tests-family.sh`** — a shipped regression test proving the skip
  flag skips check #6 while #5b still fires, and that it honors exactly `1`
  (isolated from an inherited value via `env -u`). Registered in `kit-manifest`
  so adopters receive it.

## 0.27.0 — 2026-07-23

A second principal-level architecture review (with three adversarial Codex
passes over the diff) hardens the pre-1.0 layout: a symlink-follow in the
installer's staging path is closed, the capability table and ship contract gain
schema validation, documentation assurance finally covers every canonical
knowledge zone, and a restructure-migration miss that had silently disabled the
advisory stop-hook is fixed. The four skill playbooks are reconciled with
ADR 011, and a scatter of post-restructure ownership/naming drift is swept.

### Security

- **Installer staging no longer follows a symlink.** `_harness_copy_shipped`
  staged shipped bytes to a predictable `.hk-stage.$$.<name>` path and `cp`'d
  through any symlink pre-planted there — an arbitrary external write that still
  returned success. Staging now uses `mktemp` (O_EXCL), asserts the stage file
  resolves inside the repo and is a regular file both before and after the copy,
  and aborts on a mid-copy swap. The comment states the honest boundary:
  concurrent write access to the destination directory during an install is out
  of the threat model (it already defeats the guard), so these checks are
  best-effort narrowing, not a complete race defense. `test-install-core.sh`
  gains a stage-symlink regression.

### Added

- **Capability-table schema validation (check #8g).** `check-instructions`
  validates `provider-caps` structurally: exactly five fields per row, a safe
  dotted provider dir, closed enums, and `none`-or-`<safe-relative-path>:<tag>`
  config cells. Provider names are matched case-insensitively against a reserved
  set (`.agents`, `.harness`, `.git`, `.github`) because `sync` writes generated
  stubs into `$ROOT/<provider>/` and any of those would overwrite a canonical or
  system tree. A malformed table would otherwise derive the wrong wiring
  silently. `test-check-harness.sh` gains nine cases.
- **Ship-contract layer validation (check #9e).** `check-drift` rejects a
  kit-manifest entry whose layer keyword is not one of
  `mechanism|policy|optional-policy|content|retired` — a typo silently unships
  the file (drops from completeness #9c and from what update copies) and, once
  re-pinned, passes the integrity checksum, so this is the CI-time guard.
- **`mktemp` is a named, hard-gated prerequisite.** The installer stages every
  copied file with `mktemp`, so `harness_missing_prereqs` reports it and
  `bootstrap` hard-refuses without it (like the sha256 tool; `--allow-degraded`
  does not cover it). Preflight names it up front instead of failing at the
  first copy.
- **Doc-link checking covers every canonical zone.** `check-docs` now scans the
  root entry pages (README, SECURITY, CONTRIBUTING, GEMINI, llms.txt),
  `.agents/skills/`, and `.harness/evals/` in addition to the AGENTS.md /
  ARCHITECTURE / `.harness/policies|agents` / `docs/` set. Plugin `templates/`
  and `references/` stay excluded (their links resolve post-install). This
  closes the gap that let launch-facing broken links pass verify.

### Fixed

- **The advisory stop-hook was a silent no-op.** Since the v0.23.0 move to
  `.harness/hooks/`, this repo's installed `guard-project-policy.sh` sourced a
  nonexistent `.harness/hooks/lib.sh` (the template had the correct
  `../../scripts/harness/hooks/lib.sh`), so it failed open and never ran. Fixed,
  and `test-guard-project-policy.sh` now pins the sourcing with a spy `lib.sh`
  so the regression cannot recur.
- **Broken launch-facing doc links.** `SECURITY.md` →
  `.harness/policies/changes.md` (was the removed
  `docs/conventions/risky-actions.md`); `llms.txt` → root `ARCHITECTURE.md`;
  the `release` skill and `evals/parity/skill-split.md` relative-path depths
  corrected. All are now caught by the expanded `check-docs`.
- **Telemetry privacy guidance said keep all of `.harness/` git-ignored.**
  Post-ADR-010 only `.harness/var/` is ignored; following the old text would
  leave committed policy, personas, schemas, and evals uncommitted. Corrected in
  `outcome-telemetry.md` and its template.

### Changed

- **Skill playbooks reconciled with ADR 011.** `init` no longer offers `.agents`
  as a fifth provider; `audit` no longer flags a correct v0.25+ install for
  leaving the derived `HOOK_WIRED_PROVIDERS`/`AGENT_PROVIDERS` unset; `add-hook`
  documents `.harness/hooks/` as the repo-owned custom-hook home (not the
  kit-owned mechanism tree) with the correct `lib.sh` sourcing path.
- **Ownership and naming sweep.** Retired command names (`verify.sh`,
  `check-harness.sh`, `sync-agent-skills.sh`) corrected to their extensionless
  forms across living docs (the stable `"hook": "verify.sh"` telemetry value and
  historical ADR/plan mentions are preserved); `README`, `ARCHITECTURE`, the
  plugin `SKILL.md`, and `AGENTS.md.tmpl` corrected to the three-canonical-home
  ownership model (skills in `.agents/skills/`, policy/personas in `.harness/`,
  not `docs/`); the `ARCHITECTURE.md` marketplace source path fixed.
- **Plan lifecycle models umbrella & superseded plans.** `PLANS.md` now states
  that a completed cross-release umbrella or a superseded plan stays at the
  `docs/plans/` root with its Status header authoritative, so a COMPLETE file
  there is expected rather than a contradiction.

## 0.26.0 — 2026-07-23

Pre-1.0 hardening from a principal-level architecture review (with a Codex
`gpt-5.6-sol` second opinion, plus a second Codex pass over the diff): the
ship contract is validated before it is trusted, updates are torn-file-proof,
degraded installs need explicit acknowledgement, verify's parallelism is
bounded, and two v0.23.0-era dead-coverage rots (the agent-stub block, the
fixture-isolation canary) are revived.

### Added

- **Ship-contract validation before any mutation.**
  `harness_validate_ship_contract` runs first in install, update, and
  base-persist: unknown layers (a typo silently unshipped a file), absolute
  or `..` paths (they reach `cp`/`rm` verbatim), duplicate destinations,
  shipped+retired conflicts, and missing declared sources are all rejected
  with line-numbered errors before a single file is touched. A missing
  declared source previously produced a silent PARTIAL install that still
  returned success. `test-install-core.sh` gains six adversarial cases.
- **`bootstrap update --dry-run`.** Prints the replace/add/keep/diff/remove/
  retire-keep/migrate plan from the SAME code path apply uses (the flag only
  suppresses mutations, so plan and apply cannot diverge), mutating nothing
  and requiring no jq/git acknowledgement. A sha256 tool is still hard-required
  (second Codex pass): the plan's decisions are hash comparisons, and without
  one every pristine file would preview as phantom drift at exit 0.
- **Explicit degraded-install acknowledgement.** `bootstrap install|update`
  now refuse when prerequisites are missing: a missing sha256 tool is a hard
  refusal (integrity pins would be stillborn — also enforced on `repin`);
  missing jq/git require `--allow-degraded`, with the inert-guard-layer
  consequence spelled out. Runtime hooks keep failing open — this gates only
  the install decision, mechanizing the acknowledgement the SKILL flow
  already asked for in prose.
- **Bounded verify concurrency.** `verify --jobs N` / `HARNESS_JOBS=N`
  (default: core count, fallback 8) caps concurrent parallel gates,
  Bash-3.2-safe (no `wait -n`: at capacity, spawning reaps the oldest
  running job and records its status for the declaration-order barrier).
  Invalid counts are usage errors — including zero-equivalent digit strings
  (`00`) and values past intmax, which a digit-only pattern admits but which
  degenerate the throttle loop (second Codex pass). `test-verify.sh` gains
  ten cases.

### Fixed

- **Mechanism replacement is now atomic (staged beside the destination).**
  `cp` onto a live file could tear it (the torn copy reads as local drift
  forever after — and replacing the running `bootstrap` mid-update corrupted
  its own execution, observed live during this change's rollout). Copies now
  stage as a sibling temp file and `mv` into place; symlinked destinations
  and parents that physically resolve outside the repo root are refused —
  and refused BEFORE `mkdir -p` runs (second Codex pass): the deepest
  existing ancestor's physical path is checked first, so a symlinked parent
  cannot gain externally-created directories on the way to the refusal.
- **A `parallel-each` glob matching no files now FAILS verify** instead of
  silently declaring zero gates — a typo'd glob faked a green "definition of
  done".
- **Retirement checks `rm` results.** A failed removal now reports an ERROR
  and returns non-zero instead of printing `remove` for a file still on disk.
- **`sync secrets` stages its rewrite beside the destination** instead of
  `${TMPDIR}` — a cross-filesystem `mv` is copy-then-unlink, not atomic.
- **Stale docs:** CONTRIBUTING.md still pointed at retired pre-v0.23.0
  commands and paths (`scripts/verify.sh`, `sync-agent-skills.sh`,
  `docs/conventions/`, the old manifest home, and an inverted
  canonical-vs-generated skills description); README's platform claims now
  separate CI-tested (macOS, Linux) from best-effort (WSL, Git Bash).
- **Revived the dead agent-stub conformance block.** The
  `test-check-harness.sh` agent-stub section was gated on the retired
  pre-v0.23.0 `scripts/sync-agent-skills.sh` path, so all ten of its cases
  silently skipped for two releases (dead coverage the v0.23.0 re-home left
  behind). The gate and fixture now use `scripts/harness/sync` +
  `lib/sync-lib.sh`; every case runs and passes unchanged.
- **Generated Codex agent stubs named the retired generator.** The TOML stub
  header said "generated by sync-agent-skills.sh"; it now names the current
  command (`bash scripts/harness/sync`) with an explicit do-not-edit marker,
  and the committed stub is regenerated.
- **Rebuilt the fixture-isolation canary around the current layout.** The
  same v0.23.0 re-home also hollowed `test-fixture-isolation.sh`: its canary
  still copied the flat `scripts/*.sh` + `scripts/hooks/` mechanism, so
  after the move it held almost nothing and every REPO-RELATIVE leak (an
  empty fixture path landing `bash scripts/harness/sync` in the host repo)
  died "No such file" unobserved — the suite stayed green while testing an
  empty canary. The canary now carries `scripts/harness/` (asserted after
  the copy, so the next layout move fails loudly instead of hollowing it
  again), the suite glob covers the shipped tests' new home
  (`scripts/harness/tests/`, silently dropped since the move: 8 → 23 suites
  in mode "all"), and the leak class was re-proven live — a planted
  unguarded `mktemp` produced both a leaked commit and leaked
  `.harness/adapters/` writes, caught by the suite; the same repo-relative
  leak against the old canary shape exits 127 with clean porcelain.

## 0.25.1 — 2026-07-23

A post-launch adversarial review (Codex) of the standard-consumer-layout
restructure surfaced three defects on adopter-facing paths — the ones the
deterministic gates structurally can't see. All three are fixed; none change
the shipped mechanism's happy-path behavior.

### Fixed

- **Update preflight sourced a moved library.** `references/modes/update.md`
  told the agent to source `<new_src_scripts>/install-lib.sh`, but Phase 3
  (v0.23.0) moved that library to `<new_src_scripts>/harness/lib/install-lib.sh`.
  Corrected (`init.md` was already right).
- **Eval docs pointed at a directory the runner ignores.** The shipped eval
  guide (`templates/docs/evals/README.md`, `references/modes/init.md`, and the
  dogfood `.harness/evals/README.md`) still said `tasks/_template`, but Phase 4
  (v0.24.0) renamed the bank to `scenarios/` and the runner defaults to
  `.harness/evals/scenarios` — so an adopter following the docs would author
  evals that `run-evals` never discovers (a silently empty measurement bank).
  Docs corrected; `check-packaging.sh` now asserts the shipped eval docs name
  the same directory as `EVAL_TASKS_DIR_DEFAULT`.
- **A failed copy could be reported as a successful upgrade.**
  `harness_update_apply` (and `harness_install_mechanism`) did not check `cp`
  results and returned 0 unconditionally, with the one destructive pass
  (retirement) running *between* the replace and add passes — so a
  disk-full/permission copy failure could leave a partial migration that the
  caller then re-pinned as green. Copies now go through a shared checked
  `_harness_copy_shipped` helper (a failure returns non-zero), the add pass
  uses process substitution so the failure escapes its loop subshell, and
  retirement is deferred to LAST so the destructive step never runs on a failed
  upgrade. `test-install-update.sh` gains a deterministic failure-path case.

## 0.25.0 — 2026-07-23

Phase 5 of the standard-consumer-layout restructure
(`docs/plans/standard-consumer-layout.md`): the four hand-curated provider
lists collapse to one declaration, and `sync` grows two generated artifacts
(ADR 011).

### Changed

- **Single provider declaration.** An adopter declares one `HARNESS_PROVIDERS`
  in `harness.conf`; the kit-owned capability table
  (`scripts/harness/lib/provider-caps`, plain text, no jq) + a derivation lib
  (`provider-lib.sh`) derive the three wiring facets — skill stubs, agent
  stubs, hook wiring — with override-or-derive resolution (an explicit
  per-facet value still wins). The legacy `PROVIDERS`/`HOOK_WIRED_PROVIDERS`/
  `AGENT_PROVIDERS` lists demote to optional overrides and keep validating,
  so a v0.24.0 `harness.conf` is carried forward unchanged.
- **Execution profiles stay explicit opt-in.** `EXECUTION_PROFILE_PROVIDERS`
  is deliberately *not* derived (a strict runtime floor must never be imposed
  as a side effect of naming a provider); it is now validated to be a subset
  of the wired providers, and its config path/validator move to the table.
- **`check-instructions` #8f** validates the declaration itself (every entry a
  known provider, no duplicates); a bad entry that would silently drop from
  every derived set is a loud error.

### Added

- **Generated adapters.** `sync` (write) emits one committed
  `.harness/adapters/<slug>.md` wiring summary per wired provider; `sync
  --check` keeps them current. Adapters are an opt-in generated artifact —
  `--check` enforces completeness only once any exist.
- **`sync secrets [--check]`** (jq hard-required) regenerates the native
  secret-deny mirrors from `SECRET_PATTERNS`: `.claude/settings.json` gets a
  deny-only list (`Read(./P)` + `Read(**/P)`; platform deny-beats-allow),
  `opencode.json` gets `**/P: "deny"` and keeps its hand-owned allows.
  Reconciliation is ensure-present + preserve; checks #8/#8b remain the
  independent verification and point at it. Shipped `test-sync-secrets.sh`
  covers it.

### Migration

A v0.24.0 install updates cleanly: the two new mechanism files install, the
legacy four-list `harness.conf` is preserved and validates as overrides.
Consolidating to `HARNESS_PROVIDERS` is proposed by update mode but optional.

## 0.24.0 — 2026-07-22

Phase 4 of the standard-consumer-layout restructure
(`docs/plans/standard-consumer-layout.md`): the content/IA migration.
Every knowledge zone of ADR 010's standard layout now has its final
contents.

### Changed

- **Committed `.harness/` content layer:** canonical personas move to
  `.harness/agents/` (`CANONICAL_AGENTS` default re-pointed, stubs
  regenerated); the untrusted-content and risky-actions conventions become
  `.harness/policies/{security,changes}.md`; doc skeletons land in
  `.harness/templates/` (execution-plan — formerly `docs/plans/_template.md`
  — plus new ADR and PR templates); new `.harness/schemas/` carries JSON
  Schemas for the telemetry v2 event, the audit report, and eval TASK
  metadata, transcribed from the existing prose/enum contracts. All copies
  are kit-manifest `content` entries with `dest=` mappings.
- **Eval bank moves to `.harness/evals/`:** `docs/evals/tasks` →
  `scenarios/`, plus `rubrics/`, `parity/`, `baselines.json`, `README.md`;
  eval-lib defaults, audit-log integration, the eval-cron CI template, and
  the gate declarations follow.
- **Canonical skills move to `.agents/skills/`** (ADR 003 amended): the
  cross-vendor standard location IS the source now — Codex reads it
  natively, `.agents` leaves the stub `PROVIDERS` set, and stubs continue
  for `.claude`/`.cursor`/`.opencode` with re-pointed Canonical-source
  lines.
- **docs IA:** conventions split into `docs/standards/` (templates,
  execution-profiles, outcome-telemetry) and `docs/runbooks/`
  (local-development, formerly dev-runtime); `ARCHITECTURE.md` moves to the
  repo root; `docs/plans/README.md` becomes `PLANS.md` joined by
  `tech-debt.md`; `product/`, `generated/`, `references/` gain index
  skeletons.
- **New instruction pointer templates:** `GEMINI.md.tmpl` and
  `github-copilot-instructions.md.tmpl` (content entries) give Gemini and
  the Copilot completions surface the same thin `AGENTS.md` pointer
  CLAUDE.md carries.
- **check-docs widens its link scan** to root `ARCHITECTURE.md` and the
  committed `.harness/{policies,agents}` docs (which immediately caught six
  dangling links), and gains a shallow JSON-validity arm for
  `.harness/schemas/`.
- **Mechanism fix:** `harness_install_mechanism` falls back to the
  installed repo-relative location for `src=` policy entries, so an
  installed tree is a valid install source again (the shipped smoke test
  installs from the repo's own `scripts/` — without this, every adopter's
  smoke run would miss `gates.conf` and the policy hook).

### Migration (pre-v0.24.0 installs)

Content moves are authored, not mechanical: relocate the files per the map
above (git mv), re-point `CANONICAL_SKILLS`/`CANONICAL_AGENTS`/`PROVIDERS`
in `harness.conf`, re-run `bash scripts/harness/sync`, and re-pin. The
update mode's diff flow proposes each step; nothing is auto-overwritten.

## 0.23.0 — 2026-07-22

Phase 3 of the standard-consumer-layout restructure
(`docs/plans/standard-consumer-layout.md`): the mechanism re-home. The flat
`scripts/` install becomes the standard consumer layout (ADR 010) —
`scripts/harness/` kit tree + committed `.harness/` repo policy. Old paths
are `retired` kit-manifest entries; ADR 009's retirement contract is the
migration.

### Changed

- **`scripts/harness/` command surface:** extensionless verb commands —
  `bootstrap`, `verify`, `sync`, `check-harness`, `check-instructions`,
  `check-docs`, `detect-drift`, `validate-plan`, `run-evals` — over
  `lib/*.sh`, `hooks/*.sh`, and `tests/*.sh`. The checker monolith is
  decomposed into per-family `lib/check-*.sh` scripts; the `check-harness`
  orchestrator sums their `ERROR:` lines and owns the combined summary.
- **Verify split (mechanism/policy completion):** the runner
  (`scripts/harness/verify`) is kit-owned mechanism, auto-replaced on
  update; the repo's gate list is declarative data in **`.harness/gates.conf`**
  (`gate`/`full`/`parallel`/`parallel-each` lines, commands via `bash -c`).
  A pre-v0.23.0 tailored `verify.sh` gate block migrates to gates.conf as
  an approved diff. The runner gains a documented `HARNESS_VERIFY_PRELUDE`
  test seam.
- **Hooks split by ownership:** mechanism guards live in
  `scripts/harness/hooks/`; `format.sh` is mechanism now (its formatter/lint
  maps moved to `harness.conf` `FORMAT_RULES`/`LINT_RULES` data);
  the repo-owned `guard-project-policy.sh` moves to **`.harness/hooks/`**.
  Provider hook configs, check #8d tuple tables, and the resolvability scan
  follow the new paths.
- **`.harness/` is committed policy; runtime state moves to `.harness/var/`**
  (`log.jsonl`, `base/`, `eval-results/`, `dev/`, `stop-markers/`). Init
  and update narrow a pre-v0.23.0 `.harness/` gitignore line to
  `.harness/var/` (`harness_append_gitignore`).
- **guard-config protected set collapses** to `scripts/harness/*` + the
  repo-owned enforcement-layer policy files (`.harness/gates.conf`,
  `.harness/hooks/*.sh`) + provider/CI configs; repo additions stay in
  `GUARD_PROTECTED_EXTRA`.
- **Checks rescoped:** #5b/#6 scan and run exactly the shipped floor at
  `scripts/harness/tests/test-*.sh` (the dead nested skip-list is gone —
  the smoke suite self-guards); #9c derives its expected set from the whole
  `scripts/harness` tree plus the `.harness/` policy paths.

### Migration (pre-v0.23.0 installs)

`harness_update_apply` migrates the integrity manifest to
`scripts/harness/.harness-manifest` (`migrate` report line), removes every
pristine old flat path, and installs the new tree; drifted or tailored old
copies are kept (`retire-keep`) for manual review. Then narrow the
gitignore, move runtime state under `.harness/var/`, and port tailored
policy content (gate block → gates.conf; `scripts/harness.conf` →
`scripts/harness/harness.conf`; the project hook → `.harness/hooks/`).
Pinned end-to-end by `test-install-update.sh` case (l).

## 0.22.0 — 2026-07-22

Phase 2 of the standard-consumer-layout restructure
(`docs/plans/standard-consumer-layout.md`); executes the descope queued in
`docs/plans/adopter-test-descope.md`, unblocked by v0.21.0's retirement
mechanism.

### Changed

- **Adopter test descope:** the kit's own conformance suites no longer ship —
  `test-install-core.sh`, `test-install-update.sh`,
  `test-install-recovery.sh`, `install-test-lib.sh`, `test-check-harness.sh`,
  `test-eval.sh`, and `test-fixture-isolation.sh` are `retired` in the
  kit-manifest and live on only as this repo's root-only ` # tailored`
  maintainer gates (with explicit `verify.sh` gates, since the nested harness
  gate skips exactly these). Adopter audits (check #6) now run their own
  installed policy: hook behavioral tests, the runtime suites
  (`test-verify.sh`, `test-log.sh`, `test-audit-log.sh`,
  `test-dev-instance.sh`, `test-doc-garden.sh`), and the new smoke test.
- **check #9d refinement:** a retired path pinned ` # tailored` is the
  *resolved* state (a deliberate repo-owned fork) and no longer WARNs;
  drifted or unpinned retired copies keep warning until reviewed.
- The `.tmpl` and CI-workflow rename map is now declared data — kit-manifest
  `content` entries with `dest=` — instead of prose restated across the init
  playbook.

### Added

- **`scripts/test-harness-smoke.sh`** — the one install-mechanics check that
  ships: self-contained (sources only `install-lib.sh`), nested-run-guarded,
  installs the repo's own mechanism into a throwaway fixture and asserts the
  fixture's `check-harness.sh` exits green. New maintainer fixture: a
  v0.21.0-layout install updating across the descope gets all seven pristine
  suites removed with no stale pins.

### Migration

- Update mode replaces the manifest-matching `kit-manifest` and
  `check-harness.sh`, adds `test-harness-smoke.sh`, and **removes** the seven
  descoped suites when pristine (`remove <path>` in the update plan); drifted
  or tailored copies are kept and reported `retire-keep`, and #9d keeps
  warning until you fold changes forward or re-pin the file ` # tailored` to
  keep it deliberately. No policy files change.

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
