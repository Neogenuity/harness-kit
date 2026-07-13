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

# 1. Canonical skills must satisfy the Agent Skills spec, not merely carry the
#    keys (agentskills.io/specification). The description is the activation
#    trigger, and a name that breaks the spec (wrong case, wrong parent dir,
#    consecutive hyphens, over-length) can silently fail to load in a strict
#    provider while passing a lax one — so these are ERRORs, checked here
#    rather than left as doctor hints. Prefer `skills-ref validate` when it is
#    on PATH (authoritative); otherwise fall back to dependency-free bash
#    checks, because the kit ships into repos that won't have it. Set
#    SKILLS_REF_BIN to a non-existent name to force the fallback (the tests do).
SKILLS_REF_BIN="${SKILLS_REF_BIN:-skills-ref}"
for skill in "$ROOT/$CANONICAL_SKILLS"/*/SKILL.md; do
    [ -f "$skill" ] || continue
    skill_rel=${skill#"$ROOT"/}
    skill_dir=$(basename "$(dirname "$skill")")

    # Authoritative validator when available — then skip the bash fallback.
    if command -v "$SKILLS_REF_BIN" >/dev/null 2>&1; then
        if ! sr_out=$("$SKILLS_REF_BIN" validate "$(dirname "$skill")" 2>&1); then
            echo "ERROR: $skill_rel failed '$SKILLS_REF_BIN validate': $sr_out"
            ERRORS=$((ERRORS + 1))
        fi
        continue
    fi

    # -- dependency-free fallback --
    if ! head -1 "$skill" | grep -q '^---[[:space:]]*$'; then
        echo "ERROR: $skill_rel has no YAML frontmatter (name/description required)"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    if ! awk 'NR==1{next} /^---[[:space:]]*$/{found=1; exit} END{exit !found}' "$skill"; then
        echo "ERROR: $skill_rel frontmatter has no closing '---' delimiter"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    for key in name description; do
        if ! grep -qE "^${key}:" "$skill"; then
            echo "ERROR: $skill_rel frontmatter is missing '${key}:'"
            ERRORS=$((ERRORS + 1))
        fi
    done
    name_val=$(grep -m1 -E '^name:' "$skill" \
        | sed -E "s/^name:[[:space:]]*//; s/[[:space:]]+$//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/")
    if [ -z "$name_val" ]; then
        echo "ERROR: $skill_rel frontmatter 'name:' value is empty (Agent Skills spec: 1-64 chars)"
        ERRORS=$((ERRORS + 1))
    else
        if [ "$name_val" != "$skill_dir" ]; then
            echo "ERROR: $skill_rel frontmatter name '$name_val' must equal its parent directory '$skill_dir' (Agent Skills spec)"
            ERRORS=$((ERRORS + 1))
        fi
        case "$name_val" in
            *[!a-z0-9-]*) echo "ERROR: $skill_rel frontmatter name '$name_val' has illegal characters (Agent Skills spec: lowercase a-z, 0-9, hyphens only)"; ERRORS=$((ERRORS + 1)) ;;
        esac
        case "$name_val" in
            -*|*-) echo "ERROR: $skill_rel frontmatter name '$name_val' must not start or end with a hyphen (Agent Skills spec)"; ERRORS=$((ERRORS + 1)) ;;
        esac
        case "$name_val" in
            *--*) echo "ERROR: $skill_rel frontmatter name '$name_val' must not contain consecutive hyphens (Agent Skills spec)"; ERRORS=$((ERRORS + 1)) ;;
        esac
        if [ "${#name_val}" -gt 64 ]; then
            echo "ERROR: $skill_rel frontmatter name exceeds 64 characters (Agent Skills spec limit)"
            ERRORS=$((ERRORS + 1))
        fi
    fi
    desc_len=$(awk '
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm && /^---[[:space:]]*$/    { exit }
        fm && /^description:/ { d=1; sub(/^description:[[:space:]]*([>|][-+]?)?[[:space:]]*/, ""); len+=length($0); next }
        d && /^[A-Za-z_-]+:/  { d=0 }
        d { gsub(/^[[:space:]]+/, ""); len+=length($0) }
        END { print len+0 }' "$skill")
    if [ "$desc_len" -eq 0 ]; then
        echo "ERROR: $skill_rel frontmatter 'description:' is empty (Agent Skills spec: 1-1024 chars; it is the activation trigger)"
        ERRORS=$((ERRORS + 1))
    elif [ "$desc_len" -gt 1024 ]; then
        echo "ERROR: $skill_rel frontmatter description is $desc_len characters (Agent Skills spec limit 1024)"
        ERRORS=$((ERRORS + 1))
    fi
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
#    test-install.sh drives fixtures that run check-harness.sh inside a throwaway
#    install; test-eval.sh clones fixtures whose graders run check-harness.sh.
#    HARNESS_NESTED_FIXTURE (set by test-install.sh, and by every eval grader that
#    calls check-harness.sh) makes THIS check skip only the tests that themselves
#    invoke check-harness.sh — test-install.sh and test-eval.sh (would recurse)
#    and test-check-harness.sh (already run at the top level, pure redundancy
#    inside a fixture). Every guard behavioral test (test-guard-*.sh, the catch
#    for a re-pinned guard weakening) always runs, so no single env var can switch
#    off the security-relevant regression layer. Unset in normal and CI runs.
for test in "$ROOT"/scripts/test-*.sh "$ROOT"/scripts/hooks/test-*.sh; do
    [ -f "$test" ] || continue
    case "$(basename "$test")" in
        test-install.sh|test-check-harness.sh|test-eval.sh)
            [ -n "${HARNESS_NESTED_FIXTURE:-}" ] && continue ;;
    esac
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

