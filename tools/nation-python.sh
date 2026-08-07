#!/bin/bash
# NATION AGENT — Python Execution Tool
# Usage: nation-python.sh <command> [args...]
#
# Commands:
#   run     <file.py> [args...]      Run a Python script
#   exec    <code>                   Execute inline Python code
#   repl                             Start interactive REPL (interactive mode)
#   pip     install <pkg...>         Install packages with pip3
#   pip     list                     List installed packages
#   pip     show <pkg>               Show package info
#   pip     uninstall <pkg>          Uninstall a package
#   venv    create <path>            Create a virtual environment
#   venv    activate <path>          Print activation command (eval it)
#   check   <file.py>                Syntax check without running
#   lint    <file.py>                Lint with pyflakes (if available)
#   format  <file.py>                Format with autopep8/black (if available)
#   version                          Show Python version and location
#   env                              Show Python environment info
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [PYTHON] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
[ -n "$PY" ] || die "Python not found. Install with: pkg install python"

PIP=$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || echo "")

case "$CMD" in

  run)
    [ -n "${2:-}" ] || die "Script file required"
    [ -f "$2" ] || die "File not found: $2"
    log "run $2"
    shift 2
    "$PY" "$2" "$@"  # wait — need the file var from before shift
    # Actually re-do this properly:
    ;;

  run)
    SCRIPT="$2"
    [ -n "$SCRIPT" ] || die "Script file required"
    [ -f "$SCRIPT" ] || die "File not found: $SCRIPT"
    shift 2
    log "run $SCRIPT $*"
    "$PY" "$SCRIPT" "$@"
    ;;

  exec)
    [ -n "${2:-}" ] || die "Python code string required"
    log "exec (inline code)"
    "$PY" -c "$2"
    ;;

  repl)
    log "repl"
    exec "$PY"
    ;;

  pip)
    SUBCMD="${2:-list}"
    case "$SUBCMD" in
      install)
        shift 2
        [ $# -gt 0 ] || die "Package name(s) required"
        [ -n "$PIP" ] || die "pip not found. Install with: pkg install python-pip"
        log "pip install $*"
        "$PIP" install "$@"
        ;;
      list)
        [ -n "$PIP" ] || die "pip not found"
        log "pip list"
        "$PIP" list 2>/dev/null || "$PY" -m pip list
        ;;
      show)
        [ -n "${3:-}" ] || die "Package name required"
        [ -n "$PIP" ] || die "pip not found"
        log "pip show $3"
        "$PIP" show "$3" 2>/dev/null || "$PY" -m pip show "$3"
        ;;
      uninstall)
        [ -n "${3:-}" ] || die "Package name required"
        [ -n "$PIP" ] || die "pip not found"
        log "pip uninstall $3"
        "$PIP" uninstall -y "$3"
        ;;
      *)
        die "Unknown pip subcommand: $SUBCMD. Use: install, list, show, uninstall"
        ;;
    esac
    ;;

  venv)
    SUBCMD="${2:-}"
    case "$SUBCMD" in
      create)
        [ -n "${3:-}" ] || die "Venv path required"
        log "venv create $3"
        "$PY" -m venv "$3"
        echo "Virtual environment created: $3"
        echo "Activate with: source $3/bin/activate"
        ;;
      activate)
        [ -n "${3:-}" ] || die "Venv path required"
        ACTIVATE_SCRIPT="$3/bin/activate"
        [ -f "$ACTIVATE_SCRIPT" ] || die "Venv not found: $3"
        echo "source $ACTIVATE_SCRIPT"
        ;;
      *)
        die "Unknown venv subcommand: $SUBCMD. Use: create, activate"
        ;;
    esac
    ;;

  check)
    [ -n "${2:-}" ] || die "Python file required"
    [ -f "$2" ] || die "File not found: $2"
    log "check $2"
    "$PY" -m py_compile "$2" && echo "Syntax OK: $2" || echo "Syntax ERRORS in: $2"
    ;;

  lint)
    [ -n "${2:-}" ] || die "Python file required"
    [ -f "$2" ] || die "File not found: $2"
    log "lint $2"
    if command -v pyflakes &>/dev/null; then
        pyflakes "$2"
    elif "$PY" -m pyflakes --version &>/dev/null 2>&1; then
        "$PY" -m pyflakes "$2"
    elif command -v flake8 &>/dev/null; then
        flake8 "$2"
    else
        echo "No linter found. Install with: pip3 install pyflakes"
        # Fallback to syntax check
        "$PY" -m py_compile "$2" && echo "Syntax OK (linter not available)" || echo "Syntax errors found"
    fi
    ;;

  format)
    [ -n "${2:-}" ] || die "Python file required"
    [ -f "$2" ] || die "File not found: $2"
    log "format $2"
    if command -v black &>/dev/null; then
        black "$2" && echo "Formatted with black: $2"
    elif command -v autopep8 &>/dev/null; then
        autopep8 --in-place "$2" && echo "Formatted with autopep8: $2"
    elif "$PY" -m black --version &>/dev/null 2>&1; then
        "$PY" -m black "$2" && echo "Formatted with black: $2"
    else
        echo "No formatter found. Install with: pip3 install black"
    fi
    ;;

  version)
    log "version"
    echo "Python: $("$PY" --version)"
    echo "Location: $(which "$PY")"
    [ -n "$PIP" ] && echo "Pip: $("$PIP" --version)" || echo "Pip: not found"
    ;;

  env)
    log "env"
    echo "Python: $("$PY" --version 2>&1)"
    echo "Executable: $("$PY" -c 'import sys; print(sys.executable)')"
    echo "Prefix: $("$PY" -c 'import sys; print(sys.prefix)')"
    echo "Version info: $("$PY" -c 'import sys; print(sys.version)')"
    echo "Platform: $("$PY" -c 'import sys; print(sys.platform)')"
    echo "Path:"
    "$PY" -c 'import sys; [print(" ", p) for p in sys.path if p]'
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-python.sh help"
    ;;
esac
