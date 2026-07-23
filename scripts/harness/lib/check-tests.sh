#!/usr/bin/env bash
# check-tests.sh — the "tests" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/check-harness. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

# 5. Harness scripts must be executable (a chmod lost in a copy or checkout
#    silently disables a hook — most harnesses skip non-executables).
for hook in "$ROOT"/scripts/*.sh "$ROOT"/scripts/harness/hooks/*.sh; do
    [ -f "$hook" ] || continue
    if [ ! -x "$hook" ]; then
        echo "ERROR: ${hook#"$ROOT"/} is not executable — run 'chmod +x' and commit"
        ERRORS=$((ERRORS + 1))
    fi
done

# 5b. Scratch paths in the test scripts check #6 is about to RUN must be created
#     safely: an explicit "...XXXXXX" template AND a failure guard. Both halves
#     are load-bearing and fail differently. Without a template, `mktemp -d` on
#     macOS resolves _CS_DARWIN_USER_TEMP_DIR (/var/folders/...) and ignores
#     $TMPDIR, so it simply FAILS wherever only $TMPDIR is writable (sandboxes,
#     hardened CI). Without a guard that failure is SILENT: these scripts run
#     `set -uo pipefail` (no -e), so the empty result flows on, `cd ""` is a
#     no-op that leaves cwd at the REAL repo, and `git -C "" commit` then
#     commits the fixture's junk onto the current branch — the empirical hole
#     this closes, twice landed on this repo's main. The template alone only
#     makes failure rarer; the guard alone turns every sandboxed run into a hard
#     stop. Both, or it is an ERROR. The canonical form is
#     `VAR=$(mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX") || exit 1`; templating
#     into another directory on purpose (eval-harness.sh writes its baseline temp
#     beside the target so the `mv` is a same-filesystem rename) is equally fine —
#     what is pinned is an explicit XXXXXX template, not a literal $TMPDIR.
#
#     This check runs BEFORE #6 because #6 executes exactly this file set: a
#     static safety gate on those scripts must come before the gate that launches
#     them, or the defect runs before anything can see it.
#
#     SCOPE is deliberately exactly the set #6 executes — the shipped floor at
#     scripts/harness/tests/test-*.sh — not all of scripts/. The kit ships into
#     other people's repos: their scripts/deploy.sh is theirs to write, and a
#     build gate that fails their build over a scratch file it never runs is
#     overreach. What check-harness RUNS, check-harness may demand hygiene
#     from; that is the whole claim, and it is also the blast radius (these are
#     the scripts that `git init` throwaway repos and `rm -rf` scratch trees).
#     The kit repo's maintainer-only conformance suites (root scripts/test-*.sh,
#     tailored) are covered by its own gates and fixture-isolation suite.
#
#     Boundary, as honest as #8's "detects drift, does not prove equivalence":
#     this is a line-based hygiene gate, not an adversarial control. It reads
#     command-position `mktemp` only — a `for u in ... mktemp rm ...` list, a
#     "mktemp failed" message, and comments are all skipped — and joins backslash
#     continuations so a guard on the next line counts, but it does not parse
#     heredocs, and `|| true` defeats it. A verified exception is DECLARED with a
#     trailing '# harness-mktemp-ok' (same stance as the manifest's '# tailored'
#     in #9): one comment, so ERROR severity never leaves an adopter wedged.
#
#     This comment stays OUTSIDE the process substitution below on purpose:
#     bash 3.2 finds the closing paren of <(...) with a naive scan, and a
#     stray quote in a shell comment there (an apostrophe suffices) swallows
#     it, silently skipping the whole check.
while IFS= read -r mktemp_finding; do
    [ -n "$mktemp_finding" ] || continue
    echo "$mktemp_finding"
    ERRORS=$((ERRORS + 1))
done < <(
    for tscript in "$ROOT"/scripts/harness/tests/test-*.sh; do
        [ -f "$tscript" ] || continue
        awk -v rel="${tscript#"$ROOT"/}" '
            function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
            # Strip an unquoted trailing #-comment. Quoted text is KEPT — the
            # mktemp template lives inside quotes. "#" only opens a comment at the
            # start of a word, so ${var#foo} survives.
            function uncomment(s,   i, c, q, esc, out) {
                q=""; esc=0; out=""
                for (i = 1; i <= length(s); i++) {
                    c = substr(s, i, 1)
                    if (esc) { out = out c; esc = 0; continue }
                    if (q == "\"" && c == "\\") { out = out c; esc = 1; continue }
                    if (q == "") {
                        if (c == "#" && (i == 1 || substr(s, i-1, 1) ~ /[[:space:]]/)) break
                        if (c == "\"" || c == "\047") q = c
                    } else if (c == q) q = ""
                    out = out c
                }
                return out
            }
            # Command position: mktemp is being RUN, not merely named. True at the
            # start of a statement, or right after $( ` ( { ; | & ! or then/do/else.
            # This is what keeps `die "mktemp failed"` and the utility-shim list
            # in test-verify.sh out of the scan.
            function cmdpos(s, p,   before, ch) {
                before = substr(s, 1, p - 1); sub(/[[:space:]]+$/, "", before)
                if (before == "") return 1
                ch = substr(before, length(before), 1)
                if (ch ~ /[({;&|!`]/) return 1
                if (before ~ /(^|[[:space:];&|(])(then|do|else)$/) return 1
                return 0
            }
            {
                line = $0
                # Report the line the statement STARTS on. getline advances FNR,
                # so after joining a backslash continuation FNR names the last
                # line of the run — pointing the reader past the mktemp they have
                # to fix.
                start = FNR
                while (line ~ /\\$/ && (getline nxt) > 0) { sub(/\\$/, " ", line); line = line nxt }
                if (line ~ /harness-mktemp-ok/) next
                code = uncomment(line); rest = code; off = 0
                while ((p = index(rest, "mktemp")) > 0) {
                    abs = off + p
                    if (cmdpos(code, abs) && substr(code, abs + 6, 1) !~ /[A-Za-z0-9_]/) {
                        tail = substr(code, abs)
                        templated = (index(tail, "XXXXXX") > 0)
                        guarded = (index(tail, "||") > 0) || (trim(code) ~ /^(if|elif|while|until)[[:space:](!]/)
                        if (!templated || !guarded) {
                            if (!templated && !guarded)
                                why = "no XXXXXX template and no failure guard"
                            else if (!templated)
                                why = "no explicit XXXXXX template — bare mktemp resolves /var/folders on macOS and ignores $TMPDIR, so it fails wherever only $TMPDIR is writable"
                            else
                                why = "no failure guard — an unchecked empty result leaves cwd at the real repo, and `git -C \"\"` then operates on THIS branch"
                            printf "ERROR: %s:%d creates a scratch path unsafely (%s). Use the canonical form: VAR=$(mktemp -d \"${TMPDIR:-/tmp}/<name>.XXXXXX\") || exit 1 — templating into another directory on purpose is fine, an unguarded or untemplated one is not. A verified exception is declared with a trailing '"'"'# harness-mktemp-ok'"'"'. Offending line: %s\n", rel, start, why, trim(code)
                        }
                    }
                    off = abs + 5; rest = substr(code, off + 1)
                }
            }
        ' "$tscript"
    done
)

# 6. Regression tests must pass — the shipped floor at
#    scripts/harness/tests/test-*.sh (hook guards, verify orchestration, the
#    install smoke). The maintainer-only conformance suites live at the KIT
#    repo's root as tailored files and run from its own gate list, not here —
#    an adopter's audit runs only what the kit ships (v0.22.0 descope).
#    Recursion control lives in the one test that needs it:
#    test-harness-smoke.sh installs a throwaway fixture and runs ITS checker,
#    so it exports HARNESS_NESTED_FIXTURE and skips itself inside nested runs.
#    No skip list here, and no env var switches off the guard behavioral
#    tests (test-guard-*.sh, the catch for a re-pinned guard weakening).
for test in "$ROOT"/scripts/harness/tests/test-*.sh; do
    [ -f "$test" ] || continue
    # Capture output instead of discarding it: when the failure happens inside
    # a throwaway fixture (a nested checker run), "run it directly" is advice
    # nobody can follow — the fixture is gone by the time the message is read.
    test_out=$(bash "$test" 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR: ${test#"$ROOT"/} failed — last lines of its output:"
        printf '%s\n' "$test_out" | tail -15 | sed 's/^/        /'
        ERRORS=$((ERRORS + 1))
    fi
done


check_trailer "tests"