# 8c. MCP servers get the same single-source + drift-check treatment as the
#     secret patterns (#8/#8b), extended to server *identity*: an allowed name
#     silently repointed at other code is exactly the attack a bare allowlist
#     cannot see. harness.conf's MCP_ALLOWED_SERVERS is the single source — one
#     "<name> <expected-identity-substring>" per non-# line. Enabled servers are
#     extracted per the provider matrix's MCP row (verified 2026-07): .mcp.json
#     and .cursor/mcp.json `mcpServers` (identity = command + joined args, or
#     url), opencode.json `mcp` (same shape), and .codex/config.toml
#     `[mcp_servers.*]` tables (best-effort header + command/args/url scan;
#     quoted table names unwrapped). Entries flagged "disabled": true /
#     "enabled": false are skipped; an empty map is silent (the shipped opencode
#     template carries "mcp": {}, and file existence alone must not warn).
#     Split severity: an UNSET inventory with an enabled server present is the
#     adoption path (one WARN); once the inventory is SET (even empty), a server
#     whose name is uncovered or whose identity no longer contains its pinned
#     substring is an ERROR — the same "drift from a declared single source is a
#     silent hole" logic as #8; a config that exists but cannot be parsed (or jq
#     absent while a JSON config exists) is a WARN naming the unaudited file
#     ("not audited" is never silent); no configs → silent regardless. Matching
#     is fixed-string (grep -F, set -f discipline): substring identity matching
#     detects drift, it does not prove equivalence — as honest as #8's.
mcp_inventory="${MCP_ALLOWED_SERVERS:-}"
mcp_inventory_declared=0
[ -n "${MCP_ALLOWED_SERVERS+x}" ] && mcp_inventory_declared=1
mcp_saw_enabled_server=0
mcp_tab=$(printf '\t')

