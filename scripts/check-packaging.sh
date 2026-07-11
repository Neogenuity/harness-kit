#!/usr/bin/env bash
# Dogfood/release gate: the dual-provider packaging is internally consistent.
# Beyond "is it valid JSON", this asserts the cross-file invariants that let
# `/plugin marketplace add` (Claude Code) and `codex plugin marketplace add`
# (Codex) both resolve harness-kit at one agreed version:
#   - all four manifests are valid JSON
#   - VERSION is the single semver source; both plugin.json versions equal it
#   - name agreement across every manifest
#   - each marketplace source path is ./-relative, contained, and exists
#   - the Codex plugin's skills dir resolves inside the plugin root
#   - the Codex marketplace policy/category fields are present and in-enum
#   - each marketplace entry resolves to a plugin manifest carrying VERSION
# Root-only and tailored: this repo IS the distributed plugin, so these paths
# are fixed here. See docs/architecture/decisions/007-dual-provider-packaging.md.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

PLUGIN_DIR="plugins/harness-kit"
CLAUDE_PLUGIN="$PLUGIN_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN="$PLUGIN_DIR/.codex-plugin/plugin.json"
CLAUDE_MKT=".claude-plugin/marketplace.json"
AGENTS_MKT=".agents/plugins/marketplace.json"
VERSION_FILE="$PLUGIN_DIR/VERSION"
NAME="harness-kit"

errs=0
fail() { echo "  - $1"; errs=$((errs + 1)); }

# 1. every manifest is present and valid JSON
for f in "$CLAUDE_MKT" "$AGENTS_MKT" "$CLAUDE_PLUGIN" "$CODEX_PLUGIN"; do
    if [ ! -f "$f" ]; then fail "missing manifest: $f"; continue; fi
    jq empty "$f" 2>/dev/null || fail "invalid JSON: $f"
done
[ -f "$VERSION_FILE" ] || fail "missing $VERSION_FILE"
# Bail before the cross-file checks if any input is missing/broken.
[ "$errs" -eq 0 ] || { echo "FAILED: $errs packaging issue(s)"; exit 1; }

ver=$(tr -d '[:space:]' < "$VERSION_FILE")

# 2. VERSION is semver-shaped
printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$' \
    || fail "VERSION '$ver' is not semver-shaped"

# 3. version equality: VERSION == both plugin.json versions
for f in "$CLAUDE_PLUGIN" "$CODEX_PLUGIN"; do
    v=$(jq -r '.version // empty' "$f")
    [ "$v" = "$ver" ] || fail "$f version '$v' != VERSION '$ver'"
done

# 4. name agreement across every manifest
for pair in \
    "$CLAUDE_PLUGIN:.name" "$CODEX_PLUGIN:.name" \
    "$CLAUDE_MKT:.plugins[0].name" "$AGENTS_MKT:.plugins[0].name"; do
    f="${pair%%:*}"; q="${pair#*:}"
    n=$(jq -r "$q // empty" "$f")
    [ "$n" = "$NAME" ] || fail "$f $q '$n' != '$NAME'"
done

# 5. the Codex plugin's skills path resolves inside the plugin root
skills=$(jq -r '.skills // empty' "$CODEX_PLUGIN")
[ "$skills" = "./skills/" ] || fail "$CODEX_PLUGIN skills '$skills' != './skills/'"
[ -d "$PLUGIN_DIR/skills" ] || fail "skills dir $PLUGIN_DIR/skills does not exist"

# A marketplace source path must be ./-relative, free of .., and exist.
check_src_path() { # <label> <path>
    local label="$1" p="$2"
    case "$p" in
        ./*) ;;
        *) fail "$label source path '$p' is not ./-relative"; return ;;
    esac
    case "$p" in
        *..*) fail "$label source path '$p' escapes the marketplace root"; return ;;
    esac
    [ -d "$p" ] || fail "$label source path '$p' does not exist"
}

# 6. Claude marketplace: flat string source
csrc=$(jq -r '.plugins[0].source // empty' "$CLAUDE_MKT")
check_src_path "$CLAUDE_MKT" "$csrc"

# 7. Codex marketplace: nested object source + required policy/category fields
asrc_kind=$(jq -r '.plugins[0].source.source // empty' "$AGENTS_MKT")
[ "$asrc_kind" = "local" ] || fail "$AGENTS_MKT source.source '$asrc_kind' != 'local'"
asrc=$(jq -r '.plugins[0].source.path // empty' "$AGENTS_MKT")
check_src_path "$AGENTS_MKT" "$asrc"
inst=$(jq -r '.plugins[0].policy.installation // empty' "$AGENTS_MKT")
case "$inst" in
    AVAILABLE|INSTALLED_BY_DEFAULT|NOT_AVAILABLE) ;;
    *) fail "$AGENTS_MKT policy.installation '$inst' not in enum" ;;
esac
auth=$(jq -r '.plugins[0].policy.authentication // empty' "$AGENTS_MKT")
case "$auth" in
    ON_INSTALL|ON_FIRST_USE) ;;
    *) fail "$AGENTS_MKT policy.authentication '$auth' not in enum" ;;
esac
[ -n "$(jq -r '.plugins[0].category // empty' "$AGENTS_MKT")" ] \
    || fail "$AGENTS_MKT plugins[0].category is missing"

# 8. each marketplace entry resolves to a plugin manifest carrying VERSION
cres=$(jq -r '.version // empty' "$csrc/.claude-plugin/plugin.json" 2>/dev/null)
[ "$cres" = "$ver" ] || fail "Claude marketplace source resolves to version '$cres' != '$ver'"
ares=$(jq -r '.version // empty' "$asrc/.codex-plugin/plugin.json" 2>/dev/null)
[ "$ares" = "$ver" ] || fail "Codex marketplace source resolves to version '$ares' != '$ver'"

if [ "$errs" -gt 0 ]; then
    echo "FAILED: $errs packaging issue(s)"
    exit 1
fi
echo "PASSED: dual-provider packaging is consistent (v$ver)"
