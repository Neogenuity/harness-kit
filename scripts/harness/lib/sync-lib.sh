#!/usr/bin/env bash
# Generates the provider skill stubs (.claude/.cursor/.opencode — .agents/
# skills/ IS the canonical home since v0.24.0, and Codex reads it natively)
# from the canonical skills in .agents/skills/, the single source of
# truth; the stubs exist only so each harness registers and auto-activates the
# skill. Frontmatter (name + description — the activation trigger) is copied
# verbatim from the canonical file, so tuning a trigger in the canonical
# skill propagates to every harness on the next sync.
#
# Skill resource directories (references/, scripts/, assets/ — the Agent
# Skills standard) are mirrored verbatim next to each stub, so harnesses that
# resolve resources relative to the skill directory keep working; --check
# pins the mirrors to the canonical content just like the stubs.
#
#   bash scripts/harness/sync          # (re)write all stubs
#   bash scripts/harness/sync --check  # exit 1 if stubs are stale/missing/orphaned
#
# --check is wired into scripts/harness/check-harness (CI-gated), so a stub edited
# by hand, a canonical description change without a re-sync, or a stub missing
# from a provider dir fails the build.
#
# Providers and the canonical dir come from scripts/harness/harness.conf.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness/harness.conf" ] && . "$ROOT/scripts/harness/harness.conf"

# Derive the skill-stub and agent-stub provider sets from the single
# HARNESS_PROVIDERS declaration + the kit capability table (ADR 011); an
# explicit harness.conf value for either wins. Same resolution check-harness
# uses, so sync and the checker never disagree about who gets a stub.
# shellcheck disable=SC2034  # read by provider-lib.sh across the source boundary
PROVIDER_CAPS_FILE="$ROOT/scripts/harness/lib/provider-caps"
# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness/lib/provider-lib.sh" ] && . "$ROOT/scripts/harness/lib/provider-lib.sh"
if command -v harness_resolve_set >/dev/null 2>&1; then
    harness_resolve_set PROVIDERS skill
    harness_resolve_set AGENT_PROVIDERS agent
    # Resolved for the generated-adapter wiring summary below (sync generates no
    # hook configs itself); harmless when a repo declares no hook providers.
    harness_resolve_set HOOK_WIRED_PROVIDERS hook
fi
PROVIDERS="${PROVIDERS:-.claude .cursor .opencode}"
CANONICAL_SKILLS="${CANONICAL_SKILLS:-.agents/skills}"

MODE="${1:-write}"
case "$MODE" in
    write|--check) ;;
    *)
        echo "usage: bash scripts/harness/sync [--check]" >&2
        echo "unknown argument: $MODE (a typo'd --check must not silently rewrite stubs)" >&2
        exit 64
        ;;
esac

fail=0

render_stub() {
    # $1 = canonical SKILL.md path, $2 = slug
    local canonical="$1" slug="$2" fm title
    # Frontmatter block, both --- markers inclusive.
    fm=$(awk 'NR==1 { if ($0 != "---") exit 1; print; next } { print } $0 == "---" { exit }' "$canonical")
    title=$(grep -m1 '^# ' "$canonical" | sed 's/^# //' || true)
    [ -n "$title" ] || title="$slug"
    printf '%s\n\n# %s\n\nCanonical source: `%s/%s/SKILL.md`\n\nRead that file for the full skill before starting. This stub only registers the skill with the harness — edit the canonical file, then run `bash scripts/harness/sync`.\n' "$fm" "$title" "$CANONICAL_SKILLS" "$slug"
}

