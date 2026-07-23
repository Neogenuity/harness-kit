#!/usr/bin/env bash
# check-instructions.sh — the "instructions" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/check-instructions. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

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
if [ -f "$ROOT/scripts/harness/sync" ]; then
    if ! bash "$ROOT/scripts/harness/sync" --check; then
        echo "ERROR: provider skill stubs are out of sync — run 'bash scripts/harness/sync' and commit the result"
        ERRORS=$((ERRORS + 1))
    fi
fi


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
            # Pipe-free membership test — see the check #9 completeness note
            # for why printf|grep -q is banned in this script.
            case "$deny_list" in
                *"$pat"*) ;;
                *)
                    echo "ERROR: secret pattern '$pat' (harness.conf SECRET_PATTERNS) has no matching Read(...) entry in .claude/settings.json permissions.deny — add one or run 'bash scripts/harness/sync secrets' to regenerate; the native deny list must mirror the guard"
                    ERRORS=$((ERRORS + 1)) ;;
            esac
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
            # Pipe-free membership test — see the check #9 completeness note.
            case "$oc_deny" in
                *"$pat"*) ;;
                *)
                    echo "ERROR: secret pattern '$pat' (harness.conf SECRET_PATTERNS) has no matching \"deny\" entry in opencode.json permission.read — add one or run 'bash scripts/harness/sync secrets' to regenerate; the native deny list must mirror the guard"
                    ERRORS=$((ERRORS + 1)) ;;
            esac
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
            # Pipe-free (see the check #9 completeness note); a quoted case
            # pattern is literal, matching what grep -qF gave here.
            case "$identity" in
                *"$pin"*) matched=0 ;;
                *)        matched=1 ;;
            esac
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
#     Boundary (as honest as #8/#8c's "detects drift, not equivalence"): this
#     validates the wiring STRUCTURE — which script is bound to which
#     event/matcher — by matching the script path inside the command string. It
#     does not prove the command actually execs that script, so a deliberately
#     neutered command that only name-drops the path (e.g. `true # .../guard.sh`)
#     is out of scope here; guard-config.sh (tool-mediated edits) and the
#     manifest (the scripts themselves) are the layers that defend against that.
hook_tab=$(printf '\t')

# hook_check_provider <provider_dir> — validates one declared hook-wired
# provider against the frozen tuple table, incrementing the shared ERRORS.
# Which providers are hook-wired is DERIVED from HARNESS_PROVIDERS via the
# capability table's hook_config column (check-common.sh; ADR 011); the config
# path + jq shape + event/matcher tuple contract stay inline here (a frozen,
# richer contract than a table cell).
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
        # Mechanism guards live in the kit tree; the project-policy stop hook
        # is repo-owned at .harness/hooks/ (v0.23.0 ownership split).
        case "$script" in
            guard-project-policy.sh) scriptpath=".harness/hooks/$script" ;;
            *) scriptpath="scripts/harness/hooks/$script" ;;
        esac
        info=$(printf '%s\n' "$rows" | awk -F"$hook_tab" -v sp="$scriptpath" -v ev="$event" -v m="$matcher" '
            # covers(required, configured): true when the configured matcher fires
            # on at least every event the required one does. Weakening (a missing
            # required token) fails; widening or reordering passes. Empty = the
            # universal matcher (fires on all events): a universal config covers any
            # requirement, but a universal REQUIREMENT (no-matcher guards like
            # SessionStart/Stop) is only met by a universal config — adding a
            # matcher there narrows coverage and must fail.
            function covers(req, got,   a, b, i, j, n, ok) {
                if (req == "") return (got == "")
                if (got == "") return 1
                n = split(req, a, "|"); split(got, b, "|")
                for (i=1;i<=n;i++){ ok=0; for(j in b) if(b[j]==a[i]){ok=1;break}; if(!ok) return 0 }
                return 1 }
            index($3, sp) { ref=1
                if ($1==ev) { evok=1; if (m=="@any" || covers(m, $2)) full=1; else badm=$2 }
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
                echo "ERROR: guard $script on '$event' in $cfg has matcher '$badm', which does not cover the required '$matcher' — a weakened matcher narrows the guard's coverage (e.g. dropping Grep or Write). Widening or reordering is fine; a missing required tool is not."
                ERRORS=$((ERRORS + 1)) ;;
        esac
    done <<HOOK_TUPLES
$tuples
HOOK_TUPLES

    # Command resolvability: every referenced hook script — kit-owned
    # scripts/harness/hooks/*.sh or repo-owned .harness/hooks/*.sh — must exist
    # and be executable; a command repointed at a missing/renamed script is a
    # silent no-op the tuple table alone would miss. Pull the script paths
    # straight out of every command (no tab field-split — an empty matcher
    # field collapses under read's whitespace-IFS), dedup, and check each.
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ ! -x "$ROOT/$path" ]; then
            echo "ERROR: a hook command in $cfg points at '$path' but that script is missing or not executable — restore it (chmod +x) or fix the command"
            ERRORS=$((ERRORS + 1))
        fi
    done <<HOOK_ROWS
$(printf '%s\n' "$rows" | grep -oE '(scripts/harness|\.harness)/hooks/[A-Za-z0-9_.-]+\.sh' | sort -u)
HOOK_ROWS
}

