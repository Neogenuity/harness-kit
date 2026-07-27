#!/usr/bin/env bash
# Deterministic fixture tests of the kit's install MECHANICS core
# (scripts/harness/lib/install-lib.sh): runtime-prerequisite preflight, clean init driven
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

# emits_line <captured-output> <exact-line> — pipe-free exact-line membership.
# `harness_missing_prereqs | grep -qx TOKEN` flakes under `set -o pipefail`:
# grep -q closes the pipe on its first match, so the function's NEXT printf
# takes EPIPE (non-zero), and pipefail then fails the whole pipeline though the
# match itself succeeded — a load-dependent phantom failure (the SIGPIPE class
# swept out of check-harness). Capture the output once, then match line-by-line.
emits_line() {
    case "
$1
" in
        *"
$2
"*) return 0 ;;
        *) return 1 ;;
    esac
}

# assert_layer_sentinels <inventory> <label> — every shipped LAYER is present.
#
# The full-count floors elsewhere in this file derive their expected count from
# harness_kit_shipped_paths, the very helper under test. That makes them blind
# to the failure that matters most: if the helper stops emitting a whole layer,
# expected and observed shrink together and the floor passes over the survivors.
# A hardcoded total would rot on the next shipped file, so instead pin a stable
# REPRESENTATIVE of each layer and require it by name. Adding a file to a layer
# never touches this list; deleting a layer, or a manifest-parsing regression
# that silently drops one, fails here by name.
assert_layer_sentinels() {
    local inv="$1" label="$2" s missing_s=""
    for s in scripts/harness/kit-manifest \
             scripts/harness/verify \
             scripts/harness/lib/install-lib.sh \
             scripts/harness/hooks/guard-secrets.sh \
             scripts/harness/tests/test-log.sh \
             .harness/gates.conf \
             .harness/hooks/guard-project-policy.sh; do
        case $'\n'"$inv"$'\n' in
            *$'\n'"$s"$'\n'*) ;;
            *) missing_s="$missing_s $s" ;;
        esac
    done
    if [ -z "$missing_s" ]; then
        pass "$label: the shipped inventory carries a representative of every layer"
    else
        fail "$label: the shipped inventory dropped a whole layer —$missing_s"
    fi
}

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
# One capture with the ambient PATH; the present-halves assert each tool is
# absent from the missing list (emits_line is pipe-free — see its comment).
present_missing=$(harness_missing_prereqs)
if command -v jq >/dev/null 2>&1; then
    if emits_line "$present_missing" jq; then
        fail "preflight: jq reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present jq"
    fi
fi
if command -v git >/dev/null 2>&1; then
    if emits_line "$present_missing" git; then
        fail "preflight: git reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present git"
    fi
fi
if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
    if emits_line "$present_missing" sha256sum; then
        fail "preflight: sha256sum reported missing though a sha256 tool is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present sha256 tool"
    fi
fi
if command -v mktemp >/dev/null 2>&1; then
    if emits_line "$present_missing" mktemp; then
        fail "preflight: mktemp reported missing though it is on PATH"
    else
        pass "preflight: harness_missing_prereqs stays silent about a present mktemp"
    fi
fi
EMPTYPATH=$(mktemp -d "$WORK/emptypath.XXXXXX") || exit 1
# One capture under the empty PATH; the absent-halves assert each token IS named.
empty_missing=$(PATH="$EMPTYPATH" harness_missing_prereqs)
if emits_line "$empty_missing" jq; then
    pass "preflight: harness_missing_prereqs names jq when it is off PATH"
else
    fail "preflight: jq not reported missing when hidden from PATH"
fi
if emits_line "$empty_missing" git; then
    pass "preflight: harness_missing_prereqs names git when it is off PATH"
else
    fail "preflight: git not reported missing when hidden from PATH"
fi
if emits_line "$empty_missing" mktemp; then
    pass "preflight: harness_missing_prereqs names mktemp when it is off PATH"
else
    fail "preflight: mktemp not reported missing when hidden from PATH"
fi
if emits_line "$empty_missing" sha256sum; then
    pass "preflight: harness_missing_prereqs names sha256sum when it is off PATH"
else
    fail "preflight: sha256sum not reported missing when hidden from PATH"
fi
rm -rf "$EMPTYPATH"

# --- (a) clean init -----------------------------------------------------------
# Inventory-driven: every presence/exec-bit/manifest-completeness assertion
# iterates the kit's own ship contract (kit-manifest's shipped layers) rather
# than a second hard-coded file list, so a new shipped file is covered on
# arrival — hooks included, since the kit-manifest enumerates them per file.
F=$(make_fixture) || exit 1
write_mirrored_claude_settings "$F"
( cd "${F:?}" && git_c add -A && git_c commit -qm claude >/dev/null )
missing=""
unpinned=""
manifest_paths=$(awk '{print $2}' "$F/scripts/harness/.harness-manifest")
# Process substitution + a consumption counter, not a here-doc: a here-doc
# needs a temp file (bash 3.2: $TMPDIR, then the CWD) and a failed redirection
# under `set -uo pipefail` without `set -e` skips the loop silently. This loop
# is the only thing that fills $missing and $unpinned, so a skip printed BOTH
# "ok" lines below without having examined a single shipped path. Same defect
# class as check #9c (harness-kit issue #15).
# The manifest lives at <scripts>/harness/kit-manifest. This read used the
# wrong path ($SCRIPTS_DIR/kit-manifest) from its introduction: the inventory
# came back EMPTY, printf still delivered one blank line, the per-line counter
# reached 1, and both "ok" lines below printed without inspecting a single
# shipped path. The counter therefore increments only past the blank-line
# filter — counting delivered lines cannot distinguish "56 paths inspected"
# from "one empty line", and only one of those is good news.
# A zero-floor alone is still too weak: it proves SOME path was seen, not that
# the whole contract was. A regression that drops an entire manifest layer (or
# a truncated read) leaves the survivors green. Pin the expected size up front
# and require an exact match below.
shipped_inventory=$(harness_kit_shipped_paths "$SCRIPTS_DIR/harness/kit-manifest")
inventory_total=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    inventory_total=$((inventory_total + 1))
done < <(printf '%s\n' "$shipped_inventory")
inventory_read=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    inventory_read=$((inventory_read + 1))
    [ -f "$F/$p" ] || missing="$missing $p(absent)"
    # Only .sh files must carry the exec bit (check-harness.sh check #5);
    # sourced configs and data files (harness.conf, kit-manifest, README.md)
    # are not executable.
    case "$p" in
        *.sh) [ -x "$F/$p" ] || missing="$missing $p(not-exec)" ;;
    esac
    # Pipe-free exact-line membership (printf|grep -q + pipefail turns an
    # ignored-SIGPIPE EPIPE into a phantom miss — see check #9's note).
    case $'\n'"$manifest_paths"$'\n' in
        *$'\n'"$p"$'\n'*) ;;
        *) unpinned="$unpinned $p" ;;
    esac
