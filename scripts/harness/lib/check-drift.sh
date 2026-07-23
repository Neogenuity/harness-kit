#!/usr/bin/env bash
# check-drift.sh — the "drift" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/detect-drift. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

# 9. Mechanism files must match scripts/harness/.harness-manifest (kit version plus
#    sha256 per file, written at init). An un-pinned edit — agent, human, or
#    merge — fails CI, so nobody can quietly rewrite a guard. Lines ending in
#    '# tailored' are deliberate local forks: still checksum-verified here
#    (integrity), but never auto-replaced by the kit's update mode and exempt
#    from template-equality checks (ownership) — the marker changes who may
#    rewrite the file, not whether edits must be pinned.
#    Because shell edits (rm, sed -i, `: >`) are unscanned by the guards by
#    design, this manifest is the enforcing layer for them — so it is defended on
#    three fronts, all against an adopted repo (scripts/harness/hooks/ present): (9b) a
#    missing / emptied / all-malformed manifest is an ERROR, not a silent skip;
#    (9a) a nonempty malformed line does not count as a pin; and (9c) every
#    mechanism file on disk must be pinned, so *partial* pin deletion (un-pinning
#    one guard while leaving others) is caught. A brand-new repo that has not run
#    init yet (no scripts/harness/hooks/) still skips.
# sha256_of and MANIFEST come from check-common.sh.

# 9a. Verify each pinned file, and REJECT malformed entries. A well-formed line is
#     "<64-hex sha256>  <path>"; a nonempty garbage line (e.g. `x`) must not count
#     as a pin — otherwise it would satisfy the adopted-repo guard (9b) while
#     enforcing nothing. valid_pins counts only well-formed entries.
valid_pins=0
if [ -f "$MANIFEST" ] && [ -n "$(sha256_of "$MANIFEST")" ]; then
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        want=${line%% *}
        path=$(printf '%s\n' "$line" | awk '{print $2}')
        if ! printf '%s' "$want" | grep -qE '^[0-9a-fA-F]{64}$' || [ -z "$path" ]; then
            echo "ERROR: scripts/harness/.harness-manifest has a malformed entry (expected '<sha256>  <path>'): '$line'"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        valid_pins=$((valid_pins + 1))
        if [ ! -f "$ROOT/$path" ]; then
            echo "ERROR: scripts/harness/.harness-manifest lists '$path' but it does not exist — restore the file or remove the manifest line"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        have=$(sha256_of "$ROOT/$path")
        if [ "$have" != "$want" ]; then
            case "$line" in
                *"# tailored"*)
                    echo "ERROR: '$path' does not match its scripts/harness/.harness-manifest pin — tailored files are still checksum-verified ('# tailored' only exempts them from template replacement). If the change is intentional, re-pin its line (shasum -a 256 $path), keeping the ' # tailored' marker" ;;
                *)
                    echo "ERROR: '$path' does not match scripts/harness/.harness-manifest. If the change is intentional, re-pin its line (shasum -a 256 $path) — append ' # tailored' for a deliberate fork the kit's update mode must never overwrite" ;;
            esac
            ERRORS=$((ERRORS + 1))
        fi
    done < "$MANIFEST"
fi

# 9b. An adopted repo (scripts/harness/hooks/ present) must have a manifest carrying at
#     least one VALID pin. Catches a missing, emptied/header-only, or all-malformed
#     manifest — each collapses the enforcing layer for shell edits. Pre-adoption
#     repos (no scripts/harness/hooks/) still skip.
if [ -d "$ROOT/scripts/harness/hooks" ] && [ "$valid_pins" -eq 0 ]; then
    echo "ERROR: harness is adopted (scripts/harness/hooks/ present) but scripts/harness/.harness-manifest is missing or has no valid pinned entries — it is the integrity pin for the mechanism (the enforcing layer for shell edits the guards can't scan); a deleted, emptied, or malformed manifest lets guards be rewritten undetected. Restore it (re-pin per the kit's init step 8)"
    ERRORS=$((ERRORS + 1))
fi

