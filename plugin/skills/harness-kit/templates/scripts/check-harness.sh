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
PROVIDERS="${PROVIDERS:-.claude .cursor .opencode .agents}"
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

# 4. Relative markdown links in the knowledge base must resolve — AGENTS.md
#    (root and nested, per the hierarchical standard) and every doc under
#    docs/. A dead link strands every agent. Fenced code blocks are ignored;
#    a link passes if it resolves from the doc's own directory OR the repo
#    root (both conventions are common).
check_doc_links() {
    local doc="$1" doc_rel base link target
    doc_rel=${doc#"$ROOT"/}
    base=$(dirname "$doc")
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        case "$link" in
            http://*|https://*|mailto:*|\#*) continue ;;
        esac
        target="${link%%#*}"
        # Strip an optional link title and unwrap an <angle-bracketed>
        # destination so the existence test sees the path alone:
        #   [t](dest "title")  [t](dest 'title')  [t](dest (title))  [t](<dest>)
        # Per CommonMark a bare destination ends at the first space; an
        # angle-bracketed one ends at '>' and may itself contain spaces.
        target="${target#"${target%%[![:space:]]*}"}"   # trim leading space
        case "$target" in
            "<"*) target="${target#<}"; target="${target%%>*}" ;;
            *)    target="${target%% *}" ;;
        esac
        [ -z "$target" ] && continue
        if [ ! -e "$base/$target" ] && [ ! -e "$ROOT/$target" ]; then
            echo "ERROR: $doc_rel links to '$target' but it does not exist"
            ERRORS=$((ERRORS + 1))
        fi
    done < <(awk '/^```/ { fence = !fence; next } !fence' "$doc" 2>/dev/null \
        | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//' | sort -u)
}
while IFS= read -r doc; do
    check_doc_links "$doc"
