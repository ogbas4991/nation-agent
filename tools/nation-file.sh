#!/bin/bash
# NATION AGENT — File Operations Tool
# Usage: nation-file.sh <command> [args...]
#
# Commands:
#   read    <path>                    Read file contents
#   write   <path> <content>          Write content to file (creates dirs)
#   append  <path> <content>          Append content to file
#   delete  <path>                    Delete a file (requires --confirm)
#   copy    <src> <dst>               Copy file or directory
#   move    <src> <dst>               Move/rename file or directory
#   list    <path>                    List directory contents
#   tree    <path> [depth]            Tree view of directory
#   find    <path> <pattern>          Find files matching pattern
#   info    <path>                    File metadata (size, perms, dates)
#   mkdir   <path>                    Create directory tree
#   exists  <path>                    Check if path exists
#   diff    <file1> <file2>           Diff two files
#   head    <path> [lines]            First N lines (default 20)
#   tail    <path> [lines]            Last N lines (default 20)
#   grep    <pattern> <path>          Search in file(s)
#   wc      <path>                    Word/line/char count
#   chmod   <mode> <path>             Change permissions
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [FILE] $*" >> "$LOG"; }

die() { echo "ERROR: $*" >&2; exit 1; }

require_path() {
    [ -n "${1:-}" ] || die "Path argument required"
}

case "$CMD" in

  read)
    require_path "${2:-}"
    [ -f "$2" ] || die "Not a file: $2"
    log "read $2"
    cat "$2"
    ;;

  write)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Content argument required"
    mkdir -p "$(dirname "$2")"
    printf '%s' "$3" > "$2"
    log "write $2 ($(wc -c < "$2") bytes)"
    echo "Written: $2 ($(wc -c < "$2") bytes)"
    ;;

  append)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Content argument required"
    mkdir -p "$(dirname "$2")"
    printf '%s' "$3" >> "$2"
    log "append $2"
    echo "Appended to: $2"
    ;;

  delete)
    require_path "${2:-}"
    [[ "${3:-}" == "--confirm" ]] || die "Destructive operation. Pass --confirm to proceed."
    [ -e "$2" ] || die "Path does not exist: $2"
    rm -rf "$2"
    log "delete $2"
    echo "Deleted: $2"
    ;;

  copy)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Destination path required"
    mkdir -p "$(dirname "$3")"
    cp -r "$2" "$3"
    log "copy $2 -> $3"
    echo "Copied: $2 -> $3"
    ;;

  move)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Destination path required"
    mkdir -p "$(dirname "$3")"
    mv "$2" "$3"
    log "move $2 -> $3"
    echo "Moved: $2 -> $3"
    ;;

  list)
    TARGET="${2:-.}"
    [ -d "$TARGET" ] || die "Not a directory: $TARGET"
    log "list $TARGET"
    ls -lah "$TARGET"
    ;;

  tree)
    TARGET="${2:-.}"
    DEPTH="${3:-3}"
    log "tree $TARGET depth=$DEPTH"
    if command -v tree &>/dev/null; then
      tree -L "$DEPTH" "$TARGET"
    else
      # Pure bash tree fallback
      find "$TARGET" -maxdepth "$DEPTH" | sort | sed -e 's|[^/]*/|  |g' -e 's|  \([^  ]\)|- \1|'
    fi
    ;;

  find)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Pattern argument required"
    log "find $2 -name $3"
    find "$2" -name "$3" 2>/dev/null | sort
    ;;

  info)
    require_path "${2:-}"
    [ -e "$2" ] || die "Path does not exist: $2"
    log "info $2"
    echo "Path    : $2"
    echo "Type    : $([ -d "$2" ] && echo directory || echo file)"
    echo "Size    : $(du -sh "$2" 2>/dev/null | cut -f1)"
    echo "Perms   : $(stat -c '%A %a' "$2" 2>/dev/null || ls -la "$2" | awk '{print $1,$3,$4}')"
    echo "Modified: $(stat -c '%y' "$2" 2>/dev/null | cut -d. -f1)"
    echo "Created : $(stat -c '%w' "$2" 2>/dev/null | cut -d. -f1 || echo 'N/A')"
    if [ -f "$2" ]; then
      echo "Lines   : $(wc -l < "$2")"
      echo "Encoding: $(file -b "$2" 2>/dev/null || echo 'unknown')"
    fi
    ;;

  mkdir)
    require_path "${2:-}"
    mkdir -p "$2"
    log "mkdir $2"
    echo "Created: $2"
    ;;

  exists)
    require_path "${2:-}"
    if [ -e "$2" ]; then
      echo "EXISTS: $2 ($([ -d "$2" ] && echo dir || echo file))"
      exit 0
    else
      echo "NOT_FOUND: $2"
      exit 1
    fi
    ;;

  diff)
    require_path "${2:-}"
    [ -n "${3:-}" ] || die "Second file argument required"
    log "diff $2 $3"
    diff --color=never -u "$2" "$3" || true
    ;;

  head)
    require_path "${2:-}"
    [ -f "$2" ] || die "Not a file: $2"
    LINES="${3:-20}"
    log "head $2 $LINES"
    head -n "$LINES" "$2"
    ;;

  tail)
    require_path "${2:-}"
    [ -f "$2" ] || die "Not a file: $2"
    LINES="${3:-20}"
    log "tail $2 $LINES"
    tail -n "$LINES" "$2"
    ;;

  grep)
    [ -n "${2:-}" ] || die "Pattern argument required"
    [ -n "${3:-}" ] || die "Path argument required"
    log "grep $2 in $3"
    grep -rn --color=never "$2" "$3" 2>/dev/null || echo "No matches found."
    ;;

  wc)
    require_path "${2:-}"
    [ -f "$2" ] || die "Not a file: $2"
    log "wc $2"
    echo "Lines : $(wc -l < "$2")"
    echo "Words : $(wc -w < "$2")"
    echo "Chars : $(wc -c < "$2")"
    ;;

  chmod)
    [ -n "${2:-}" ] || die "Mode argument required (e.g. 755)"
    require_path "${3:-}"
    chmod "$2" "$3"
    log "chmod $2 $3"
    echo "Permissions set: $2 on $3"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-file.sh help"
    ;;
esac
