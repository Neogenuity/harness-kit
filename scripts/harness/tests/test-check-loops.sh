#!/usr/bin/env bash
# Regression test for the here-doc fail-open class in the check families
# (harness-kit issue #15).
#
# Bash backs a here-doc with a temp file — bash 3.2 writes it under $TMPDIR and
# falls back to the CWD. With neither writable the redirection fails, and under
# `set -uo pipefail` without `set -e` a failed redirection skips the entire
# compound command. A `while read` loop that is a check's only error source
# therefore leaves its family printing "OK: <family> checks passed" for a repo
# it never examined: a check that COULD NOT RUN is indistinguishable from a
# clean one. Reproduced live in two adopter repos, one losing the #8d
# hook-wiring validator — the check that proves the guards are wired at all.
#
# Four cases, cheapest first:
#   1. structural — every surviving here-doc-fed loop in the shipped lib/ and
#      hooks/ carries the marker saying its retention is deliberate. This is the
#      durable guard: it stops the class from growing back one loop at a time.
#   2. positive control — the scanner of case 1 is itself falsifiable: run
#      against fixtures it MUST flag one and MUST NOT flag the other. Without
#      this, a scan program that matches nothing prints case 1's "ok" forever.
#   3. unit — assert_loop_ran raises an ERROR on a zero count and stays silent
#      on a positive one.
#   4. end-to-end — the real check-doctor.sh, run against a fixture with NO
#      writable temp dir, must not go silent about a kit path its formatter
#      config fails to cover.
#
# Runnable standalone and picked up by check-harness's own check #6.
set -uo pipefail

# Guarded mktemp: this script lives in the very floor check #5b scans, so its
# own scratch path must be safe (explicit XXXXXX template + failure guard) or
# it would self-fail that check.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-check-loops.XXXXXX") || exit 1
# Case 3 makes a directory unwritable on purpose; restore write before the
# recursive delete or the cleanup itself fails.
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# Every glob root is resolved and checked SEPARATELY, and a root that does not
# resolve is fatal. `$(cd … && pwd)` prints nothing and writes only to stderr
# when its directory is gone, so an unguarded root degrades silently to a bare
# `/*.sh` glob — and because the sweep counted files globally, the surviving
# roots kept that count positive and the narrowing went unreported. Moving
# hooks/ aside was demonstrated to hide an unmarked reader exactly that way.
_resolve_dir() {
    (cd "$1" 2>/dev/null && pwd)
}
_SELF_DIR=$(dirname "$0")
LIB_SRC=$(_resolve_dir "$_SELF_DIR/../lib")
HOOK_SRC=$(_resolve_dir "$_SELF_DIR/../hooks")
TEST_SRC=$(_resolve_dir "$_SELF_DIR/../tests")
HARNESS_DIR=$(_resolve_dir "$_SELF_DIR/..")
ROOT_DIR=$(_resolve_dir "$_SELF_DIR/../../..")
_root_fail=0
for _pair in "lib:$LIB_SRC" "hooks:$HOOK_SRC" "tests:$TEST_SRC" \
    "entrypoints:$HARNESS_DIR" "repo-root:$ROOT_DIR"; do
    [ -n "${_pair#*:}" ] && continue
    echo "FAIL: test-check-loops — scan root '${_pair%%:*}' does not resolve; the sweep would silently narrow to the surviving roots"
    _root_fail=1
done
[ "$_root_fail" -eq 0 ] || exit 1
PIN_FILE="$ROOT_DIR/scripts/harness/.harness-manifest"
fails=0
# Counted so a skipped case can never hide behind a silent exit 0.
skips=0