done < <(printf '%s\n' "$shipped_inventory")
assert_layer_sentinels "$shipped_inventory" "clean init"
if [ "$inventory_total" -eq 0 ]; then
    fail "clean init: the shipped inventory is EMPTY — the two assertions below would have passed without examining a single shipped path"
elif [ "$inventory_read" -ne "$inventory_total" ]; then
    fail "clean init: only $inventory_read of $inventory_total shipped paths were examined — the two assertions below saw an incomplete inventory"
fi
if [ -z "$missing" ]; then
    pass "clean init: every shipped kit-manifest entry installed and executable"
else
    fail "clean init: mechanism incomplete —$missing"
fi
if [ -z "$unpinned" ]; then
    pass "clean init: manifest pins every shipped kit-manifest entry"
else
    fail "clean init: manifest omits an installed mechanism file —$unpinned"
fi
grep -qxF '.harness/var/' "$F/.gitignore" \
    && pass "clean init: .harness/var/ is git-ignored" \
    || fail "clean init: .gitignore missing .harness/var/"
out=$(bash "$F/scripts/harness/check-harness" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "clean init: check-harness.sh passes in the fixture (deny list mirrors SECRET_PATTERNS)"
else
    fail "clean init: check-harness.sh failed in the fixture" "$out"
fi
rm -rf "$F"

# --- (a2) clean init: installed permission modes -------------------------------
# The exec-bit inventory in (a) asserts with `[ -x ]`, which is true for 711 and
# 700 alike — and those are exactly what a regression here produces. The stage
# file is created by mktemp (0600) and `cp` onto an existing file preserves the
# DESTINATION mode, so an install that does not normalize the stage lands data
# files 0600 and executables 0711 (default umask) or 0700 (restrictive umask,
# because symbolic `chmod +x` is `a+x` masked by umask). Every one of those is
# unreadable to the other uids that run gates in containers and multi-uid CI,
# where bash must READ a script to execute it.
#
# Installing under `umask 077` in a subshell is the whole point of this case:
# the contract is that installed modes are a deterministic property of the ship
# contract (644/755) and never of the installing shell umask, so a permissive
# ambient umask must not be what makes this pass. `[ -x ]` cannot see any of
# it; only an octal comparison can.
#
# FILES ARE ONLY HALF OF IT. `mkdir -p` is umask-masked exactly like symbolic
# `chmod +x`, so the directories the install creates land 0700 under this same
# umask — and a 0755 file inside a 0700 directory is still unreachable to
# another uid, because traversal needs the directory search bit. An earlier
# version of this case asserted file modes only and passed green on a tree
# whose every directory was 0700, i.e. on a tree where the ticket harm was
# fully intact. Hence the second, directory-mode assertion below.
F2=$(mktemp -d "$WORK/modes.XXXXXX") || exit 1
( cd "${F2:?}" && git init -q )
# The install rc is an assertion, not noise: a half-failed install leaves the
# files it never wrote ABSENT, and an absent file is skipped by the mode loops
# below rather than flagged. Checking rc AND the full-count floors means a
# partial install fails here twice over instead of reporting green modes for
# whatever happened to land.
install_ok=1
( umask 077; harness_install_mechanism "$SCRIPTS_DIR" "$F2" ) \
    || { install_ok=0; fail "clean init modes: install failed under umask 077"; }
badmodes=""
baddirs=""
# Process substitution + counted floors, not a pipe or a here-doc: same SIGPIPE
# / temp-file hazard the (a) loop documents.
#
# Both floors below are FULL-COUNT, not zero-floors. A zero-floor only proves
# the loop ran at least once, so an install that dropped a third of the tree
# still printed "ok" for the survivors — the missing files were skipped by the
# existence test and never counted. Requiring an exact match against the
# inventory size makes "did not inspect it" as loud as "inspected it and it was
# wrong", which is the only version of this case worth having.
mode_inventory=$(harness_kit_shipped_paths "$SCRIPTS_DIR/harness/kit-manifest")
# One pass to size the file inventory and to derive the DIRECTORY set: every
# intermediate component of every shipped path, deduped. Directories are half
# the contract — a 755 file under a 0700 directory is unreachable to another
# uid, because traversal needs the search bit — and in a fresh fixture every
# directory except .git/ is install-created, so all of them are fair game.
mode_total=0
dirset=""
while IFS= read -r p; do
    [ -n "$p" ] || continue
    mode_total=$((mode_total + 1))
    d=$(dirname "$p")
    while [ "$d" != "." ] && [ "$d" != "/" ]; do
        # Pipe-free exact-line membership, as elsewhere in this suite.
        case $'\n'"$dirset"$'\n' in
            *$'\n'"$d"$'\n'*) ;;
            *) dirset="$dirset$d"$'\n' ;;
        esac
        d=$(dirname "$d")
    done
