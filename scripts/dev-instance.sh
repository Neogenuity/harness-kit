#!/usr/bin/env bash
# dev-instance.sh — deterministic per-worktree identity and port candidates.
#
# The input is the physical Git worktree root plus a caller-selected namespace.
# A finite hash cannot guarantee a free port; scripts/dev.sh must still reject a
# candidate already owned by another process instead of reusing or killing it.
set -uo pipefail

usage() {
    echo "usage: bash scripts/dev-instance.sh suffix [namespace]" >&2
    echo "       bash scripts/dev-instance.sh port <base> <span> [namespace]" >&2
    exit 64
}

die() {
    echo "dev-instance.sh: $*" >&2
    exit 1
}

normalize_uint() {
    local value="$1"
    while [ "${value#0}" != "$value" ]; do value=${value#0}; done
    [ -n "$value" ] || value=0
    printf '%s' "$value"
}

case "${1:-}" in
    suffix)
        [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
        if [ "$#" -eq 2 ]; then namespace="$2"; else namespace=app; fi
        ;;
    port)
        [ "$#" -ge 3 ] && [ "$#" -le 4 ] || usage
        base="$2"
        span="$3"
        if [ "$#" -eq 4 ]; then namespace="$4"; else namespace=app; fi
        case "$base" in ''|*[!0-9]*) die "base must be an integer >= 1024" ;; esac
        case "$span" in ''|*[!0-9]*) die "span must be an integer >= 1" ;; esac
        base=$(normalize_uint "$base")
        span=$(normalize_uint "$span")
        # Values above five digits cannot satisfy the allowed port range. This
        # also prevents shell-arithmetic overflow on hostile giant arguments.
        [ "${#base}" -le 5 ] && [ "$base" -ge 1024 ] \
            || die "base must be an integer >= 1024"
        [ "${#span}" -le 5 ] && [ "$span" -ge 1 ] \
            || die "span must be an integer >= 1"
        max=$((base + span - 1))
        [ "$max" -le 65535 ] \
            || die "base + span - 1 must be <= 65535"
        ;;
    *) usage ;;
esac

[ -n "$namespace" ] || die "namespace must be non-empty"
command -v git >/dev/null 2>&1 \
    || die "git is required to identify the current worktree"
if command -v shasum >/dev/null 2>&1; then
    hash_command=shasum
elif command -v sha256sum >/dev/null 2>&1; then
    hash_command=sha256sum
else
    die "a SHA-256 tool is required (shasum or sha256sum)"
fi

git_root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || die "current directory is not inside a Git worktree"
physical_root=$(cd "$git_root" 2>/dev/null && pwd -P) \
    || die "cannot resolve the physical Git worktree root: $git_root"

if [ "$hash_command" = shasum ]; then
    digest=$(printf '%s\0%s\0' "$physical_root" "$namespace" | shasum -a 256 | awk '{print $1}')
else
    digest=$(printf '%s\0%s\0' "$physical_root" "$namespace" | sha256sum | awk '{print $1}')
fi
prefix=$(printf '%s' "$digest" | cut -c1-12 | tr '[:upper:]' '[:lower:]')
[ "${#prefix}" -eq 12 ] || die "SHA-256 tool returned an invalid digest"
case "$prefix" in *[!0-9a-f]*) die "SHA-256 tool returned an invalid digest" ;; esac

case "$1" in
    suffix) printf 'h%s\n' "$prefix" ;;
    port)
        hash_value=$((16#$prefix))
        printf '%s\n' "$((base + (hash_value % span)))"
        ;;
esac