done < <({ find "$ROOT" -name AGENTS.md \
             -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*'; \
           [ -d "$ROOT/docs" ] && find "$ROOT/docs" -name '*.md'; } 2>/dev/null | sort -u)

# 5. Harness scripts must be executable (a chmod lost in a copy or checkout
#    silently disables a hook — most harnesses skip non-executables).
for hook in "$ROOT"/scripts/*.sh "$ROOT"/scripts/hooks/*.sh; do
    [ -f "$hook" ] || continue
    if [ ! -x "$hook" ]; then
        echo "ERROR: ${hook#"$ROOT"/} is not executable — run 'chmod +x' and commit"
        ERRORS=$((ERRORS + 1))
    fi
done

# 6. Regression tests must pass — both hook guards (scripts/hooks/test-*.sh)
#    and top-level mechanism tests (scripts/test-*.sh, e.g. test-check-harness.sh).
for test in "$ROOT"/scripts/test-*.sh "$ROOT"/scripts/hooks/test-*.sh; do
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

# 8. The Claude Code native deny list must cover the shared secret patterns
#    from harness.conf. guard-secrets.sh only works where hooks fire; the
#    native list is the backstop (subagent contexts, hookless sessions), so
#    the two layers drifting apart is a silent hole. Matching is substring-
#    based (a deny entry mentioning the pattern counts) — this detects drift,
#    it does not prove equivalence. Skipped when jq or the conf vars are
#    absent (pre-0.2.0 installs) — but a wired .claude/ with the settings
#    file deleted is an ERROR, not a skip: removing the file would silently
#    remove the backstop along with the check that notices.
if command -v jq >/dev/null 2>&1 && [ -n "${SECRET_PATTERNS:-}" ]; then
    if [ -f "$ROOT/.claude/settings.json" ]; then
        deny_list=$(jq -r '.permissions.deny[]? // empty' "$ROOT/.claude/settings.json" 2>/dev/null)
        set -f
        for pat in $SECRET_PATTERNS; do
            if ! printf '%s\n' "$deny_list" | grep -qF "$pat"; then
                echo "ERROR: secret pattern '$pat' (harness.conf SECRET_PATTERNS) has no matching Read(...) entry in .claude/settings.json permissions.deny — add one; the native deny list must mirror the guard"
                ERRORS=$((ERRORS + 1))
            fi
        done
        set +f
    elif [ -d "$ROOT/.claude" ]; then
        echo "ERROR: .claude/ is wired but .claude/settings.json is missing — it carries the native secret deny list (guard-secrets.sh's backstop); restore it or remove the provider dir"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 8b. Same drift check for OpenCode's native deny list (opencode.json
#     permission.read). guard-secrets.sh only fires where hooks run; this
#     native list is the backstop for OpenCode, so it must mirror the same
#     patterns. Substring-based, like check #8; skipped when jq or the conf
#     vars are absent — but a wired .opencode/ with opencode.json deleted is
#     an ERROR, not a skip (same reasoning as #8).
if command -v jq >/dev/null 2>&1 && [ -n "${SECRET_PATTERNS:-}" ]; then
    if [ -f "$ROOT/opencode.json" ]; then
        oc_deny=$(jq -r '.permission.read // {} | to_entries[]? | select(.value == "deny") | .key' "$ROOT/opencode.json" 2>/dev/null)
        set -f
        for pat in $SECRET_PATTERNS; do
            if ! printf '%s\n' "$oc_deny" | grep -qF "$pat"; then
                echo "ERROR: secret pattern '$pat' (harness.conf SECRET_PATTERNS) has no matching \"deny\" entry in opencode.json permission.read — add one; the native deny list must mirror the guard"
                ERRORS=$((ERRORS + 1))
            fi
        done
        set +f
    elif [ -d "$ROOT/.opencode" ]; then
        echo "ERROR: .opencode/ is wired but opencode.json is missing — it carries OpenCode's native secret deny list (guard-secrets.sh's backstop); restore it or remove the provider dir"
        ERRORS=$((ERRORS + 1))
    fi
fi

# 9. Mechanism files must match scripts/.harness-manifest (kit version plus
#    sha256 per file, written at init). An un-pinned edit — agent, human, or
#    merge — fails CI, so nobody can quietly rewrite a guard. Lines ending in
#    '# tailored' are deliberate local forks: still checksum-verified here
#    (integrity), but never auto-replaced by the kit's update mode and exempt
#    from template-equality checks (ownership) — the marker changes who may
#    rewrite the file, not whether edits must be pinned.
sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    fi
}
if [ -f "$ROOT/scripts/.harness-manifest" ] && [ -n "$(sha256_of "$ROOT/scripts/.harness-manifest")" ]; then
    while IFS= read -r line; do
        case "$line" in
            \#*|"") continue ;;
        esac
        want=${line%% *}
        path=$(printf '%s\n' "$line" | awk '{print $2}')
        [ -n "$path" ] || continue
        if [ ! -f "$ROOT/$path" ]; then
            echo "ERROR: scripts/.harness-manifest lists '$path' but it does not exist — restore the file or remove the manifest line"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        have=$(sha256_of "$ROOT/$path")
        if [ "$have" != "$want" ]; then
            case "$line" in
                *"# tailored"*)
                    echo "ERROR: '$path' does not match its scripts/.harness-manifest pin — tailored files are still checksum-verified ('# tailored' only exempts them from template replacement). If the change is intentional, re-pin its line (shasum -a 256 $path), keeping the ' # tailored' marker" ;;
                *)
                    echo "ERROR: '$path' does not match scripts/.harness-manifest. If the change is intentional, re-pin its line (shasum -a 256 $path) — append ' # tailored' for a deliberate fork the kit's update mode must never overwrite" ;;
            esac
            ERRORS=$((ERRORS + 1))
        fi
    done < "$ROOT/scripts/.harness-manifest"
fi

# 10. Doctor: conditions that silently weaken the harness. Warnings only —
#     they don't fail the build, they tell you where the floor is soft.
command -v jq >/dev/null 2>&1 \
    || echo "WARNING: jq not found — every guard hook fails open without it; the native permission deny lists are the only live layer"
if [ -f "$ROOT/AGENTS.md" ]; then
    agents_lines=$(wc -l < "$ROOT/AGENTS.md" | tr -d '[:space:]')
    [ "$agents_lines" -gt 120 ] \
        && echo "WARNING: AGENTS.md is $agents_lines lines (target <=120) — it should route to docs/, not explain; instruction compliance degrades as it grows"
fi
for skill in "$ROOT/$CANONICAL_SKILLS"/*/SKILL.md; do
    [ -f "$skill" ] || continue
    skill_rel=${skill#"$ROOT"/}
    skill_lines=$(wc -l < "$skill" | tr -d '[:space:]')
    [ "$skill_lines" -gt 500 ] \
        && echo "WARNING: $skill_rel is $skill_lines lines (target <=500) — move detail into the skill's references/ (progressive disclosure)"
    name_val=$(grep -m1 -E '^name:' "$skill" | sed -E 's/^name:[[:space:]]*//' || true)
    if [ -n "$name_val" ]; then
        case "$name_val" in
            *[!a-z0-9-]*) echo "WARNING: $skill_rel frontmatter name '$name_val' is not kebab-case (Agent Skills spec: lowercase a-z, 0-9, hyphens)" ;;
        esac
        [ "${#name_val}" -gt 64 ] \
            && echo "WARNING: $skill_rel frontmatter name exceeds 64 characters (Agent Skills spec limit)"
    fi
    desc_len=$(awk '
        NR==1 && $0=="---" { fm=1; next }
        fm && $0=="---"    { exit }
        fm && /^description:/ { d=1; sub(/^description:[[:space:]]*[>|]?-?[[:space:]]*/, ""); len+=length($0); next }
        d && /^[A-Za-z_-]+:/  { d=0 }
        d { gsub(/^[[:space:]]+/, ""); len+=length($0) }
        END { print len+0 }' "$skill")
    [ "$desc_len" -gt 1024 ] \
        && echo "WARNING: $skill_rel frontmatter description is $desc_len characters (Agent Skills spec limit 1024) — routers truncate; tighten the trigger"
done

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