done < <(printf '%s\n' "$mode_inventory")
dir_total=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    dir_total=$((dir_total + 1))
done < <(printf '%s' "$dirset")
mode_read=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$F2/$p" ] || continue
    mode_read=$((mode_read + 1))
    # Expected mode mirrors _harness_copy_shipped exec-bit cases: .sh files and
    # extensionless scripts/harness/* command entries whose first two bytes are
    # a shebang are executable (755); everything else is data (644).
    want=644
    case "$p" in
        *.sh) want=755 ;;
        scripts/harness/*/*) ;;
        scripts/harness/*)
            case "$(head -c2 "$F2/$p" 2>/dev/null)" in '#!') want=755 ;; esac ;;
    esac
    got=$(mode_of "$F2/$p")
    [ "$got" = "$want" ] || badmodes="$badmodes $p(got-$got want-$want)"
done < <(printf '%s\n' "$mode_inventory")
dir_read=0
while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$F2/$d" ] || { baddirs="$baddirs $d(absent)"; continue; }
    dir_read=$((dir_read + 1))
    got=$(mode_of "$F2/$d")
    [ "$got" = "755" ] || baddirs="$baddirs $d(got-$got want-755)"
done < <(printf '%s' "$dirset")
assert_layer_sentinels "$mode_inventory" "clean init modes"
mode_floor_ok=1
dir_floor_ok=1
if [ "$mode_total" -eq 0 ]; then
    mode_floor_ok=0
    fail "clean init modes: the shipped inventory is EMPTY — the mode assertions below would have passed vacuously"
elif [ "$mode_read" -ne "$mode_total" ]; then
    mode_floor_ok=0
    fail "clean init modes: only $mode_read of $mode_total shipped files were inspected — the rest never installed, so their modes were never checked"
fi
if [ "$dir_total" -eq 0 ]; then
    dir_floor_ok=0
    fail "clean init modes: no installed directories were derived from the inventory — the directory assertion below would have passed vacuously"
elif [ "$dir_read" -ne "$dir_total" ]; then
    dir_floor_ok=0
    fail "clean init modes: only $dir_read of $dir_total installed directories were inspected"
fi
# WITHHOLD the pass line when the install rc or a floor already failed. "Every
# installed file lands 644" is a claim about the whole shipped set; printing it
# because the SUBSET that happened to install had good modes is a false green in
# the log even though the suite's exit status is right. No pass, no duplicate
# fail — the earlier check already recorded one.
if [ -n "$badmodes" ]; then
    fail "clean init: installed files do not carry the ship contract mode —$badmodes"
elif [ "$install_ok" = "1" ] && [ "$mode_floor_ok" = "1" ]; then
    pass "clean init: every installed file lands 644 (755 for executables) under a restrictive umask"
fi
if [ -n "$baddirs" ]; then
    fail "clean init: installed directories do not carry the ship contract mode —$baddirs"
elif [ "$install_ok" = "1" ] && [ "$dir_floor_ok" = "1" ]; then
    pass "clean init: every install-created directory lands 755 under a restrictive umask"
fi
rm -rf "$F2"

# --- (a3) clean init: a symlinked tree component is refused --------------------
# `[ -d ]`, `mkdir`, and `chmod` all FOLLOW symlinks, so a $root/scripts planted
# as a link to somewhere else turns "create the installed tree" into "create it
# in the attacker's directory". File CONTENT was always contained (the copy
# function re-resolves the destination's physical path and refuses anything
# outside the root), so the exposure is directory CREATION — which is exactly
# what _harness_mkdir_installed now owns, and therefore what it must refuse.
#
# Two independent assertions, because they fail apart: the install must abort
# loudly (naming the symlink), and the link target must be untouched. Without
# the refusal the first still holds — the per-file containment check rejects
# every copy, so the install returns non-zero anyway — while the second flips.
# Asserting only the exit status would have looked green on a tree where the
# installer had already created directories outside the repo.
F3=$(mktemp -d "$WORK/symdir.XXXXXX") || exit 1
OUTSIDE=$(mktemp -d "$WORK/outside.XXXXXX") || exit 1
( cd "${F3:?}" && git init -q )
ln -s "$OUTSIDE" "$F3/scripts"
sym_out=$(harness_install_mechanism "$SCRIPTS_DIR" "$F3" 2>&1); sym_rc=$?
sym_named=0
case "$sym_out" in *"is a symlink"*) sym_named=1 ;; esac
if [ "$sym_rc" != "0" ] && [ "$sym_named" = "1" ]; then
    pass "symlinked tree component: install refuses loudly instead of creating through the link"
else
    fail "symlinked tree component: install did not refuse by name (rc=$sym_rc)" "$sym_out"
fi
# Nothing at all may appear under the link target — not a file, not an empty
# directory. `find -mindepth 1` is the whole-subtree form of that question.
sym_created=$(find "$OUTSIDE" -mindepth 1 2>/dev/null)
if [ -z "$sym_created" ]; then
    pass "symlinked tree component: nothing was created under the link target"
else
    fail "symlinked tree component: install created paths outside the repo through the link" "$sym_created"
fi
rm -rf "$F3" "$OUTSIDE"

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
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/harness/.harness-manifest"
s_after=$(sha_of "$F" ".claude/settings.json")
a_after=$(sha_of "$F" "AGENTS.md")
if [ "$s_before" = "$s_after" ] && [ "$a_before" = "$a_after" ]; then
    pass "non-clobber floor: hand-written settings.json and AGENTS.md untouched by install"
else
    fail "non-clobber floor: install modified a hand-written file"
fi
rm -rf "$F"

# --- (c) gitignore append: no-trailing-newline merge safety --------------------
# A '.gitignore' lacking a trailing newline must not have '.harness/var/' merge
# onto its last line (e.g. 'node_modules' + '.harness/var/' -> 'node_modules.harness/var/').
F=$(mktemp -d "$WORK/gitignore.XXXXXX") || exit 1
printf 'node_modules' > "$F/.gitignore"
harness_append_gitignore "$F"
if grep -qxF 'node_modules' "$F/.gitignore" && grep -qxF '.harness/var/' "$F/.gitignore"; then
    pass "gitignore append: a no-trailing-newline file gets its own '.harness/var/' line, not a merge"
else
    fail "gitignore append: '.harness/var/' merged onto the prior line (or the prior line was lost)" "$(cat "$F/.gitignore")"
fi

# --- (d) gitignore append: idempotent ------------------------------------------
before=$(sha_of "$F" ".gitignore")
harness_append_gitignore "$F"
after=$(sha_of "$F" ".gitignore")
count=$(grep -cxF '.harness/var/' "$F/.gitignore")
if [ "$before" = "$after" ] && [ "$count" -eq 1 ]; then
    pass "gitignore append: a second call is a no-op (sha unchanged, one '.harness/var/' line)"
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
grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness/harness.conf" > "$F/scripts/hc" \
    && mv "$F/scripts/hc" "$F/scripts/harness/harness.conf"
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
grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS)=' "$F/scripts/harness/harness.conf" > "$F/scripts/hc" \
    && mv "$F/scripts/hc" "$F/scripts/harness/harness.conf"
harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude .cursor .codex"
harness_conf_declare "$F" HOOK_WIRED_PROVIDERS ".claude"
n=$(grep -c '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness/harness.conf")
v=$(grep '^HOOK_WIRED_PROVIDERS=' "$F/scripts/harness/harness.conf")
if [ "$n" -eq 1 ] && [ "$v" = 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"' ]; then
    pass "harness_conf_declare: a second declare is a no-op (no duplicate line, first value retained)"
else
    fail "harness_conf_declare: not idempotent (n=$n v=$v)"
fi
rm -rf "$F"

# --- (f2) harness_repin_manifest: a missing version fails loudly, stdout empty -
# The function is pure-stdout by contract (issue #19): the caller redirects it
# onto the manifest, so before the guard a missing/empty <kit_version> emitted
# a "# harness-kit " header with no version at exit 0 -- and the redirect then
# pinned that corrupt manifest silently. The guard must return nonzero, name
# the version argument on stderr, and print NOTHING to stdout, so no redirect
# of the failure can produce a corrupt manifest.
# Sourced fresh from the TEMPLATE library in a bash -c subshell (same shape as
# the (l2) case above) rather than calling the copy this suite sourced at
# startup -- that one is the root's installed mirror -- and under `set -u`,
# because the guard's "${2:-}" exists precisely so a version-less call reaches
# the diagnostic instead of dying on an unbound $2.
F=$(make_fixture) || exit 1
out=$(bash -c 'set -uo pipefail; . "$1"; harness_repin_manifest "$2"' \
    _ "$SCRIPTS_DIR/harness/lib/install-lib.sh" "$F" 2>"$WORK/repin-nover.err"); rc=$?
err=$(cat "$WORK/repin-nover.err")
case "$err" in *version*) named_version=1 ;; *) named_version=0 ;; esac
if [ "$rc" -ne 0 ] && [ -z "$out" ] && [ "$named_version" -eq 1 ]; then
    pass "repin guard: a missing <kit_version> returns nonzero, names the argument on stderr, and emits no stdout"
else
    fail "repin guard: a version-less call was accepted or wrote to stdout (rc=$rc, stdout=${out:-<empty>})" "$err"
fi
# Explicit-empty is the same defect through a different caller shape
# (VERSION="" from a failed lookup): the guard must catch "" too.
out=$(bash -c 'set -uo pipefail; . "$1"; harness_repin_manifest "$2" ""' \
    _ "$SCRIPTS_DIR/harness/lib/install-lib.sh" "$F" 2>/dev/null); rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
    pass "repin guard: an explicitly empty version is rejected the same way"
else
    fail "repin guard: an empty-string version was accepted (rc=$rc, stdout=${out:-<empty>})"
fi
rm -rf "$F"

# --- (g) ship-contract validation: a bad manifest aborts BEFORE any copy ------
# harness_install_mechanism must reject unknown layers, traversal/absolute
# paths, duplicate destinations, and missing declared sources up front. The
# pre-validation failure mode was a silent PARTIAL install that still returned
# success (a missing declared source was simply skipped); the target must now
# stay completely untouched — validation runs before the first mkdir.
for bad in \
    'mechanism ../escape.sh' \
    'mechanism /etc/absolute-path.sh' \
    'mechanizm scripts/harness/typo-layer.sh' \
    'mechanism scripts/harness/no-such-source.sh' \
    'policy scripts/harness/x.conf src=../../outside' \
    'mechanism scripts/harness/sync'; do
    K=$(mktemp -d "$WORK/badkit.XXXXXX") || exit 1
    cp -R "$SCRIPTS_DIR" "$K/scripts"
    printf '%s\n' "$bad" >> "$K/scripts/harness/kit-manifest"
    T2=$(mktemp -d "$WORK/badtarget.XXXXXX") || exit 1
    out=$(harness_install_mechanism "$K/scripts" "$T2" 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && [ ! -d "$T2/scripts" ] && [ ! -e "$WORK/escape.sh" ]; then
        pass "ship contract: '$bad' rejected before any copy"
    else
        fail "ship contract: '$bad' accepted, or files were written before the abort (rc=$rc)" "$out"
    fi
    rm -rf "$K" "$T2"
done

# --- (h) bootstrap prereq gate: a degraded install needs explicit opt-in -------
# The SKILL's init flow asks the user to acknowledge missing prerequisites in
# prose; the bootstrap CLI must enforce the same contract mechanically. jq/git
# missing => refuse with the degradation spelled out, proceed only under
# --allow-degraded; no sha256 tool => refuse ALWAYS (integrity pins would be
# stillborn — --allow-degraded does not cover it). Runtime hooks keep failing
# open regardless; this gates only the install decision. Substring checks are
# pipe-free `case` (the grep -q + pipefail SIGPIPE phantom-failure class).
GATEBIN=$(mktemp -d "$WORK/gatebin.XXXXXX") || exit 1
for tool in bash sh sed dirname mkdir cp mv chmod head tail find sort uniq awk tr rm touch cat grep basename ln mktemp shasum sha256sum; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$GATEBIN/$tool"
done
T2=$(mktemp -d "$WORK/gatetarget.XXXXXX") || exit 1
out=$(PATH="$GATEBIN" "$BASH" "$SCRIPTS_DIR/harness/bootstrap" install "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
case "$out" in
    *jq*"--allow-degraded"*|*"--allow-degraded"*jq*) gate_named_jq=1 ;;
    *) gate_named_jq=0 ;;
esac
if [ "$rc" -ne 0 ] && [ ! -d "$T2/scripts" ] && [ "$gate_named_jq" -eq 1 ]; then
    pass "prereq gate: install without jq/git refuses, names jq, and offers --allow-degraded"
else
    fail "prereq gate: a degraded install was not refused (rc=$rc)" "$out"
fi
out=$(PATH="$GATEBIN" "$BASH" "$SCRIPTS_DIR/harness/bootstrap" install --allow-degraded "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$T2/scripts/harness/bootstrap" ]; then
    pass "prereq gate: --allow-degraded acknowledges and the install proceeds"
else
    fail "prereq gate: --allow-degraded install failed (rc=$rc)" "$out"
fi
rm -rf "$T2"
# No sha256 tool at all: refuse even with --allow-degraded.
NOSHABIN=$(mktemp -d "$WORK/noshabin.XXXXXX") || exit 1
for tool in bash sh sed dirname mkdir cp mv chmod head tail find sort uniq awk tr rm touch cat grep basename ln mktemp jq git; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$NOSHABIN/$tool"
done
T2=$(mktemp -d "$WORK/gatetarget2.XXXXXX") || exit 1
out=$(PATH="$NOSHABIN" "$BASH" "$SCRIPTS_DIR/harness/bootstrap" install --allow-degraded "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
case "$out" in *sha256*) gate_named_sha=1 ;; *) gate_named_sha=0 ;; esac
if [ "$rc" -ne 0 ] && [ ! -d "$T2/scripts" ] && [ "$gate_named_sha" -eq 1 ]; then
    pass "prereq gate: a missing sha256 tool is a hard refusal (--allow-degraded does not cover it)"
else
    fail "prereq gate: install proceeded without any sha256 tool (rc=$rc)" "$out"
fi
# mktemp missing is a hard refusal too: the installer stages every copied file
# with mktemp, so nothing can be installed without it (--allow-degraded does not
# cover it). Build a PATH with every base tool INCLUDING a sha256 tool, jq, and
# git, but no mktemp; the fixture dirs themselves are created with the ambient
# mktemp before PATH is narrowed for the bootstrap call.
NOMKTEMPBIN=$(mktemp -d "$WORK/nomktempbin.XXXXXX") || exit 1
for tool in bash sh sed dirname mkdir cp mv chmod head tail find sort uniq awk tr rm touch cat grep basename ln jq git shasum sha256sum; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$NOMKTEMPBIN/$tool"
done
T2=$(mktemp -d "$WORK/gatetarget3.XXXXXX") || exit 1
out=$(PATH="$NOMKTEMPBIN" "$BASH" "$SCRIPTS_DIR/harness/bootstrap" install --allow-degraded "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
case "$out" in *mktemp*) gate_named_mktemp=1 ;; *) gate_named_mktemp=0 ;; esac
if [ "$rc" -ne 0 ] && [ ! -d "$T2/scripts" ] && [ "$gate_named_mktemp" -eq 1 ]; then
    pass "prereq gate: a missing mktemp is a hard refusal (--allow-degraded does not cover it)"
else
    fail "prereq gate: install proceeded without mktemp (rc=$rc)" "$out"
fi
rm -rf "$NOMKTEMPBIN" "$T2"

# update --dry-run waives jq/git (a preview gates nothing at runtime) but must
# keep the sha256 hard gate: _harness_sha256 with no tool prints NOTHING, so a
# plan computed without it compares "" against every pin and reports phantom
# diff/retire-keep at exit 0 — a preview that lies is worse than none.
F=$(make_fixture) || exit 1
out=$(PATH="$NOSHABIN" "$BASH" "$SCRIPTS_DIR/harness/bootstrap" update --dry-run "$SCRIPTS_DIR" "$F" 2>&1); rc=$?
case "$out" in *sha256*) dry_named_sha=1 ;; *) dry_named_sha=0 ;; esac
case "$out" in *diff*|*retire-keep*) dry_planned=1 ;; *) dry_planned=0 ;; esac
if [ "$rc" -ne 0 ] && [ "$dry_named_sha" -eq 1 ] && [ "$dry_planned" -eq 0 ]; then
    pass "prereq gate: dry-run without a sha256 tool refuses instead of printing a phantom-drift plan"
else
    fail "prereq gate: dry-run planned without a sha256 tool (rc=$rc)" "$out"
fi
rm -rf "$F" "$T2" "$GATEBIN" "$NOSHABIN"

# --- (i) copy containment: a symlinked parent must not GAIN directories -------
# `mkdir -p` follows a symlinked ancestor: with scripts/harness -> $OUT and a
# shipped path scripts/harness/lib/x.sh, the pre-fix code created $OUT/lib
# OUTSIDE the repo before the physical-containment check refused the copy. The
# deepest EXISTING ancestor's physical path must be checked before any
# directory is created — [ ! -d "$OUT/lib" ] below is the regression pin (the
# old code also returned non-zero; it just left the external directory behind).
R=$(mktemp -d "$WORK/linkroot.XXXXXX") || exit 1
OUTDIR=$(mktemp -d "$WORK/linkout.XXXXXX") || exit 1
mkdir -p "$R/scripts"
ln -s "$OUTDIR" "$R/scripts/harness"
printf '#!/bin/sh\n' > "$WORK/copysrc.sh"
out=$(_harness_copy_shipped "$WORK/copysrc.sh" scripts/harness/lib/x.sh "$R" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && [ ! -d "$OUTDIR/lib" ] && [ ! -e "$OUTDIR/lib/x.sh" ]; then
    pass "copy containment: a symlinked parent is refused before any mkdir escapes the root"
else
    fail "copy containment: directories were created through a symlinked parent (rc=$rc)" "$out"
fi
rm -rf "$R" "$OUTDIR" "$WORK/copysrc.sh"


# --- (j) copy containment: a pre-planted stage symlink must not be followed ---
# The stage path used to be a predictable '.hk-stage.$$.<basename>'; an attacker
# who pre-planted a symlink there had `cp` write the shipped bytes THROUGH it to
# an arbitrary external file while _harness_copy_shipped still returned success.
# mktemp (O_EXCL) now creates the stage file, so a pre-existing symlink at the
# old predictable path can never be opened. _harness_copy_shipped runs in THIS
# shell (install-test-lib sources install-lib.sh), so its $$ equals ours — the
# exact legacy vector is reproducible in-process: plant the symlink at
# scripts/harness/lib/.hk-stage.$$.x.sh, point it at an external victim, and
# assert the victim is untouched and a real regular file was installed. Pre-fix
# this failed (victim overwritten with the shipped bytes, dest left a symlink).
R=$(mktemp -d "$WORK/stagelink.XXXXXX") || exit 1
VICT=$(mktemp -d "$WORK/stagevictim.XXXXXX") || exit 1
mkdir -p "$R/scripts/harness/lib"
printf 'ORIGINAL\n' > "$VICT/victim.txt"
printf '#!/bin/sh\necho shipped\n' > "$WORK/stagesrc.sh"
ln -s "$VICT/victim.txt" "$R/scripts/harness/lib/.hk-stage.$$.x.sh"
out=$(_harness_copy_shipped "$WORK/stagesrc.sh" scripts/harness/lib/x.sh "$R" 2>&1); rc=$?
victim_content=$(cat "$VICT/victim.txt")
if [ "$victim_content" = "ORIGINAL" ] && [ -f "$R/scripts/harness/lib/x.sh" ] && [ ! -L "$R/scripts/harness/lib/x.sh" ]; then
    pass "copy containment: a pre-planted stage symlink is not followed (external file untouched, real file installed)"
else
    fail "copy containment: stage symlink was followed or dest is not a regular file (rc=$rc, victim=$victim_content)" "$out"
fi
rm -rf "$R" "$VICT" "$WORK/stagesrc.sh"
# --- (k) formatterignore: appends the marked block once -----------------------
# harness_append_formatterignore is the prettier-exclusion counterpart to
# harness_append_gitignore above, modeled on it directly (see its own comment
# in install-lib.sh). Assert the marker line and a couple of the listed paths
# land in a fresh .prettierignore.
F=$(mktemp -d "$WORK/formatterignore.XXXXXX") || exit 1
harness_append_formatterignore "$F"
if [ -f "$F/.prettierignore" ] \
    && grep -qxF '# harness-kit: kit-owned mechanism + generated stubs — do not reformat' "$F/.prettierignore" \
    && grep -qxF '**/scripts/harness/' "$F/.prettierignore" \
    && grep -qxF '**/.claude/skills/' "$F/.prettierignore"; then
    pass "formatterignore: appends the marked kit-owned block"
