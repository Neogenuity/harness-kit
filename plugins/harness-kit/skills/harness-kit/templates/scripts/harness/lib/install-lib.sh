#!/usr/bin/env bash
# install-lib.sh — the deterministic, model-free core of the kit's init/update
# workflow. Pure filesystem operations: copy the mechanism into place, keep
# .harness/ git-ignored, generate the integrity manifest, and decide (per
# manifest line) whether update mode may replace a file or must only diff it.
#
# The *authoring* half of init/update — writing AGENTS.md from the codebase,
# merging a hand-written .claude/settings.json without clobbering it, the audit
# gap table — is judgment and stays prose in the kit SKILL. It is deliberately
# NOT here: this file is only the part a test can pin without a model in the loop
# (the test-install-core.sh / test-install-update.sh / test-install-recovery.sh
# suites, sharing install-test-lib.sh, drive these functions against throwaway
# fixtures).
#
# Source it — it defines functions and runs nothing:
#   . scripts/harness/lib/install-lib.sh
# Compatible with macOS (BSD) and Linux (GNU). Hard dependencies: a sha256 tool
# (shasum or sha256sum, the same one check-harness needs) and mktemp (every
# copied file is staged with mktemp for a race-safe atomic write) — both are
# reported by harness_missing_prereqs and hard-gated by bootstrap.

# The shipped-file inventory lives in scripts/harness/kit-manifest — the declarative
# SHIP CONTRACT (layer + repo-relative path per line, plus a retired section).
# Every function below derives its file set from it; there are no hard-coded
# inventory lists (before v0.21.0 three shell-string lists lived here, with a
# fourth copy in check-harness.sh's check #9c). Ship a new file by adding a
# kit-manifest line; stop shipping one by moving its line to 'retired'.

# harness_kit_manifest_paths <kit_manifest_file> <layer...>
# Prints the repo-relative path of every kit-manifest entry whose layer field
# matches one of the given layers, in file order. Comment and blank lines are
# skipped; any fields after the path (src=/dest=) are ignored here.
# Missing file → prints nothing, returns 1.
harness_kit_manifest_paths() {
    local kmf="$1" layer path _rest want; shift
    [ -f "$kmf" ] || return 1
    while read -r layer path _rest; do
        case "$layer" in \#*|"") continue ;; esac
        [ -n "$path" ] || continue
        for want in "$@"; do
            [ "$layer" = "$want" ] && { printf '%s\n' "$path"; break; }
        done
    done < "$kmf"
    return 0
}

# _harness_kit_src_rel <kit_manifest_file> <repo-relative-path>
# Prints the entry's template source, relative to the kit's scripts/ tree:
# the src= field when the entry carries one, else the default derivation
# (the path with its leading `scripts/` stripped). This is how a shipped
# file whose installed location is outside scripts/ (.harness/gates.conf,
# the repo-owned policy hook) still has a template home.
_harness_kit_src_rel() {
    local kmf="$1" want="$2" layer path rest field
    [ -f "$kmf" ] || return 1
    while read -r layer path rest; do
        case "$layer" in \#*|"") continue ;; esac
        [ "$path" = "$want" ] || continue
        for field in $rest; do
            case "$field" in src=*) printf '%s\n' "${field#src=}"; return 0 ;; esac
        done
        printf '%s\n' "${want#scripts/}"
        return 0
    done < "$kmf"
    printf '%s\n' "${want#scripts/}"
    return 0
}

# harness_kit_shipped_paths <kit_manifest_file>
# The paths the kit SHIPS (copies at init, adds on update): the mechanism and
# policy layers. optional-policy is authored per repo (never copied) and
# retired is what update removes — neither ships.
harness_kit_shipped_paths() {
    harness_kit_manifest_paths "$1" mechanism policy
}

# harness_kit_is_diff_only <kit_manifest_file> <repo-relative-path>
# Returns 0 when update mode must never auto-overwrite <path> even while it is
# pristine and unmarked (the policy and optional-policy layers): a fresh
# install pins policy templates unmarked, and repo-owned gate/format/invariant
# policy must be reviewed, never silently replaced.
harness_kit_is_diff_only() {
    local kmf="$1" path="$2" p
    [ -f "$kmf" ] || return 1
    while IFS= read -r p; do
        [ "$p" = "$path" ] && return 0
    done < <(harness_kit_manifest_paths "$kmf" policy optional-policy)
    return 1
}