for canonical in "$ROOT/$CANONICAL_SKILLS"/*/SKILL.md; do
    [ -f "$canonical" ] || continue
    slug=$(basename "$(dirname "$canonical")")

    if ! head -1 "$canonical" | grep -q '^---$'; then
        echo "ERROR: $CANONICAL_SKILLS/$slug/SKILL.md has no YAML frontmatter — cannot generate stubs"
        exit 1
    fi

    stub=$(render_stub "$canonical" "$slug")

    for provider in $PROVIDERS; do
        dest="$ROOT/$provider/skills/$slug/SKILL.md"
        dest_rel="$provider/skills/$slug/SKILL.md"
        if [ "$MODE" = "--check" ]; then
            if [ ! -f "$dest" ]; then
                echo "STALE: $dest_rel is missing — run 'bash scripts/harness/sync' and commit the result"
                fail=1
            elif [ "$(cat "$dest")" != "$stub" ]; then
                echo "STALE: $dest_rel does not match the generator output (canonical: $CANONICAL_SKILLS/$slug/SKILL.md) — run 'bash scripts/harness/sync' and commit the result"
                fail=1
            fi
        else
            mkdir -p "$(dirname "$dest")"
            printf '%s\n' "$stub" > "$dest"
            echo "wrote $dest_rel"
        fi

        # Mirror the skill's resource directories (Agent Skills standard).
        for res in references scripts assets; do
            src_dir="$(dirname "$canonical")/$res"
            dst_dir="$(dirname "$dest")/$res"
            dst_rel="$provider/skills/$slug/$res"
            if [ "$MODE" = "--check" ]; then
                if [ -d "$src_dir" ]; then
                    if ! diff -rq "$src_dir" "$dst_dir" >/dev/null 2>&1; then
                        echo "STALE: $dst_rel does not match canonical $CANONICAL_SKILLS/$slug/$res — run 'bash scripts/harness/sync' and commit the result"
                        fail=1
                    fi
                elif [ -d "$dst_dir" ]; then
                    echo "STALE: $dst_rel exists but the canonical skill has no $res/ — run 'bash scripts/harness/sync' and commit the result"
                    fail=1
                fi
            else
                rm -rf "$dst_dir"
                if [ -d "$src_dir" ]; then
                    cp -R "$src_dir" "$dst_dir"
                    echo "wrote $dst_rel/"
                fi
            fi
        done
    done
done

# Orphan stubs: a provider skill with no canonical source drifts by definition.
# Fails in BOTH modes — in write mode the sync still completes, but the orphan
# needs a human decision (delete the stub or add the canonical skill), so the
# exit code must not read as "all clean".
for provider in $PROVIDERS; do
    for stub_dir in "$ROOT/$provider"/skills/*/; do
        [ -d "$stub_dir" ] || continue
        slug=$(basename "$stub_dir")
        if [ ! -f "$ROOT/$CANONICAL_SKILLS/$slug/SKILL.md" ]; then
            echo "ORPHAN: $provider/skills/$slug has no canonical $CANONICAL_SKILLS/$slug/SKILL.md — delete the stub or add the canonical skill"
            fail=1
        fi
    done
done

# --- Agent stubs -------------------------------------------------------------
# Canonical agent personas (.harness/agents/<slug>.md) carry name/description/tools
# frontmatter; each declared AGENT_PROVIDER gets a generated pointer stub in its
# own dialect — .codex uses TOML (*.toml), the rest Markdown (*.md). Codex's
# custom-agent schema has no frontmatter-style tool-name list: its `tools` key is
# a different config value, so Codex stubs intentionally omit canonical tools.
# The Markdown-provider stubs keep their provider-appropriate tools mapping. Same
# single-source contract as skills: the routing description lives in the
# canonical doc and propagates on sync, and --check enforces BIDIRECTIONAL set
# equality — every canonical has a stub in every declared provider, every stub
# points at an existing canonical, and each stub must match the generator (so a
# stale description fails). The provider set is DECLARED (harness.conf
# AGENT_PROVIDERS), never inferred from directory presence: PROVIDERS cannot
# serve (it models skill-stub dirs — excludes .codex, includes .agents), and
# inferring from existing dirs would let a deleted agents dir pass unnoticed.
CANONICAL_AGENTS="${CANONICAL_AGENTS:-.harness/agents}"
agent_providers_declared=0
[ -n "${AGENT_PROVIDERS+x}" ] && agent_providers_declared=1

# agent_fm_field <file> <key> — value of a frontmatter key (empty if absent).
agent_fm_field() {
    awk -v key="$2" '
        NR==1 && $0!="---" { exit }
        NR==1 { next }
        $0=="---" { exit }
        { k=$0; sub(/:.*/,"",k)
          if (k==key) { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); print v; exit } }
    ' "$1"
}

# render_agent_md <name> <desc> <tools> <title> <slug> [extra_fm_line]
# extra_fm_line is an optional frontmatter line appended after tools (OpenCode
# marks a subagent with `mode: subagent`, per the provider matrix).
render_agent_md() {
    local extra=""
    [ -n "${6:-}" ] && extra="$6"$'\n'
    printf -- '---\nname: %s\ndescription: %s\ntools: %s\n%s---\n\n# %s\n\nCanonical source: `%s/%s.md`\n\nRead that file for the full persona before delegating. This stub only registers the agent with the harness — edit the canonical doc, then run `bash scripts/harness/sync`.\n' \
        "$1" "$2" "$3" "$extra" "$4" "$CANONICAL_AGENTS" "$5"
}

