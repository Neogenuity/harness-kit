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
# Compatible with macOS (BSD) and Linux (GNU); the only hard dependency is a
# sha256 tool (shasum or sha256sum), the same one check-harness.sh needs.

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
# resolution), and a sha256 tool (`shasum`/`sha256sum`, the manifest-integrity
# check). Empty output = all present. init/update run this as an early PREFLIGHT
# and ask the user to ACKNOWLEDGE any gap before scaffolding a harness whose
# feedback layer would be inert; check-harness.sh's doctor keeps WARNing on the
# same condition afterward (check #10). Detection only — it does NOT change the
# guards' deliberate fail-open posture (a missing dep must degrade, never block a
# contributor's turn). No side effects, so a test pins it with no model in loop.
harness_missing_prereqs() {
    command -v jq  >/dev/null 2>&1 || printf 'jq\n'
    command -v git >/dev/null 2>&1 || printf 'git\n'
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
harness_install_mechanism() {
    local src="$1" root="$2" kmf="$1/harness/kit-manifest" p srcfile
    [ -f "$kmf" ] || return 1
    mkdir -p "$root/scripts/harness"
    harness_kit_shipped_paths "$kmf" | while IFS= read -r p; do
        srcfile="$src/$(_harness_kit_src_rel "$kmf" "$p")"
        # An INSTALLED tree is a valid source too (the smoke test installs
        # from the repo's own scripts/, and so would a self-heal re-install),
        # but src= policy entries live at their installed repo-relative
        # homes there, not at the kit's template-relative path — fall back
        # to the installed location under the source tree's parent.
        [ -f "$srcfile" ] || srcfile="$src/../$p"
        if [ -f "$srcfile" ]; then
            mkdir -p "$root/$(dirname "$p")"
            cp "$srcfile" "$root/$p"
            case "$p" in
                *.sh) chmod +x "$root/$p" ;;
                scripts/harness/*/*) ;;
                scripts/harness/*)
                    # extensionless command entries are executable too
                    case "$(head -c2 "$root/$p" 2>/dev/null)" in '#!') chmod +x "$root/$p" ;; esac ;;
            esac
        fi
    done
    return 0
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

# harness_update_apply <src_scripts_dir> <repo_root>
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
harness_update_apply() {
    local src="$1" root="$2" mf="$2/scripts/harness/.harness-manifest" kmf="$1/harness/kit-manifest"
    local line path decision srcfile p retired pinline want have
    # Pre-v0.23.0 installs keep the integrity manifest at the old flat
    # location; migrate it (content unchanged — the caller's repin rewrites
    # it at the new path afterward) so the replace loop sees the old pins.
    if [ ! -f "$mf" ] && [ -f "$root/scripts/.harness-manifest" ]; then
        mkdir -p "$root/scripts/harness"
        mv "$root/scripts/.harness-manifest" "$mf"
        printf 'migrate scripts/harness/.harness-manifest\n'
    fi
    retired=" $(harness_kit_manifest_paths "$kmf" retired 2>/dev/null | tr '\n' ' ') "
    if [ -f "$mf" ]; then
        while IFS= read -r line; do
            case "$line" in \#*|"") continue ;; esac
            path=$(printf '%s\n' "$line" | awk '{print $2}')
            [ -n "$path" ] || continue
            # Retired paths are handled (and reported) by the pass below.
            case "$retired" in *" $path "*) continue ;; esac
            decision=$(harness_update_decision "$root" "$line" "$kmf")
            srcfile="$src/$(_harness_kit_src_rel "$kmf" "$path")"
            if [ "$decision" = "replace" ] && [ -f "$srcfile" ]; then
                cp "$srcfile" "$root/$path"
                printf 'replace %s\n' "$path"
            else
                printf 'keep %s\n' "$path"
            fi
        done < "$mf"
    fi
    # Remove retired files (pristine + unmarked only — see the contract above).
    for path in $retired; do
        [ -f "$root/$path" ] || continue
        pinline=""
        [ -f "$mf" ] && pinline=$(awk -v p="$path" '$2 == p {print; exit}' "$mf")
        case "$pinline" in
            ""|*"# tailored"*)
                # never pinned (unknown provenance) or a deliberate fork
                printf 'retire-keep %s\n' "$path"
                continue ;;
        esac
        want=${pinline%% *}
        have=$(_harness_sha256 "$root/$path" | awk '{print $1}')
        if [ "$have" = "$want" ]; then
            rm -f "$root/$path"
            printf 'remove %s\n' "$path"
        else
            printf 'retire-keep %s\n' "$path"
        fi
    done
    # Add newly-shipped files absent from the target (one pass covers
    # commands, libraries, hooks, and tests alike — the kit-manifest
    # enumerates them all).
    mkdir -p "$root/scripts/harness"
    harness_kit_shipped_paths "$kmf" 2>/dev/null | while IFS= read -r p; do
        srcfile="$src/$(_harness_kit_src_rel "$kmf" "$p")"
        if [ -f "$srcfile" ] && [ ! -f "$root/$p" ]; then
            mkdir -p "$root/$(dirname "$p")"
            cp "$srcfile" "$root/$p"
            case "$p" in
                *.sh) chmod +x "$root/$p" ;;
                scripts/harness/*/*) ;;
                scripts/harness/*)
                    case "$(head -c2 "$root/$p" 2>/dev/null)" in '#!') chmod +x "$root/$p" ;; esac ;;
            esac
            printf 'add %s\n' "$p"
        fi
    done
    return 0
}