# has <haystack> <needle> — pure-shell substring test. `printf | grep -qF` is
# banned here for the same reason as in the check families: grep -q exits on
# first match, and under an inherited IGNORED SIGPIPE printf's EPIPE becomes a
# nonzero status that pipefail turns into a phantom failure — precisely when the
# needle WAS found.
has() {
    case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

# --- 1. structural: no undocumented here-doc-fed loop in the check mechanism --
# A loop that exits early (`return`/`break` on the first hit) must NOT be
# converted: the `printf` writer would take an EPIPE under an inherited-ignored
# SIGPIPE, the phantom-failure mode this repo hit twice. Those sites stay
# here-docs and say so in a comment; every other one is a latent fail-open.
# The marker is what separates "considered and kept" from "not yet looked at".
#
# The marker must appear in the contiguous comment block IMMEDIATELY above the
# reader, not merely somewhere nearby. A fixed look-behind window was the first
# cut and it was wrong twice over: an unmarked loop within the window of an
# unrelated marker was excused (two here-doc loops in adjacent functions is all
# it takes), and a marker at the far edge of the window was dropped. Tying the
# marker to the adjacent comment block has no window to get wrong.
#
# Scope is EVERY shell file in the harness tree — lib/, hooks/, tests/, and the
# extensionless entry points (bootstrap, verify, sync, check-*, ...) — because
# the entry points are exactly where the first version of this scan missed a
# live `read -r ... <<LINE` in verify's gates.conf parser. Both fed forms are
# matched: `done <<`/`<<<` (loops) and `read ... <<` (single reads).
# `done < <(...)` is deliberately NOT matched — the `< <` there is a redirect
# from process substitution, which is the fix, not the defect.
MARKER="DELIBERATELY still a here-doc"
scan_prog='
    function verdict() {
        if (index(block, marker) == 0) printf "%s:%d\n", FILENAME, FNR
        block = ""; pending = 0
    }
    FNR == 1 { block = ""; pending = 0 }
    /^[[:space:]]*#/ { block = block $0 "\n"; pending = 0; next }
    # `done \` + a continuation line starting with `<<` is the same defect
    # wearing a line break; carry the comment block across to the redirect.
    pending && /^[[:space:]]*<</ { verdict(); next }
    /^[[:space:]]*done[[:space:]]*<</ { verdict(); next }
    /^[[:space:]]*read[[:space:]][^<]*<</ { verdict(); next }
    /^[[:space:]]*done[[:space:]]*\\[[:space:]]*$/ { pending = 1; next }
    { block = ""; pending = 0 }
'

# _sha <file> — the manifest's checksum tool selection, mirrored.
_sha() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    fi
}

# kit_owned <abs-path> — 0 when the integrity manifest pins this file AND its
# checksum still matches, i.e. the kit is accountable for its contents. A
# '# tailored' pin, a drifted file, or no pin at all means the REPO owns it, and
# the kit's update mode deliberately leaves those alone (harness_update_decision
# returns 'diff' for both cases). Hard-failing an adopter's build over a file the
# upgrade pointedly did not replace would be a demand they cannot satisfy by
# upgrading — so those are reported as notes instead. In the kit's own repo every
# mechanism file is pinned and pristine, so this scan runs at full strength there.
kit_owned() {
    local abs="$1" rel line want have
    rel=${abs#"$ROOT_DIR"/}
    [ -f "$PIN_FILE" ] || return 0
    line=$(awk -v p="$rel" '$2 == p {print; exit}' "$PIN_FILE")
    [ -n "$line" ] || return 1
    case "$line" in *"# tailored"*) return 1 ;; esac
    want=${line%% *}
    have=$(_sha "$abs")
    [ -n "$have" ] || return 0
    [ "$have" = "$want" ]
}