hook_wired_declared=0
[ -n "${HOOK_WIRED_PROVIDERS+x}" ] && hook_wired_declared=1
if [ "$hook_wired_declared" -eq 0 ]; then
    # Undeclared: only a diagnostic once the harness is adopted (scripts/harness/hooks/
    # present) — a brand-new repo that has not run init yet still skips, like #9.
    if [ -d "$ROOT/scripts/harness/hooks" ]; then
        echo "ERROR: harness is adopted (scripts/harness/hooks/ present) but harness.conf declares no HOOK_WIRED_PROVIDERS — the semantic hook-wiring check would validate ZERO providers, leaving every provider's hooks silently disableable. Declare the hook-wired set (init populates it; update/audit proposes a set to confirm — never inferred from surviving configs; see install-lib.sh harness_conf_declare). Set it to \"\" if this harness wires no hooks."
        ERRORS=$((ERRORS + 1))
    fi
else
    for hook_prov in $HOOK_WIRED_PROVIDERS; do
        hook_check_provider "$hook_prov"
    done
fi

# 8e. Stable execution-profile validation. Adoption is OPTIONAL and DECLARED
#     through EXECUTION_PROFILE_PROVIDERS; unset/empty means unadopted and is a
#     clean pass. Never infer adoption from surviving provider configs: a config
#     deleted before audit is indistinguishable from a provider never adopted.
#     Once declared, however, the provider's native config is a security policy:
#     missing, malformed, or weakened required values are ERRORs. Extra provider
#     settings remain project-owned and are ignored by this floor check.
execution_json_require() {
    local provider="$1" cfg="$2" key="$3" filter="$4"
    if ! jq -e "$filter" "$ROOT/$cfg" >/dev/null 2>&1; then
        echo "ERROR: $provider stable execution profile requires '$key' in $cfg; restore the declared profile floor or remove $provider from EXECUTION_PROFILE_PROVIDERS"
        ERRORS=$((ERRORS + 1))
    fi
}

execution_check_json_config() {
    local provider="$1" cfg="$2"
    if [ ! -f "$ROOT/$cfg" ]; then
        echo "ERROR: execution-profile provider '$provider' is declared (harness.conf EXECUTION_PROFILE_PROVIDERS) but $cfg is missing — restore it or remove '$provider' from the declaration"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: execution-profile provider '$provider' is declared but jq is unavailable, so $cfg cannot be semantically validated"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    if ! jq -e . "$ROOT/$cfg" >/dev/null 2>&1; then
        echo "ERROR: execution-profile provider '$provider' config $cfg is malformed JSON — its declared security profile cannot be validated"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    return 0
}

