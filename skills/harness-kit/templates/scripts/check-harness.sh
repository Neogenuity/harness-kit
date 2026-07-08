#!/usr/bin/env bash
# Validates that the agent harness stays coherent: canonical skills are
# well-formed, provider stubs match the generator, AGENTS.md links resolve,
# hooks are executable and pass their regression tests.
#
# Run: bash scripts/check-harness.sh
# Exit code: 0 if all checks pass, 1 otherwise.
# Compatible with macOS (BSD grep) and Linux (GNU grep). CI-gated.
set -uo pipefail

ERRORS=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness.conf" ] && . "$ROOT/scripts/harness.conf"
PROVIDERS="${PROVIDERS:-.claude .cursor .codex .opencode .agents}"
CANONICAL_SKILLS="${CANONICAL_SKILLS:-docs/skills}"

echo "Checking agent harness..."

# 1. Canonical skills must have name/description frontmatter (agents use the
#    description as the trigger signal — a skill without it never auto-activates).
for skill in "$ROOT/$CANONICAL_SKILLS"/*/SKILL.md; do
    [ -f "$skill" ] || continue
    skill_rel=${skill#"$ROOT"/}
    if ! head -1 "$skill" | grep -q '^---$'; then
        echo "ERROR: $skill_rel has no YAML frontmatter (name/description required)"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    for key in name description; do
        if ! grep -qE "^${key}:" "$skill"; then
            echo "ERROR: $skill_rel frontmatter is missing '${key}:'"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

# 2. Provider skill copies must be pointer stubs, not full copies. The
#    canonical dir is the single source of truth; each provider SKILL.md must
#    carry a "Canonical source:" line naming an existing canonical file, and
#    stay small so full copies (which drift) cannot reappear.
STUB_MAX_LINES=25
for provider_dir in $PROVIDERS; do
    for stub in "$ROOT/$provider_dir"/skills/*/SKILL.md; do
        [ -f "$stub" ] || continue
        stub_rel=${stub#"$ROOT"/}
        canonical=$(grep -oE "${CANONICAL_SKILLS}/[A-Za-z0-9/_.-]+" "$stub" | head -1 || true)
        if [ -z "$canonical" ]; then
            echo "ERROR: $stub_rel has no 'Canonical source: $CANONICAL_SKILLS/...' pointer"
            ERRORS=$((ERRORS + 1))
        elif [ ! -f "$ROOT/$canonical" ]; then
            echo "ERROR: $stub_rel points to '$canonical' but that file does not exist"
            ERRORS=$((ERRORS + 1))
        fi
        lines=$(wc -l < "$stub" | tr -d '[:space:]')
        if [ "$lines" -gt "$STUB_MAX_LINES" ]; then
            echo "ERROR: $stub_rel is $lines lines (max $STUB_MAX_LINES) — provider skills must be pointer stubs, not full copies; edit the canonical file instead"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

# 3. Provider skill stubs must match the generator output exactly. This gives
#    frontmatter parity (the description is the activation trigger — a
#    canonical edit without a re-sync leaves harnesses firing on the stale
#    trigger) and full coverage (every skill present in every provider dir).
#    Complements check 2: that one bounds stub *shape*, this one pins *content*.
if [ -f "$ROOT/scripts/sync-agent-skills.sh" ]; then
    if ! bash "$ROOT/scripts/sync-agent-skills.sh" --check; then
        echo "ERROR: provider skill stubs are out of sync — run 'bash scripts/sync-agent-skills.sh' and commit the result"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 4. Relative markdown links in AGENTS.md must resolve (it is the table of
#    contents for the knowledge base — a dead link strands every agent).
if [ -f "$ROOT/AGENTS.md" ]; then
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        case "$link" in
            http://*|https://*|mailto:*|\#*) continue ;;
        esac
        target="${link%%#*}"
        [ -z "$target" ] && continue
        if [ ! -e "$ROOT/$target" ]; then
            echo "ERROR: AGENTS.md links to '$target' but it does not exist"
            ERRORS=$((ERRORS + 1))
        fi
    done < <(grep -oE '\]\([^)]+\)' "$ROOT/AGENTS.md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | sort -u)
fi

# 5. Hook scripts must be executable (a chmod lost in a copy or checkout
#    silently disables the hook — most harnesses skip non-executables).
for hook in "$ROOT"/scripts/hooks/*.sh; do
    [ -f "$hook" ] || continue
    if [ ! -x "$hook" ]; then
        echo "ERROR: ${hook#"$ROOT"/} is not executable — run 'chmod +x' and commit"
        ERRORS=$((ERRORS + 1))
    fi
done

# 6. Hook regression tests must pass.
for test in "$ROOT"/scripts/hooks/test-*.sh; do
    [ -f "$test" ] || continue
    if ! bash "$test" >/dev/null 2>&1; then
        echo "ERROR: ${test#"$ROOT"/} failed — run it directly for details"
        ERRORS=$((ERRORS + 1))
    fi
done

# 7. Cursor rules (if present) must stay anchored to the canonical docs: every
#    docs/*.md path a rule cites must exist, and each rule must cite at least
#    one — rules carry summarized key points, and the pointer keeps them honest.
if [ -d "$ROOT/.cursor/rules" ]; then
    for rule in "$ROOT"/.cursor/rules/*.mdc; do
        [ -f "$rule" ] || continue
        rule_rel=${rule#"$ROOT"/}
        refs=$(grep -oE 'docs/[A-Za-z0-9/_.-]+\.md' "$rule" | sort -u || true)
        if [ -z "$refs" ]; then
            echo "WARNING: $rule_rel cites no docs/*.md file — cursor rules should point at the canonical doc they summarize"
        fi
        while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            if [ ! -f "$ROOT/$ref" ]; then
                echo "ERROR: $rule_rel references '$ref' but that file does not exist"
                ERRORS=$((ERRORS + 1))
            fi
        done <<< "$refs"
    done
fi

# -- TAILOR: project-specific freshness checks below ---------------------------
# Add checks that keep YOUR docs honest against YOUR code layout, e.g.:
#   - every module dir referenced in the architecture doc exists
#   - every module dir is mentioned in the dependency map
#   - plans reference only existing paths
# ------------------------------------------------------------------------------

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS harness check(s)"
    exit 1
fi
echo "OK: agent harness is coherent"
exit 0