# render_agent_toml <name> <desc> <slug>
render_agent_toml() {
    local name="$1" desc="$2" slug="$3"
    # Escape backslash then double-quote for the TOML basic string.
    desc=$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '# Codex agent stub — generated by sync-agent-skills.sh from %s/%s.md.\n# Edit the canonical doc frontmatter, then re-run the sync. Non-blocking.\nname = "%s"\ndescription = "%s"\ndeveloper_instructions = """\nCanonical source: %s/%s.md — read it first for the full persona. This stub only\nregisters the agent with the harness; edit the canonical doc and re-run\nbash scripts/harness/sync. Non-blocking.\n"""\n' \
        "$CANONICAL_AGENTS" "$slug" "$name" "$desc" "$CANONICAL_AGENTS" "$slug"
}

if [ "$agent_providers_declared" -eq 1 ]; then
    for canonical in "$ROOT/$CANONICAL_AGENTS"/*.md; do
        [ -f "$canonical" ] || continue
        slug=$(basename "$canonical" .md)
        case "$slug" in _*|README) continue ;; esac
        if ! head -1 "$canonical" | grep -q '^---$'; then
            echo "ERROR: $CANONICAL_AGENTS/$slug.md has no YAML frontmatter — add name/description/tools to generate agent stubs"
            fail=1; continue
        fi
        a_name=$(agent_fm_field "$canonical" name)
        a_desc=$(agent_fm_field "$canonical" description)
        a_tools=$(agent_fm_field "$canonical" tools)
        a_title=$(grep -m1 '^# ' "$canonical" | sed 's/^# //' || true)
        [ -n "$a_title" ] || a_title="$slug"
        if [ -z "$a_name" ] || [ -z "$a_desc" ] || [ -z "$a_tools" ]; then
            echo "ERROR: $CANONICAL_AGENTS/$slug.md frontmatter must define name, description, and tools to generate agent stubs"
            fail=1; continue
        fi
        if [ "$a_name" != "$slug" ]; then
            echo "ERROR: $CANONICAL_AGENTS/$slug.md frontmatter name '$a_name' must equal its filename slug '$slug' (the routing name must match the file)"
            fail=1; continue
        fi
        for provider in $AGENT_PROVIDERS; do
            case "$provider" in
                .codex)
                    dest="$ROOT/$provider/agents/$slug.toml"; dest_rel="$provider/agents/$slug.toml"
                    stub=$(render_agent_toml "$a_name" "$a_desc" "$slug") ;;
                .opencode)
                    dest="$ROOT/$provider/agents/$slug.md"; dest_rel="$provider/agents/$slug.md"
                    stub=$(render_agent_md "$a_name" "$a_desc" "$a_tools" "$a_title" "$slug" "mode: subagent") ;;
                *)
                    dest="$ROOT/$provider/agents/$slug.md"; dest_rel="$provider/agents/$slug.md"
                    stub=$(render_agent_md "$a_name" "$a_desc" "$a_tools" "$a_title" "$slug") ;;
            esac
            if [ "$MODE" = "--check" ]; then
                if [ ! -f "$dest" ]; then
                    echo "STALE: agent stub $dest_rel is missing — run 'bash scripts/harness/sync' and commit the result"
                    fail=1
                elif [ "$(cat "$dest")" != "$stub" ]; then
                    echo "STALE: agent stub $dest_rel does not match the generator output (canonical: $CANONICAL_AGENTS/$slug.md) — run 'bash scripts/harness/sync' and commit the result"
                    fail=1
                fi
            else
                mkdir -p "$(dirname "$dest")"
                printf '%s\n' "$stub" > "$dest"
                echo "wrote $dest_rel"
            fi
        done
    done

    # Orphan agent stubs: a provider stub with no canonical persona drifts by
    # definition — the reverse half of the bidirectional equality.
    for provider in $AGENT_PROVIDERS; do
        for stub_file in "$ROOT/$provider"/agents/*.md "$ROOT/$provider"/agents/*.toml; do
            [ -f "$stub_file" ] || continue
            slug=$(basename "$stub_file"); slug=${slug%.md}; slug=${slug%.toml}
            if [ ! -f "$ROOT/$CANONICAL_AGENTS/$slug.md" ]; then
                echo "ORPHAN: $provider/agents/$(basename "$stub_file") has no canonical $CANONICAL_AGENTS/$slug.md — delete the stub or add the canonical persona"
                fail=1
            fi
        done
    done
else
    # Undeclared AGENT_PROVIDERS: loud once the repo actually has personas or
    # stubs (a legacy pre-declaration install — harness.conf is diff-only on
    # update, so the set never appears on its own). A harness with no agents at
    # all stays silent, like the skills path.
    have_agents=0
    for canonical in "$ROOT/$CANONICAL_AGENTS"/*.md; do
        [ -f "$canonical" ] || continue
        case "$(basename "$canonical")" in _*|README.md) continue ;; esac
        have_agents=1; break
    done
    if [ "$have_agents" -eq 0 ]; then
        for provider in .claude .cursor .codex .opencode; do
            for stub_file in "$ROOT/$provider"/agents/*; do
                [ -e "$stub_file" ] && { have_agents=1; break; }
            done
            [ "$have_agents" -eq 1 ] && break
        done
    fi
    if [ "$have_agents" -eq 1 ]; then
        echo "STALE: harness.conf declares no AGENT_PROVIDERS but agent personas or provider stubs exist — declare the agent-stub provider set (init populates it; update/audit proposes a set to confirm, never inferred from surviving stubs; see install-lib.sh harness_conf_declare). Agent-stub coherence cannot be validated until then."
        fail=1
    fi
fi

# --- Generated adapters ------------------------------------------------------
# One committed wiring summary per wired provider at .harness/adapters/<slug>.md
# (<slug> is the provider dir without its leading dot), rendered from the
# capability table + this repo's resolved wiring sets (ADR 011). Generated like
# a stub: written in write mode, pinned in --check, and an orphan (a provider
# dropped from HARNESS_PROVIDERS) fails in BOTH modes. The set of wired
# providers is the union of the resolved facet sets in capability-table order —
# it equals HARNESS_PROVIDERS when derived, or the explicit lists for a legacy
# install. Skipped entirely when the capability table is unavailable (a broken
# mechanism tree the drift checks already flag).

# render_adapter <provider> — the generated .harness/adapters/<slug>.md body.
render_adapter() {
    local prov="$1" skill agentd hookc execc
    local in_skill="no" in_agent="no" in_hook="no" in_exec="no"
    local skill_line agent_line hook_line exec_line native_line
    skill=$(harness_caps_field "$prov" 2 2>/dev/null || echo "?")
    agentd=$(harness_caps_field "$prov" 3 2>/dev/null || echo "none")
    hookc=$(harness_caps_field "$prov" 4 2>/dev/null || echo "none")
    execc=$(harness_caps_field "$prov" 5 2>/dev/null || echo "none")
    case " $PROVIDERS " in *" $prov "*) in_skill="yes" ;; esac
    case " ${AGENT_PROVIDERS:-} " in *" $prov "*) in_agent="yes" ;; esac
    case " ${HOOK_WIRED_PROVIDERS:-} " in *" $prov "*) in_hook="yes" ;; esac
    case " ${EXECUTION_PROFILE_PROVIDERS:-} " in *" $prov "*) in_exec="yes" ;; esac

    if [ "$skill" = "no" ]; then
        skill_line="reads \`$CANONICAL_SKILLS/\` natively — no generated skill stub"; native_line="yes"
    elif [ "$in_skill" = "yes" ]; then
        skill_line="generated in \`$prov/skills/\` from \`$CANONICAL_SKILLS/\`"; native_line="no"
    else
        skill_line="not wired"; native_line="no"
    fi
    if [ "$in_agent" = "yes" ] && [ "$agentd" != "none" ]; then
        agent_line="\`$agentd\` stubs in \`$prov/agents/\` from \`$CANONICAL_AGENTS/\`"
    else
        agent_line="not wired"
    fi
    if [ "$in_hook" = "yes" ] && [ "$hookc" != "none" ]; then
        hook_line="\`${hookc%:*}\` (${hookc##*:} shape)"
    elif [ "$hookc" = "none" ]; then
        hook_line="no bash hook shim (descoped)"
    else
        hook_line="not wired"
    fi
    if [ "$in_exec" = "yes" ] && [ "$execc" != "none" ]; then
        exec_line="adopted — floor validated in \`${execc%:*}\`"
    else
        exec_line="not adopted"
    fi

    printf '<!-- generated by scripts/harness/sync from scripts/harness/lib/provider-caps + HARNESS_PROVIDERS; do not edit -->\n'
    printf '# %s — harness wiring adapter\n\n' "$prov"
    printf 'Generated wiring summary for the `%s` provider. Do not edit by hand:\n' "$prov"
    printf 'change `HARNESS_PROVIDERS` (harness.conf) or the capability table\n'
    printf '(`scripts/harness/lib/provider-caps`) and run `bash scripts/harness/sync`.\n'
    printf '`sync --check` (CI-gated) fails if this file drifts.\n\n'
    printf -- '- **Skill stubs:** %s\n' "$skill_line"
    printf -- '- **Agent stubs:** %s\n' "$agent_line"
    printf -- '- **Hook wiring:** %s\n' "$hook_line"
    printf -- '- **Execution profile:** %s\n' "$exec_line"
    printf -- '- **Reads `%s/` natively:** %s\n' "$CANONICAL_SKILLS" "$native_line"
}

if command -v harness_caps_field >/dev/null 2>&1; then
    # The wired set: HARNESS_PROVIDERS when declared (even if empty — "wires no
    # providers" means no adapters), else the union of the explicit wiring
    # lists (a legacy pre-declaration install). NOT the PROVIDERS default
    # fallback, so a repo that declares nothing gets no adapters.
    if [ -n "${HARNESS_PROVIDERS+x}" ]; then
        adapter_source="$HARNESS_PROVIDERS"
    else
        adapter_source="${PROVIDERS:-} ${AGENT_PROVIDERS:-} ${HOOK_WIRED_PROVIDERS:-}"
    fi
    adapter_set=""
    for _p in $(harness_caps_providers 2>/dev/null); do
        case " $adapter_source " in
            *" $_p "*) adapter_set="$adapter_set $_p" ;;
        esac
    done
    adapter_set=${adapter_set# }

    # Adapters are an OPT-IN generated artifact: `sync` (write) creates them,
    # and thereafter --check keeps them complete and current. A repo that never
    # ran sync has none and is not nagged (unlike skill stubs, adapters are a
    # documentation summary, not functional wiring); once ANY exist, every
    # wired provider must have a current one and there must be no orphans. So
    # --check enforces only when adapters are already in use.
    adapters_present=0
    if [ -d "$ROOT/.harness/adapters" ]; then
        for adapter_file in "$ROOT"/.harness/adapters/*.md; do
            [ -f "$adapter_file" ] && { adapters_present=1; break; }
        done
    fi

    if [ "$MODE" != "--check" ] || [ "$adapters_present" -eq 1 ]; then
        for _p in $adapter_set; do
            slug=${_p#.}
            dest="$ROOT/.harness/adapters/$slug.md"
            dest_rel=".harness/adapters/$slug.md"
            adapter=$(render_adapter "$_p")
            if [ "$MODE" = "--check" ]; then
                if [ ! -f "$dest" ]; then
                    echo "STALE: adapter $dest_rel is missing — run 'bash scripts/harness/sync' and commit the result"
                    fail=1
                elif [ "$(cat "$dest")" != "$adapter" ]; then
                    echo "STALE: adapter $dest_rel does not match the generator output — run 'bash scripts/harness/sync' and commit the result"
                    fail=1
                fi
            else
                mkdir -p "$ROOT/.harness/adapters"
                printf '%s\n' "$adapter" > "$dest"
                echo "wrote $dest_rel"
            fi
        done

        # Orphan adapters: a provider dropped from the declaration leaves a
        # stale summary. Fails in BOTH modes (write completes, but the exit
        # must not read as clean, like orphan stubs).
        if [ -d "$ROOT/.harness/adapters" ]; then
            for adapter_file in "$ROOT"/.harness/adapters/*.md; do
                [ -f "$adapter_file" ] || continue
                aslug=$(basename "$adapter_file" .md)
                case " $adapter_set " in
                    *" .$aslug "*) ;;
                    *)
                        echo "ORPHAN: .harness/adapters/$aslug.md has no matching wired provider (.$aslug not in HARNESS_PROVIDERS) — delete it or re-add the provider"
                        fail=1 ;;
                esac
            done
        fi
    fi
fi

[ "$fail" -eq 0 ] || exit 1
exit 0