execution_check_claude() {
    local cfg=".claude/settings.json" provider=".claude"
    execution_check_json_config "$provider" "$cfg" || return
    execution_json_require "$provider" "$cfg" "sandbox.enabled = true" '.sandbox.enabled? == true'
    execution_json_require "$provider" "$cfg" "sandbox.failIfUnavailable = true" '.sandbox.failIfUnavailable? == true'
    execution_json_require "$provider" "$cfg" "sandbox.allowUnsandboxedCommands = true" '.sandbox.allowUnsandboxedCommands? == true'
    execution_json_require "$provider" "$cfg" "sandbox.excludedCommands is absent or []" '(.sandbox | (has("excludedCommands") | not) or (.excludedCommands == []))'
    execution_json_require "$provider" "$cfg" "sandbox.filesystem.allowWrite = []" '.sandbox.filesystem.allowWrite? == []'
    execution_json_require "$provider" "$cfg" "sandbox.network.allowedDomains = []" '.sandbox.network.allowedDomains? == []'
    execution_json_require "$provider" "$cfg" "sandbox.network.deniedDomains contains *" '((.sandbox.network.deniedDomains? | type) == "array") and ((.sandbox.network.deniedDomains | index("*")) != null)'
    execution_json_require "$provider" "$cfg" "sandbox.network.allowLocalBinding = false" '.sandbox.network.allowLocalBinding? == false'
    execution_json_require "$provider" "$cfg" "sandbox.network.allowAllUnixSockets = false" '.sandbox.network.allowAllUnixSockets? == false'
    execution_json_require "$provider" "$cfg" "sandbox.network.allowUnixSockets is absent or []" '(.sandbox.network | (has("allowUnixSockets") | not) or (.allowUnixSockets == []))'
    execution_json_require "$provider" "$cfg" "sandbox.network.allowMachLookup is absent or []" '(.sandbox.network | (has("allowMachLookup") | not) or (.allowMachLookup == []))'
    execution_json_require "$provider" "$cfg" "sandbox.enableWeakerNetworkIsolation is absent or false" '(.sandbox | (has("enableWeakerNetworkIsolation") | not) or (.enableWeakerNetworkIsolation == false))'
    execution_json_require "$provider" "$cfg" "sandbox.enableWeakerNestedSandbox is absent or false" '(.sandbox | (has("enableWeakerNestedSandbox") | not) or (.enableWeakerNestedSandbox == false))'
    execution_json_require "$provider" "$cfg" "sandbox.credentials.files denies ~/.aws/credentials" 'any(.sandbox.credentials.files[]?; .path == "~/.aws/credentials" and .mode == "deny")'
    execution_json_require "$provider" "$cfg" "sandbox.credentials.files denies ~/.ssh" 'any(.sandbox.credentials.files[]?; .path == "~/.ssh" and .mode == "deny")'
    execution_json_require "$provider" "$cfg" "sandbox.credentials.envVars denies GITHUB_TOKEN" 'any(.sandbox.credentials.envVars[]?; .name == "GITHUB_TOKEN" and .mode == "deny")'
    execution_json_require "$provider" "$cfg" "sandbox.credentials.envVars denies NPM_TOKEN" 'any(.sandbox.credentials.envVars[]?; .name == "NPM_TOKEN" and .mode == "deny")'
}

execution_check_cursor() {
    local cfg=".cursor/sandbox.json" provider=".cursor"
    execution_check_json_config "$provider" "$cfg" || return
    execution_json_require "$provider" "$cfg" "type = workspace_readwrite" '.type? == "workspace_readwrite"'
    execution_json_require "$provider" "$cfg" "additionalReadwritePaths = []" '.additionalReadwritePaths? == []'
    execution_json_require "$provider" "$cfg" "additionalReadonlyPaths = []" '.additionalReadonlyPaths? == []'
    execution_json_require "$provider" "$cfg" "disableTmpWrite = false" '.disableTmpWrite? == false'
    execution_json_require "$provider" "$cfg" "enableSharedBuildCache = false" '.enableSharedBuildCache? == false'
    execution_json_require "$provider" "$cfg" "networkPolicy.default = deny" '.networkPolicy.default? == "deny"'
    execution_json_require "$provider" "$cfg" "networkPolicy.allow = []" '.networkPolicy.allow? == []'
    # Extra deny entries only tighten a default-deny profile; require the
    # documented array shape without rejecting project-specific denials.
    execution_json_require "$provider" "$cfg" "networkPolicy.deny is an array" '(.networkPolicy.deny? | type) == "array"'
}

