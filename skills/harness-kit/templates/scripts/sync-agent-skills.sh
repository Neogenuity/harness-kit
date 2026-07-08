#!/usr/bin/env bash
# Generates the provider skill stubs (.claude/.cursor/.opencode/.agents —
# Codex reads .agents/skills/, so it needs no directory of its own)
# from the canonical skills in docs/skills/. docs/ is the single source of
# truth; the stubs exist only so each harness registers and auto-activates the
# skill. Frontmatter (name + description — the activation trigger) is copied
# verbatim from the canonical file, so tuning a trigger in the canonical
# skill propagates to every harness on the next sync.
#
#   bash scripts/sync-agent-skills.sh          # (re)write all stubs
#   bash scripts/sync-agent-skills.sh --check  # exit 1 if stubs are stale/missing/orphaned
#
# --check is wired into scripts/check-harness.sh (CI-gated), so a stub edited
# by hand, a canonical description change without a re-sync, or a stub missing
# from a provider dir fails the build.
#
# Providers and the canonical dir come from scripts/harness.conf.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness.conf" ] && . "$ROOT/scripts/harness.conf"
PROVIDERS="${PROVIDERS:-.claude .cursor .opencode .agents}"
CANONICAL_SKILLS="${CANONICAL_SKILLS:-docs/skills}"

MODE="${1:-write}"
case "$MODE" in
    write|--check) ;;
    *)
        echo "usage: bash scripts/sync-agent-skills.sh [--check]" >&2
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
    printf '%s\n\n# %s\n\nCanonical source: `%s/%s/SKILL.md`\n\nRead that file for the full skill before starting. This stub only registers the skill with the harness — edit the canonical file, then run `bash scripts/sync-agent-skills.sh`.\n' "$fm" "$title" "$CANONICAL_SKILLS" "$slug"
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
                echo "STALE: $dest_rel is missing — run 'bash scripts/sync-agent-skills.sh' and commit the result"
                fail=1
            elif [ "$(cat "$dest")" != "$stub" ]; then
                echo "STALE: $dest_rel does not match the generator output (canonical: $CANONICAL_SKILLS/$slug/SKILL.md) — run 'bash scripts/sync-agent-skills.sh' and commit the result"
                fail=1
            fi
        else
            mkdir -p "$(dirname "$dest")"
            printf '%s\n' "$stub" > "$dest"
            echo "wrote $dest_rel"
        fi
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

[ "$fail" -eq 0 ] || exit 1
exit 0
