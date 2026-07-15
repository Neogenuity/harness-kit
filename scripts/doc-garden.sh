#!/usr/bin/env bash
# Portable, offline, read-only documentation health scanner.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORMAT=table
STALE_MONTHS=6
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) ROOT="$2"; shift 2 ;;
        --format) FORMAT="$2"; shift 2 ;;
        --stale-months) STALE_MONTHS="$2"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "doc-garden.sh: unknown option: $1" >&2; exit 64 ;;
    esac
done
case "$FORMAT" in table|json) ;; *) echo "doc-garden.sh: --format must be table or json" >&2; exit 64 ;; esac
case "$STALE_MONTHS" in ''|*[!0-9]*) echo "doc-garden.sh: --stale-months must be a non-negative integer" >&2; exit 64 ;; esac
command -v git >/dev/null 2>&1 || { echo "doc-garden.sh: git is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "doc-garden.sh: jq is required" >&2; exit 1; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "doc-garden.sh: not a Git repository: $ROOT" >&2; exit 1; }
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || exit 1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/doc-garden.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
FINDINGS="${DOC_GARDEN_FINDINGS_FILE:-$WORK/findings.jsonl}"
: > "$FINDINGS" 2>/dev/null \
    || { echo "doc-garden.sh: cannot initialize findings record: $FINDINGS" >&2; exit 1; }

add_finding() {
    local rule="$1" severity="$2" file="$3" line="$4" target="$5" detail="$6"
    jq -cn --arg rule "$rule" --arg severity "$severity" --arg file "$file" \
        --argjson line "$line" --arg target "$target" --arg detail "$detail" \
        '{rule:$rule,severity:$severity,file:$file,line:$line,target:$target,detail:$detail}' \
        >> "$FINDINGS" 2>/dev/null \
        || { echo "doc-garden.sh: cannot record finding: $FINDINGS" >&2; return 1; }
}

# One shared visibility pass keeps links, anchors, stamps, and deleted-path
# checks aligned. CommonMark allows up to three leading spaces on backtick or
# tilde fences. The exact inline future marker applies only to its visible line.
markdown_visible() {
    awk '
      function fence_prefix(line, s,n,c) {
        s=line; n=0
        while (n < 3 && substr(s,1,1) == " ") { s=substr(s,2); n++ }
        c=substr(s,1,1); if (c != "`" && c != "~") return ""
        n=0; while (substr(s,n+1,1) == c) n++
        return (n >= 3 ? c ":" n ":" s : "")
      }
      function strip_comments(s, start,tail,endpos) {
        while ((start=index(s,"<!--")) > 0) {
          tail=substr(s,start+4); endpos=index(tail,"-->")
          if (endpos > 0) s=substr(s,1,start-1) substr(tail,endpos+3)
          else { s=substr(s,1,start-1); html=1; break }
        }
        return s
      }
      {
        line=$0
        if (fenced) {
          p=fence_prefix(line)
          if (p != "" && substr(p,1,1) == fencechar) {
            s=line; sub(/^   /,"",s); sub(/^  /,"",s); sub(/^ /,"",s)
            n=0; while (substr(s,n+1,1) == fencechar) n++
            rest=substr(s,n+1)
            if (n >= fencelen && rest ~ /^[[:space:]]*$/) fenced=0
          }
          next
        }
        if (html) {
          endpos=index(line,"-->")
          if (endpos == 0) next
          line=substr(line,endpos+3); html=0
        }
        planned=(index(line,"<!-- doc-garden: planned -->") > 0)
        gsub(/<!-- doc-garden: planned -->/,"",line)
        line=strip_comments(line)
        p=fence_prefix(line)
        if (p != "") {
          fencechar=substr(p,1,1); rest=substr(p,3); fencelen=rest+0; fenced=1; next
        }
        if (line ~ /[^[:space:]]/) {
          if (planned) line=line " <!-- doc-garden: planned -->"
          print NR "\t" line
        }
      }' "$1"
}

# Visible Markdown links, one "line<TAB>destination<TAB>planned" per link.
markdown_links() {
    markdown_visible "$1" | awk -F '\t' '
      {
        line=$1; sub(/^[^\t]*\t/,"",$0); planned=(index($0,"<!-- doc-garden: planned -->") > 0)
        rest=$0
        while (match(rest, /\]\([^)]+\)/)) {
          token=substr(rest,RSTART+2,RLENGTH-3)
          print line "\t" token "\t" planned
          rest=substr(rest,RSTART+RLENGTH)
        }
      }'
}