else
    fail "formatterignore: block missing or incomplete" "$(cat "$F/.prettierignore" 2>/dev/null)"
fi

# --- (k2) formatterignore: the block covers a NESTED checkout too --------------
# Regression for the reproduced adopter failure: .prettierignore follows
# gitignore anchoring, so the block's original 'scripts/harness/' matched the
# repo-root copy ONLY. Claude Code's worktree feature puts a full second
# checkout under .claude/worktrees/<name>/ and hides it from Git via
# .git/info/exclude -- which prettier does not read -- so `prettier --check .`
# reached the nested pinned/generated files and the adopter's format gate (and
# with it `scripts/harness/verify`) went red on a clean tree. Two independent
# requirements, asserted separately because either alone leaves the hole open:
# the worktree root itself is excluded (which also spares the nested copy of
# the adopter's OWN sources, inside which their own anchored entries stop
# applying), and every kit-owned entry is written in the depth-agnostic '**/'
# form gitignore matches at any level INCLUDING the root.
missing_nested=""
grep -qxF '.claude/worktrees/' "$F/.prettierignore" || missing_nested=" .claude/worktrees/(absent)"
while IFS= read -r line; do
    case "$line" in
        ''|'#'*|'.claude/worktrees/') continue ;;
        '**/'*) ;;
        *) missing_nested="$missing_nested $line(root-anchored)" ;;
    esac
