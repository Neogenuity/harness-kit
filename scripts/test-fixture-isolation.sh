#!/usr/bin/env bash
# Regression test: a failed mktemp must ABORT a fixture, never fall back to the
# host repo. Runnable standalone and in CI.
#
# The bug this pins is not hypothetical — it put junk commits on this repo's own
# branch. Three facts compose into it:
#   1. bare `mktemp -d` ignores $TMPDIR on macOS (it resolves
#      _CS_DARWIN_USER_TEMP_DIR, i.e. /var/folders) and fails outright under a
#      sandbox that denies that path;
#   2. an unguarded `WORK=$(mktemp -d)` swallows that failure and leaves WORK
#      EMPTY — these suites run `set -uo pipefail`, so there is no `set -e` to
#      stop them;
#   3. bash `cd ""` is a silent rc=0 no-op that stays in the CURRENT directory.
# So `( cd "$WORK" && git init -q && git add -A && git commit )` commits the
# developer's working tree onto their checked-out branch.
#
# Method: build a throwaway git repo, put a mktemp on PATH that fails exactly
# the way the sandbox fails (exit 1, EMPTY stdout), run each real sibling test
# with CWD set to the throwaway repo, and assert its HEAD and porcelain are
# unchanged afterwards. The throwaway repo stands in for the host repo: because
# `cd ""` is a no-op, a leak lands there and this test sees it.
#
# Boundary, stated as plainly as check #8's "detects drift, does not prove
# equivalence": this catches any leak whose damage is SELF-CONTAINED (`git init`,
# `git add -A`, `git commit`, a stray write) — the class that actually put
# commits on this repo's main. It is NOT a universal oracle. A leak whose damage
# depends on host-repo FILES existing only lands if the canary has them, which is
# why new_canary copies the mechanism in rather than standing up a bare README.
# A leak that reads without writing, or writes only outside the repo, is out of
# scope by construction — porcelain is the detector.
#
# Two failure modes, because one does not imply the other:
#   all    — every mktemp fails. Pins the `|| exit 1` guard on the scratch base.
#   nested — the FIRST allocation is granted, every later one fails. Pins the
#            carve-outs, where `w=$(mktemp -d "$WORK/x.XXXXXX") || return 1`
#            inside a `F=$(make_fixture)` command substitution CANNOT abort the
#            caller: the subshell returns, the caller gets "", and the next
#            `cd "$F"` is back in the host repo. `${w:?}` at each cd/rm site is
#            the second line of defense.
#
# Boundary on "nested", measured rather than assumed: it fails the first
# carve-out a suite REACHES, so it pins that site and shadows every later one.
# Where a suite's first carve-out is a top-level `|| exit 1`, the suite aborts
# right there and the factory below it is never called — test-install-core.sh's
# emptypath alloc fires before its first `F=$(make_fixture)`, so this mode
# proves that guard and never enters make_fixture. test-install-update.sh,
# test-install-recovery.sh (no preflight allocation of their own — their first
# carve-out IS the fixture factory), and test-check-harness.sh have no earlier
# site, so their fixture factory IS entered, on every case. The shadowed half
# is not unguarded, it is guarded ELSEWHERE: check #5b is a static gate over
# this same file set and rejects a carve-out that loses its `|| return 1`
# (ERROR, and it runs before #6 launches these). Behavioral here, static
# there — neither alone covers both, which is why #5b is ordered ahead of #6
# rather than folded in.
#
# This test cannot fall for the bug it tests: its own base is allocated with the
# guarded form BEFORE any shim exists, the shim is applied per-invocation via
# `env PATH=...` and never exported, and every destructive expansion below is
# ${VAR:?}-hardened.
#
# Recursion needs no exclusion list, but not for the reason it first looks like.
# The grant budget is GLOBAL to a run_case process tree, not per-process:
# $SHIM_CALLS is one file every descendant appends to, so mode "all" grants
# nothing and mode "nested" grants exactly ONE allocation anywhere in the tree —
# whichever caller asks first consumes it. Do not "simplify" that to a
# per-process budget on the theory that fixtures always carve out of a base and
# so never need allocation 1: that theory is false. test-eval.sh allocates each
# of its roots straight from ${TMPDIR:-/tmp} and has no base to carve from, so
# nested does hand it a working fixture on allocation 1 and it runs for real.
# What stops it there is the shared counter — every path onward to a nested
# check-harness.sh needs a second allocation, and there is none. A broken mktemp
# is the recursion guard; the shared budget is what keeps it broken.
# Only this script excludes itself.
set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-fixture-isolation.XXXXXX") || exit 1
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: guarded mktemp returned an unusable path — refusing to run"
    exit 1