heading_has_anchor() {
    local file="$1" wanted="$2"
    markdown_visible "$file" | awk -v wanted="$wanted" '
      { sub(/^[^\t]*\t/,"") }
      /^#{1,6}[[:space:]]+/ {
        h=$0; sub(/^#{1,6}[[:space:]]+/,"",h); sub(/[[:space:]]+#+[[:space:]]*$/,"",h)
        h=tolower(h); gsub(/[^[:alnum:] _-]/,"",h); gsub(/[[:space:]]+/,"-",h)
        if (h == wanted) found=1
      }
      END { exit(found ? 0 : 1) }'
}

resolve_inside_repo() {
    local candidate="$1" link parent resolved hops=0
    [ -e "$candidate" ] || [ -L "$candidate" ] || return 1
    while [ -L "$candidate" ]; do
        hops=$((hops + 1)); [ "$hops" -le 20 ] || return 1
        link=$(readlink "$candidate") || return 1
        case "$link" in /*) candidate="$link" ;; *) candidate="$(dirname "$candidate")/$link" ;; esac
    done
    if [ -d "$candidate" ]; then
        resolved=$(cd -P "$candidate" 2>/dev/null && pwd -P) || return 1
    else
        parent=$(cd -P "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
        resolved="$parent/$(basename "$candidate")"
    fi
    case "$resolved" in "$ROOT"|"$ROOT"/*) printf '%s\n' "$resolved" ;; *) return 2 ;; esac
}

now="${DOC_GARDEN_NOW:-$(date -u +%Y-%m)}"
case "$now" in [0-9][0-9][0-9][0-9]-[0-9][0-9]) ;; *) echo "doc-garden.sh: invalid current month: $now" >&2; exit 1 ;; esac
now_y=${now%-*}; now_m=${now#*-}; now_ord=$((10#$now_y * 12 + 10#$now_m))
if [ $((10#$now_m)) -lt 1 ] || [ $((10#$now_m)) -gt 12 ]; then
    echo "doc-garden.sh: invalid current month: $now" >&2; exit 1
fi
scanned=0

while IFS= read -r -d '' rel; do
    file="$ROOT/$rel"
    [ -f "$file" ] || continue
    scanned=$((scanned + 1))
    base=$(dirname "$file")
    while IFS="$(printf '\t')" read -r line destination planned; do
        [ -n "$destination" ] || continue
        case "$destination" in http://*|https://*|mailto:*|data:*) continue ;; esac
        destination="${destination#"${destination%%[![:space:]]*}"}"
        case "$destination" in
            '<'*) destination=${destination#<}; destination=${destination%%>*} ;;
            *) destination=${destination%% *} ;;
        esac
        path=${destination%%#*}; anchor=""
        case "$destination" in *'#'*) anchor=${destination#*#} ;; esac
        path=$(printf '%s' "$path" | sed 's/%20/ /g')
        if [ -z "$path" ]; then
            candidate="$file"
        elif [ -e "$base/$path" ] || [ -L "$base/$path" ]; then
            candidate="$base/$path"
        elif [ -e "$ROOT/$path" ] || [ -L "$ROOT/$path" ]; then
            candidate="$ROOT/$path"
        else
            [ "$planned" = 1 ] && continue
            add_finding broken-local-link high "$rel" "$line" "$path" "local Markdown target does not exist" || exit 1
            continue
        fi
        if ! target_file=$(resolve_inside_repo "$candidate"); then
            [ "$planned" = 1 ] && continue
            add_finding broken-local-link high "$rel" "$line" "$path" "local Markdown target does not resolve inside repository" || exit 1
            continue
        fi
        if [ -n "$anchor" ] && [ -f "$target_file" ] && ! heading_has_anchor "$target_file" "$anchor"; then
            add_finding missing-anchor medium "$rel" "$line" "$anchor" "target file has no matching Markdown heading" || exit 1
        fi
    done < <(markdown_links "$file")

    while IFS="$(printf '\t')" read -r line stamp valid; do
        [ -n "$stamp" ] || continue
        if [ "$valid" != 1 ]; then
            add_finding malformed-verification-stamp low "$rel" "$line" "$stamp" \
                "verification stamp must use YYYY-MM or YYYY-MM-DD with valid month/day ranges" || exit 1
            continue
        fi
        month_stamp=${stamp:0:7}
        y=${month_stamp%-*}; m=${month_stamp#*-}; ord=$((10#$y * 12 + 10#$m)); age=$((now_ord - ord))
        if [ "$age" -gt "$STALE_MONTHS" ]; then
            add_finding stale-verification-stamp low "$rel" "$line" "$stamp" \
                "verification stamp is $age months old (threshold: $STALE_MONTHS)" || exit 1
        fi
    done < <(markdown_visible "$file" | awk '
      { line=$1; sub(/^[^\t]*\t/,""); rest=$0
        while (match(rest, /(verified|re-verified|validated)[[:space:]]+[0-9][0-9-]*/)) {
          token=substr(rest,RSTART,RLENGTH); sub(/^.*[[:space:]]/,"",token)
          valid=(token ~ /^[0-9][0-9][0-9][0-9]-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01]))?$/ ? 1 : 0)
          print line "\t" token "\t" valid; rest=substr(rest,RSTART+RLENGTH)
        }
      }')