# The pin is the point: a name-only inventory line would make the identity
# check vacuous (an empty grep -F pattern matches every identity), so a
# declared line with no identity substring is itself an ERROR, whether or not
# that server is currently configured anywhere.
if [ "$mcp_inventory_declared" -eq 1 ] && [ -n "$mcp_inventory" ]; then
    while IFS= read -r mcp_line; do
        mcp_line=${mcp_line#"${mcp_line%%[![:space:]]*}"}
        case "$mcp_line" in ''|\#*) continue ;; esac
        mcp_lname=${mcp_line%%[[:space:]]*}
        mcp_lpin=${mcp_line#"$mcp_lname"}
        mcp_lpin=${mcp_lpin#"${mcp_lpin%%[![:space:]]*}"}
        mcp_lpin=${mcp_lpin%"${mcp_lpin##*[![:space:]]}"}
        if [ -z "$mcp_lpin" ]; then
            echo "ERROR: MCP_ALLOWED_SERVERS line '$mcp_lname' has no identity substring — a name-only line pins nothing (any identity would pass); add the expected command/args or URL fragment after the name (harness.conf)"
            ERRORS=$((ERRORS + 1))
        fi
    done <<EOF
$mcp_inventory
EOF
fi

# name -> pinned identity substring: prints the pin and returns 0 when the name
# is present in the inventory, else returns 1. The pin may itself contain
# whitespace (a command+args fragment), so it is "everything after the first
# whitespace run".
mcp_inventory_lookup() {
    local want="$1" line lname lpin
    while IFS= read -r line; do
        line=${line#"${line%%[![:space:]]*}"}            # trim leading whitespace
        case "$line" in ''|\#*) continue ;; esac
        lname=${line%%[[:space:]]*}
        case "$line" in
            *[[:space:]]*)
                lpin=${line#"$lname"}
                lpin=${lpin#"${lpin%%[![:space:]]*}"}     # trim leading whitespace
                lpin=${lpin%"${lpin##*[![:space:]]}"} ;;  # trim trailing whitespace
            *) lpin="" ;;
        esac
        [ "$lname" = "$want" ] || continue
        printf '%s' "$lpin"
        return 0
    done <<EOF
$mcp_inventory
EOF
    return 1
}

# Apply the split-severity policy to a batch of "<name>\t<identity>" lines from
# one config file ($2 = its repo-relative path, named in every message).
mcp_apply_severity() {
    local servers="$1" file="$2" name identity pin matched
    [ -n "$servers" ] || return 0
    while IFS="$mcp_tab" read -r name identity; do
        [ -n "$name" ] || continue
        mcp_saw_enabled_server=1
        [ "$mcp_inventory_declared" -eq 1 ] || continue   # no inventory: WARN once, later
        if pin=$(mcp_inventory_lookup "$name"); then
            # Fixed-string, glob-disabled: the identity must CONTAIN the pin.
            set -f
            printf '%s' "$identity" | grep -qF -- "$pin"; matched=$?
            set +f
            if [ "$matched" -ne 0 ]; then
                echo "ERROR: MCP server '$name' in $file has a configured identity ('$identity') that does not contain its pinned substring '$pin' (harness.conf MCP_ALLOWED_SERVERS) — identity drift; the server may be repointed. Re-verify and update its inventory line."
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "ERROR: MCP server '$name' in $file is not covered by the MCP trust inventory (harness.conf MCP_ALLOWED_SERVERS) — add a '$name <expected-identity-substring>' line after verifying what it runs, or remove the server."
            ERRORS=$((ERRORS + 1))
        fi
    done <<EOF
$servers
EOF
}

# Extract + audit a JSON MCP config ($1 = repo-relative path, $2 = the
# top-level key holding the server map). jq absent, or a parse failure, is a
# loud "not audited" WARN — never a silent skip. Non-object entries under the
# key are ignored, not fatal: a junk sibling value must not crash the jq
# program and downgrade a real drift ERROR on the same file into a parse WARN.
mcp_audit_json() {
    local rel="$1" key="$2" out rc stripped after_first
    [ -f "$ROOT/$rel" ] || return 0
    # Trivially-empty map fast path, dependency-free: the shipped opencode
    # template carries "mcp": {}, and a machine without jq must not WARN
    # forever about a config with zero servers. Only taken when the key
    # occurs exactly once — a decoy empty map alongside a real key falls
    # through to the audited paths below.
    stripped=$(tr -d '[:space:]' < "$ROOT/$rel" 2>/dev/null)
    case "$stripped" in
        *"\"$key\":{}"*)
            after_first=${stripped#*"\"$key\":"}
            case "$after_first" in
                *"\"$key\":"*) ;;
                *) return 0 ;;
            esac ;;
    esac
    if ! command -v jq >/dev/null 2>&1; then
        echo "WARNING: $rel is an MCP config but jq is unavailable — its servers are not audited against the trust inventory (harness.conf MCP_ALLOWED_SERVERS)"
        return 0
    fi
    out=$(jq -r --arg k "$key" '
        def ident:
            if (.url // null) != null then (.url | tostring)
            else ((.command // "") | if type == "array" then join(" ") else tostring end)
                 + " " + ((.args // []) | if type == "array" then join(" ") else tostring end)
            end;
        (.[$k] // {}) | to_entries[]
        | select((.value | type) == "object")
        | select(((.value.disabled // false) != true) and ((.value.enabled // true) != false))
        | [.key, (.value | ident)] | @tsv
    ' "$ROOT/$rel" 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "WARNING: $rel could not be parsed as JSON — its MCP servers are not audited against the trust inventory (harness.conf MCP_ALLOWED_SERVERS)"
        return 0
    fi
    mcp_apply_severity "$out" "$rel"
}

# Best-effort scan of .codex/config.toml [mcp_servers.*] tables — full TOML
# parsing is out of scope (documented). Reads table headers plus the
# command/args/url/enabled/disabled lines inside each table; needs no jq.
mcp_audit_toml() {
    local rel="$1" out
    [ -f "$ROOT/$rel" ] || return 0
    out=$(awk '
        function trim(s){ sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
        /^[[:space:]]*\[/ {
            hdr=$0; sub(/^[[:space:]]*\[+/,"",hdr); sub(/\].*$/,"",hdr); hdr=trim(hdr)
            cur=""
            if (index(hdr,"mcp_servers.")==1) {
                rest=substr(hdr,length("mcp_servers.")+1)
                qc=substr(rest,1,1)
                if (qc=="\"" || qc=="'\''") {
                    rest=substr(rest,2); q=index(rest,qc)
                    if (q>0) nm=substr(rest,1,q-1); else nm=rest
                } else {
                    d=index(rest,"."); if (d>0) nm=substr(rest,1,d-1); else nm=rest
                }
                if (nm!="") { cur=nm
                    if (!(cur in seen)) { seen[cur]=1; order[++n]=cur; ident[cur]=""; dis[cur]=0 } }
            }
            next
        }
        cur!="" {
            l=trim($0)
            if (l ~ /^command[[:space:]]*=/)     { v=l; sub(/^command[[:space:]]*=[[:space:]]*/,"",v); ident[cur]=ident[cur] " " v }
            else if (l ~ /^args[[:space:]]*=/)   { v=l; sub(/^args[[:space:]]*=[[:space:]]*/,"",v);    ident[cur]=ident[cur] " " v }
            else if (l ~ /^url[[:space:]]*=/)    { v=l; sub(/^url[[:space:]]*=[[:space:]]*/,"",v);     ident[cur]=ident[cur] " " v }
            else if (l ~ /^disabled[[:space:]]*=[[:space:]]*true/) { dis[cur]=1 }
            else if (l ~ /^enabled[[:space:]]*=[[:space:]]*false/) { dis[cur]=1 }
        }
        END { for (i=1;i<=n;i++){ c=order[i]; if(dis[c]) continue; s=ident[c]; gsub(/[[:space:]]+/," ",s); s=trim(s); printf "%s\t%s\n", c, s } }
    ' "$ROOT/$rel" 2>/dev/null)
    mcp_apply_severity "$out" "$rel"
}

mcp_audit_json ".mcp.json" "mcpServers"
mcp_audit_json ".cursor/mcp.json" "mcpServers"
mcp_audit_json "opencode.json" "mcp"
mcp_audit_toml ".codex/config.toml"

if [ "$mcp_inventory_declared" -eq 0 ] && [ "$mcp_saw_enabled_server" -eq 1 ]; then
    echo "WARNING: MCP servers configured but no trust inventory declared — set MCP_ALLOWED_SERVERS in harness.conf to pin each enabled server's expected identity (name + a command/args or URL substring); until then their identities are unaudited"
fi

# 8d. Semantic hook-wiring validation. The 8-family checks provider-config
#     SEMANTICS the manifest deliberately does not byte-pin (they are tailored
#     policy): #8/#8b the native secret deny lists, #8c MCP server identity, and
#     here the per-provider hook wiring. For every hook-wired provider, each
#     required (config path, event, matcher, script) TUPLE from the frozen
#     provider-matrix hook table must hold — the guard on its correct event and
#     matcher, its command resolving to an existing executable script. Presence
#     alone is NOT enough: a guard swapped onto the wrong event, or a matcher
#     weakened so it no longer covers Grep/Write, passes a presence check while
#     leaving the guard inert. The empirical hole this closes: deleting the whole
#     `hooks` object from .claude/settings.json used to leave check-harness green.
#
#     Which providers are hook-wired is DECLARED (harness.conf
#     HOOK_WIRED_PROVIDERS), never inferred from directory presence — a provider
#     dir also holds generated stubs, so a deleted .cursor/hooks.json would be
#     indistinguishable from a provider never wired. A declared provider whose
#     config is missing is an ERROR (mirrors #8's deleted-settings.json stance).
#     harness.conf is tailored/diff-only on update, so a pre-declaration install
#     would validate ZERO providers — to keep the headline hole from shipping, an
#     adopted harness that leaves the set UNSET is a loud ERROR until update/audit
#     proposes a set and the user confirms it (install-lib.sh harness_conf_declare;
#     never inferred from surviving configs). Structural validation, never
#     byte-pinning; the tuple parse is jq-gated like the rest of the 8-family
#     (guards fail open without jq, and the doctor already WARNs), but the
#     declared-yet-missing-config and undeclared-yet-adopted ERRORs need no jq.
hook_tab=$(printf '\t')

# hook_check_provider <provider_dir> — validates one declared hook-wired
# provider against the frozen tuple table, incrementing the shared ERRORS.
hook_check_provider() {
    local prov="$1" cfg shape tuples rows rc script event matcher info path
    local scriptpath wrongev badm
    case "$prov" in
        .claude)
            cfg=".claude/settings.json"; shape="nested"
            # "<script> <event> [<matcher>]"; no matcher field = require none;
            # @any = event pinned, matcher not pinned (the contract for .codex
            # and .cursor, whose matchers the provider matrix leaves open).
            tuples='session-context.sh SessionStart
guard-secrets.sh PreToolUse Read|Grep
guard-config.sh PreToolUse Edit|Write
format.sh PostToolUse Edit|Write
guard-project-policy.sh Stop' ;;
        .cursor)
            cfg=".cursor/hooks.json"; shape="flat"
            tuples='session-context.sh sessionStart @any
guard-secrets.sh beforeReadFile @any
format.sh afterFileEdit @any
guard-project-policy.sh stop @any' ;;
        .codex)
            cfg=".codex/hooks.json"; shape="nested"
            tuples='session-context.sh SessionStart @any
guard-secrets.sh PreToolUse @any
guard-config.sh PreToolUse @any
format.sh PostToolUse @any
guard-project-policy.sh Stop @any' ;;
        *)
            echo "ERROR: HOOK_WIRED_PROVIDERS names '$prov' but check-harness.sh has no hook-tuple contract for it — only .claude, .cursor, .codex are hook-wired; remove it or extend the contract table"
            ERRORS=$((ERRORS + 1)); return ;;
    esac

    if [ ! -f "$ROOT/$cfg" ]; then
        echo "ERROR: hook-wired provider '$prov' is declared (harness.conf HOOK_WIRED_PROVIDERS) but its hook config $cfg is missing — restore it or remove '$prov' from the declaration (mirrors #8's deleted-settings.json stance)"
        ERRORS=$((ERRORS + 1)); return
    fi

    # Parsing the wiring needs jq; without it the guards fail open anyway.
    command -v jq >/dev/null 2>&1 || return 0
    if [ "$shape" = "nested" ]; then
        rows=$(jq -r '(.hooks // {}) | to_entries[] | .key as $ev | (.value[]?) | (.matcher // "") as $m | (.hooks[]?.command // empty) as $c | [$ev, $m, $c] | @tsv' "$ROOT/$cfg" 2>/dev/null); rc=$?
    else
        rows=$(jq -r '(.hooks // {}) | to_entries[] | .key as $ev | (.value[]?) | [$ev, "", (.command // empty)] | @tsv' "$ROOT/$cfg" 2>/dev/null); rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: hook-wired provider '$prov' config $cfg could not be parsed as JSON — its hook wiring cannot be validated; fix the file"
        ERRORS=$((ERRORS + 1)); return
    fi

    # Tuple coverage: each required guard on its correct event (+ matcher). awk
    # computes the verdict per guard (no subshell touches ERRORS); the heredoc
    # loop stays in this shell so ERRORS increments persist.
    while read -r script event matcher; do
        [ -n "$script" ] || continue
        scriptpath="scripts/hooks/$script"
        info=$(printf '%s\n' "$rows" | awk -F"$hook_tab" -v sp="$scriptpath" -v ev="$event" -v m="$matcher" '
            index($3, sp) { ref=1
                if ($1==ev) { evok=1; if (m=="@any" || $2==m) full=1; else badm=$2 }
                else wrongev=$1 }
            END {
                if (!ref) { print "NOREF"; exit }
                if (full) { print "OK"; exit }
                if (evok) { print "BADM\t" badm; exit }
                print "BADEV\t" wrongev }')
        case "$info" in
            OK) : ;;
            NOREF)
                echo "ERROR: guard $script is not wired in $cfg — the frozen provider-matrix contract requires it on event '$event'; every declared hook-wired provider must carry all its required guards"
                ERRORS=$((ERRORS + 1)) ;;
            BADEV*)
                wrongev=${info#BADEV"$hook_tab"}
                echo "ERROR: guard $script is wired on event '$wrongev' in $cfg but the frozen contract requires '$event' — a guard on the wrong event does not fire when it must"
                ERRORS=$((ERRORS + 1)) ;;
            BADM*)
                badm=${info#BADM"$hook_tab"}
                echo "ERROR: guard $script on '$event' in $cfg has matcher '$badm', not the required '$matcher' — a weakened matcher narrows the guard's coverage (e.g. dropping Grep or Write)"
                ERRORS=$((ERRORS + 1)) ;;
        esac
    done <<HOOK_TUPLES
$tuples
HOOK_TUPLES

    # Command resolvability: every referenced scripts/hooks/*.sh must exist and
    # be executable — a command repointed at a missing/renamed script is a silent
    # no-op the tuple table alone would miss. Pull the script paths straight out
    # of every command (no tab field-split — an empty matcher field collapses
    # under read's whitespace-IFS), dedup, and check each.
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ ! -x "$ROOT/$path" ]; then
            echo "ERROR: a hook command in $cfg points at '$path' but that script is missing or not executable — restore it (chmod +x) or fix the command"
            ERRORS=$((ERRORS + 1))
        fi
    done <<HOOK_ROWS
$(printf '%s\n' "$rows" | grep -oE 'scripts/hooks/[A-Za-z0-9_.-]+\.sh' | sort -u)
HOOK_ROWS
}

hook_wired_declared=0
[ -n "${HOOK_WIRED_PROVIDERS+x}" ] && hook_wired_declared=1
if [ "$hook_wired_declared" -eq 0 ]; then
    # Undeclared: only a diagnostic once the harness is adopted (scripts/hooks/
    # present) — a brand-new repo that has not run init yet still skips, like #9.
    if [ -d "$ROOT/scripts/hooks" ]; then
        echo "ERROR: harness is adopted (scripts/hooks/ present) but harness.conf declares no HOOK_WIRED_PROVIDERS — the semantic hook-wiring check would validate ZERO providers, leaving every provider's hooks silently disableable. Declare the hook-wired set (init populates it; update/audit proposes a set to confirm — never inferred from surviving configs; see install-lib.sh harness_conf_declare). Set it to \"\" if this harness wires no hooks."
        ERRORS=$((ERRORS + 1))
    fi
else
    for hook_prov in $HOOK_WIRED_PROVIDERS; do
        hook_check_provider "$hook_prov"
    done
fi

# 9. Mechanism files must match scripts/.harness-manifest (kit version plus
#    sha256 per file, written at init). An un-pinned edit — agent, human, or
#    merge — fails CI, so nobody can quietly rewrite a guard. Lines ending in
#    '# tailored' are deliberate local forks: still checksum-verified here
#    (integrity), but never auto-replaced by the kit's update mode and exempt
#    from template-equality checks (ownership) — the marker changes who may
#    rewrite the file, not whether edits must be pinned.
#    Because shell edits (rm, sed -i, `: >`) are unscanned by the guards by
#    design, this manifest is the enforcing layer for them — so it is defended on
#    three fronts, all against an adopted repo (scripts/hooks/ present): (9b) a
#    missing / emptied / all-malformed manifest is an ERROR, not a silent skip;
#    (9a) a nonempty malformed line does not count as a pin; and (9c) every
#    mechanism file on disk must be pinned, so *partial* pin deletion (un-pinning
#    one guard while leaving others) is caught. A brand-new repo that has not run
#    init yet (no scripts/hooks/) still skips.
sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    fi
}
MANIFEST="$ROOT/scripts/.harness-manifest"

# 9a. Verify each pinned file, and REJECT malformed entries. A well-formed line is
#     "<64-hex sha256>  <path>"; a nonempty garbage line (e.g. `x`) must not count
#     as a pin — otherwise it would satisfy the adopted-repo guard (9b) while
#     enforcing nothing. valid_pins counts only well-formed entries.
valid_pins=0
if [ -f "$MANIFEST" ] && [ -n "$(sha256_of "$MANIFEST")" ]; then
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        want=${line%% *}
        path=$(printf '%s\n' "$line" | awk '{print $2}')
        if ! printf '%s' "$want" | grep -qE '^[0-9a-fA-F]{64}$' || [ -z "$path" ]; then
            echo "ERROR: scripts/.harness-manifest has a malformed entry (expected '<sha256>  <path>'): '$line'"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        valid_pins=$((valid_pins + 1))
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
    done < "$MANIFEST"
fi

# 9b. An adopted repo (scripts/hooks/ present) must have a manifest carrying at
#     least one VALID pin. Catches a missing, emptied/header-only, or all-malformed
#     manifest — each collapses the enforcing layer for shell edits. Pre-adoption
#     repos (no scripts/hooks/) still skip.
if [ -d "$ROOT/scripts/hooks" ] && [ "$valid_pins" -eq 0 ]; then
    echo "ERROR: harness is adopted (scripts/hooks/ present) but scripts/.harness-manifest is missing or has no valid pinned entries — it is the integrity pin for the mechanism (the enforcing layer for shell edits the guards can't scan); a deleted, emptied, or malformed manifest lets guards be rewritten undetected. Restore it (re-pin per the kit's init step 8)"
    ERRORS=$((ERRORS + 1))
fi

# 9c. Manifest COMPLETENESS: every mechanism file present on disk must be pinned.
#     The expected set is derived from the FILESYSTEM, not the manifest (which is
#     what an attacker edits) — a file must be on disk to run, so if it is on disk
#     it must be pinned. This closes *partial* pin deletion: removing the manifest
#     line for a still-present guard (leaving other pins, so 9b passes) would
#     otherwise silently exempt that guard from checksum verification. The set
#     mirrors install-lib.sh's _HARNESS_MECHANISM_TOPLEVEL + the hooks/ tree.
#     Gated on scripts/hooks/ present (adopted): to dodge it an attacker would
#     have to delete the hooks tree — i.e. the guards themselves — which defeats
#     the point. (Also keeps pre-adoption / minimal fixtures out of scope.)
if [ -f "$MANIFEST" ] && [ -d "$ROOT/scripts/hooks" ]; then
    pinned_paths=$(awk '$1 ~ /^[0-9a-fA-F]{64}$/ {print $2}' "$MANIFEST")
    for mech in "$ROOT"/scripts/hooks/* \
                "$ROOT"/scripts/harness.conf "$ROOT"/scripts/check-harness.sh \
                "$ROOT"/scripts/sync-agent-skills.sh "$ROOT"/scripts/install-lib.sh \
                "$ROOT"/scripts/eval-lib.sh "$ROOT"/scripts/eval.sh \
                "$ROOT"/scripts/eval-harness.sh \
                "$ROOT"/scripts/verify.sh "$ROOT"/scripts/test-*.sh; do
        [ -f "$mech" ] || continue
        rel="scripts/${mech#"$ROOT"/scripts/}"
        printf '%s\n' "$pinned_paths" | grep -qxF "$rel" || {
            echo "ERROR: mechanism file '$rel' is present but not pinned in scripts/.harness-manifest — every mechanism file on disk must be integrity-pinned; an unpinned file is silently exempt from checksum verification. Re-pin it (init step 8)"
            ERRORS=$((ERRORS + 1))
        }
    done
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
done
# (Skill name/description spec conformance — kebab-case, length, non-empty,
#  name==dir — is now enforced as ERRORs in check 1, not warned here.)

# 10b. Doctor: active plans that have gone stale. A plan in PLANS_DIR that has
#      lost its 'Next action', or hasn't been touched in a month, is usually
#      abandoned — yet the session banner keeps announcing it. Age uses git
#      commit time (file mtime is checkout time), so it needs a real history:
#      it is a no-op in the shallow checkout the shipped CI uses
#      (actions/checkout defaults to fetch-depth 1) and skips gracefully with
#      no git at all — effective in local doctor runs.
PLANS_DIR="${PLANS_DIR:-docs/plans/active}"
PLAN_STALE_DAYS="${HARNESS_PLAN_STALE_DAYS:-30}"
if [ -d "$ROOT/$PLANS_DIR" ]; then
    _now=$(date +%s)
    for plan in "$ROOT/$PLANS_DIR"/*.md; do
        [ -f "$plan" ] || continue
        case "$(basename "$plan")" in README.md) continue ;; esac
        plan_rel=${plan#"$ROOT"/}
        grep -qE '^#+[[:space:]]+Next action' "$plan" \
            || echo "WARNING: $plan_rel (active plan) has no 'Next action' section — a resuming session can't tell what to do next"
        if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
            _ct=$(git -C "$ROOT" log -1 --format=%ct -- "$plan_rel" 2>/dev/null)
            if [ -n "$_ct" ]; then
                _age=$(( (_now - _ct) / 86400 ))
                [ "$_age" -ge "$PLAN_STALE_DAYS" ] \
                    && echo "WARNING: $plan_rel (active plan) last changed $_age days ago (>= $PLAN_STALE_DAYS) — update it or move it to completed/"
            fi
        fi
    done
fi

# 10c. Doctor: keep a verification-stamped reference (e.g. a provider/capability
#      matrix) fresh. Watches PROVIDER_MATRIX_DOC (default
#      references/provider-matrix.md; absent in most repos, so a no-op there).
#      Stamps are self-dating text ("verified YYYY-MM" or "YYYY-MM-DD"), so —
#      unlike the plan check — this needs no git history and works in shallow
#      CI. WARNs on a stamp older than the configured age, and on a doc that has
#      tables but carries no stamp at all.
MATRIX_DOC="${PROVIDER_MATRIX_DOC:-references/provider-matrix.md}"
MATRIX_STALE_DAYS="${HARNESS_MATRIX_STALE_DAYS:-90}"
if [ -f "$ROOT/$MATRIX_DOC" ]; then
    _thresh=$(date -d "-${MATRIX_STALE_DAYS} days" +%F 2>/dev/null \
        || date -v-"${MATRIX_STALE_DAYS}"d +%F 2>/dev/null || true)
    _stamps=$(grep -oE 'verified [0-9]{4}-[0-9]{2}(-[0-9]{2})?' "$ROOT/$MATRIX_DOC" \
        | sed -E 's/^verified //' | sort -u)
    if [ -z "$_stamps" ] && grep -qE '^\|.*\|' "$ROOT/$MATRIX_DOC"; then
        echo "WARNING: $MATRIX_DOC has tables but no 'verified <date>' stamps — its facts carry no freshness marker"
    fi
    if [ -n "$_thresh" ]; then
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            case "$_s" in ????-??) _cmp="${_s}-01" ;; *) _cmp="$_s" ;; esac
            if [[ "$_cmp" < "$_thresh" ]]; then
                echo "WARNING: $MATRIX_DOC has a 'verified $_s' stamp older than $MATRIX_STALE_DAYS days — re-verify those facts against their primary docs and restamp"
            fi
        done <<< "$_stamps"
    fi
fi

# 10d. Doctor: CI workflow actions should be pinned to an immutable commit SHA.
#      A `uses:` ref pointing at a tag or branch is mutable — a retagged or
#      compromised third-party action would run with the workflow's token, the
#      supply-chain exposure the shipped-CI hardening closes. Local `uses: ./path`
#      composite actions are first-party and skipped, as are `docker://` refs
#      (a different pinning model). Freshness/hygiene WARNING like the other
#      doctor checks — it never fails the build. Best-effort line scan; full
#      YAML parsing is out of scope.
if [ -d "$ROOT/.github/workflows" ]; then
    for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
        [ -f "$wf" ] || continue
        wf_rel=${wf#"$ROOT"/}
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            case "$ref" in
                ./*|docker://*) continue ;;
            esac
            # ${ref##*@} is the pin (the whole ref when there is no '@' — an
            # unpinned owner/repo is mutable too). A full commit SHA is 40 hex.
            if ! printf '%s' "${ref##*@}" | grep -qE '^[0-9a-fA-F]{40}$'; then
                echo "WARNING: $wf_rel uses '$ref' pinned to a mutable ref — pin third-party actions to a full 40-char commit SHA (a tag or branch can be moved under you); keep the human-readable tag in a trailing comment"
            fi
        done < <(grep -oE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^[:space:]]+' "$wf" 2>/dev/null \
                    | sed -E 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//' \
                    | tr -d "\"'")
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
