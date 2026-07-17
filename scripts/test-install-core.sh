#!/usr/bin/env bash
# Deterministic fixture tests of the kit's install MECHANICS core
# (scripts/install-lib.sh): runtime-prerequisite preflight, clean init driven
# by the shipped mechanism inventory, the non-clobber floor, .gitignore append
# safety/idempotency, and the harness_conf_* declaration helpers. Each case
# spins up a throwaway git repo in a scratch dir, drives the library — no
# model in the loop — and asserts concrete post-state, then tears the fixture
# down. See install-test-lib.sh for the shared preamble (nested-run guard,
# scratch base, make_fixture/repin/pass/fail/finish). Runnable standalone and
# in CI (it is a scripts/test-*.sh, so check-harness.sh check #6 and
# verify.sh's template-tests gate both pick it up by name).
#
# Update mechanics (no-op/upgrade/tailored-preservation/migration) live in
# test-install-update.sh; recovery + dev.sh policy live in
# test-install-recovery.sh. The MODEL-GRADED half of init/update — does the
# authored AGENTS.md read well, is a hand-written settings.json merged
# sensibly — is out of scope here by design; that is a behavioral-evals golden
# task. This suite pins only the deterministic floor.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-test-lib.sh"

# --- runtime-prerequisite preflight detection ---------------------------------
# harness_missing_prereqs is the deterministic core of init/update's early
# preflight: it NAMES any missing hard dependency so the user can acknowledge
# that (notably) a jq-less install ships an inert feedback layer — every guard
# fails open. Detection only; it changes no guard's fail-open posture. Present
# halves are gated on `command -v` (robust to whatever the ambient env
# actually has); absent halves run under an empty PATH and assert the exact
# tokens harness_missing_prereqs emits (install-lib.sh:61-67) — 'jq', 'git',
# 'sha256sum' — which it can do because the function uses only shell builtins
# (`command -v`), so it still runs with nothing else on PATH.
if command -v jq >/dev/null 2>&1; then
    if harness_missing_prereqs | grep -qx 'jq'; then
        fail "preflight: jq reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present jq"
    fi
fi
if command -v git >/dev/null 2>&1; then
    if harness_missing_prereqs | grep -qx 'git'; then
        fail "preflight: git reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present git"
    fi
fi
if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
    if harness_missing_prereqs | grep -qx 'sha256sum'; then
        fail "preflight: sha256sum reported missing though a sha256 tool is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present sha256 tool"
    fi
fi
EMPTYPATH=$(mktemp -d "$WORK/emptypath.XXXXXX") || exit 1
if PATH="$EMPTYPATH" harness_missing_prereqs | grep -qx 'jq'; then
    pass "preflight: harness_missing_prereqs names jq when it is off PATH"
else
    fail "preflight: jq not reported missing when hidden from PATH"
fi
if PATH="$EMPTYPATH" harness_missing_prereqs | grep -qx 'git'; then
    pass "preflight: harness_missing_prereqs names git when it is off PATH"
else
    fail "preflight: git not reported missing when hidden from PATH"
fi
if PATH="$EMPTYPATH" harness_missing_prereqs | grep -qx 'sha256sum'; then
    pass "preflight: harness_missing_prereqs names sha256sum when it is off PATH"
else
    fail "preflight: sha256sum not reported missing when hidden from PATH"
fi
rm -rf "$EMPTYPATH"

# --- (a) clean init -----------------------------------------------------------
# Inventory-driven: every presence/exec-bit/manifest-completeness assertion
# iterates install-lib.sh's own _HARNESS_MECHANISM_TOPLEVEL rather than a
# second hard-coded file list, so a new mechanism file is covered on arrival.
F=$(make_fixture) || exit 1
write_mirrored_claude_settings "$F"
( cd "${F:?}" && git_c add -A && git_c commit -qm claude >/dev/null )
missing=""
unpinned=""
manifest_paths=$(awk '{print $2}' "$F/scripts/.harness-manifest")
for f in $_HARNESS_MECHANISM_TOPLEVEL; do
    [ -f "$F/scripts/$f" ] || missing="$missing $f(absent)"
    # harness.conf is a sourced config (not executable, like every non-.sh
    # file); every other mechanism file is a .sh and must carry the exec bit
    # (check-harness.sh check #5).
    case "$f" in
        harness.conf) ;;
        *) [ -x "$F/scripts/$f" ] || missing="$missing $f(not-exec)" ;;
    esac
    printf '%s\n' "$manifest_paths" | grep -qxF "scripts/$f" \
        || unpinned="$unpinned $f"
done
[ -f "$F/scripts/hooks/lib.sh" ] || missing="$missing hooks/lib.sh(absent)"
if [ -z "$missing" ]; then
    pass "clean init: mechanism installed and executable"
else
    fail "clean init: mechanism incomplete —$missing"
