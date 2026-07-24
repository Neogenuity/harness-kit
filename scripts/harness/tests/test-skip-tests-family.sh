#!/usr/bin/env bash
# Regression test for the HARNESS_SKIP_TESTS_FAMILY escape hatch in
# lib/check-tests.sh: check #6 (the loop that runs every shipped
# scripts/harness/tests/test-*.sh) must be skipped when
# HARNESS_SKIP_TESTS_FAMILY is set to the EXACT string "1" — never merely
# truthy — while check #5b (the static mktemp-hygiene scan of that same
# directory) must keep running regardless. The skip only relocates #6's
# coverage to a caller that has already run this byte-identical floor itself
# (see check-tests.sh's own comment on the flag); it must never also silence
# #5b, which has nothing to do with whether the tests actually execute.
#
# Runs the REAL, unmodified check-tests.sh + check-common.sh against an
# isolated fixture tests/ directory seeded with two single-purpose probes:
# one that only #6 can catch (it just fails, no mktemp at all) and one that
# only #5b can catch (an unsafe bare mktemp, but a clean exit so it never
# fails #6 on its own). Runnable standalone and picked up by check-harness's
# own check #6.
set -uo pipefail

# Guarded mktemp: this script lives in the very floor check #5b scans, so its
# own scratch path must be safe (explicit XXXXXX template + failure guard) or
# it would self-fail that check.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-skip-tests-family.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

LIB_SRC="$(cd "$(dirname "$0")/../lib" && pwd)"
mkdir -p "$WORK/scripts/harness/lib" "$WORK/scripts/harness/tests"
cp "$LIB_SRC/check-tests.sh" "$WORK/scripts/harness/lib/check-tests.sh"
cp "$LIB_SRC/check-common.sh" "$WORK/scripts/harness/lib/check-common.sh"

# Probe 1: fails outright, no mktemp anywhere — check #6 catches this only
# when its loop actually runs; #5b has nothing to flag in it.
cat > "$WORK/scripts/harness/tests/test-zz-a-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

# Probe 2: a deliberately unsafe bare mktemp (no XXXXXX template, no failure
# guard) but a clean exit — #5b's static scan must flag this regardless of
# whether #6 ever runs it. #5b is a line-based scanner with no heredoc
# awareness (its own boundary comment says as much), so a literal `mktemp -d`
# typed directly into a heredoc here would be caught in THIS file too — it
# cannot tell "probe file content" from "code this script runs". Assemble the
# line at runtime instead: "mktemp" only appears here as the value of a
# variable assignment (never in command position, so the scanner's own
# command-position rule — the thing that lets it skip a mere mention like a
# `for u in ... mktemp ...` list — correctly leaves this script alone), while
# the file actually written to disk gets a real, bare `mktemp -d` line that
# the fixture's own #5b (scanning that file as a real script) still catches.
mk=mktemp
printf '#!/usr/bin/env bash\n%s -d\nexit 0\n' "$mk" > "$WORK/scripts/harness/tests/test-zz-b-mktemp.sh"

chmod +x "$WORK/scripts/harness/tests/test-zz-a-fail.sh" "$WORK/scripts/harness/tests/test-zz-b-mktemp.sh"

CHECKER="$WORK/scripts/harness/lib/check-tests.sh"

# has <haystack> <needle> — pure-shell substring test, no grep pipeline: a
# grep -q short-circuit downstream of a large captured variable, under an
# inherited ignored SIGPIPE plus pipefail, can misreport a real match as a
# failure (the completeness note in lib/check-drift.sh; see also
# test-verify.sh's own has()).
has() {
    case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

# env -u: isolate the "unset" case from an inherited HARNESS_SKIP_TESTS_FAMILY
# (e.g. a CI that exports it before running the floor) — otherwise this
# invocation would inherit the skip and the assertion below would fail.
out_unset=$(env -u HARNESS_SKIP_TESTS_FAMILY HARNESS_CHECK_CHILD=1 bash "$CHECKER" 2>&1); rc_unset=$?
if [ "$rc_unset" -eq 0 ] || ! has "$out_unset" "test-zz-a-fail.sh failed" \
        || ! has "$out_unset" "test-zz-b-mktemp.sh" || ! has "$out_unset" "creates a scratch path unsafely"; then
    echo "FAIL: test-skip-tests-family — HARNESS_SKIP_TESTS_FAMILY unset must run check #6 (catching the failing probe) and check #5b (flagging the unsafe-mktemp probe); exit=$rc_unset"
    printf '%s\n' "$out_unset" | sed 's/^/        /'
    exit 1
fi

out_skip=$(HARNESS_SKIP_TESTS_FAMILY=1 HARNESS_CHECK_CHILD=1 bash "$CHECKER" 2>&1); rc_skip=$?
if has "$out_skip" "test-zz-a-fail.sh failed" || ! has "$out_skip" "check #6 skipped" \
        || ! has "$out_skip" "test-zz-b-mktemp.sh" || ! has "$out_skip" "creates a scratch path unsafely" \
        || [ "$rc_skip" -eq 0 ]; then
    echo "FAIL: test-skip-tests-family — HARNESS_SKIP_TESTS_FAMILY=1 must skip check #6 (no failing-probe report, but the skip note present) while check #5b still flags the unsafe-mktemp probe; exit=$rc_skip"
    printf '%s\n' "$out_skip" | sed 's/^/        /'
    exit 1
fi

# Exact "1" only: HARNESS_SKIP_TESTS_FAMILY=0 must behave like unset.
out_zero=$(HARNESS_SKIP_TESTS_FAMILY=0 HARNESS_CHECK_CHILD=1 bash "$CHECKER" 2>&1)
if ! has "$out_zero" "test-zz-a-fail.sh failed"; then
    echo "FAIL: test-skip-tests-family — HARNESS_SKIP_TESTS_FAMILY=0 must behave like unset (check #6 still runs), got:"
    printf '%s\n' "$out_zero" | sed 's/^/        /'
    exit 1
fi

echo "ok: test-skip-tests-family — #6 honors HARNESS_SKIP_TESTS_FAMILY=1 while #5b still runs"
exit 0