done < <(git -C "$ROOT" ls-files -z -- '*.md')

# A deleted path is actionable only when docs still name it as a code-formatted
# exact path and it has not since been recreated.
git -C "$ROOT" log --diff-filter=D --name-only --format= -- 2>/dev/null | awk 'NF && !seen[$0]++' > "$WORK/deleted"
while IFS= read -r deleted; do
    [ -n "$deleted" ] || continue
    [ ! -e "$ROOT/$deleted" ] || continue
    while IFS= read -r -d '' rel; do
        file="$ROOT/$rel"
        while IFS= read -r hit; do
            line=${hit%%:*}
            add_finding deleted-path-reference medium "$rel" "$line" "$deleted" \
                "documentation references a path deleted from Git history" || exit 1
        done < <(markdown_visible "$file" | awk -v target="$deleted" '
            index($0,"<!-- doc-garden: planned -->") == 0 && index($0,"`" target "`") {
              line=$1; print line ":" $0
            }' 2>/dev/null)
    done < <(git -C "$ROOT" ls-files -z -- '*.md')
done < "$WORK/deleted"

findings=$(jq -s 'sort_by([(if .severity=="high" then 0 elif .severity=="medium" then 1 else 2 end),.file,.line,.rule,.target])' "$FINDINGS") \
    || { echo "doc-garden.sh: failed to aggregate findings" >&2; exit 1; }
count=$(printf '%s' "$findings" | jq length)
if [ "$count" -eq 0 ]; then status=clean; else status=findings; fi
report=$(jq -cn --arg status "$status" --argjson scanned "$scanned" --argjson findings "$findings" \
    '{version:1,status:$status,scanned_files:$scanned,findings:$findings}') || exit 1
if [ "$FORMAT" = json ]; then
    printf '%s\n' "$report" | jq -S '.'
else
    printf 'Doc garden: %s (%s tracked Markdown files, %s findings)\n' "$status" "$scanned" "$count"
    printf '%s' "$findings" | jq -r '.[] | [.severity,.rule,(.file+":"+(.line|tostring)),.target,.detail] | @tsv' \
        | while IFS="$(printf '\t')" read -r severity rule location target detail; do
            printf '%-6s %-26s %-32s %s — %s\n' "$severity" "$rule" "$location" "$target" "$detail"
          done
fi
exit 0
