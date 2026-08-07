#!/bin/bash
# NATION AGENT — Self-Healing Error Handler
# Diagnoses errors, suggests fixes, and attempts automatic recovery.
#
# Usage: nation-heal.sh <command> [args...]
#
# Commands:
#   diagnose  <error_text>           Diagnose an error and suggest fix
#   fix       <category> [context]   Attempt automatic fix for a known issue
#   retry     <cmd> [max_attempts]   Retry a command with backoff
#   check                            Run full system health check
#   report    <tool> <error>         Log an error to memory for learning
#   history                          Show past errors and their fixes
#
set -euo pipefail

MEMORY="$HOME/.kiro/tools/nation-memory.sh"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [HEAL] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

CMD="${1:-check}"

# ─── Error pattern database ───────────────────────────────────────────────────
diagnose_error() {
    local ERROR="$1"
    local FIXED=0

    echo "=== NATION AGENT Self-Healing Diagnostics ==="
    echo "Error: $ERROR"
    echo ""

    # command not found
    if echo "$ERROR" | grep -qiE "command not found|not found|No such file"; then
        CMD_NAME=$(echo "$ERROR" | grep -oE "[a-z0-9_-]+: command not found|No such file.*'([^']+)'" | head -1 | sed "s/: command not found//" | tr -d "'")
        echo "DIAGNOSIS: Missing binary or script"
        echo ""
        echo "FIXES to try:"
        case "$CMD_NAME" in
            sqlite3)   echo "  pkg install sqlite" ;;
            jq)        echo "  pkg install jq" ;;
            docker)    echo "  pkg install docker  (or use Termux:Docker)" ;;
            node|npm)  echo "  pkg install nodejs" ;;
            python3)   echo "  pkg install python" ;;
            git)       echo "  pkg install git" ;;
            curl)      echo "  pkg install curl" ;;
            ssh|scp)   echo "  pkg install openssh" ;;
            black)     echo "  pip3 install black" ;;
            pyflakes)  echo "  pip3 install pyflakes" ;;
            *)         echo "  pkg install $CMD_NAME  OR  pip3 install $CMD_NAME  OR  npm install -g $CMD_NAME" ;;
        esac
        FIXED=1
    fi

    # permission denied
    if echo "$ERROR" | grep -qiE "permission denied|EACCES|not executable"; then
        echo "DIAGNOSIS: Permission problem"
        echo ""
        echo "FIXES to try:"
        SCRIPT=$(echo "$ERROR" | grep -oE "[/~][^ :]+" | head -1)
        [ -n "$SCRIPT" ] && echo "  chmod +x $SCRIPT" || echo "  chmod +x <script_path>"
        echo "  ls -la <file>  (check current permissions)"
        FIXED=1
    fi

    # not a git repository
    if echo "$ERROR" | grep -qiE "not a git repo|fatal.*not.*git|not inside"; then
        echo "DIAGNOSIS: Not in a git repository"
        echo ""
        echo "FIXES to try:"
        echo "  cd /path/to/your/project   (navigate to your project)"
        echo "  git init                    (initialize new repo)"
        echo "  git clone <url>             (clone existing repo)"
        FIXED=1
    fi

    # network errors
    if echo "$ERROR" | grep -qiE "could not resolve|connection refused|network|timeout|curl.*failed|SSL"; then
        echo "DIAGNOSIS: Network connectivity issue"
        echo ""
        echo "FIXES to try:"
        echo "  ~/.kiro/tools/nation-browser.sh status https://httpbin.org/status/200"
        echo "  ping -c 3 8.8.8.8"
        echo "  Check WiFi/mobile data is enabled on device"
        echo "  If SSL error: curl -k (bypass, dev only) or update ca-certificates"
        FIXED=1
    fi

    # python errors
    if echo "$ERROR" | grep -qiE "ModuleNotFoundError|ImportError|No module named"; then
        MOD=$(echo "$ERROR" | grep -oE "No module named '[^']+'" | head -1 | sed "s/No module named '//;s/'//")
        echo "DIAGNOSIS: Missing Python module"
        echo ""
        echo "FIXES to try:"
        [ -n "$MOD" ] && echo "  pip3 install $MOD" || echo "  pip3 install <module_name>"
        echo "  ~/.kiro/tools/nation-python.sh pip list  (check installed packages)"
        FIXED=1
    fi

    # sqlite errors
    if echo "$ERROR" | grep -qiE "no such table|OperationalError|database is locked|disk.*full"; then
        echo "DIAGNOSIS: SQLite database issue"
        echo ""
        echo "FIXES to try:"
        if echo "$ERROR" | grep -qi "no such table"; then
            echo "  ~/.kiro/tools/nation-sqlite.sh tables <db>   (list existing tables)"
            echo "  ~/.kiro/tools/nation-sqlite.sh schema <db>   (check schema)"
        elif echo "$ERROR" | grep -qi "locked"; then
            echo "  Wait a moment and retry (another process has the DB locked)"
            echo "  Kill other processes using the DB"
        elif echo "$ERROR" | grep -qi "full"; then
            echo "  df -h  (check disk space)"
            echo "  ~/.kiro/tools/nation-sqlite.sh vacuum <db>  (reclaim space)"
        fi
        FIXED=1
    fi

    # port in use
    if echo "$ERROR" | grep -qiE "address already in use|EADDRINUSE|port.*in use"; then
        PORT=$(echo "$ERROR" | grep -oE "[0-9]{4,5}" | head -1)
        echo "DIAGNOSIS: Port already in use"
        echo ""
        echo "FIXES to try:"
        [ -n "$PORT" ] && echo "  fuser -k ${PORT}/tcp   (kill process on port $PORT)" || echo "  fuser -k <port>/tcp"
        echo "  ss -tlnp | grep <port>   (find what's using it)"
        echo "  Change port number in your config"
        FIXED=1
    fi

    # out of memory / disk
    if echo "$ERROR" | grep -qiE "out of memory|OOM|no space left|disk full"; then
        echo "DIAGNOSIS: Resource exhaustion"
        echo ""
        echo "FIXES to try:"
        echo "  df -h          (check disk space)"
        echo "  free -h        (check RAM)"
        echo "  du -sh ~/.kiro/  (check agent dir size)"
        echo "  ~/.kiro/tools/nation-memory.sh prune 30  (prune old memories)"
        FIXED=1
    fi

    # JSON parse error
    if echo "$ERROR" | grep -qiE "json.*error|invalid.*json|JSONDecodeError|Unexpected token"; then
        echo "DIAGNOSIS: Invalid JSON"
        echo ""
        echo "FIXES to try:"
        echo "  python3 -c \"import json; json.load(open('<file>'))\"  (validate file)"
        echo "  echo '<json>' | python3 -m json.tool  (validate string)"
        echo "  Check for: trailing commas, unquoted keys, single quotes"
        FIXED=1
    fi

    if [ $FIXED -eq 0 ]; then
        echo "DIAGNOSIS: Unknown error pattern"
        echo ""
        echo "General fixes to try:"
        echo "  1. Check ~/.kiro/logs/nation-agent.log for full context"
        echo "  2. Run the failing command manually to see full output"
        echo "  3. Search: ~/.kiro/tools/nation-search.sh todo ~/.kiro/tools/"
        echo "  4. Check memory for past similar errors:"
        echo "     ~/.kiro/tools/nation-memory.sh search 'error'"
    fi

    # Always log the error to memory
    $MEMORY remember error "$(date +%s)-error" "$ERROR" 2>/dev/null || true
    log "diagnose: $ERROR"
}