# toml_profile_value <file> <semantic-key>
# Dependency-free, narrow TOML reader for the stable Codex floor. It reads keys
# semantically within their table (order/spacing/comments/quote style do not
# matter), normalizes strings, booleans, and empty arrays, and rejects duplicate
# or malformed required values. Unrelated tables and multiline values are left
# alone rather than pretending this portable bash+jq harness ships a TOML parser.
toml_profile_value() {
    awk -v want="$2" '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        function uncomment(s,    i,c,q,esc,out) {
            q=""; esc=0; out=""
            for (i=1; i<=length(s); i++) {
                c=substr(s,i,1)
                if (esc) { out=out c; esc=0; continue }
                if (q=="\"" && c=="\\") { out=out c; esc=1; continue }
                if (q=="") {
                    if (c=="#") break
                    if (c=="\"" || c=="\047") q=c
                } else if (c==q) q=""
                out=out c
            }
            return out
        }
        function normalized(v,    first,last) {
            v=trim(v); first=substr(v,1,1); last=substr(v,length(v),1)
            if (length(v)>=2 && ((first=="\"" && last=="\"") || (first=="\047" && last=="\047"))) return substr(v,2,length(v)-2)
            if (v=="true" || v=="false") return v
            if (v ~ /^\[[[:space:]]*\]$/) return "[]"
            if (v ~ /^\{[[:space:]]*\}$/) return "{}"
            return "!malformed"
        }
        {
            line=trim(uncomment($0)); if (line=="") next
            if (line ~ /^\[[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*\]$/) {
                section=line; sub(/^\[[[:space:]]*/, "", section); sub(/[[:space:]]*\]$/, "", section)
                if (section==want) table_count++
                next
            }
            eq=index(line,"="); if (!eq) next
            key=trim(substr(line,1,eq-1)); value=substr(line,eq+1)
            path=(section=="" ? key : section "." key)
            # Dotted keys at the root are already their full semantic path.
            if (path==want || (section=="" && key==want)) { count++; result=normalized(value) }
        }
        END {
            if (count==0) {
                if (table_count>0) { print "!malformed"; exit }
                exit 1
            }
            if (count>1) { print "!duplicate"; exit }
            print result
        }
    ' "$1"
}

execution_codex_require() {
    local cfg="$1" key="$2" expected="$3" value rc
    value=$(toml_profile_value "$cfg" "$key"); rc=$?
    if [ "$rc" -ne 0 ] || [ "$value" != "$expected" ]; then
        echo "ERROR: .codex declared execution profile requires '$key = $expected' in .codex/config.toml; the key is missing, malformed, duplicated, or outside the accepted profile tuple"
        ERRORS=$((ERRORS + 1))
    fi
}

execution_codex_optional_false() {
    local cfg="$1" key="$2" value rc
    value=$(toml_profile_value "$cfg" "$key"); rc=$?
    [ "$rc" -eq 1 ] && return
    if [ "$rc" -ne 0 ] || [ "$value" != "false" ]; then
        echo "ERROR: .codex experimental local/private compatibility profile requires optional '$key' to be absent or false in .codex/config.toml"
        ERRORS=$((ERRORS + 1))
    fi
}