fi
trap 'rm -rf "${WORK:?}"' EXIT

CANARY="$WORK/canary"
SHIM="$WORK/shim"
CALLS="$WORK/mktemp-calls"
GRANTED="$WORK/granted"
CANARY_HEAD=""
CANARY_STATUS=""
MODE_CALLS=0
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

# The failing mktemp. One file serves both modes (behavior is env-driven), so
# nothing has to be escaped into it.
mkdir -p "$SHIM" || exit 1
cat > "$SHIM/mktemp" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SHIM_CALLS"
if [ "${SHIM_MODE:-all}" = "nested" ] \
        && [ "$(wc -l < "$SHIM_CALLS" | tr -d ' ')" -le 1 ]; then
    case " $* " in
        *" -d "*)
            mkdir -p "$SHIM_GRANTED" || exit 1
            printf '%s\n' "$SHIM_GRANTED"
            exit 0
            ;;
    esac
fi
exit 1
SHIM
chmod +x "$SHIM/mktemp" || exit 1
# The shim proves nothing unless it actually intercepts, and the failure mode is
# SILENT: bash skips a non-executable PATH entry without a word and falls through
# to the real mktemp. Every allocation then succeeds, the canary is never
# touched, and every case below "passes" without one failed mktemp — a green run
# asserting the opposite of what it claims. Verified: chmod -x on this one file
# turns the whole suite green. `chmod +x` is not enough on its own either (a
# no-exec mount or a mode-stripping filesystem can defeat it), so assert the
# postcondition here and count real interceptions per mode in run_mode.
if [ ! -x "$SHIM/mktemp" ]; then
    echo "FAIL: the mktemp shim is not executable — bash would silently skip it"
    exit 1
fi

