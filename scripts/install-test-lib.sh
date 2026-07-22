#!/usr/bin/env bash
# install-test-lib.sh — shared preamble for the test-install-*.sh suites
# (test-install-core.sh, test-install-update.sh, test-install-recovery.sh):
# the nested-run guard, install-lib.sh sourcing, a guarded scratch base, the
# pass/fail/git/sha helpers, the fixture builders, and the pass/fail trailer.
# Each suite exercises a different slice of scripts/install-lib.sh against
# throwaway fixtures — no model in the loop — so this file holds only what
# every slice needs in common.
#
# SOURCED, never run standalone — deliberately NOT named test-*.sh so
# check-harness.sh's check #5b (static mktemp-hygiene scan) and check #6
# (regression-test runner) and test-fixture-isolation.sh's sibling glob all
# skip it by name; it has no case count of its own to report. Maintainer-only
# since v0.22.0 (retired from the ship contract with the suites that source
# it): this root copy is a deliberate ' # tailored' fork, pinned like the
# other root-only gates.
#
# Direct execution (`bash scripts/install-test-lib.sh`) is a harmless no-op:
# there is no caller-set SCRIPTS_DIR to source install-lib.sh from, so rather
# than fail confusingly this just exits 0 without doing anything.
if [ "${BASH_SOURCE:-}" = "$0" ]; then
    exit 0
fi

# Recursion guard. Cases in the calling suite install the full mechanism into
# a fixture and run the fixture's check-harness.sh, whose check #6 runs every
# scripts/test-*.sh — including a nested copy of the CALLING suite, which
# would install-and-check forever. Exporting HARNESS_NESTED_FIXTURE tells that
# nested check #6 to skip ONLY the test-install-*.sh suites (every other
# regression test still runs inside the fixture); seeing it already set on
# entry means we ARE such a nested run. Because this file is SOURCED, `exit`
# here exits the CALLING suite too — that is the point: a nested
# test-install-core.sh (or -update.sh/-recovery.sh) run never reaches its own
# body.
if [ -n "${HARNESS_NESTED_FIXTURE:-}" ]; then
    echo "ok:   $(basename "$0") skipped (HARNESS_NESTED_FIXTURE set — nested run)"
    exit 0
fi
export HARNESS_NESTED_FIXTURE=1

# The caller sets SCRIPTS_DIR (its own directory) before sourcing this file.
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-lib.sh"
KIT_VERSION="0.0.0-fixture"

# One guarded scratch base for every fixture the calling suite builds. The
# guard is load-bearing, not decoration: bare `mktemp -d` ignores $TMPDIR on
# macOS (it resolves _CS_DARWIN_USER_TEMP_DIR, i.e. /var/folders) and fails
# outright in a sandbox. An unguarded failure leaves the path EMPTY, and bash
# `cd ""` is a silent rc=0 no-op — so `( cd "$w" && git commit ... )` runs in
# the HOST repo. That put junk commits on this repo's main branch twice before
# check #6b existed. Fixtures carve subdirectories out of this base, so their
# own mktemp cannot fail loose.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/$(basename "$0" .sh).XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; fails=$((fails + 1)); }

git_c() { git -c user.email=t@example.com -c user.name=t "$@"; }

# sha_of <root> <relpath> — the file's sha256, nothing else.
sha_of() { ( cd "$1" && _harness_sha256 "$2" | awk '{print $1}' ); }

# make_fixture — prints a fresh installed + committed fixture root: a throwaway
# git repo with one source file, the mechanism installed from this script's own
# scripts/ dir, a generated manifest, and .harness/ git-ignored.
make_fixture() {
    local w
    w=$(mktemp -d "$WORK/fixture.XXXXXX") || return 1
    ( cd "${w:?}" && git init -q && mkdir -p src && printf 'echo hi\n' > src/app.sh )
    harness_install_mechanism "$SCRIPTS_DIR" "$w"
    harness_append_gitignore "$w"
    # This is a bare install-MECHANICS fixture: no provider hook configs or agent
    # personas are authored (that is the model-graded half). Declare the validated
    # provider sets EMPTY so check-harness's #8d hook check and agent-stub check
    # validate zero providers instead of failing on absent configs. Set BEFORE the
    # manifest so the harness.conf pin matches. Robust to a source conf that never
    # had the lines (strip-then-append). The non-empty sets get their own cases.
    { grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS|EXECUTION_PROFILE_PROVIDERS)=' "$w/scripts/harness.conf"
      printf 'HOOK_WIRED_PROVIDERS=""\nAGENT_PROVIDERS=""\nEXECUTION_PROFILE_PROVIDERS=""\n'
    } > "$w/scripts/harness.conf.tmp" && mv "$w/scripts/harness.conf.tmp" "$w/scripts/harness.conf"
    harness_generate_manifest "$w" "$KIT_VERSION" > "$w/scripts/.harness-manifest"
    ( cd "${w:?}" && git_c add -A && git_c commit -qm init >/dev/null )
    printf '%s' "$w"
}

# repin <root> [version] — regenerate the manifest (default: KIT_VERSION) after
# a harness.conf edit so check #9's checksum verification keeps passing (only
# harness.conf is manifest-pinned among the files most migration cases mutate;
# provider configs are not).
repin() {
    harness_repin_manifest "$1" "${2:-$KIT_VERSION}" > "$1/scripts/.hm" \
        && mv "$1/scripts/.hm" "$1/scripts/.harness-manifest"
}

# write_mirrored_claude_settings <root> — a .claude/settings.json whose deny list
# mirrors the fixture's SECRET_PATTERNS, so check-harness.sh check #8 runs green.
write_mirrored_claude_settings() {
    local root="$1" pat sp deny=""
    sp=$(. "$root/scripts/harness.conf" && printf '%s' "$SECRET_PATTERNS")
    set -f
    for pat in $sp; do deny="$deny \"Read($pat)\","; done
    set +f
    deny=${deny%,}
    mkdir -p "$root/.claude"
    printf '{ "permissions": { "deny": [%s ] } }\n' "$deny" > "$root/.claude/settings.json"
}

# finish <label> — the standard PASSED/FAILED trailer: prints the case-count
# summary from $fails and exits non-zero on any recorded failure.
finish() {
    if [ "$fails" -gt 0 ]; then
        echo "FAILED: $fails $1 case(s)"
        exit 1
    fi
    echo "PASSED: all $1 cases"
}