execution_check_codex() {
    local cfg="$ROOT/.codex/config.toml" network_access network_rc proxy_state domains_exact unix_sockets_empty
    if [ ! -f "$cfg" ]; then
        echo "ERROR: execution-profile provider '.codex' is declared (harness.conf EXECUTION_PROFILE_PROVIDERS) but .codex/config.toml is missing — restore it or remove '.codex' from the declaration"
        ERRORS=$((ERRORS + 1))
        return
    fi
    # The semantic floor below deliberately stays dependency-light and focused,
    # but it must never bless a file Codex itself cannot parse. Python's stdlib
    # TOML parser is a conditional prerequisite only for a declared Codex
    # profile; isolated mode prevents the target repo from shadowing tomllib.
    if ! command -v python3 >/dev/null 2>&1 \
            || ! python3 -I -c 'import tomllib' >/dev/null 2>&1; then
        echo "ERROR: execution-profile provider '.codex' requires Python 3.11+ with tomllib to validate complete .codex/config.toml — the declared profile is unverifiable"
        ERRORS=$((ERRORS + 1))
        return
    fi
    if ! proxy_state=$(python3 -I - "$cfg" <<'PY'
import sys
import tomllib

try:
    with open(sys.argv[1], "rb") as config:
        data = tomllib.load(config)
except (OSError, UnicodeError, tomllib.TOMLDecodeError):
    raise SystemExit(1)

features = data.get("features", {})
if not isinstance(features, dict):
    features = {}
proxy = features.get("network_proxy", {})
if not isinstance(proxy, dict):
    proxy = {}
domains_exact = proxy.get("domains") == {
    "localhost": "allow",
    "127.0.0.1": "allow",
}
unix_sockets_empty = proxy.get("unix_sockets", {}) == {}
print(f"{int(domains_exact)} {int(unix_sockets_empty)}")
PY
    ); then
        echo "ERROR: execution-profile provider '.codex' config .codex/config.toml is malformed TOML — its declared security profile cannot be validated"
        ERRORS=$((ERRORS + 1))
        return
    fi
    domains_exact=${proxy_state%% *}
    unix_sockets_empty=${proxy_state#* }
    execution_codex_require "$cfg" "sandbox_mode" "workspace-write"
    execution_codex_require "$cfg" "approval_policy" "on-request"
    execution_codex_require "$cfg" "approvals_reviewer" "user"
    execution_codex_require "$cfg" "allow_login_shell" "false"
    execution_codex_require "$cfg" "sandbox_workspace_write.writable_roots" "[]"
    execution_codex_require "$cfg" "sandbox_workspace_write.exclude_tmpdir_env_var" "false"
    execution_codex_require "$cfg" "sandbox_workspace_write.exclude_slash_tmp" "false"
    execution_codex_require "$cfg" "shell_environment_policy.inherit" "core"
    execution_codex_require "$cfg" "shell_environment_policy.ignore_default_excludes" "false"

    network_access=$(toml_profile_value "$cfg" "sandbox_workspace_write.network_access"); network_rc=$?
    case "$network_rc:$network_access" in
        0:false) ;;
        0:true)
            execution_codex_require "$cfg" "features.network_proxy.enabled" "true"
            execution_codex_require "$cfg" "features.network_proxy.allow_local_binding" "true"
            if [ "$domains_exact" != "1" ]; then
                echo "ERROR: .codex experimental local/private compatibility profile requires 'features.network_proxy.domains = exactly localhost/127.0.0.1 allow' in .codex/config.toml; public, wildcard, extra, denied, or duplicate entries are not accepted"
                ERRORS=$((ERRORS + 1))
            fi
            if [ "$unix_sockets_empty" != "1" ]; then
                echo "ERROR: .codex experimental local/private compatibility profile requires 'features.network_proxy.unix_sockets = absent or empty' in .codex/config.toml"
                ERRORS=$((ERRORS + 1))
            fi
            execution_codex_optional_false "$cfg" "features.network_proxy.dangerously_allow_non_loopback_proxy"
            execution_codex_optional_false "$cfg" "features.network_proxy.dangerously_allow_all_unix_sockets"
            ;;
        *)
            echo "ERROR: .codex declared execution profile requires 'sandbox_workspace_write.network_access = false' or the exact experimental broad local/private compatibility variant in .codex/config.toml; the key is missing, malformed, or duplicated"
            ERRORS=$((ERRORS + 1))
            ;;
    esac
}