# new_canary — a pristine throwaway repo standing in for the host repo, plus the
# exact baseline a leak would disturb. Rebuilt per case so one leak cannot
# cascade into false reports against every later script.
new_canary() {
    rm -rf "${CANARY:?}" "${GRANTED:?}"
    mkdir -p "$CANARY" || return 1
    git -C "$CANARY" init -q >/dev/null 2>&1 || return 1
    git -C "$CANARY" config user.email "fixture@example.invalid"
    git -C "$CANARY" config user.name "fixture"
    printf 'baseline\n' > "$CANARY/README.md"
    # The canary must look enough like the host repo that a REPO-RELATIVE leak
    # actually lands. A leak of the shape `( cd "$w" && bash scripts/X.sh )` with
    # an empty $w runs `bash scripts/X.sh` in the CWD — here, the canary. Against
    # a canary holding only README.md that dies "No such file or directory",
    # perturbs nothing, and the case would PASS while the leak is live. Copy the
    # mechanism in so the invocation resolves and its writes show up in porcelain
    # (sync-agent-skills.sh regenerates stubs and rm -rf's a directory — that is
    # the shape this covers). test-*.sh is deliberately NOT copied: a leaked
    # check-harness.sh run must not re-enter this suite.
    mkdir -p "$CANARY/scripts" || return 1
    for _m in "$SCRIPTS_DIR"/*.sh; do
        case "$(basename "$_m")" in test-*) continue ;; esac
        cp "$_m" "$CANARY/scripts/" 2>/dev/null || true
    done
    [ -d "$SCRIPTS_DIR/hooks" ] && cp -R "$SCRIPTS_DIR/hooks" "$CANARY/scripts/" 2>/dev/null
    rm -f "$CANARY"/scripts/hooks/test-*.sh 2>/dev/null
    [ -f "$SCRIPTS_DIR/harness.conf" ] && cp "$SCRIPTS_DIR/harness.conf" "$CANARY/scripts/" 2>/dev/null
    git -C "$CANARY" add -A >/dev/null 2>&1 || return 1
    git -C "$CANARY" commit -qm baseline >/dev/null 2>&1 || return 1
    CANARY_HEAD=$(git -C "$CANARY" rev-parse HEAD 2>/dev/null) || return 1
    CANARY_STATUS=$(git -C "$CANARY" status --porcelain 2>/dev/null)
    [ -n "$CANARY_HEAD" ]
}

# run_case <mode> <script> — 0 when the script left the host repo untouched.
run_case() {
    local mode="$1" script="$2"
    local rel out rc calls head_now status_now
    rel="${script#"$SCRIPTS_DIR"/}"
    if ! new_canary; then
        fail "could not build the canary repo for $rel [$mode]"
        return 1
    fi
    : > "$CALLS"
    # HARNESS_NESTED_FIXTURE is unset so each test-install-*.sh suite runs its
    # real body instead of exiting 0 with "skipped" — which would read as a
    # silent pass. PATH keeps its real tail: only mktemp is broken, exactly as
    # in the sandbox.
    out=$( cd "${CANARY:?}" && env -u HARNESS_NESTED_FIXTURE \
        PATH="$SHIM:$PATH" SHIM_CALLS="$CALLS" SHIM_MODE="$mode" \
        SHIM_GRANTED="$GRANTED" bash "$script" 2>&1 )
    rc=$?
    calls=$(wc -l < "$CALLS" | tr -d ' ')
    MODE_CALLS=$((MODE_CALLS + calls))
    head_now=$(git -C "$CANARY" rev-parse HEAD 2>/dev/null)
    status_now=$(git -C "$CANARY" status --porcelain 2>/dev/null)

    if [ "$head_now" != "$CANARY_HEAD" ] || [ "$status_now" != "$CANARY_STATUS" ]; then
        fail "$rel [$mode]: a failed mktemp fell back to the host repo"
        echo "        HEAD $CANARY_HEAD -> ${head_now:-<gone>}"
        git -C "$CANARY" log --oneline "$CANARY_HEAD..HEAD" 2>/dev/null \
            | sed 's/^/        leaked commit: /'
        printf '%s\n' "$status_now" | grep -v '^$' | sed 's/^/        leaked file:   /'
        return 1
    fi

    # A broken mktemp the script actually observed must not end in a green
    # report: the fixture never existed, so "passed" would be a lie. The shim's
    # call log is the oracle — a suite that never allocates scratch space
    # (calls == 0) has nothing to prove here, so it is not judged.
    if [ "$mode" = "all" ] && [ "$calls" -ge 1 ] && [ "$rc" -eq 0 ] \
            && ! printf '%s\n' "$out" | grep -q 'SKIP:'; then
        fail "$rel [$mode]: reported success (exit 0) though every mktemp failed"
        printf '%s\n' "$out" | tail -3 | sed 's/^/        /'
        return 1
    fi
    return 0
}

# run_mode <mode> — every sibling regression script, discovered by the same glob
# check-harness.sh check #6 uses, so a newly added suite is covered on arrival.
run_mode() {
    local mode="$1" script base ran=0 leaks=0
    MODE_CALLS=0
    for script in "$SCRIPTS_DIR"/test-*.sh "$SCRIPTS_DIR"/hooks/test-*.sh; do
        [ -f "$script" ] || continue
        base=$(basename "$script")
        [ "$base" = "$SELF" ] && continue
        # Mode "nested" concerns suites that carve a fixture OUT OF a base dir —
        # a template rooted at a plain "$VAR, not "${TMPDIR:-/tmp}. Those are the
        # only callers that can strand an empty path via `|| return 1` inside a
        # command substitution.
        #
        # This grep OVER-approximates that set, deliberately: it also matches an
        # unrelated "$var" elsewhere on an mktemp line (a `[ -z "$tmp" ]` guard
        # is enough), so a suite with only base allocations can be selected. That
        # is the safe direction to be wrong in. Over-selecting costs one extra
        # run of a suite whose guards then abort it; UNDER-selecting would drop a
        # real carve-out out of this mode silently, and nothing downstream would
        # notice. A tighter pattern would have to track quoting and ${} forms to
        # avoid exactly that, so the loose one stays.
        if [ "$mode" = "nested" ] && ! grep -qE 'mktemp .*"\$[A-Za-z_]' "$script"; then
            continue
        fi
        ran=$((ran + 1))
        run_case "$mode" "$script" || leaks=$((leaks + 1))
    done
    if [ "$ran" -eq 0 ]; then
        fail "[$mode] discovered no sibling test scripts — the glob went stale"
        return 1
    fi
    # Vacuity guard. `ran` proves the glob found scripts; it does NOT prove the
    # shim intercepted a single one. If PATH injection ever breaks — a skipped
    # non-executable shim, a refactor of the `env` line, a suite calling mktemp
    # by absolute path — every case runs against a real mktemp, perturbs nothing,
    # and passes. The suite would then certify isolation it never tested. One
    # interception per mode is the floor; a per-suite calls==0 stays legal above
    # (test-template-sync.sh allocates no scratch and has nothing to prove).
    if [ "$MODE_CALLS" -eq 0 ]; then
        fail "[$mode] the mktemp shim was never invoked across $ran suite(s) — PATH injection is broken, so this run proved nothing"
        return 1
    fi
    [ "$leaks" -eq 0 ] && pass "[$mode] $ran suite(s) aborted without touching the host repo"
    return 0
}

run_mode "all"
run_mode "nested"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails fixture-isolation case(s)"
    exit 1
fi
echo "OK: a failed mktemp aborts every fixture — the host repo stays untouched"
exit 0
