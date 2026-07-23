#!/usr/bin/env bash
# Generates the provider skill stubs (.claude/.cursor/.opencode/.agents —
# Codex reads .agents/skills/, so it needs no directory of its own)
# from the canonical skills in docs/skills/. docs/ is the single source of
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
PROVIDERS="${PROVIDERS:-.claude .cursor .opencode .agents}"
CANONICAL_SKILLS="${CANONICAL_SKILLS:-docs/skills}"

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

[ "$fail" -eq 0 ] || exit 1
exit 0