execution_check_opencode() {
    local cfg="opencode.json" provider=".opencode"
    execution_check_json_config "$provider" "$cfg" || return
    execution_json_require "$provider" "$cfg" "permission.external_directory = deny" '.permission.external_directory? == "deny"'
    execution_json_require "$provider" "$cfg" "permission.bash = ask" '.permission.bash? == "ask"'
    execution_json_require "$provider" "$cfg" "permission.webfetch = deny" '.permission.webfetch? == "deny"'
    execution_json_require "$provider" "$cfg" "permission.websearch = deny" '.permission.websearch? == "deny"'
}

execution_seen=" "
for execution_provider in ${EXECUTION_PROFILE_PROVIDERS:-}; do
    case "$execution_provider" in
        .claude|.cursor|.codex|.opencode) ;;
        *)
            echo "ERROR: EXECUTION_PROFILE_PROVIDERS names unknown provider '$execution_provider' — allowed values: .claude .cursor .codex .opencode"
            ERRORS=$((ERRORS + 1))
            continue ;;
    esac
    case "$execution_seen" in
        *" $execution_provider "*)
            echo "ERROR: EXECUTION_PROFILE_PROVIDERS contains duplicate provider '$execution_provider' — declare each adopted provider once"
            ERRORS=$((ERRORS + 1))
            continue ;;
    esac
    execution_seen="$execution_seen$execution_provider "
    # Execution-profile adoption is opt-in and SEPARATE from wiring (ADR 011):
    # it is NOT derived from HARNESS_PROVIDERS, because the strict runtime
    # sandbox floors routinely conflict with local dev. But a floor can only be
    # adopted for a provider this repo actually wires — when HARNESS_PROVIDERS
    # is declared, the adopted set must be a subset of it.
    if [ -n "${HARNESS_PROVIDERS+x}" ]; then
        case " $HARNESS_PROVIDERS " in
            *" $execution_provider "*) ;;
            *)
                echo "ERROR: EXECUTION_PROFILE_PROVIDERS names '$execution_provider' but it is not in HARNESS_PROVIDERS — an execution floor can only be adopted for a wired provider; add it to HARNESS_PROVIDERS or drop it here"
                ERRORS=$((ERRORS + 1))
                continue ;;
        esac
    fi
    case "$execution_provider" in
        .claude) execution_check_claude ;;
        .cursor) execution_check_cursor ;;
        .codex) execution_check_codex ;;
        .opencode) execution_check_opencode ;;
    esac
done


# 8f. The single provider declaration (harness.conf HARNESS_PROVIDERS) is what
#     the kit capability table derives every per-facet wiring set from
#     (check-common.sh; ADR 011). Validate the declaration itself: each entry
#     must be a KNOWN provider (present in scripts/harness/lib/provider-caps)
#     and appear at most once. An unknown or duplicated entry silently drops
#     from every derived set — a wiring hole the downstream per-set checks
#     (#8d hooks, sync stubs) cannot see, because they only receive the
#     already-derived set. Skipped when the declaration or the table is absent
#     (a legacy pre-declaration install keeps the explicit four lists, which
#     #8d/#8e/sync validate directly).
if [ -n "${HARNESS_PROVIDERS+x}" ] && command -v harness_caps_providers >/dev/null 2>&1; then
    hp_known=" $(harness_caps_providers | tr '\n' ' ') "
    hp_seen=" "
    for hp in $HARNESS_PROVIDERS; do
        case "$hp_known" in
            *" $hp "*) ;;
            *)
                echo "ERROR: HARNESS_PROVIDERS names unknown provider '$hp' — it has no row in the capability table (scripts/harness/lib/provider-caps), so it would drop from every derived wiring set. Known providers:$hp_known"
                ERRORS=$((ERRORS + 1)); continue ;;
        esac
        case "$hp_seen" in
            *" $hp "*)
                echo "ERROR: HARNESS_PROVIDERS lists '$hp' more than once — declare each wired provider exactly once"
                ERRORS=$((ERRORS + 1)); continue ;;
        esac
        hp_seen="$hp_seen$hp "
    done
fi

check_trailer "instructions"