# 9c. Manifest COMPLETENESS: every mechanism file present on disk must be pinned.
#     The expected set is the FILESYSTEM crossed with the SHIP CONTRACT
#     (scripts/harness/kit-manifest) — never the integrity manifest itself (which is
#     what an attacker edits): a file must be on disk to run, so if it is on
#     disk and the kit-manifest declares it in an installing layer (mechanism,
#     policy, optional-policy), it must be pinned. The scripts/harness tree is
#     taken from disk wholesale, so a repo-local addition to it (an extra
#     hook, a local command) must be pinned too. This closes
#     *partial* pin deletion: removing the manifest line for a still-present
#     guard (leaving other pins, so 9b passes) would otherwise silently exempt
#     that guard from checksum verification. Before v0.21.0 the expected set
#     was a hard-coded mirror of install-lib.sh's inventory lists; the shipped
#     kit-manifest replaced both copies. Gated on scripts/harness/hooks/ present
#     (adopted — to dodge it an attacker would have to delete the guards
#     themselves) AND a readable kit-manifest: a missing kit-manifest is its
#     own ERROR (#9d), so this check never guesses at the expected set.
if [ -f "$MANIFEST" ] && [ -d "$ROOT/scripts/harness/hooks" ] && [ -f "$ROOT/scripts/harness/kit-manifest" ]; then
    pinned_paths=$(awk '$1 ~ /^[0-9a-fA-F]{64}$/ {print $2}' "$MANIFEST")
    expected_paths=$(
        { find "$ROOT/scripts/harness" -type f \
              ! -name '.harness-manifest' ! -name '.hm.new' 2>/dev/null \
              | sed "s|^$ROOT/||"
          awk '$1=="mechanism" || $1=="policy" || $1=="optional-policy" {print $2}' \
              "$ROOT/scripts/harness/kit-manifest"
        } | sort -u
    )
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        # The ship contract installs under scripts/ and the two repo-owned
        # .harness/ policy homes; ignore anything else a malformed
        # kit-manifest line might name.
        case "$rel" in scripts/*|.harness/gates.conf|.harness/hooks/*) ;; *) continue ;; esac
        [ -f "$ROOT/$rel" ] || continue
        # Pipe-free exact-line membership test. `printf ... | grep -q` is
        # banned in this script: grep -q exits on first match, and when the
        # process tree inherits an IGNORED SIGPIPE (GitHub's Actions runner
        # does this), printf survives the EPIPE with a nonzero status that
        # pipefail then turns into a phantom failure — precisely when the
        # entry WAS found. Caught live twice (v0.16.0 macOS, v0.20.0 ubuntu),
        # both inside fixture checkers at peak parallel-gate load.
        case $'\n'"$pinned_paths"$'\n' in
            *$'\n'"$rel"$'\n'*) ;;
            *)
                echo "ERROR: mechanism file '$rel' is present but not pinned in scripts/harness/.harness-manifest — every mechanism file on disk must be integrity-pinned; an unpinned file is silently exempt from checksum verification. Re-pin it (init step 8)"
                ERRORS=$((ERRORS + 1)) ;;
        esac
    done <<EOF
$expected_paths
EOF
fi

# 9d. Ship contract: an adopted repo must carry scripts/harness/kit-manifest — present,
#     parseable, and declaring a non-empty shipped set. It is the file #9c
#     derives its expected set from and update mode derives replace/add/remove
#     decisions from, and it is itself pinned mechanism (#9a) and
#     guard-protected. Retired paths still on disk are surfaced as WARNINGs,
#     not ERRORs: update deliberately keeps a drifted copy for manual review
#     (retirement must never delete local changes), and the warning is the
#     standing nudge that the review is still owed. A retired path pinned
#     ' # tailored' is the RESOLVED state — a deliberate repo-owned fork of a
#     file the kit stopped shipping (the kit repo's own maintainer-only
#     conformance suites are the canonical case) — so it does not warn:
#     warning forever on a resolved state trains people to ignore the
#     warning that matters.
if [ -d "$ROOT/scripts/harness/hooks" ]; then
    if [ ! -f "$ROOT/scripts/harness/kit-manifest" ]; then
        echo "ERROR: harness is adopted (scripts/harness/hooks/ present) but scripts/harness/kit-manifest is missing — it is the ship contract that completeness check #9c derives its expected file set from and the kit's update mode derives replace/add/remove decisions from; without it neither can run. Restore it via the kit's update mode, then re-pin"
        ERRORS=$((ERRORS + 1))
    else
        kit_shipped=$(awk '$1=="mechanism" || $1=="policy" {c++} END{print c+0}' "$ROOT/scripts/harness/kit-manifest")
        if [ "$kit_shipped" -eq 0 ]; then
            echo "ERROR: scripts/harness/kit-manifest declares no shipped entries — an emptied or malformed ship contract disarms completeness check #9c exactly like a deleted one. Restore it via the kit's update mode, then re-pin"
            ERRORS=$((ERRORS + 1))
        fi
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            [ -f "$ROOT/$rel" ] || continue
            # A ' # tailored' pin on a retired path is a deliberate,
            # integrity-verified fork — resolved, no warning.
            if [ -f "$MANIFEST" ] \
                    && awk -v p="$rel" '$2 == p && /# tailored$/ {found=1} END {exit !found}' "$MANIFEST"; then
                continue
            fi
            echo "WARNING: retired path '$rel' is still present — the kit no longer ships it; update keeps drifted copies for manual review. Fold your local changes forward and delete the file (or keep it deliberately by re-pinning its line ' # tailored')"
        done <<EOF
$(awk '$1=="retired" {print $2}' "$ROOT/scripts/harness/kit-manifest")
EOF
    fi
fi


check_trailer "drift"
