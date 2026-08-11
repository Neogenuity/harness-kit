#!/usr/bin/env bash
# Shared, fail-open writer for harness outcome events. Source this file; it
# defines functions and performs no work. The v2 envelope has exactly these
# top-level keys:
#   version, ts, hook, event, file, detail, context, data

# _harness_log_bounded <value> <max> <slug-only>
# Prints a safe attribution value or nothing. Attribution is optional; an
# invalid or overlong value is omitted rather than allowed to break work.
_harness_log_bounded() {
    local value="${1:-}" max="${2:-128}" slug_only="${3:-0}"
    [ -n "$value" ] || return 0
    [ "${#value}" -le "$max" ] || return 0
    case "$value" in *[$'\001'-$'\037'$'\177']*) return 0 ;; esac
    if [ "$slug_only" -eq 1 ]; then
        case "$value" in *[!A-Za-z0-9._/-]*) return 0 ;; esac
    fi
    printf '%s' "$value"
}

# harness_log_context <run-id> <run-source> <session-id> <session-source>
#                     <provider> <provider-source> <plan-slug> <plan-source>
# Emits one compact context object. Sources are a closed vocabulary; callers
# must pass an empty value rather than infer an attribution they do not know.
harness_log_context() {
    command -v jq >/dev/null 2>&1 || { printf '{}'; return 0; }
    local run_id session_id provider plan_slug
    local run_source="${2:-}" session_source="${4:-}" provider_source="${6:-}" plan_source="${8:-}"
    run_id=$(_harness_log_bounded "${1:-}" 128 1)
    session_id=$(_harness_log_bounded "${3:-}" 256 0)
    provider=$(_harness_log_bounded "${5:-}" 64 1)
    plan_slug=$(_harness_log_bounded "${7:-}" 128 1)
    case "$run_source" in verify|env) ;; *) run_id=""; run_source="" ;; esac
    case "$session_source" in env|payload|provider-env) ;; *) session_id=""; session_source="" ;; esac
    case "$provider_source" in env|provider-env) ;; *) provider=""; provider_source="" ;; esac
    case "$plan_source" in env) ;; *) plan_slug=""; plan_source="" ;; esac
    jq -cn \
        --arg run_id "$run_id" --arg run_source "$run_source" \
        --arg session_id "$session_id" --arg session_source "$session_source" \
        --arg provider "$provider" --arg provider_source "$provider_source" \
        --arg plan_slug "$plan_slug" --arg plan_source "$plan_source" '
        {}
        | if $run_id != "" then .run_id=$run_id | .provenance.run_id=$run_source else . end
        | if $session_id != "" then .session_id=$session_id | .provenance.session_id=$session_source else . end
        | if $provider != "" then .provider=$provider | .provenance.provider=$provider_source else . end
        | if $plan_slug != "" then .plan_slug=$plan_slug | .provenance.plan_slug=$plan_source else . end'
}

# harness_log_v2 <repo-root> <hook> <event> <file> <detail> <context-json> <data-json>
# Appends exactly one compact line. HARNESS_LOG/HARNESS_LOG_FILE control the
# destination. Every failure is swallowed: observability must not change the
# command or hook it observes.
harness_log_v2() {
    local root="${1:-}" hook="${2:-}" event="${3:-}" file="${4:-}" detail="${5:-}"
    local context="${6:-}" data="${7:-}" enabled logfile line limit size lock lock_tmp lock_token owner acquired stamp archive suffix
    [ -n "$context" ] || context='{}'
    [ -n "$data" ] || data='{}'
    command -v jq >/dev/null 2>&1 || return 0
    enabled="${HARNESS_LOG:-1}"
    [ "$enabled" = "0" ] && return 0
    [ -n "$root" ] || return 0
    printf '%s' "$context" | jq -e 'type == "object"' >/dev/null 2>&1 || context='{}'
    printf '%s' "$data" | jq -e 'type == "object"' >/dev/null 2>&1 || data='{}'
    logfile="${HARNESS_LOG_FILE:-$root/.harness/var/log.jsonl}"
    mkdir -p "$(dirname "$logfile")" 2>/dev/null || return 0
    # Keep the active stream bounded without deleting history. Rotation is
    # best-effort and lock-directory serialized (portable atomic mkdir): a
    # failure merely leaves the current file growing. Archives are timestamped
    # siblings and are never auto-deleted; retention remains an explicit local
    # choice. Set HARNESS_LOG_MAX_BYTES=0 to disable.
    limit="${HARNESS_LOG_MAX_BYTES:-10485760}"
    case "$limit" in ''|*[!0-9]*) limit=10485760 ;; esac
    if [ "$limit" -gt 0 ] 2>/dev/null && [ -f "$logfile" ]; then
        size=$(wc -c 2>/dev/null < "$logfile" | tr -d '[:space:]') || size=0
        case "$size" in ''|*[!0-9]*) size=0 ;; esac
        if [ "$size" -ge "$limit" ] 2>/dev/null; then
            lock="$logfile.rotate-lock"
            lock_token="${BASHPID:-$$}"
            lock_tmp="$lock.$lock_token"
            acquired=0
            if printf '%s\n' "$lock_token" > "$lock_tmp" 2>/dev/null; then
                if ln "$lock_tmp" "$lock" 2>/dev/null; then
                    acquired=1
                elif [ -f "$lock" ]; then
                    owner=$(sed -n '1p' "$lock" 2>/dev/null)
                    case "$owner" in
                        ''|*[!0-9]*) ;;
                        *) if ! kill -0 "$owner" 2>/dev/null; then
                               rm -f -- "$lock" 2>/dev/null
                               ln "$lock_tmp" "$lock" 2>/dev/null && acquired=1
                           fi ;;
                    esac
                fi
                rm -f -- "$lock_tmp" 2>/dev/null
            fi
            if [ "$acquired" -eq 1 ]; then
                size=$(wc -c 2>/dev/null < "$logfile" | tr -d '[:space:]') || size=0
                case "$size" in ''|*[!0-9]*) size=0 ;; esac
                if [ "$size" -ge "$limit" ] 2>/dev/null; then
                    stamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null) || stamp="unknown"
                    archive="$logfile.$stamp"
                    suffix=0
                    while [ -e "$archive" ]; do
                        suffix=$((suffix + 1))
                        archive="$logfile.$stamp.$suffix"
                    done
                    mv "$logfile" "$archive" 2>/dev/null || true
                fi
                rm -f -- "$lock" 2>/dev/null || true
            fi
        fi
    fi
    line=$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg hook "$hook" --arg event "$event" --arg file "$file" \
        --arg detail "$detail" --argjson context "$context" --argjson data "$data" \
        '{version:2,ts:$ts,hook:$hook,event:$event,file:$file,detail:$detail,context:$context,data:$data}' \
        2>/dev/null) || return 0
    [ -n "$line" ] || return 0
    printf '%s\n' "$line" >> "$logfile" 2>/dev/null || true
    return 0
}