done < "$F/.prettierignore"
if [ -z "$missing_nested" ]; then
    pass "formatterignore: excludes .claude/worktrees/ and writes every kit entry in depth-agnostic '**/' form"
else
    fail "formatterignore: nested-checkout coverage gap ->$missing_nested" "$(cat "$F/.prettierignore")"
fi

# --- (l) formatterignore: idempotent -------------------------------------------
before=$(sha_of "$F" ".prettierignore")
harness_append_formatterignore "$F"
after=$(sha_of "$F" ".prettierignore")
count=$(grep -cxF '# harness-kit: kit-owned mechanism + generated stubs — do not reformat' "$F/.prettierignore")
if [ "$before" = "$after" ] && [ "$count" -eq 1 ]; then
    pass "formatterignore: a second call is a no-op (sha unchanged, one marker line)"
else
    fail "formatterignore: a second call changed the file or duplicated the marker (count=$count)"
fi
rm -rf "$F"

# --- (l2) formatterignore: an undeliverable entry list is reported, not skipped -
# The "which required lines are missing?" loop is the ONLY thing that discovers
# an incomplete block. It used to read through a here-doc, which needs a temp
# file (bash 3.2: $TMPDIR, then the CWD); when neither is writable the
# redirection fails and `set -uo pipefail` without `set -e` skips the loop —
# leaving $missing empty, so the function returned 0 having healed nothing. The
# heal this function exists for, silently not happening. It must now fail loudly.
F=$(mktemp -d "$WORK/formatterignore-notemp.XXXXXX") || exit 1
printf '# harness-kit: kit-owned mechanism + generated stubs — do not reformat\n' \
    > "$F/.prettierignore"          # marker present, every entry line missing
