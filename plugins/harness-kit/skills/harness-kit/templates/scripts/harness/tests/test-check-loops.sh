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

LIB_SRC="$(cd "$(dirname "$0")/../lib" && pwd)"
HOOK_SRC="$(cd "$(dirname "$0")/../hooks" && pwd)"
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PIN_FILE="$ROOT_DIR/scripts/harness/.harness-manifest"
fails=0

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
for _f in "$LIB_SRC"/*.sh "$HOOK_SRC"/*.sh "$HARNESS_DIR"/tests/*.sh "$HARNESS_DIR"/*; do
    [ -f "$_f" ] || continue
    # Shell files only: kit-manifest, provider-caps and harness.conf carry no
    # shebang and are not code this scan can reason about.
    head -n 1 "$_f" 2>/dev/null | grep -q '^#!.*sh' || continue
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
if [ "$scan_errors" -ne 0 ]; then
    echo "FAIL: test-check-loops — $scan_errors file(s) the scanner could not read (see above); an empty finding list is not evidence, so the structural ok is withheld"
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
# having proven nothing. So run the same program against two fixtures whose
# verdict is known in advance and demand the precise result: the marked reader
# left alone, the unmarked one flagged at an exact line.
#
# The fixture bodies are written with printf, with the loop terminator held in
# "$_d", never as a here-doc body: case 1 sweeps tests/*.sh, THIS FILE
# INCLUDED, so a literal `done <<` at the start of a line in this source would
# make the test flag itself. The fixtures live under $WORK, outside every glob
# root of the case-1 loop, so they are invisible to it — deliberately.
mkdir -p "$WORK/fixtures"
_d='done'
_fx_write() {
    # $1 = destination path, $2 = the comment line immediately above the reader.
    {
        printf '#!/usr/bin/env bash\n'
        printf 'while read -r _line; do\n'
        printf '    printf "%%s\\n" "$_line"\n'
        printf '%s\n' "$2"
        printf '%s <<FXEOF\n' "$_d"
        printf 'x\n'
        printf 'FXEOF\n'
    } > "$1"
}
# The reader is line 5 of that 7-line body. Asserting the exact `file:line`
# rather than "non-empty" is what pins the scan program against silent drift.
FX_READER_LINE=5
_fx_marked="$WORK/fixtures/marked.sh"
_fx_unmarked="$WORK/fixtures/unmarked.sh"
_fx_write "$_fx_marked" "# $MARKER: this reader returns on the first hit."
_fx_write "$_fx_unmarked" "# an ordinary comment saying nothing about the redirection"

_pc_marked=$(awk -v marker="$MARKER" "$scan_prog" "$_fx_marked" 2>"$WORK/pc-marked.err")
_pc_marked_rc=$?
if [ "$_pc_marked_rc" -eq 0 ] && [ -z "$_pc_marked" ]; then
    echo "ok: test-check-loops — the scanner leaves a marked here-doc reader alone"
else
    echo "FAIL: test-check-loops — the scanner flagged a MARKED reader (awk rc=$_pc_marked_rc), got:"
    printf '%s\n' "$_pc_marked" | sed 's/^/        /'
    sed 's/^/        /' "$WORK/pc-marked.err" 2>/dev/null
    fails=$((fails + 1))
fi

_pc_want="$_fx_unmarked:$FX_READER_LINE"
_pc_unmarked=$(awk -v marker="$MARKER" "$scan_prog" "$_fx_unmarked" 2>"$WORK/pc-unmarked.err")
_pc_unmarked_rc=$?
if [ "$_pc_unmarked_rc" -eq 0 ] && [ "$_pc_unmarked" = "$_pc_want" ]; then
    echo "ok: test-check-loops — the scanner still finds an unmarked here-doc reader"
else
    echo "FAIL: test-check-loops — the scanner did not report the unmarked reader as '$_pc_want' (awk rc=$_pc_unmarked_rc), got:"
    printf '%s\n' "$_pc_unmarked" | sed 's/^/        /'
    sed 's/^/        /' "$WORK/pc-unmarked.err" 2>/dev/null
    echo "        Case 1 reports by absence of findings; a scanner that can no"
    echo "        longer produce this finding makes that \"ok\" meaningless."
    fails=$((fails + 1))
fi

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
    echo "skip: test-check-loops — this process can write to a mode-500 directory (DAC override, e.g. running as root), so the no-writable-temp case cannot be set up here"
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
exit 0
