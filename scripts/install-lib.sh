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
# (scripts/test-install.sh drives these functions against throwaway fixtures).
#
# Source it — it defines functions and runs nothing:
#   . scripts/install-lib.sh
# Compatible with macOS (BSD) and Linux (GNU); the only hard dependency is a
# sha256 tool (shasum or sha256sum), the same one check-harness.sh needs.

# The mechanism files pinned by the manifest, relative to a repo's scripts/.
# This is the single source for "which top-level files are integrity-checked":
# the SKILL init step-8 producer and update's re-pin both flow through
# harness_generate_manifest, which reads this list. The scripts/hooks/ tree is
# always included wholesale (see harness_manifest_paths). Add a new top-level
# mechanism file here and it is covered by the manifest and the installer at once.
_HARNESS_MECHANISM_TOPLEVEL="harness.conf sync-agent-skills.sh check-harness.sh test-check-harness.sh install-lib.sh test-install.sh verify.sh"

# _harness_sha256 <file...> — prints "<sha256>  <path>" lines, the manifest's
# own line format. Mirrors check-harness.sh's sha256_of tool selection.
_harness_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
    fi
}

# harness_manifest_paths <repo_root>
# Prints the sorted, repo-relative paths the manifest pins: the whole
# scripts/hooks/ tree (matching the producer's `find scripts/hooks -type f`)
# plus each present top-level mechanism file. Deterministic (sorted), so two
# runs over the same tree produce byte-identical output.
harness_manifest_paths() {
    local f
    ( cd "$1" 2>/dev/null || return 1
      {
          find scripts/hooks -type f ! -name '.harness-manifest' 2>/dev/null
          for f in $_HARNESS_MECHANISM_TOPLEVEL; do
              [ -f "scripts/$f" ] && printf 'scripts/%s\n' "$f"
          done
      } | sort
    )
}

# harness_generate_manifest <repo_root> <kit_version>
# Prints the .harness-manifest content: a "# harness-kit <version>" header then
# one "<sha256>  <path>" line per mechanism file. Pure stdout — the caller
# redirects it to scripts/.harness-manifest. Does NOT emit '# tailored' markers
# (those are per-repo ownership decisions); use harness_repin_manifest to
# regenerate while preserving existing markers.
harness_generate_manifest() {
    local root="$1" version="$2" p
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
# line that carried one before (update mode must never silently un-fork a file).
# Pure stdout — the caller redirects it. Used by update after replacing the
# kit-managed files.
harness_repin_manifest() {
    local root="$1" version="$2" mf="$1/scripts/.harness-manifest"
    local old tailored=" " path line
    if [ -f "$mf" ]; then
        while IFS= read -r old; do
            case "$old" in *"# tailored"*) ;; *) continue ;; esac
            path=$(printf '%s\n' "$old" | awk '{print $2}')
            [ -n "$path" ] && tailored="${tailored}${path} "
        done < "$mf"
    fi
    harness_generate_manifest "$root" "$version" | while IFS= read -r line; do
        case "$line" in
            \#*|"") printf '%s\n' "$line"; continue ;;
        esac
        path=$(printf '%s\n' "$line" | awk '{print $2}')
        case "$tailored" in
            *" $path "*) printf '%s # tailored\n' "$line" ;;
            *)           printf '%s\n' "$line" ;;
        esac
    done
}

# harness_append_gitignore <repo_root>
# Ensures '.harness/' (the hook observability log dir) is git-ignored.
# Idempotent — a second call is a no-op.
harness_append_gitignore() {
    local gi="$1/.gitignore"
    if [ -f "$gi" ] && grep -qxF '.harness/' "$gi"; then return 0; fi
    # Start on a fresh line even if an existing .gitignore lacks a trailing
    # newline, so the entry never merges onto its last line
    # (e.g. node_modules -> node_modules.harness/).
    if [ -s "$gi" ] && [ -n "$(tail -c1 "$gi" 2>/dev/null)" ]; then
        printf '\n.harness/\n' >> "$gi"
    else
        printf '.harness/\n' >> "$gi"
    fi
}

# harness_install_mechanism <src_scripts_dir> <repo_root>
# Copies the mechanism — the pinned top-level files plus the hooks/ tree — from
# an existing scripts/ dir into <repo_root>/scripts and sets exec bits. Copies
# only the known mechanism set, so a source dir that also carries repo-local
# scripts (a packaging gate, a template-sync check) does not leak them into the
# target. Touches only scripts/: hand-written content elsewhere (AGENTS.md, a
# .claude/settings.json) is never the installer's concern — that is the caller's
# authoring/merge step, so the "never clobber hand-written files" floor holds by
# construction.
harness_install_mechanism() {
    local src="$1" root="$2" f
    mkdir -p "$root/scripts/hooks"
    for f in $_HARNESS_MECHANISM_TOPLEVEL; do
        [ -f "$src/$f" ] && cp "$src/$f" "$root/scripts/$f"
    done
    [ -d "$src/hooks" ] && cp -R "$src/hooks/." "$root/scripts/hooks/"
    chmod +x "$root/scripts/"*.sh "$root/scripts/hooks/"*.sh 2>/dev/null
    return 0
}

# harness_update_decision <repo_root> <manifest_line>
# Echoes how update mode must treat one mechanism file:
#   replace — the file is kit-managed and still matches its pin: safe to
#             overwrite with the new template.
#   diff    — the file is '# tailored', or has drifted locally from its pin
#             (someone edited it since install): the project owns it, so update
#             only shows a diff and lets the user choose.
# Comment/blank lines echo nothing. Pure classification plus one hash.
harness_update_decision() {
    local root="$1" line="$2" want path have
    case "$line" in \#*|"") return 0 ;; esac
    case "$line" in *"# tailored"*) printf 'diff\n'; return 0 ;; esac
    want=${line%% *}
    path=$(printf '%s\n' "$line" | awk '{print $2}')
    [ -n "$path" ] || return 0
    have=$(_harness_sha256 "$root/$path" | awk '{print $1}')
    if [ "$have" = "$want" ]; then printf 'replace\n'; else printf 'diff\n'; fi
}

# harness_update_apply <src_scripts_dir> <repo_root>
# Runs the deterministic half of update mode: for each pinned mechanism file,
# replace it with the new template from <src_scripts_dir> IF harness_update_decision
# says "replace"; leave tailored/locally-drifted files untouched (the caller
# diffs those for the user). Prints one "replace <path>" or "keep <path>" line
# per file so callers and tests can see what it did. Does NOT re-pin the manifest
# — call harness_repin_manifest afterward.
harness_update_apply() {
    local src="$1" root="$2" mf="$2/scripts/.harness-manifest"
    local line path decision srcfile
    [ -f "$mf" ] || return 0
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        path=$(printf '%s\n' "$line" | awk '{print $2}')
        [ -n "$path" ] || continue
        decision=$(harness_update_decision "$root" "$line")
        srcfile="$src/${path#scripts/}"
        if [ "$decision" = "replace" ] && [ -f "$srcfile" ]; then
            cp "$srcfile" "$root/$path"
            printf 'replace %s\n' "$path"
        else
            printf 'keep %s\n' "$path"
        fi
    done < "$mf"
}