NOTEMP="$F/no-writable-temp"
mkdir -p "$NOTEMP" && chmod 500 "$NOTEMP"
if ( : > "$NOTEMP/.probe" ) 2>/dev/null; then
    rm -f "$NOTEMP/.probe"; chmod 700 "$NOTEMP"
    echo "skip: formatterignore undeliverable-list case — cannot make a directory unwritable here (DAC override, e.g. root)"
else
    out=$(cd "$NOTEMP" && TMPDIR="$NOTEMP" bash -c '
        . "$1"
        harness_append_formatterignore "$2"' _ "$SCRIPTS_DIR/harness/lib/install-lib.sh" "$F" 2>&1); rc=$?
    chmod 700 "$NOTEMP"
    # Either it delivered the list and healed the block (rc 0, entries present),
    # or it could not and said so (rc 1 + the ERROR). Returning 0 with the block
    # still unhealed is the regression.
    if { [ "$rc" -ne 0 ] && case "$out" in *"could not read the required"*) true ;; *) false ;; esac; } \
        || grep -qxF '**/scripts/harness/' "$F/.prettierignore"; then
        pass "formatterignore: an undeliverable entry list fails loudly instead of reporting a heal that never happened"
    else
        fail "formatterignore: returned $rc with the block still unhealed and no error" "$out"
    fi
