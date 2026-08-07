#!/bin/bash
# NATION AGENT — Search Tool
# Usage: nation-search.sh <command> [args...]
#
# Commands:
#   text    <pattern> <path> [options]   Regex search in file contents
#   files   <pattern> [path]             Find files by name pattern
#   type    <ext> [path]                 Find files by extension
#   large   [path] [min_size]            Find large files (default >1M)
#   recent  [path] [days]               Find recently modified files (default 7d)
#   dupes   [path]                       Find duplicate files by checksum
#   replace <pattern> <replace> <path>   Find and replace (dry run first)
#   apply   <pattern> <replace> <path>   Apply find-and-replace in-place
#   context <pattern> <path> [n]         Search with N lines of context (default 3)
#   count   <pattern> <path>             Count matches per file
#   todo    [path]                       Find TODO/FIXME/HACK/XXX comments
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [SEARCH] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

case "$CMD" in

  text)
    [ -n "${2:-}" ] || die "Pattern required"
    [ -n "${3:-}" ] || die "Path required"
    PATTERN="$2"
    SEARCH_PATH="$3"
    OPTS="${4:-}"
    log "text '$PATTERN' in $SEARCH_PATH"
    grep -rn --color=never $OPTS "$PATTERN" "$SEARCH_PATH" 2>/dev/null \
      | grep -v '.git/' \
      | head -200 \
      || echo "No matches found for: $PATTERN"
    ;;

  files)
    [ -n "${2:-}" ] || die "Pattern required"
    SEARCH_PATH="${3:-.}"
    log "files '$2' in $SEARCH_PATH"
    find "$SEARCH_PATH" -name "$2" 2>/dev/null \
      | grep -v '.git/' \
      | sort \
      | head -200
    ;;

  type)
    [ -n "${2:-}" ] || die "Extension required (e.g. py, js, sh)"
    SEARCH_PATH="${3:-.}"
    EXT="${2#.}"  # strip leading dot if present
    log "type .$EXT in $SEARCH_PATH"
    find "$SEARCH_PATH" -name "*.${EXT}" 2>/dev/null \
      | grep -v '.git/' \
      | sort \
      | head -200
    ;;

  large)
    SEARCH_PATH="${2:-.}"
    MIN_SIZE="${3:-+1M}"
    # Normalize: add + prefix if not present
    [[ "$MIN_SIZE" == +* ]] || MIN_SIZE="+$MIN_SIZE"
    log "large files in $SEARCH_PATH (size $MIN_SIZE)"
    find "$SEARCH_PATH" -type f -size "$MIN_SIZE" 2>/dev/null \
      | grep -v '.git/' \
      | xargs du -sh 2>/dev/null \
      | sort -rh \
      | head -50
    ;;

  recent)
    SEARCH_PATH="${2:-.}"
    DAYS="${3:-7}"
    log "recent files in $SEARCH_PATH (last ${DAYS}d)"
    find "$SEARCH_PATH" -type f -mtime "-${DAYS}" 2>/dev/null \
      | grep -v '.git/' \
      | xargs ls -lt 2>/dev/null \
      | head -50
    ;;

  dupes)
    SEARCH_PATH="${2:-.}"
    log "dupes in $SEARCH_PATH"
    find "$SEARCH_PATH" -type f 2>/dev/null \
      | grep -v '.git/' \
      | xargs md5sum 2>/dev/null \
      | sort \
      | awk 'seen[$1]++ { print "DUP:", $2, "(matches earlier file with same checksum)" }' \
      | head -100 \
      || echo "md5sum not available or no duplicates found"
    ;;

  replace)
    [ -n "${2:-}" ] || die "Pattern required"
    [ -n "${3:-}" ] || die "Replacement required"
    [ -n "${4:-}" ] || die "Path required"
    log "replace (dry-run) '$2' -> '$3' in $4"
    echo "=== DRY RUN — files that would be modified ==="
    grep -rl "$2" "$4" 2>/dev/null | grep -v '.git/' | head -50 || echo "No matches"
    echo ""
    echo "=== Sample matches ==="
    grep -rn --color=never "$2" "$4" 2>/dev/null | grep -v '.git/' | head -20 || true
    echo ""
    echo "Run 'nation-search.sh apply $2 $3 $4' to apply changes"
    ;;

  apply)
    [ -n "${2:-}" ] || die "Pattern required"
    [ -n "${3:-}" ] || die "Replacement required"
    [ -n "${4:-}" ] || die "Path required"
    log "apply '$2' -> '$3' in $4"
    MODIFIED=0
    while IFS= read -r -d '' file; do
        if grep -qF "$2" "$file" 2>/dev/null; then
            sed -i "s|${2}|${3}|g" "$file"
            echo "Modified: $file"
            MODIFIED=$((MODIFIED + 1))
        fi
    done < <(find "$4" -type f -not -path '*/.git/*' -print0 2>/dev/null)
    echo "Total files modified: $MODIFIED"
    ;;

  context)
    [ -n "${2:-}" ] || die "Pattern required"
    [ -n "${3:-}" ] || die "Path required"
    N="${4:-3}"
    log "context '$2' in $3 (n=$N)"
    grep -rn --color=never -C "$N" "$2" "$3" 2>/dev/null \
      | grep -v '.git/' \
      | head -300 \
      || echo "No matches found"
    ;;

  count)
    [ -n "${2:-}" ] || die "Pattern required"
    [ -n "${3:-}" ] || die "Path required"
    log "count '$2' in $3"
    grep -rc --color=never "$2" "$3" 2>/dev/null \
      | grep -v '.git/' \
      | grep -v ':0$' \
      | sort -t: -k2 -rn \
      | head -50 \
      || echo "No matches"
    ;;

  todo)
    SEARCH_PATH="${2:-.}"
    log "todo in $SEARCH_PATH"
    echo "=== TODOs, FIXMEs, HACKs, XXXs ==="
    grep -rn --color=never -E '\b(TODO|FIXME|HACK|XXX|NOTE|BUG|OPTIMIZE|DEPRECATED)\b' \
      "$SEARCH_PATH" 2>/dev/null \
      | grep -v '.git/' \
      | head -100 \
      || echo "None found."
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-search.sh help"
    ;;
esac