# _harness_path_sane <path>
# Returns 0 when <path> is safe to join under a root with "$root/$path":
# relative (no leading /) and free of '..' segments. Every kit-manifest path
# and src=/dest= value must pass — these strings reach cp, mv, and rm.
_harness_path_sane() {
    case "$1" in
        ""|/*) return 1 ;;
        ..|../*|*/..|*/../*) return 1 ;;
    esac
    return 0
}

# harness_validate_ship_contract <kit_manifest_file> <src_scripts_dir>
# Validates the SHIP CONTRACT before any filesystem operation trusts it.
# install/update/persist run this FIRST, so a malformed, truncated, or hostile
# kit-manifest is rejected before a single file is copied, replaced, or
# removed — never discovered midway through a partial mutation. Checks:
#   - every layer is known (mechanism|policy|optional-policy|content|retired):
#     a typo'd layer name would otherwise silently unship its file;
#   - every path and src=/dest= value is relative and '..'-free — these
#     strings are joined under the repo root and reach cp/mv/rm verbatim;
#   - no installed destination appears twice across the installing layers,
#     content dest= values, and the retired layer (a duplicate silently
#     last-write-wins; a shipped+retired pair would install then delete);
#   - every mechanism/policy entry's template source EXISTS under
#     <src_scripts_dir> (or at its installed home under the source tree's
#     parent — the same fallback harness_install_mechanism uses): a missing
#     declared source must abort loudly, never produce a partial install
#     that still reports success. optional-policy (authored per repo, never
#     copied) and content (the SKILL's authoring flow owns those sources)
#     are exempt from the source-existence check.
# Prints one "ERROR: kit-manifest line N: ..." per finding (all findings, not
# just the first) and returns 1 if any; 0 on a clean contract.
harness_validate_ship_contract() {
    local kmf="$1" src="$2" layer path rest field val lineno=0 bad=0
    local dests="" srcrel srcfile dup
    if [ ! -f "$kmf" ]; then
        echo "ERROR: kit-manifest: $kmf is missing — not a valid install source" >&2
        return 1
    fi
    while read -r layer path rest; do
        lineno=$((lineno + 1))
        case "$layer" in ""|\#*) continue ;; esac
        case "$layer" in
            mechanism|policy|optional-policy|content|retired) ;;
            *)
                echo "ERROR: kit-manifest line $lineno: unknown layer '$layer' — a typo'd layer silently unships its file; known layers: mechanism policy optional-policy content retired" >&2
                bad=1; continue ;;
        esac
        if [ -z "$path" ]; then
            echo "ERROR: kit-manifest line $lineno: layer '$layer' entry has no path" >&2
            bad=1; continue
        fi
        if ! _harness_path_sane "$path"; then
            echo "ERROR: kit-manifest line $lineno: unsafe path '$path' — must be relative with no '..' segments (it is joined under the repo root and passed to cp/rm)" >&2
            bad=1; continue
        fi
        srcrel=""
        for field in $rest; do
            case "$field" in
                src=*|dest=*)
                    val=${field#*=}
                    if ! _harness_path_sane "$val"; then
                        echo "ERROR: kit-manifest line $lineno: unsafe ${field%%=*}= value '$val' — must be relative with no '..' segments" >&2
                        bad=1
                    fi
                    case "$field" in
                        src=*) srcrel="$val" ;;
                        dest=*) [ -n "$val" ] && dests="$dests$val
" ;;
                    esac ;;
            esac
        done
        case "$layer" in
            mechanism|policy|optional-policy) dests="$dests$path
" ;;
            retired) dests="$dests$path
" ;;
        esac
        # Source existence: only the layers install actually copies.
        case "$layer" in
            mechanism|policy)
                [ -n "$srcrel" ] || srcrel="${path#scripts/}"
                srcfile="$src/$srcrel"
                [ -f "$srcfile" ] || srcfile="$src/../$path"
                if [ ! -f "$srcfile" ]; then
                    echo "ERROR: kit-manifest line $lineno: declared $layer file '$path' has no source under $src — a missing declared source would otherwise produce a silent partial install" >&2
                    bad=1
                fi ;;
        esac
    done < "$kmf"
    dup=$(printf '%s' "$dests" | sort | uniq -d)
    if [ -n "$dup" ]; then
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            echo "ERROR: kit-manifest: destination '$path' is declared more than once (duplicate entry, colliding content dest=, or a shipped+retired conflict) — one declaration per installed path" >&2
        done <<KDUP
$dup
KDUP
        bad=1
    fi
    return "$bad"
}

# _harness_sha256 <file...> — prints "<sha256>  <path>" lines, the manifest's
# own line format. Mirrors check-harness.sh's sha256_of tool selection.
_harness_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
    fi
}

# harness_missing_prereqs
# Prints, one per line, each runtime prerequisite the installed harness needs
# that is NOT on PATH: `jq` (WITHOUT IT EVERY GUARD HOOK FAILS OPEN — the whole
# in-turn feedback layer is silently inert, leaving only the native permission
# deny lists live), `git` (session-context banner + Codex hook Git-root
# resolution), `mktemp` (race-safe staging of every copied file — install cannot
# proceed without it), and a sha256 tool (`shasum`/`sha256sum`, the
# manifest-integrity check). Empty output = all present. jq/git are degrade-OK;
# mktemp and sha256 are hard-gated by bootstrap. init/update run this as an early PREFLIGHT
# and ask the user to ACKNOWLEDGE any gap before scaffolding a harness whose
# feedback layer would be inert; check-harness.sh's doctor keeps WARNing on the
# same condition afterward (check #10). Detection only — it does NOT change the
# guards' deliberate fail-open posture (a missing dep must degrade, never block a
# contributor's turn). No side effects, so a test pins it with no model in loop.
harness_missing_prereqs() {
    command -v jq     >/dev/null 2>&1 || printf 'jq\n'
    command -v git    >/dev/null 2>&1 || printf 'git\n'
    command -v mktemp >/dev/null 2>&1 || printf 'mktemp\n'
    if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
        printf 'sha256sum\n'
    fi
}

# harness_manifest_paths <repo_root>
# Prints the sorted, repo-relative paths the integrity manifest pins: the whole
# scripts/harness/hooks/ tree (filesystem-derived, so a repo-local hook added beside
# the shipped ones is pinned too) plus each PRESENT path the installed
# scripts/harness/kit-manifest declares in its shipped or optional-policy layers.
# Deterministic (sorted, de-duplicated), so two runs over the same tree produce
# byte-identical output. Requires scripts/harness/kit-manifest — a repo without one
# predates v0.21.0 and must run update (which installs it) before re-pinning;
# returning 1 here keeps the producers loud instead of emitting a header-only
# manifest.
harness_manifest_paths() {
    local p
    [ -f "$1/scripts/harness/kit-manifest" ] || return 1
    ( cd "$1" 2>/dev/null || return 1
      {
          # the whole kit dir from disk (also covers repo-local additions the
          # kit never shipped — a local hook or helper must be pinned too);
          # the integrity manifest itself and its rewrite temp are the only
          # exclusions
          find scripts/harness -type f ! -name '.harness-manifest' ! -name '.hm.new' 2>/dev/null
          { harness_kit_shipped_paths scripts/harness/kit-manifest
            harness_kit_manifest_paths scripts/harness/kit-manifest optional-policy
          } | while IFS= read -r p; do
              # everything under scripts/harness/ is pinned via the find above
              case "$p" in scripts/harness/*) continue ;; esac
              # if/fi, not `&&`: a trailing false file test must not become the
              # while's exit status — callers run under pipefail
              if [ -f "$p" ]; then printf '%s\n' "$p"; fi
          done
      } | sort -u
    )
}

# harness_generate_manifest <repo_root> <kit_version>
# Prints the .harness-manifest content: a "# harness-kit <version>" header then
# one "<sha256>  <path>" line per mechanism file. Pure stdout — the caller
# redirects it to scripts/harness/.harness-manifest. Does NOT emit '# tailored' markers
# (those are per-repo ownership decisions); use harness_repin_manifest to
# regenerate while preserving existing markers.
harness_generate_manifest() {
    local root="$1" version="$2" p
    if [ ! -f "$root/scripts/harness/kit-manifest" ]; then
        echo "harness_generate_manifest: $root/scripts/harness/kit-manifest missing — install the mechanism first (it ships the kit-manifest)" >&2
        return 1
    fi
    printf '# harness-kit %s\n' "$version"
    # harness_manifest_paths and the per-file hash each cd into $root from the
    # caller's cwd in their own subshell — never nested — so a relative $root
    # (not only "." or an absolute path) resolves correctly.
    harness_manifest_paths "$root" | while IFS= read -r p; do
        [ -n "$p" ] || continue
        ( cd "$root" 2>/dev/null && _harness_sha256 "$p" )
    done
}

# harness_repin_manifest <repo_root> <kit_version>
# Prints a regenerated manifest that PRESERVES the '# tailored' marker on every
# line that carried one before (update mode must never silently un-fork a file),
# AND carries forward tailored pins the shipped producer doesn't emit — a repo
# may pin its own local gates (e.g. a packaging or template-sync check) as
# '# tailored'; a re-pin must not silently drop those integrity pins. Emits a
# path-sorted union of the shipped mechanism set and any still-present
# previously-tailored path. Pure stdout — the caller redirects it.
harness_repin_manifest() {
    local root="$1" version="$2" mf="$1/scripts/harness/.harness-manifest"
    local old tailored=" " path allpaths
    if [ ! -f "$root/scripts/harness/kit-manifest" ]; then
        echo "harness_repin_manifest: $root/scripts/harness/kit-manifest missing — run update mode first (it installs the kit-manifest a re-pin derives its file set from)" >&2
        return 1
    fi
    if [ -f "$mf" ]; then
        while IFS= read -r old; do
            case "$old" in *"# tailored"*) ;; *) continue ;; esac
            path=$(printf '%s\n' "$old" | awk '{print $2}')
            [ -n "$path" ] && tailored="${tailored}${path} "
        done < "$mf"
    fi
    allpaths=$(
        { harness_manifest_paths "$root"
          for path in $tailored; do [ -f "$root/$path" ] && printf '%s\n' "$path"; done
        } | sort -u
    )
    printf '# harness-kit %s\n' "$version"
    printf '%s\n' "$allpaths" | while IFS= read -r path; do
        [ -n "$path" ] || continue
        line="$( cd "$root" 2>/dev/null && _harness_sha256 "$path" )"
        case "$tailored" in
            *" $path "*) printf '%s # tailored\n' "$line" ;;
            *)           printf '%s\n' "$line" ;;
        esac
    done
}

# harness_append_gitignore <repo_root>
# Ensures '.harness/var/' (runtime state: outcome log, persisted template
# bases, eval results, app runtime state) is git-ignored — and ONLY var/:
# the rest of .harness/ is committed repo policy (gates.conf, the policy
# hook). A pre-v0.23.0 install ignored the whole '.harness/' dir; that exact
# line is rewritten to the narrowed one (any other pattern a repo added is
# left alone). Idempotent — a second call is a no-op.
harness_append_gitignore() {
    local gi="$1/.gitignore"
    if [ -f "$gi" ] && grep -qxF '.harness/' "$gi"; then
        awk '$0 == ".harness/" { print ".harness/var/"; next } { print }' "$gi" > "$gi.hk.tmp" \
            && mv "$gi.hk.tmp" "$gi"
    fi
    if [ -f "$gi" ] && grep -qxF '.harness/var/' "$gi"; then return 0; fi
    # Start on a fresh line even if an existing .gitignore lacks a trailing
    # newline, so the entry never merges onto its last line
    # (e.g. node_modules -> node_modules.harness/var/).
    if [ -s "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ]; then
        printf '\n.harness/var/\n' >> "$gi"
    else
        printf '.harness/var/\n' >> "$gi"
    fi
}

# harness_conf_declared <repo_root> <VARNAME>
# Returns 0 if scripts/harness/harness.conf declares VARNAME (an uncommented
# `VARNAME=` assignment), 1 otherwise. Update/audit uses it to tell a legacy
# pre-declaration install (needs HOOK_WIRED_PROVIDERS / AGENT_PROVIDERS migrated
# in) from a current one — check-harness.sh fails loudly on the former.
harness_conf_declared() {
    local conf="$1/scripts/harness/harness.conf" var="$2"
    [ -f "$conf" ] || return 1
    grep -qE "^[[:space:]]*${var}=" "$conf"
}

# harness_conf_declare <repo_root> <VARNAME> <value>
# Idempotently ensure scripts/harness/harness.conf declares VARNAME="value". The value
# is the CALLER's (the user's confirmed choice from update/audit's proposal),
# NEVER inferred from whichever provider configs/stubs survive on disk — a config
# deleted before an upgrade is mechanically indistinguishable from one never
# wired, so adopting survivors would silently bless the deletion. If VARNAME is
# already declared this is a NO-OP: migration confirms the set ONCE, and a
# second update must neither duplicate the line nor reset a value the user has
# since edited. Appends when absent. Returns 1 if there is no harness.conf.
harness_conf_declare() {
    local conf="$1/scripts/harness/harness.conf" var="$2" value="$3"
    [ -f "$conf" ] || return 1
    harness_conf_declared "$1" "$var" && return 0
    printf '%s="%s"\n' "$var" "$value" >> "$conf"
}

# harness_install_mechanism <src_scripts_dir> <repo_root>
# Copies the shipped set — every path in the source kit-manifest's mechanism
# and policy layers, including the kit-manifest itself — from an existing
# scripts/ dir into <repo_root>/scripts and sets exec bits. Copies only the
# declared set, so a source dir that also carries repo-local scripts (a
# packaging gate, a template-sync check) does not leak them into the target.
# Touches only scripts/: hand-written content elsewhere (AGENTS.md, a
# .claude/settings.json) is never the installer's concern — that is the
# caller's authoring/merge step, so the "never clobber hand-written files"
# floor holds by construction. Returns 1 when the source has no kit-manifest
# (a pre-v0.21.0 template dir — not a valid install source for this library).
# _harness_copy_shipped <srcfile> <path> <root>
# Copy one shipped file into the tree and set its executable bit by the rule
# install and update both use (every *.sh, and any scripts/harness/ top-level
# command whose first bytes are a shebang). Returns non-zero — with an ERROR on
# stderr — on a copy OR chmod failure, so the caller can ABORT instead of
# reporting a false success. A silently-failed copy that still returned 0 was
# the defect behind the "partial upgrade re-pinned as success" hazard.
_harness_copy_shipped() {
    local srcfile="$1" p="$2" root="$3" destdir tmp destphys rootphys anc ancphys stagephys
    destdir="$root/$(dirname "$p")"
    # Never write through a symlink: a link at the destination — or a parent
    # directory that physically resolves outside the repo — would redirect a
    # trusted manifest path somewhere the ship contract never named.
    # Containment is checked against the ROOT's physical path, so a root that
    # itself lives under a symlink (macOS TMPDIR: /var/folders -> /private/var)
    # stays valid.
    #
    # The ancestor check runs BEFORE the mkdir, not only after: `mkdir -p`
    # follows a symlinked ancestor, so checking only the finished destdir
    # would have already created directories OUTSIDE the repo on the way to
    # refusing the copy. Walk to the deepest EXISTING ancestor and pin its
    # physical path first; the destphys check below then re-verifies the full
    # path mkdir actually produced.
    rootphys="$(cd "$root" 2>/dev/null && pwd -P)" || return 1
    anc="$destdir"
    while [ ! -d "$anc" ]; do anc="$(dirname "$anc")"; done
    ancphys="$(cd "$anc" 2>/dev/null && pwd -P)" || return 1
    case "$ancphys/" in
        "$rootphys"/*) ;;
        *)
            printf 'ERROR: harness: destination ancestor %s resolves outside the repo root %s — refusing to create directories through it\n' "$anc" "$rootphys" >&2
            return 1 ;;
    esac
    mkdir -p "$destdir" || return 1
    if [ -L "$root/$p" ]; then
        printf 'ERROR: harness: destination %s is a symlink — refusing to write through it\n' "$root/$p" >&2
        return 1
    fi
    destphys="$(cd "$destdir" 2>/dev/null && pwd -P)" || return 1
    case "$destphys/" in
        "$rootphys"/*) ;;
        *)
            printf 'ERROR: harness: destination dir %s resolves outside the repo root %s — refusing to write\n' "$destdir" "$rootphys" >&2
            return 1 ;;
    esac
    # Stage beside the destination, then rename: the tree never holds a
    # half-written mechanism file (a torn cp would read as local drift on the
    # next update — permanently kept — with no hint it was ever the kit's).
    # Same-directory mv is a rename(2), never a cross-filesystem copy. A
    # leftover stage file after a hard kill is caught loudly by completeness
    # check #9c (present-but-unpinned), which is the desired failure mode.
    #
    # The stage path is created with mktemp (O_EXCL), never a predictable
    # `.hk-stage.$$.<name>`: a guessable path let an attacker pre-plant a symlink
    # at it, and `cp` — which follows symlinks — would then write the shipped
    # bytes THROUGH the link into an arbitrary external file while the copy
    # reported success. Exclusive creation cannot open a pre-existing symlink.
    #
    # BOUNDARY: concurrent write access to destdir during an install/update is
    # OUTSIDE the threat model — a process that can write here can also write
    # guard-config.sh (or any mechanism file) directly, so the guard is already
    # defeated. Everything below is best-effort narrowing of the exploit surface,
    # NOT a complete race defense: `cp`/`mv` reopen `$tmp` by name and portable
    # shell has no open-with-O_NOFOLLOW, so a determined racer inside destdir can
    # still (a) swap `$tmp` to a symlink between the post-copy check and `mv`,
    # landing a symlink in the tree, or (b) symlink→cp→restore between the two
    # checks, letting one external write slip through. We do NOT claim to catch
    # those. What these checks DO buy: the predictable-name pre-plant (no race
    # needed) is fully closed by mktemp's O_EXCL, the stage file is confirmed to
    # resolve inside the repo (catching a destdir swapped before mktemp), and the
    # common lingering-symlink case is detected and aborted rather than silently
    # completed.
    tmp=$(mktemp "$destdir/.hk-stage.XXXXXX") || {
        printf 'ERROR: harness: failed to create a stage file in %s\n' "$destdir" >&2
        return 1
    }
    stagephys="$(cd "$(dirname "$tmp")" 2>/dev/null && pwd -P)" || { rm -f "$tmp"; return 1; }
    case "$stagephys/" in
        "$rootphys"/*) ;;
        *)
            printf 'ERROR: harness: stage file %s resolves outside the repo root %s — refusing to write\n' "$tmp" "$rootphys" >&2
            rm -f "$tmp"; return 1 ;;
    esac
    if [ -L "$tmp" ] || [ ! -f "$tmp" ]; then
        printf 'ERROR: harness: stage file %s is not a regular file — refusing to write\n' "$tmp" >&2
        rm -f "$tmp"
        return 1
    fi
    if ! cp "$srcfile" "$tmp"; then
        printf 'ERROR: harness: failed to copy %s -> %s\n' "$srcfile" "$root/$p" >&2
        rm -f "$tmp"
        return 1
    fi
    # A stage file that turned into a symlink (or vanished) between the check
    # above and now was raced — abort so the copy is not moved into the tree.
    if [ -L "$tmp" ] || [ ! -f "$tmp" ]; then
        printf 'ERROR: harness: stage file %s changed to a non-regular file mid-copy — aborting (possible symlink race)\n' "$tmp" >&2
        rm -f "$tmp"
        return 1
    fi
    case "$p" in
        *.sh) chmod +x "$tmp" || { rm -f "$tmp"; return 1; } ;;
        scripts/harness/*/*) ;;
        scripts/harness/*)
            # extensionless command entries are executable too
            case "$(head -c2 "$tmp" 2>/dev/null)" in '#!') chmod +x "$tmp" || { rm -f "$tmp"; return 1; } ;; esac ;;
    esac
    if ! mv "$tmp" "$root/$p"; then
        printf 'ERROR: harness: failed to move staged copy into place at %s\n' "$root/$p" >&2
        rm -f "$tmp"
        return 1
    fi
    return 0
}

harness_install_mechanism() {
    local src="$1" root="$2" kmf="$1/harness/kit-manifest" p srcfile
    local failed=0
    [ -f "$kmf" ] || return 1
    # Reject a bad ship contract BEFORE the first copy: unknown layers,
    # unsafe paths, duplicate destinations, and missing declared sources all
    # abort here instead of surfacing as a partial install.
    harness_validate_ship_contract "$kmf" "$src" || return 1
    mkdir -p "$root/scripts/harness"
    # Process substitution (not `... | while`) so a copy failure inside the
    # loop reaches `failed` in THIS shell instead of dying in a pipe subshell.
    while IFS= read -r p; do
        srcfile="$src/$(_harness_kit_src_rel "$kmf" "$p")"
        # An INSTALLED tree is a valid source too (the smoke test installs
        # from the repo's own scripts/, and so would a self-heal re-install),
        # but src= policy entries live at their installed repo-relative
        # homes there, not at the kit's template-relative path — fall back
        # to the installed location under the source tree's parent.
        [ -f "$srcfile" ] || srcfile="$src/../$p"
        if [ -f "$srcfile" ]; then
            _harness_copy_shipped "$srcfile" "$p" "$root" || failed=1
        else
            # Validation guarantees the source existed moments ago; a miss
            # here is a race or filesystem fault — loud, never a silent skip.
            printf 'ERROR: harness: declared source for %s vanished during install\n' "$p" >&2
            failed=1
        fi
    done < <(harness_kit_shipped_paths "$kmf")
    return "$failed"
}

# --- old-template recovery for update's tailored-file diff --------------------
# Update mode diffs each tailored/policy file old-kit-template → new-kit-template
# so the user can port upstream changes into their fork. That needs the OLD kit
# version's TEMPLATES. Recovery differs by INSTALL CHANNEL:
#   * git checkout of the kit  → `git show v<version>:…templates/scripts/<f>`
#     (version = manifest header); the diff base is in-repo, no persistence needed.
#   * plugin install           → the provider cache holds only plugins/harness-kit/
#     and need not retain .git; recover from the persisted base, else fetch tag
#     v<version> from the declared upstream repo when it is reachable/public.
#   * copied ("clone-and-copy")→ need not retain .git either; same persisted-base
#     path.
# The persisted base below is the channel-INDEPENDENT path: it needs no .git and
# no network, so it is the one that always works (the others are optimizations).
# init writes it right after install; update refreshes it after re-pinning.

# harness_manifest_version <repo_root>
# Prints the kit version in scripts/harness/.harness-manifest's header
# ("# harness-kit <version>") — the version whose templates update must recover
# to diff tailored files, and the tag (v<version>) the git-checkout channel uses.
# Absent file or header → returns 1.
harness_manifest_version() {
    local mf="$1/scripts/harness/.harness-manifest" v
    [ -f "$mf" ] || return 1
    v=$(awk '/^# harness-kit /{print $3; exit}' "$mf")
    [ -n "$v" ] && printf '%s\n' "$v"
}

# harness_base_dir <repo_root> <kit_version>
# Prints where the installed mechanism BASE for <kit_version> is persisted:
# <repo_root>/.harness/var/base/<kit_version>/scripts. It lives under the git-ignored
# .harness/ tree, so it is never committed and never manifest-pinned — a
# per-working-tree recovery cache, not shipped state.
harness_base_dir() {
    printf '%s/.harness/var/base/%s/scripts' "$1" "$2"
}

# harness_persist_base <src_scripts_dir> <repo_root> <kit_version>
# Snapshots the kit's mechanism TEMPLATES (the same set harness_install_mechanism
# copies, taken from the pristine <src_scripts_dir> so the snapshot is the
# untailored upstream — the correct diff base) into harness_base_dir, so a LATER
# update can recover them with no local git. Call it at init right after install,
# and again after each successful update keyed by the version just installed.
# Idempotent: re-copies over any existing snapshot for that version.
harness_persist_base() {
    local src="$1" root="$2" version="$3" kmf="$1/harness/kit-manifest" dest p srcfile rel
    [ -f "$kmf" ] || return 1
    harness_validate_ship_contract "$kmf" "$src" || return 1
    dest=$(harness_base_dir "$root" "$version")
    mkdir -p "$dest"
    harness_kit_shipped_paths "$kmf" | while IFS= read -r p; do
        # the base mirrors the SOURCE tree layout (src-relative), so recovery
        # reproduces a usable template dir for the diff
        rel="$(_harness_kit_src_rel "$kmf" "$p")"
        srcfile="$src/$rel"
        if [ -f "$srcfile" ]; then
            mkdir -p "$dest/$(dirname "$rel")"
            cp "$srcfile" "$dest/$rel"
        fi
    done
    return 0
}

# harness_recover_old_templates <repo_root> <out_dir>
# Populates <out_dir> with the OLD kit version's mechanism templates — update's
# diff base — WITHOUT needing local git, from the locally-persisted base for the
# version in the manifest header. Prints the recovered version and returns 0 on
# success. Returns 1 when no persisted base exists for that version (e.g. a
# teammate's fresh clone, where the git-ignored base was never checked out), so
# the caller falls back to the git-tag or upstream-fetch channels, or a degraded
# new-template-only diff — never a silent empty diff.
harness_recover_old_templates() {
    local root="$1" out="$2" version base
    version=$(harness_manifest_version "$root") || return 1
    [ -n "$version" ] || return 1
    base=$(harness_base_dir "$root" "$version")
    [ -d "$base" ] || return 1
    mkdir -p "$out"
    cp -R "$base/." "$out/"
    printf '%s\n' "$version"
}

# harness_update_decision <repo_root> <manifest_line> [kit_manifest_file]
# Echoes how update mode must treat one pinned file:
#   replace — the file is kit-managed and still matches its pin: safe to
#             overwrite with the new template.
#   diff    — the file is policy/optional-policy in the kit-manifest, is
#             '# tailored', or has drifted locally from its pin (someone edited
#             it since install): the project owns it, so update only shows a
#             diff and lets the user choose.
# Layering comes from <kit_manifest_file> — update mode passes the NEW kit's
# copy (the incoming release defines the current layers); it defaults to the
# target's installed scripts/harness/kit-manifest for direct callers. Comment/blank
# lines echo nothing. Pure classification plus one hash.
harness_update_decision() {
    local root="$1" line="$2" kmf="${3:-$1/scripts/harness/kit-manifest}" want path have
    case "$line" in \#*|"") return 0 ;; esac
    case "$line" in *"# tailored"*) printf 'diff\n'; return 0 ;; esac
    path=$(printf '%s\n' "$line" | awk '{print $2}')
    [ -n "$path" ] || return 0
    # Policy layers are diff-only even when pristine and unmarked (step 3).
    if harness_kit_is_diff_only "$kmf" "$path"; then
        printf 'diff\n'; return 0
    fi
    want=${line%% *}
    have=$(_harness_sha256 "$root/$path" | awk '{print $1}')
    if [ "$have" = "$want" ]; then printf 'replace\n'; else printf 'diff\n'; fi
}

# harness_update_apply <src_scripts_dir> <repo_root> [--dry-run]
# Runs the deterministic half of update mode against the NEW kit's
# <src_scripts_dir> (whose kit-manifest defines the incoming inventory):
#   1. For each pinned file, replace it with the new template IF
#      harness_update_decision (judged against the NEW kit-manifest) says
#      "replace"; leave policy/tailored/locally-drifted files untouched (the
#      caller diffs those for the user).
#   2. REMOVE each path the new kit-manifest lists as retired — but only when
#      the on-disk copy is pristine (sha still matches its pin) and not
#      '# tailored'. A drifted, tailored, or never-pinned copy is kept and
#      reported ('retire-keep') for manual review: retirement must never
#      delete local changes.
#   3. Install any shipped path (toplevel or hook, one unified pass) the
#      target doesn't have yet — the old manifest can't list a file the
#      previous kit version didn't ship.
# Prints one "replace|keep|remove|retire-keep|add <path>" line per file. Does
# NOT re-pin the manifest — call harness_repin_manifest afterward (it pins the
# newly-added files and drops the removed ones).
#
# --dry-run prints the SAME decision table without mutating anything: one code
# path computes both (the plan can never diverge from what apply would do).
# Dry-run output additionally distinguishes 'diff' (policy/tailored/drifted,
# with a new template available to diff against) from plain 'keep', and
# 'migrate' lines report a pending manifest-location migration.
harness_update_apply() {
    local src="$1" root="$2" mf="$2/scripts/harness/.harness-manifest" kmf="$1/harness/kit-manifest"
    local line path decision srcfile p retired pinline want have
    local failed=0 dry="" mf_read
    case "${3:-}" in
        --dry-run) dry=1 ;;
        "") ;;
        *) printf 'harness_update_apply: unknown mode %s\n' "$3" >&2; return 64 ;;
    esac
    # Reject a bad ship contract BEFORE any mutation — including the manifest
    # migration below (validation errors surface identically in dry-run).
    harness_validate_ship_contract "$kmf" "$src" || return 1
    # Pre-v0.23.0 installs keep the integrity manifest at the old flat
    # location; migrate it (content unchanged — the caller's repin rewrites
    # it at the new path afterward) so the replace loop sees the old pins.
    mf_read="$mf"
    if [ ! -f "$mf" ] && [ -f "$root/scripts/.harness-manifest" ]; then
        if [ -n "$dry" ]; then
            mf_read="$root/scripts/.harness-manifest"
        else
            mkdir -p "$root/scripts/harness"
            if ! mv "$root/scripts/.harness-manifest" "$mf"; then
                printf 'ERROR: harness_update_apply: failed to migrate the integrity manifest\n' >&2
                return 1
            fi
        fi
        printf 'migrate scripts/harness/.harness-manifest\n'
    fi
    retired=" $(harness_kit_manifest_paths "$kmf" retired 2>/dev/null | tr '\n' ' ') "
    # --- Replace pass. Every copy is CHECKED; a failure sets `failed`, and with
    # the one destructive pass (retirement) deferred to LAST, the function then
    # returns non-zero BEFORE deleting anything — so a partial upgrade is never
    # re-pinned as a success. The old defect: a failed cp still printed
    # 'replace' and the function returned 0 unconditionally. Replacement goes
    # through _harness_copy_shipped (staged beside the destination, renamed
    # into place), so an interrupted update can leave old files and new files
    # but never a TORN file — a half-written mechanism file would read as
    # local drift on every later update and be kept forever.
    if [ -f "$mf_read" ]; then
        while IFS= read -r line; do
            case "$line" in \#*|"") continue ;; esac
            path=$(printf '%s\n' "$line" | awk '{print $2}')
            [ -n "$path" ] || continue
            # Retired paths are handled (and reported) by the pass below.
            case "$retired" in *" $path "*) continue ;; esac
            decision=$(harness_update_decision "$root" "$line" "$kmf")
            srcfile="$src/$(_harness_kit_src_rel "$kmf" "$path")"
            if [ "$decision" = "replace" ] && [ -f "$srcfile" ]; then
                if [ -n "$dry" ]; then
                    printf 'replace %s\n' "$path"
                elif _harness_copy_shipped "$srcfile" "$path" "$root"; then
                    printf 'replace %s\n' "$path"
                else
                    printf 'ERROR: harness_update_apply: failed to replace %s\n' "$path" >&2
                    failed=1
                fi
            elif [ -n "$dry" ] && [ "$decision" = "diff" ] && [ -f "$srcfile" ]; then
                printf 'diff %s\n' "$path"
            else
                printf 'keep %s\n' "$path"
            fi
        done < "$mf_read"
    fi
    # --- Add newly-shipped files absent from the target (one pass covers
    # commands, libraries, hooks, and tests alike — the kit-manifest enumerates
    # them all). Process substitution (not `... | while`) keeps `failed` in
    # THIS shell; every copy is checked via _harness_copy_shipped.
    [ -n "$dry" ] || mkdir -p "$root/scripts/harness"
    while IFS= read -r p; do
        srcfile="$src/$(_harness_kit_src_rel "$kmf" "$p")"
        if [ -f "$srcfile" ] && [ ! -f "$root/$p" ]; then
            if [ -n "$dry" ]; then
                printf 'add %s\n' "$p"
            elif _harness_copy_shipped "$srcfile" "$p" "$root"; then
                printf 'add %s\n' "$p"
            else
                failed=1
            fi
        fi
    done < <(harness_kit_shipped_paths "$kmf" 2>/dev/null)
    # A failed copy above aborts BEFORE the one destructive pass, so an
    # interrupted or failed upgrade never also deletes files; the caller sees
    # non-zero and must not re-pin the mixed state.
    [ "$failed" -eq 0 ] || return 1
    # --- Remove retired files (pristine + unmarked only — see the contract
    # above). LAST, so the single destructive step runs only after every copy
    # above has succeeded.
    for path in $retired; do
        [ -f "$root/$path" ] || continue
        pinline=""
        [ -f "$mf_read" ] && pinline=$(awk -v p="$path" '$2 == p {print; exit}' "$mf_read")
        case "$pinline" in
            ""|*"# tailored"*)
                # never pinned (unknown provenance) or a deliberate fork
                printf 'retire-keep %s\n' "$path"
                continue ;;
        esac
        want=${pinline%% *}
        have=$(_harness_sha256 "$root/$path" | awk '{print $1}')
        if [ "$have" = "$want" ]; then
            if [ -n "$dry" ]; then
                printf 'remove %s\n' "$path"
            elif rm -f "$root/$path"; then
                printf 'remove %s\n' "$path"
            else
                # An unremovable retired file must not be reported as removed:
                # the caller would re-pin a state the tree does not have.
                printf 'ERROR: harness_update_apply: failed to remove retired %s\n' "$path" >&2
                failed=1
            fi
        else
            printf 'retire-keep %s\n' "$path"
        fi
    done
    [ "$failed" -eq 0 ] || return 1
    return 0
}
