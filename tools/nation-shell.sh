#!/bin/bash
# NATION AGENT — Shell Execution Tool
# Usage: nation-shell.sh <command> [options]
#
# Commands:
#   run     <cmd>               Run a shell command, capture output
#   bg      <cmd>               Run command in background, return PID
#   script  <file>              Run a shell script file
#   env                         Show current environment variables
#   which   <binary>            Locate a binary
#   ps                          List running processes
#   kill    <pid> [signal]      Send signal to process (default TERM)
#   timeout <secs> <cmd>        Run command with timeout
#   pipe    <cmd1> --- <cmd2>   Pipe two commands (use --- as separator)
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [SHELL] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Safety: block known destructive patterns
check_safety() {
    local cmd="$1"
    local DANGEROUS=(
        "rm -rf /"
        "rm -rf \$HOME"
        "dd if="
        "mkfs"
        ":(){:|:&};:"
        "chmod -R 777 /"
        "> /dev/sda"
        "git push --force"
        "git reset --hard"
    )
    for pattern in "${DANGEROUS[@]}"; do
        if echo "$cmd" | grep -qF "$pattern" 2>/dev/null; then
            echo "BLOCKED: command matches dangerous pattern '$pattern'" >&2
            exit 2
        fi
    done
}

case "$CMD" in

  run)
    shift
    FULL_CMD="$*"
    [ -n "$FULL_CMD" ] || die "Command required"
    check_safety "$FULL_CMD"
    log "run: $FULL_CMD"
    echo "$ $FULL_CMD"
    echo "---"
    eval "$FULL_CMD"
    EXIT=$?
    echo "---"
    echo "Exit: $EXIT"
    exit $EXIT
    ;;

  bg)
    shift
    FULL_CMD="$*"
    [ -n "$FULL_CMD" ] || die "Command required"
    check_safety "$FULL_CMD"
    log "bg: $FULL_CMD"
    eval "$FULL_CMD" &
    BG_PID=$!
    echo "Started in background. PID: $BG_PID"
    echo "$BG_PID"
    ;;

  script)
    [ -n "${2:-}" ] || die "Script file path required"
    [ -f "$2" ] || die "Script not found: $2"
    [ -x "$2" ] || chmod +x "$2"
    log "script: $2"
    echo "Running script: $2"
    echo "---"
    bash "$2"
    EXIT=$?
    echo "---"
    echo "Exit: $EXIT"
    exit $EXIT
    ;;

  env)
    log "env"
    env | sort
    ;;

  which)
    [ -n "${2:-}" ] || die "Binary name required"
    log "which $2"
    which "$2" 2>/dev/null || { echo "Not found: $2"; exit 1; }
    ;;

  ps)
    log "ps"
    ps aux 2>/dev/null || ps -ef 2>/dev/null || die "ps not available"
    ;;

  kill)
    [ -n "${2:-}" ] || die "PID required"
    SIG="${3:-TERM}"
    log "kill -$SIG $2"
    kill "-$SIG" "$2" && echo "Sent $SIG to PID $2" || die "Failed to kill PID $2"
    ;;

  timeout)
    [ -n "${2:-}" ] || die "Timeout seconds required"
    shift 2
    FULL_CMD="$*"
    [ -n "$FULL_CMD" ] || die "Command required after timeout value"
    check_safety "$FULL_CMD"
    log "timeout ${2:-?}s: $FULL_CMD"
    timeout "$((${1:-10}))" bash -c "$FULL_CMD"
    EXIT=$?
    [ $EXIT -eq 124 ] && echo "TIMEOUT: command exceeded time limit" >&2
    exit $EXIT
    ;;

  pipe)
    # Usage: nation-shell.sh pipe "cmd1 args" --- "cmd2 args"
    shift
    # Split on literal ---
    PART1=""
    PART2=""
    FOUND_SEP=0
    for arg in "$@"; do
        if [ "$arg" = "---" ]; then
            FOUND_SEP=1
        elif [ $FOUND_SEP -eq 0 ]; then
            PART1="$PART1 $arg"
        else
            PART2="$PART2 $arg"
        fi
    done
    PART1="${PART1# }"
    PART2="${PART2# }"
    [ -n "$PART1" ] || die "First command required"
    [ -n "$PART2" ] || die "Second command required (after ---)"
    check_safety "$PART1"
    check_safety "$PART2"
    log "pipe: $PART1 | $PART2"
    eval "$PART1" | eval "$PART2"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-shell.sh help"
    ;;
esac