fi
rm -rf "$F"

# --- (m) formatterignore: no-trailing-newline merge safety --------------------
# Same hazard harness_append_gitignore guards against (case (c) above): a
# '.prettierignore' lacking a trailing newline must not have the block merge
# onto its last line (e.g. 'dist' + the marker -> 'dist# harness-kit: ...').
F=$(mktemp -d "$WORK/formatterignore-nl.XXXXXX") || exit 1
printf 'dist' > "$F/.prettierignore"
harness_append_formatterignore "$F"
if grep -qxF 'dist' "$F/.prettierignore" \
    && grep -qxF '# harness-kit: kit-owned mechanism + generated stubs — do not reformat' "$F/.prettierignore"; then
    pass "formatterignore: a no-trailing-newline file gets its own block, not a merge"
else
    fail "formatterignore: block merged onto the prior line (or the prior line was lost)" "$(cat "$F/.prettierignore")"
fi
rm -rf "$F"

# --- (n) formatterignore: a symlinked destination is refused -------------------
# `.prettierignore` as a symlink must never be written through: [ -f ] alone
# follows symlinks, so the old code would happily append the kit's block
# through a link to an arbitrary path outside the repo. The helper must
# refuse (nonzero), and the link's target must stay byte-for-byte untouched.
F=$(mktemp -d "$WORK/formatterignore-symlink.XXXXXX") || exit 1
VICT=$(mktemp -d "$WORK/formatterignore-symlink-victim.XXXXXX") || exit 1
printf 'OUTSIDE\n' > "$VICT/target.txt"
ln -s "$VICT/target.txt" "$F/.prettierignore"
out=$(harness_append_formatterignore "$F" 2>&1); rc=$?
victim_content=$(cat "$VICT/target.txt")
if [ "$rc" -ne 0 ] && [ -L "$F/.prettierignore" ] && [ "$victim_content" = "OUTSIDE" ]; then
    pass "formatterignore: a symlinked .prettierignore is refused, link target untouched"
else
    fail "formatterignore: symlink was followed or its target was modified (rc=$rc, target=$victim_content)" "$out"
fi
rm -rf "$F" "$VICT"

# --- (o) formatterignore: a write failure returns nonzero, not silent success --
# The old code ended in an unconditional `return 0`, so a failed write (full
# disk, denied permission, ...) was indistinguishable from success. A
# non-writable destination directory means the staged temp file can never be
# created; the helper must return nonzero and must leave no .prettierignore
# behind (same read-only-dir technique test-install-migrate.sh already uses to
# force a staging failure).
F=$(mktemp -d "$WORK/formatterignore-nowrite.XXXXXX") || exit 1
chmod a-w "$F"
out=$(harness_append_formatterignore "$F" 2>&1); rc=$?
chmod u+w "$F"
if [ "$rc" -ne 0 ] && [ ! -e "$F/.prettierignore" ]; then
    pass "formatterignore: a non-writable destination directory returns nonzero, not a false success"
else
    fail "formatterignore: a write failure was reported as success (rc=$rc)" "$out"
fi
rm -rf "$F"

# --- (p) formatterignore: a marker-only partial block gets healed ---------------
# An interrupted run can leave just the marker comment with none of the
# required entries; the old code treated the marker ALONE as proof of a
# complete block and returned early forever. A healing call must append every
# missing entry and must NOT duplicate the marker line.
F=$(mktemp -d "$WORK/formatterignore-partial.XXXXXX") || exit 1
printf '%s\n' '# harness-kit: kit-owned mechanism + generated stubs — do not reformat' > "$F/.prettierignore"
harness_append_formatterignore "$F"
marker_count=$(grep -cxF '# harness-kit: kit-owned mechanism + generated stubs — do not reformat' "$F/.prettierignore")
if [ "$marker_count" -eq 1 ] \
    && grep -qxF '.claude/worktrees/' "$F/.prettierignore" \
    && grep -qxF '**/scripts/harness/' "$F/.prettierignore" \
    && grep -qxF '**/.claude/skills/' "$F/.prettierignore" \
    && grep -qxF '**/.opencode/agents/' "$F/.prettierignore"; then
    pass "formatterignore: a marker-only partial block is healed (missing entries appended, marker not duplicated)"
else
    fail "formatterignore: partial block was not healed (marker_count=$marker_count)" "$(cat "$F/.prettierignore")"