undocumented=""
skipped=""
# This test is the guard against checks that report success having examined
# nothing, so it may not do that itself: count what the scan actually read, and
# never discard awk's exit status or its stderr (a broken $scan_prog would
# otherwise yield empty hits on every file and print the "ok" below).
scanned=0
scan_errors=0
read_errors=0
root_gaps=0
# _scan_root <label> <path…> — sweep ONE glob root and require it to have
# yielded at least one shell file. Per-root is the only honest unit: a single
# global count cannot see one root vanish, because the other three hold it
# above zero while the files that root was supposed to cover go unexamined.
_scan_root() {
    local label="$1"
    shift
    local n=0
    for _f in "$@"; do
        [ -f "$_f" ] || continue
        # Shell files only: kit-manifest, provider-caps and harness.conf carry
        # no shebang and are not code this scan can reason about. The READ and
        # the MATCH are separate steps on purpose: `head … | grep -q` made both
        # "could not open the file" and "not a shell file" the same nonzero
        # status under pipefail, so an unreadable mechanism file was skipped in
        # silence while the other files kept this root's counter positive — and
        # an unreadable mechanism file is exactly what the mode defect in issue
        # #20 produced. The match itself is a case, not a grep pipe, per the
        # no-grep-pipes rule at the top of this file.
        _first=$(head -n 1 "$_f" 2>/dev/null)
        _hrc=$?
        if [ "$_hrc" -ne 0 ]; then
            echo "FAIL: test-check-loops — could not read $_f (head rc=$_hrc); an unreadable mechanism file is not the same thing as a non-shell one, and skipping it silently is the fail-open this test exists to stop"
            read_errors=$((read_errors + 1))
            fails=$((fails + 1))
            continue
        fi
        case "$_first" in
        '#!'*sh*) ;;
        *) continue ;;
        esac
        n=$((n + 1))
        scanned=$((scanned + 1))
        _hits=$(awk -v marker="$MARKER" "$scan_prog" "$_f" 2>"$WORK/scan.err")
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            echo "FAIL: test-check-loops — scanner failed on $_f (awk rc=$_rc):"
            sed 's/^/        /' "$WORK/scan.err" 2>/dev/null
            scan_errors=$((scan_errors + 1))
            fails=$((fails + 1))
            continue
        fi
        [ -n "$_hits" ] || continue
        if kit_owned "$_f"; then
            undocumented="${undocumented}${_hits}"$'\n'
        else
            skipped="${skipped}${_hits}"$'\n'
        fi
    done
    if [ "$n" -eq 0 ]; then
        echo "FAIL: test-check-loops — scan root '$label' contributed zero shell files — that root moved or the shebang filter broke, and everything under it went unexamined"
        root_gaps=$((root_gaps + 1))
        fails=$((fails + 1))
    fi
}
_scan_root lib "$LIB_SRC"/*.sh
_scan_root hooks "$HOOK_SRC"/*.sh
_scan_root tests "$TEST_SRC"/*.sh
_scan_root entrypoints "$HARNESS_DIR"/*
undocumented=$(printf '%s' "$undocumented" | sed '/^$/d')
skipped=$(printf '%s' "$skipped" | sed '/^$/d')

# Same philosophy as assert_loop_ran: an empty finding list is only evidence
# when the loop that produces it ran at all.
if [ "$scanned" -eq 0 ]; then
    echo "FAIL: test-check-loops — scan loop examined zero files — glob roots moved or shebang filter broke"
    fails=$((fails + 1))
fi

# Never silent about what was not checked.
if [ -n "$skipped" ]; then
    echo "note: test-check-loops — repo-owned ('# tailored' or locally drifted) file(s) not held to this rule; the kit's update mode does not replace them, so folding the fix forward is the repo's call:"
    printf '%s\n' "$skipped" | sed 's/^/        /'
fi
if [ "$scan_errors" -ne 0 ] || [ "$read_errors" -ne 0 ] || [ "$scanned" -eq 0 ] \
    || [ "$root_gaps" -ne 0 ]; then
    echo "FAIL: test-check-loops — structural ok withheld: $scanned file(s) examined, $root_gaps glob root(s) empty, $read_errors file(s) that could not be opened, $scan_errors file(s) the scanner could not process (see above); an empty finding list is not evidence"
elif [ -z "$undocumented" ]; then
    echo "ok: test-check-loops — every surviving here-doc-fed reader is marked deliberate"
fi
if [ -n "$undocumented" ]; then
    echo "FAIL: test-check-loops — here-doc-fed reader(s) with no '$MARKER' comment:"
    printf '%s\n' "$undocumented" | sed 's/^/        /'
    echo "        A here-doc needs a temp file; when one cannot be created the read is"
    echo "        silently skipped and its check reports success. Either feed it with"
    echo "        \`< <(printf '%s\\n' \"\$var\")\` plus an assert_loop_ran counter (or plain"
    echo "        parameter expansion for a single read), or — if it exits early, where"
    echo "        process substitution risks an ignored-SIGPIPE EPIPE — keep the here-doc"
    echo "        and say so with a '$MARKER' comment."
    fails=$((fails + 1))
fi

# --- 2. positive control: the scanner of case 1 must be falsifiable ----------
# Case 1 reports by ABSENCE of findings — the exact shape that fails open. A
# scan program that matches nothing, or an awk that never ran, prints its "ok"
# having proven nothing. So run the same program against fixtures whose verdict
# is known in advance and demand the precise `file:line`, not merely non-empty
# output: exactness is what pins the program against silent drift.
#
# EVERY match rule needs its own fixture. The swept tree happens to contain only
# `done <<` sites today, so case 1 gives the other two rules no incidental
# coverage at all — deleting the `read … <<` rule, or the continuation pair,
# left the whole test green. That `read … <<` rule is there because the first
# version of this scan MISSED a live one in verify's gates.conf parser; a
# control that cannot see it removed is not a control.
#
# The fixture bodies are printf-built with every trigger token held in a
# variable ("$_d" done, "$_r" read, "$_h" <<), never as a here-doc body: case 1
# sweeps tests/*.sh, THIS FILE INCLUDED, so a literal `done <<`, `read … <<`,
# `done \` or a bare `<<` continuation at the start of a line in this source
# would make the test flag itself. The fixtures live under $WORK, outside every
# glob root of case 1, so they are invisible to it — deliberately.
mkdir -p "$WORK/fixtures"
_d='done'
_r='read'
_h='<<'
_fx_write() {
    # $1 = destination path, $2 = form, $3 = comment line above the reader.
    # The reader's line number per form is asserted by the caller.
    case "$2" in
    loop)
        # 1 shebang / 2 while / 3 body / 4 comment / 5 READER / 6 data / 7 end
        {
            printf '#!/usr/bin/env bash\n'
            printf 'while %s -r _line; do\n' "$_r"
            printf '    printf "%%s\\n" "$_line"\n'
            printf '%s\n' "$3"
            printf '%s %sFXEOF\n' "$_d" "$_h"
            printf 'x\n'
            printf 'FXEOF\n'
        } > "$1"
        ;;
    single-read)
        # 1 shebang / 2 comment / 3 READER / 4 data / 5 end
        {
            printf '#!/usr/bin/env bash\n'
            printf '%s\n' "$3"
            printf '%s -r a b %sFXEOF\n' "$_r" "$_h"
            printf 'x y\n'
            printf 'FXEOF\n'
        } > "$1"
        ;;
    continuation)
        # The same defect wearing a line break.
        # 1 shebang / 2 while / 3 body / 4 `done \` / 5 READER / 6 data / 7 end
        {
            printf '#!/usr/bin/env bash\n'
            printf 'while %s -r _line; do\n' "$_r"
            printf '    printf "%%s\\n" "$_line"\n'
            printf '%s \\\n' "$_d"
            printf '    %sFXEOF\n' "$_h"
            printf 'x\n'
            printf 'FXEOF\n'
        } > "$1"
        ;;
    stale-marker)
        # A marked comment block, then a non-comment line, then an UNMARKED
        # reader. The marker is 4 lines up: any fixed look-behind window would
        # excuse this reader, which is the bug the adjacent-comment-block rule
        # replaced. It must still be flagged.
        # 1 shebang / 2 marker / 3 x=1 / 4 while / 5 body / 6 READER / 7-8 data
        {
            printf '#!/usr/bin/env bash\n'
            printf '# %s: this marker documents the assignment, not the reader.\n' "$MARKER"
            printf 'x=1\n'
            printf 'while %s -r _line; do\n' "$_r"
            printf '    printf "%%s\\n" "$_line"\n'
            printf '%s %sFXEOF\n' "$_d" "$_h"
            printf 'x\n'
            printf 'FXEOF\n'
        } > "$1"
        ;;
    esac
}

# _pc_expect <label> <fixture> <exact expected stdout> — one ok/FAIL pair.
_pc_expect() {
    local out rc
    out=$(awk -v marker="$MARKER" "$scan_prog" "$2" 2>"$WORK/pc.err")
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "$3" ]; then
        echo "ok: test-check-loops — $1"
        return 0
    fi
    echo "FAIL: test-check-loops — $1 — expected '$3' (awk rc=$rc), got:"
    printf '%s\n' "$out" | sed 's/^/        /'
    sed 's/^/        /' "$WORK/pc.err" 2>/dev/null
    echo "        Case 1 reports by absence of findings; a scanner that can no"
    echo "        longer produce this finding makes that \"ok\" meaningless."
    fails=$((fails + 1))
}

_fx_marked="$WORK/fixtures/marked.sh"
_fx_unmarked="$WORK/fixtures/unmarked.sh"
_fx_single="$WORK/fixtures/single-read.sh"
_fx_cont="$WORK/fixtures/continuation.sh"
_fx_stale="$WORK/fixtures/stale-marker.sh"
_fx_plain="# an ordinary comment saying nothing about the redirection"
_fx_write "$_fx_marked" loop "# $MARKER: this reader returns on the first hit."
_fx_write "$_fx_unmarked" loop "$_fx_plain"
_fx_write "$_fx_single" single-read "$_fx_plain"
_fx_write "$_fx_cont" continuation ""
_fx_write "$_fx_stale" stale-marker ""

_pc_expect "the scanner leaves a marked here-doc reader alone" "$_fx_marked" ""
_pc_expect "the scanner still finds an unmarked here-doc reader" "$_fx_unmarked" "$_fx_unmarked:5"
_pc_expect "the scanner still finds an unmarked single-read here-doc" "$_fx_single" "$_fx_single:3"
_pc_expect "the scanner still finds a line-continued here-doc redirect" "$_fx_cont" "$_fx_cont:5"
_pc_expect "a marker outside the reader's own comment block does not excuse it" "$_fx_stale" "$_fx_stale:6"

# --- 3. unit: assert_loop_ran ------------------------------------------------
# The probe sits at lib/ depth so check-common.sh's own $0-relative ROOT
# resolution lands on the fixture root, exactly as it does for a real family.
mkdir -p "$WORK/unit/scripts/harness/lib"
cp "$LIB_SRC/check-common.sh" "$WORK/unit/scripts/harness/lib/check-common.sh"
cat > "$WORK/unit/scripts/harness/lib/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"
assert_loop_ran 0 "probe check"
echo "after-zero ERRORS=$ERRORS"
assert_loop_ran 4 "probe check"
echo "after-positive ERRORS=$ERRORS"
PROBE
unit_out=$(bash "$WORK/unit/scripts/harness/lib/probe.sh" 2>&1)
if has "$unit_out" "ERROR: probe check did not run" \
    && has "$unit_out" "after-zero ERRORS=1" \
    && has "$unit_out" "after-positive ERRORS=1"; then
    echo "ok: test-check-loops — assert_loop_ran errors on a zero count and is silent otherwise"
else
    echo "FAIL: test-check-loops — assert_loop_ran did not behave as specified, got:"
    printf '%s\n' "$unit_out" | sed 's/^/        /'
    fails=$((fails + 1))
fi

# --- 4. end-to-end: a real family with nowhere to write a here-doc temp ------
# check-doctor's #10e is the cheapest family to stand up (no jq, no git, no sha
# tool: its manifest read only needs each line's first field to LOOK like a
# sha256) and its warning-only severity makes the failure mode the quiet half of
# the class — a skipped loop cost no exit code, it just deleted the warning.
E2E="$WORK/e2e"
mkdir -p "$E2E/scripts/harness/lib" "$E2E/scripts/harness/hooks"
cp "$LIB_SRC/check-common.sh" "$LIB_SRC/check-doctor.sh" "$E2E/scripts/harness/lib/"
# A .md pin is what makes #10e collapse the manifest into the "scripts/harness"
# kit path at all (see _10e_formatter_parseable) — a .sh-only manifest derives
# no root and the case would silently stop exercising anything.
printf '# harness-kit 0.0.0\n%064d  scripts/harness/README.md\n' 0 \
    > "$E2E/scripts/harness/.harness-manifest"
printf '# readme\n' > "$E2E/scripts/harness/README.md"
: > "$E2E/.prettierrc"
printf 'node_modules/\n' > "$E2E/.prettierignore"

NOTEMP="$E2E/no-writable-temp"
mkdir -p "$NOTEMP" && chmod 500 "$NOTEMP"
# Mode 500 does not stop a process with DAC override — root in a container
# writes to it regardless, the here-doc succeeds, and the case would "pass"
# having exercised nothing. Prove the directory is really unwritable first, and
# SKIP loudly if it is not. A test that cannot set up its own precondition must
# say so; silence is what this whole change exists to stamp out.
if ( : > "$NOTEMP/.probe" ) 2>/dev/null; then
    rm -f "$NOTEMP/.probe"
    chmod 700 "$NOTEMP"
    skips=$((skips + 1))
    echo "SKIP: test-check-loops — this process can write to a mode-500 directory (DAC override, e.g. running as root), so the no-writable-temp case cannot be set up here"
else
    # check-doctor.sh takes its ROOT from $0 and opens no temp file of its own,
    # so the CWD here only supplies the here-doc fallback the failure needs.
    e2e_out=$(cd "$NOTEMP" && TMPDIR="$NOTEMP" bash "$E2E/scripts/harness/lib/check-doctor.sh" 2>&1)
    chmod 700 "$NOTEMP"
    # Either outcome is correct: the loop ran (the coverage WARNING), or it
    # could not be fed and said so (the assert_loop_ran ERROR). Silence is the bug.
    if has "$e2e_out" "does not cover kit-owned path" || has "$e2e_out" "did not run"; then
        echo "ok: test-check-loops — an unbackable redirection cannot silence a check family"
    else
        echo "FAIL: test-check-loops — check-doctor went SILENT with no writable temp dir;"
        echo "        expected the kit-path coverage WARNING or the did-not-run ERROR, got:"
        printf '%s\n' "$e2e_out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
fi

[ "$fails" -eq 0 ] || exit 1
[ "$skips" -eq 0 ] || echo "PASSED: all check-loops cases that ran ($skips skipped)"
exit 0
