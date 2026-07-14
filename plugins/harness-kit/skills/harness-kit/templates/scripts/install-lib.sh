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
_HARNESS_MECHANISM_TOPLEVEL="harness.conf sync-agent-skills.sh check-harness.sh test-check-harness.sh install-lib.sh test-install.sh dev-instance.sh test-dev-instance.sh eval-lib.sh eval.sh eval-harness.sh test-eval.sh test-verify.sh verify.sh"

# Optional project-owned policy that is authored for an application repo, never
# copied from this template directory. When present, it is still integrity-
# pinned and carried through re-pin. Keep this set separate from mechanism:
# install, persisted template bases, and update's add-new-files pass must never
# mistake a repo-specific dev launcher for a generic kit template.
_HARNESS_OPTIONAL_PROJECT_POLICY_TOPLEVEL="dev.sh"

# Policy files: update mode must NEVER auto-overwrite these, even when the
# installed copy still matches its pin (SKILL update step 3). The project may
# have tailored them without the '# tailored' marker (a fresh install pins them
# unmarked), and secret/format/guard policy must be reviewed, never silently
# replaced. harness_update_decision returns 'diff' for any path here regardless
# of marker — repo-relative, matching manifest paths.
_HARNESS_POLICY_FILES="scripts/verify.sh scripts/harness.conf scripts/dev.sh scripts/hooks/format.sh scripts/hooks/guard-secrets.sh scripts/hooks/guard-project-policy.sh"

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
          for f in $_HARNESS_OPTIONAL_PROJECT_POLICY_TOPLEVEL; do
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
# line that carried one before (update mode must never silently un-fork a file),
# AND carries forward tailored pins the shipped producer doesn't emit — a repo
# may pin its own local gates (e.g. a packaging or template-sync check) as
# '# tailored'; a re-pin must not silently drop those integrity pins. Emits a
# path-sorted union of the shipped mechanism set and any still-present
# previously-tailored path. Pure stdout — the caller redirects it.
harness_repin_manifest() {
    local root="$1" version="$2" mf="$1/scripts/.harness-manifest"
    local old tailored=" " path allpaths
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

# harness_conf_declared <repo_root> <VARNAME>
# Returns 0 if scripts/harness.conf declares VARNAME (an uncommented
# `VARNAME=` assignment), 1 otherwise. Update/audit uses it to tell a legacy
# pre-declaration install (needs HOOK_WIRED_PROVIDERS / AGENT_PROVIDERS migrated
# in) from a current one — check-harness.sh fails loudly on the former.
harness_conf_declared() {
    local conf="$1/scripts/harness.conf" var="$2"
    [ -f "$conf" ] || return 1
    grep -qE "^[[:space:]]*${var}=" "$conf"
}

# harness_conf_declare <repo_root> <VARNAME> <value>
# Idempotently ensure scripts/harness.conf declares VARNAME="value". The value
# is the CALLER's (the user's confirmed choice from update/audit's proposal),
# NEVER inferred from whichever provider configs/stubs survive on disk — a config
# deleted before an upgrade is mechanically indistinguishable from one never
# wired, so adopting survivors would silently bless the deletion. If VARNAME is
# already declared this is a NO-OP: migration confirms the set ONCE, and a
# second update must neither duplicate the line nor reset a value the user has
# since edited. Appends when absent. Returns 1 if there is no harness.conf.
harness_conf_declare() {
    local conf="$1/scripts/harness.conf" var="$2" value="$3"
    [ -f "$conf" ] || return 1
    harness_conf_declared "$1" "$var" && return 0
    printf '%s="%s"\n' "$var" "$value" >> "$conf"
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
# Prints the kit version in scripts/.harness-manifest's header
# ("# harness-kit <version>") — the version whose templates update must recover
# to diff tailored files, and the tag (v<version>) the git-checkout channel uses.
# Absent file or header → returns 1.
harness_manifest_version() {
    local mf="$1/scripts/.harness-manifest" v
    [ -f "$mf" ] || return 1
    v=$(awk '/^# harness-kit /{print $3; exit}' "$mf")
    [ -n "$v" ] && printf '%s\n' "$v"
}

# harness_base_dir <repo_root> <kit_version>
# Prints where the installed mechanism BASE for <kit_version> is persisted:
# <repo_root>/.harness/base/<kit_version>/scripts. It lives under the git-ignored
# .harness/ tree, so it is never committed and never manifest-pinned — a
# per-working-tree recovery cache, not shipped state.
harness_base_dir() {
    printf '%s/.harness/base/%s/scripts' "$1" "$2"
}

# harness_persist_base <src_scripts_dir> <repo_root> <kit_version>
# Snapshots the kit's mechanism TEMPLATES (the same set harness_install_mechanism
# copies, taken from the pristine <src_scripts_dir> so the snapshot is the
# untailored upstream — the correct diff base) into harness_base_dir, so a LATER
# update can recover them with no local git. Call it at init right after install,
# and again after each successful update keyed by the version just installed.
# Idempotent: re-copies over any existing snapshot for that version.
harness_persist_base() {
    local src="$1" root="$2" version="$3" dest f
    dest=$(harness_base_dir "$root" "$version")
    mkdir -p "$dest/hooks"
    for f in $_HARNESS_MECHANISM_TOPLEVEL; do
        [ -f "$src/$f" ] && cp "$src/$f" "$dest/$f"
    done
    [ -d "$src/hooks" ] && cp -R "$src/hooks/." "$dest/hooks/"
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

# harness_update_decision <repo_root> <manifest_line>
# Echoes how update mode must treat one mechanism file:
#   replace — the file is kit-managed and still matches its pin: safe to
#             overwrite with the new template.
#   diff    — the file is a policy file, is '# tailored', or has drifted locally
#             from its pin (someone edited it since install): the project owns
#             it, so update only shows a diff and lets the user choose.
# Comment/blank lines echo nothing. Pure classification plus one hash.
harness_update_decision() {
    local root="$1" line="$2" want path have pf
    case "$line" in \#*|"") return 0 ;; esac
    case "$line" in *"# tailored"*) printf 'diff\n'; return 0 ;; esac
    path=$(printf '%s\n' "$line" | awk '{print $2}')
    [ -n "$path" ] || return 0
    # Policy files are diff-only even when pristine and unmarked (step 3).
    for pf in $_HARNESS_POLICY_FILES; do
        [ "$path" = "$pf" ] && { printf 'diff\n'; return 0; }
    done
    want=${line%% *}
    have=$(_harness_sha256 "$root/$path" | awk '{print $1}')
    if [ "$have" = "$want" ]; then printf 'replace\n'; else printf 'diff\n'; fi
}

# harness_update_apply <src_scripts_dir> <repo_root>
# Runs the deterministic half of update mode: for each pinned mechanism file,
# replace it with the new template from <src_scripts_dir> IF harness_update_decision
# says "replace"; leave policy/tailored/locally-drifted files untouched (the
# caller diffs those for the user). Then installs any mechanism file the new kit
# ships that the target doesn't have yet — the old manifest can't list a file the
# previous kit version didn't ship, so a v0.6->v0.7 upgrade must still pick up
# install-lib.sh / test-install.sh. Prints one "replace|keep|add <path>" line per
# file. Does NOT re-pin the manifest — call harness_repin_manifest afterward
# (it will pin the newly-added files).
harness_update_apply() {
    local src="$1" root="$2" mf="$2/scripts/.harness-manifest"
    local line path decision srcfile f hf base
    if [ -f "$mf" ]; then
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
    fi
    # Add newly-shipped mechanism files absent from the target.
    mkdir -p "$root/scripts/hooks"
    for f in $_HARNESS_MECHANISM_TOPLEVEL; do
        if [ -f "$src/$f" ] && [ ! -f "$root/scripts/$f" ]; then
            cp "$src/$f" "$root/scripts/$f"
            case "$f" in *.sh) chmod +x "$root/scripts/$f" ;; esac
            printf 'add scripts/%s\n' "$f"
        fi
    done
    if [ -d "$src/hooks" ]; then
        for hf in "$src"/hooks/*; do
            [ -f "$hf" ] || continue
            base=$(basename "$hf")
            if [ ! -f "$root/scripts/hooks/$base" ]; then
                cp "$hf" "$root/scripts/hooks/$base"
                case "$base" in *.sh) chmod +x "$root/scripts/hooks/$base" ;; esac
                printf 'add scripts/hooks/%s\n' "$base"
            fi
        done
    fi
}