# ─── Auto-fix for known categories ───────────────────────────────────────────
auto_fix() {
    local CATEGORY="$1"
    local CONTEXT="${2:-}"
    log "fix: $CATEGORY $CONTEXT"

    case "$CATEGORY" in
        permissions)
            echo "Fixing permissions on all tool scripts..."
            chmod +x ~/.kiro/tools/*.sh ~/.kiro/hooks/*.sh 2>/dev/null || true
            echo "Done. All .sh files in tools/ and hooks/ are now executable."
            ;;
        memory-db)
            echo "Re-initializing memory database..."
            $MEMORY init
            ;;
        log-dir)
            echo "Creating missing log directory..."
            mkdir -p ~/.kiro/logs
            echo "Done."
            ;;
        git-config)
            echo "Fixing git config..."
            git config --global user.name "${CONTEXT:-$(git config user.name 2>/dev/null || echo 'nation-agent')}"
            git config --global user.email "$(git config user.email 2>/dev/null || echo 'nation-agent@localhost')"
            git config --global init.defaultBranch main
            echo "Git config fixed."
            ;;
        npm-install)
            echo "Installing missing npm package: $CONTEXT"
            [ -n "$CONTEXT" ] || die "Package name required"
            npm install -g "$CONTEXT"
            ;;
        pip-install)
            echo "Installing missing Python package: $CONTEXT"
            [ -n "$CONTEXT" ] || die "Package name required"
            pip3 install "$CONTEXT"
            ;;
        pkg-install)
            echo "Installing system package: $CONTEXT"
            [ -n "$CONTEXT" ] || die "Package name required"
            apt-get install -y "$CONTEXT" 2>/dev/null || pkg install "$CONTEXT"
            ;;
        *)
            die "Unknown fix category: $CATEGORY. Use: permissions, memory-db, log-dir, git-config, npm-install, pip-install, pkg-install"
            ;;
    esac
}

# ─── Retry with exponential backoff ──────────────────────────────────────────
retry_cmd() {
    local MAX="${2:-3}"
    local WAIT=2
    local ATTEMPT=1
    local CMD_STR="$1"

    log "retry: $CMD_STR (max=$MAX)"

    while [ $ATTEMPT -le $MAX ]; do
        echo "Attempt $ATTEMPT/$MAX: $CMD_STR"
        if eval "$CMD_STR"; then
            echo "SUCCESS on attempt $ATTEMPT"
            $MEMORY remember event "retry-success" "attempt=$ATTEMPT cmd=$CMD_STR" 2>/dev/null || true
            return 0
        fi
        EXIT=$?
        echo "FAILED (exit $EXIT). Waiting ${WAIT}s before retry..."
        sleep $WAIT
        WAIT=$((WAIT * 2))
        ATTEMPT=$((ATTEMPT + 1))
    done

    echo "FAILED after $MAX attempts: $CMD_STR"
    $MEMORY remember error "retry-failed" "cmd=$CMD_STR" 2>/dev/null || true
    return 1
}

# ─── Full system health check ─────────────────────────────────────────────────
health_check() {
    log "health check"
    ISSUES=0

    echo "=== NATION AGENT Health Check ==="
    echo ""

    # Tool scripts
    echo "[ Tool Scripts ]"
    for script in ~/.kiro/tools/nation-*.sh; do
        name=$(basename "$script")
        if [ -x "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                echo "  ✓ $name"
            else
                echo "  ✗ $name — syntax error"
                ISSUES=$((ISSUES+1))
            fi
        else
            echo "  ✗ $name — not executable"
            ISSUES=$((ISSUES+1))
        fi
    done

    # Hook scripts
    echo ""
    echo "[ Hook Scripts ]"
    for script in ~/.kiro/hooks/nation-*.sh; do
        name=$(basename "$script")
        if [ -x "$script" ]; then
            echo "  ✓ $name"
        else
            echo "  ✗ $name — not executable"
            ISSUES=$((ISSUES+1))
        fi
    done

    # Memory DB
    echo ""
    echo "[ Memory System ]"
    if [ -f "$HOME/.kiro/memory/memory.db" ]; then
        COUNT=$(python3 -c "import sqlite3; c=sqlite3.connect('$HOME/.kiro/memory/memory.db'); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])" 2>/dev/null || echo "?")
        echo "  ✓ memory.db ($COUNT entries)"
    else
        echo "  ✗ memory.db not found — run: nation-memory.sh init"
        ISSUES=$((ISSUES+1))
    fi

    # Agent config
    echo ""
    echo "[ Agent Config ]"
    if [ -f "$HOME/.kiro/agents/nation-agent.json" ]; then
        python3 -c "import json; json.load(open('$HOME/.kiro/agents/nation-agent.json'))" 2>/dev/null \
            && echo "  ✓ nation-agent.json (valid JSON)" \
            || { echo "  ✗ nation-agent.json — invalid JSON!"; ISSUES=$((ISSUES+1)); }
    else
        echo "  ✗ nation-agent.json not found"
        ISSUES=$((ISSUES+1))
    fi

    # Skill
    echo ""
    echo "[ Skills ]"
    if [ -f "$HOME/.kiro/skills/nation-tools/SKILL.md" ]; then
        echo "  ✓ SKILL.md"
    else
        echo "  ✗ SKILL.md not found"
        ISSUES=$((ISSUES+1))
    fi

    # Runtimes
    echo ""
    echo "[ Runtimes ]"
    for bin in python3 git curl ssh node; do
        if command -v $bin &>/dev/null; then
            VER=$({ $bin --version 2>&1 || true; } | head -1 | cut -c1-40)
            echo "  ✓ $bin — $VER"
        else
            echo "  ✗ $bin — not found"
            ISSUES=$((ISSUES+1))
        fi
    done

    # Optional
    echo ""
    echo "[ Optional ]"
    for bin in docker sqlite3 jq; do
        if command -v $bin &>/dev/null; then
            echo "  ✓ $bin — available"
        else
            echo "  - $bin — not installed (optional)"
        fi
    done

    # MCP
    echo ""
    echo "[ MCP Bridge ]"
    if [ -f "$HOME/.kiro/agents/nation-agent.json" ]; then
        HAS_MCP=$(python3 -c "import json; d=json.load(open('$HOME/.kiro/agents/nation-agent.json')); print('yes' if d.get('mcpServers') else 'no')" 2>/dev/null)
        [ "$HAS_MCP" = "yes" ] && echo "  ✓ MCP servers configured" || echo "  - No MCP servers configured"
    fi

    echo ""
    echo "================================="
    if [ $ISSUES -eq 0 ]; then
        echo "✓ All checks passed — NATION AGENT is healthy"
    else
        echo "✗ $ISSUES issue(s) found — run: nation-heal.sh fix <category>"
    fi
    echo "================================="

    $MEMORY log "health-check" "issues=$ISSUES" 2>/dev/null || true
    return $ISSUES
}

# ─── Report error to memory ───────────────────────────────────────────────────
report_error() {
    local TOOL="$1"
    local ERROR="${2:-unknown error}"
    log "report error: $TOOL — $ERROR"
    $MEMORY remember error "error.$TOOL.$(date +%s)" "Tool: $TOOL | Error: $ERROR | Time: $TS" 2>/dev/null || true
    echo "Error reported and stored in memory."
}

# ─── Show error history ───────────────────────────────────────────────────────
show_history() {
    log "history"
    $MEMORY recall error 2>/dev/null || echo "No error history found."
}

# ─── Main ──────────────────────────────────────────────────────────────────────
case "$CMD" in
  diagnose)
    [ -n "${2:-}" ] || die "Error text required"
    shift
    diagnose_error "$*"
    ;;
  fix)
    [ -n "${2:-}" ] || die "Category required"
    auto_fix "${2}" "${3:-}"
    ;;
  retry)
    [ -n "${2:-}" ] || die "Command required"
    retry_cmd "$2" "${3:-3}"
    ;;
  check)
    health_check
    ;;
  report)
    [ -n "${2:-}" ] || die "Tool name required"
    report_error "${2}" "${3:-unknown error}"
    ;;
  history)
    show_history
    ;;
  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;
  *)
    die "Unknown command: $CMD. Run: nation-heal.sh help"
    ;;
esac
