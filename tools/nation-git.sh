#!/bin/bash
# NATION AGENT — Git Tool
# Usage: nation-git.sh <command> [args...]
#
# Commands:
#   status   [path]                 Git status (short + branch)
#   log      [n] [path]             Last N commits (default 10)
#   diff     [ref] [file]           Show diff (unstaged by default)
#   staged                          Show staged diff
#   add      <path...>              Stage files
#   commit   <message>              Commit staged files
#   branch   [name] [base]          List branches or create one
#   checkout <ref>                  Checkout branch or commit
#   stash    [pop|list|show]        Stash operations
#   pull     [remote] [branch]      Pull with rebase
#   push     <remote> <branch>      Push (no --force allowed)
#   clone    <url> [dir]            Clone a repository
#   remote                          List remotes
#   tag      [name] [ref]           List or create tags
#   blame    <file> [line_start] [line_end]  Blame a file or range
#   show     <ref>                  Show a commit
#   reset    <file>                 Unstage a file (soft only)
#   init     [path]                 Init a new repo
#   ignore   <pattern> [path]       Add a pattern to .gitignore
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [GIT] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_git() {
    command -v git &>/dev/null || die "git not installed"
    git rev-parse --is-inside-work-tree &>/dev/null 2>&1 || die "Not inside a git repository"
}

case "$CMD" in

  status)
    command -v git &>/dev/null || die "git not installed"
    log "status ${2:-}"
    echo "=== Branch ==="
    git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "(unknown)"
    echo ""
    echo "=== Status ==="
    if [ -n "${2:-}" ]; then
        git status --short "$2"
    else
        git status --short
    fi
    echo ""
    echo "=== Stashes ==="
    git stash list 2>/dev/null | head -5 || echo "(none)"
    ;;

  log)
    require_git
    N="${2:-10}"
    PATH_FILTER="${3:-}"
    log "log -n $N $PATH_FILTER"
    if [ -n "$PATH_FILTER" ]; then
        git log --oneline --graph --decorate -n "$N" -- "$PATH_FILTER"
    else
        git log --oneline --graph --decorate -n "$N"
    fi
    ;;

  diff)
    require_git
    REF="${2:-}"
    FILE="${3:-}"
    log "diff $REF $FILE"
    if [ -n "$REF" ]; then
        git diff "$REF" -- ${FILE:+"$FILE"}
    else
        git diff -- ${FILE:+"$FILE"}
    fi
    ;;

  staged)
    require_git
    log "diff --staged"
    git diff --staged
    ;;

  add)
    require_git
    shift
    [ $# -gt 0 ] || die "At least one path required"
    log "add $*"
    git add "$@"
    echo "Staged: $*"
    git status --short
    ;;

  commit)
    require_git
    [ -n "${2:-}" ] || die "Commit message required"
    log "commit: $2"
    git commit -m "$2"
    ;;

  branch)
    require_git
    if [ -z "${2:-}" ]; then
        log "branch list"
        git branch -a
    else
        BASE="${3:-HEAD}"
        log "branch create $2 from $BASE"
        git branch "$2" "$BASE"
        echo "Created branch: $2 (from $BASE)"
    fi
    ;;

  checkout)
    require_git
    [ -n "${2:-}" ] || die "Branch/ref required"
    log "checkout $2"
    git checkout "$2"
    ;;

  stash)
    require_git
    SUBCMD="${2:-}"
    log "stash $SUBCMD"
    case "$SUBCMD" in
        pop)    git stash pop ;;
        list)   git stash list ;;
        show)   git stash show -p ;;
        "")     git stash push -m "nation-agent stash $(date +%s)" ;;
        *)      git stash "$SUBCMD" ;;
    esac
    ;;

  pull)
    require_git
    REMOTE="${2:-origin}"
    BRANCH="${3:-$(git branch --show-current)}"
    log "pull $REMOTE $BRANCH"
    git pull --rebase "$REMOTE" "$BRANCH"
    ;;

  push)
    require_git
    REMOTE="${2:-origin}"
    BRANCH="${3:-$(git branch --show-current)}"
    log "push $REMOTE $BRANCH"
    # Never allow --force
    git push "$REMOTE" "$BRANCH"
    ;;

  clone)
    [ -n "${2:-}" ] || die "Repository URL required"
    DIR="${3:-}"
    log "clone $2 $DIR"
    git clone "$2" ${DIR:+"$DIR"}
    ;;

  remote)
    require_git
    log "remote -v"
    git remote -v
    ;;

  tag)
    require_git
    if [ -z "${2:-}" ]; then
        log "tag list"
        git tag --sort=-version:refname | head -20
    else
        REF="${3:-HEAD}"
        log "tag create $2 at $REF"
        git tag "$2" "$REF"
        echo "Created tag: $2"
    fi
    ;;

  blame)
    require_git
    [ -n "${2:-}" ] || die "File path required"
    START="${3:-}"
    END="${4:-}"
    log "blame $2 $START $END"
    if [ -n "$START" ] && [ -n "$END" ]; then
        git blame -L "${START},${END}" "$2"
    else
        git blame "$2"
    fi
    ;;

  show)
    require_git
    [ -n "${2:-}" ] || die "Commit ref required"
    log "show $2"
    git show "$2"
    ;;

  reset)
    require_git
    [ -n "${2:-}" ] || die "File path required (use 'reset <file>' to unstage)"
    log "reset HEAD $2"
    git reset HEAD "$2"
    echo "Unstaged: $2"
    ;;

  init)
    TARGET="${2:-.}"
    log "init $TARGET"
    mkdir -p "$TARGET"
    git init "$TARGET"
    ;;

  ignore)
    [ -n "${2:-}" ] || die "Pattern required"
    GITIGNORE="${3:-.gitignore}"
    log "ignore $2 -> $GITIGNORE"
    echo "$2" >> "$GITIGNORE"
    echo "Added '$2' to $GITIGNORE"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-git.sh help"
    ;;
esac