fi
# A second call over the now-complete block is a true no-op (idempotence
# still holds after healing, not just on a block written all at once).
before=$(sha_of "$F" ".prettierignore")
harness_append_formatterignore "$F"
after=$(sha_of "$F" ".prettierignore")
if [ "$before" = "$after" ]; then
    pass "formatterignore: a healed complete block stays a no-op on the next call"
else
    fail "formatterignore: a healed block was rewritten by a following no-op call"
fi
rm -rf "$F"

# --- (q) formatterignore via bootstrap: install wiring is opt-in ---------------
# --formatter-ignore must write the block; its absence must leave the repo's
# config untouched (this kit never mutates repo-owned config unconditionally).
T2=$(mktemp -d "$WORK/bootstrap-install-fmt.XXXXXX") || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" install --formatter-ignore "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$T2/.prettierignore" ] && grep -qxF '**/scripts/harness/' "$T2/.prettierignore"; then
    pass "bootstrap install --formatter-ignore: writes the .prettierignore block"
else
    fail "bootstrap install --formatter-ignore: block missing after install (rc=$rc)" "$out"
fi
T3=$(mktemp -d "$WORK/bootstrap-install-nofmt.XXXXXX") || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" install "$SCRIPTS_DIR" "$T3" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$T3/.prettierignore" ]; then
    pass "bootstrap install: .prettierignore is NOT written without --formatter-ignore (opt-in only)"
else
    fail "bootstrap install: .prettierignore appeared without --formatter-ignore (rc=$rc)" "$out"
fi
rm -rf "$T2" "$T3"

# --- (r) bootstrap install: --formatter-ignore AFTER the positionals works -----
# Flag parsing used to stop at the first positional argument, so the natural
# invocation `bootstrap install SRC ROOT --formatter-ignore` silently dropped
# the trailing flag and reported success without ever writing anything. This
# fix accepts flags anywhere among the arguments — assert the flag-after
# form actually WRITES the block (not merely that it exits 0), which is what
# proves the flag was not dropped.
T2=$(mktemp -d "$WORK/bootstrap-install-fmt-after.XXXXXX") || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" install "$SCRIPTS_DIR" "$T2" --formatter-ignore 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$T2/.prettierignore" ] && grep -qxF '**/scripts/harness/' "$T2/.prettierignore"; then
    pass "bootstrap install SRC ROOT --formatter-ignore: flag after positionals still writes the block"
else
    fail "bootstrap install SRC ROOT --formatter-ignore: block missing after install (rc=$rc)" "$out"
fi
rm -rf "$T2"
# A third positional (or trailing garbage) must be rejected loudly, not
# silently ignored — exit 64 (EX_USAGE), no partial install.
T2=$(mktemp -d "$WORK/bootstrap-install-extra-arg.XXXXXX") || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" install "$SCRIPTS_DIR" "$T2" extra-positional 2>&1); rc=$?
if [ "$rc" -eq 64 ] && [ ! -e "$T2/scripts" ]; then
    pass "bootstrap install: a third positional argument is rejected (exit 64), nothing installed"
else
    fail "bootstrap install: an extra positional was accepted or mis-reported (rc=$rc)" "$out"
fi
rm -rf "$T2"

# --- (s) bootstrap install: a failed --formatter-ignore warns but doesn't fail -
# A symlinked .prettierignore makes harness_append_formatterignore fail (case
# (n) above); that failure must not flip a successful install's exit code, but
# it must not be silent either — bootstrap must print a WARNING naming what
# did not happen, and the symlink's target must stay untouched.
T2=$(mktemp -d "$WORK/bootstrap-install-fmt-fail.XXXXXX") || exit 1
VICT=$(mktemp -d "$WORK/bootstrap-install-fmt-fail-victim.XXXXXX") || exit 1
printf 'OUTSIDE\n' > "$VICT/target.txt"
ln -s "$VICT/target.txt" "$T2/.prettierignore"
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" install --formatter-ignore "$SCRIPTS_DIR" "$T2" 2>&1); rc=$?
case "$out" in *WARNING*) warned=1 ;; *) warned=0 ;; esac
victim_content=$(cat "$VICT/target.txt")
if [ "$rc" -eq 0 ] && [ -f "$T2/scripts/harness/bootstrap" ] \
    && [ -L "$T2/.prettierignore" ] && [ "$victim_content" = "OUTSIDE" ] && [ "$warned" -eq 1 ]; then
    pass "bootstrap install: a failed --formatter-ignore warns on stderr but does not fail the install"
else
    fail "bootstrap install: failed formatter-ignore was silent or flipped the install's exit code (rc=$rc, warned=$warned)" "$out"
fi
rm -rf "$T2" "$VICT"

# --- (t) formatterignore via bootstrap: UPDATE wiring (not just install) ------
# The update branch previously called no ignore helper at all — an existing
# adopter running update would never receive the block without this wiring.
F=$(make_fixture) || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" update --formatter-ignore "$SCRIPTS_DIR" "$F" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$F/.prettierignore" ] && grep -qxF '**/scripts/harness/' "$F/.prettierignore"; then
    pass "bootstrap update --formatter-ignore: writes the .prettierignore block on a real apply"
else
    fail "bootstrap update --formatter-ignore: block missing after update (rc=$rc)" "$out"
fi
rm -rf "$F"

# --- (u) formatterignore via bootstrap: --dry-run update writes nothing -------
F=$(make_fixture) || exit 1
out=$("$BASH" "$SCRIPTS_DIR/harness/bootstrap" update --dry-run --formatter-ignore "$SCRIPTS_DIR" "$F" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$F/.prettierignore" ]; then
    pass "bootstrap update --dry-run --formatter-ignore: mutates nothing"
else
    fail "bootstrap update --dry-run --formatter-ignore: .prettierignore appeared under --dry-run (rc=$rc)" "$out"
fi
rm -rf "$F"
finish "install-mechanism core"