fi
if [ -z "$unpinned" ]; then
    pass "clean init: manifest pins every _HARNESS_MECHANISM_TOPLEVEL entry"
else
    fail "clean init: manifest omits an installed mechanism file —$unpinned"
fi
grep -qxF '.harness/' "$F/.gitignore" \
    && pass "clean init: .harness/ is git-ignored" \
    || fail "clean init: .gitignore missing .harness/"
out=$(bash "$F/scripts/check-harness.sh" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "clean init: check-harness.sh passes in the fixture (deny list mirrors SECRET_PATTERNS)"
else
    fail "clean init: check-harness.sh failed in the fixture" "$out"
fi
rm -rf "$F"

# --- (b) non-clobber floor ----------------------------------------------------
# A partial-harness repo's hand-written files must survive install byte-for-byte.
F=$(mktemp -d "$WORK/partial.XXXXXX") || exit 1
( cd "${F:?}" && git init -q && mkdir -p src && printf 'echo hi\n' > src/app.sh )
mkdir -p "$F/.claude"
printf '{ "hand": "written", "permissions": { "deny": [] } }\n' > "$F/.claude/settings.json"
printf '# My Project\n\nHand-authored AGENTS.md.\n' > "$F/AGENTS.md"
s_before=$(sha_of "$F" ".claude/settings.json")
a_before=$(sha_of "$F" "AGENTS.md")
harness_install_mechanism "$SCRIPTS_DIR" "$F"
harness_append_gitignore "$F"
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/.harness-manifest"
s_after=$(sha_of "$F" ".claude/settings.json")
a_after=$(sha_of "$F" "AGENTS.md")
if [ "$s_before" = "$s_after" ] && [ "$a_before" = "$a_after" ]; then
    pass "non-clobber floor: hand-written settings.json and AGENTS.md untouched by install"
else
    fail "non-clobber floor: install modified a hand-written file"
fi
rm -rf "$F"

# --- (c) gitignore append: no-trailing-newline merge safety --------------------
# A '.gitignore' lacking a trailing newline must not have '.harness/' merge
# onto its last line (e.g. 'node_modules' + '.harness/' -> 'node_modules.harness/').
F=$(mktemp -d "$WORK/gitignore.XXXXXX") || exit 1
printf 'node_modules' > "$F/.gitignore"
harness_append_gitignore "$F"
if grep -qxF 'node_modules' "$F/.gitignore" && grep -qxF '.harness/' "$F/.gitignore"; then
    pass "gitignore append: a no-trailing-newline file gets its own '.harness/' line, not a merge"
else
    fail "gitignore append: '.harness/' merged onto the prior line (or the prior line was lost)" "$(cat "$F/.gitignore")"
fi

# --- (d) gitignore append: idempotent ------------------------------------------
before=$(sha_of "$F" ".gitignore")
harness_append_gitignore "$F"
after=$(sha_of "$F" ".gitignore")
count=$(grep -cxF '.harness/' "$F/.gitignore")
if [ "$before" = "$after" ] && [ "$count" -eq 1 ]; then
    pass "gitignore append: a second call is a no-op (sha unchanged, one '.harness/' line)"
else
    fail "gitignore append: a second call changed the file or duplicated the line (count=$count)"
fi
rm -rf "$F"

# --- (e) harness_conf_declared: pre-declaration conf reads as undeclared -------
# jq-gate dropped from the old migration block: harness_conf_declared is pure
# grep/printf, so it needs no jq to pin.
F=$(make_fixture) || exit 1
# Simulate the legacy state: strip the declaration entirely (make_fixture
# leaves it set-but-empty; a pre-v0.14 conf had no line at all).
grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness.conf" > "$F/scripts/hc" \
    && mv "$F/scripts/hc" "$F/scripts/harness.conf"
repin "$F"
if ! harness_conf_declared "$F" HOOK_WIRED_PROVIDERS; then
    pass "harness_conf_declared: a pre-declaration harness.conf reads as undeclared"
else
    fail "harness_conf_declared: undeclared conf misreported as declared"
fi
rm -rf "$F"

# --- (f) harness_conf_declare: idempotent --------------------------------------
# A second declare must neither duplicate the line nor reset a value the user
# has since edited (migration confirms the set ONCE).
F=$(make_fixture) || exit 1
grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness.conf" > "$F/scripts/hc" \
    && mv "$F/scripts/hc" "$F/scripts/harness.conf"
harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude .cursor .codex"
harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude"
n=$(grep -c '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness.conf")
v=$(grep '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness.conf")
if [ "$n" -eq 1 ] && [ "$v" = 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"' ]; then
    pass "harness_conf_declare: a second declare is a no-op (no duplicate line, first value retained)"
else
    fail "harness_conf_declare: not idempotent (n=$n v=$v)"
fi
rm -rf "$F"

finish "install-mechanism core"
