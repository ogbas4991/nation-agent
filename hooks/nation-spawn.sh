#!/bin/bash
# NATION AGENT — agentSpawn hook (v2)
# Runs when the agent initializes.
# - Gathers environment context
# - Loads persistent memory summary
# - Runs lightweight health check
set -euo pipefail

MEMORY="$HOME/.kiro/tools/nation-memory.sh"
HEAL="$HOME/.kiro/tools/nation-heal.sh"
LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
SESSION="${KIRO_SESSION_ID:-unknown}"
echo "[$TS] [SPAWN] Session: $SESSION CWD: $PWD" >> "$LOG"

# ── Environment context ──────────────────────────────────────────────────────
echo "=== NATION AGENT v2 — Online ==="
echo "Time : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "CWD  : $PWD"
echo "User : $(whoami)  Host: $(uname -n)  Arch: $(uname -m)"
echo "Shell: Bash $BASH_VERSION"

# ── Git context (if in a repo) ───────────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "detached")
    LAST=$(git log --oneline -1 2>/dev/null || echo "no commits")
    CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo "=== Git: $BRANCH ($CHANGES changed files) ==="
    echo "Last: $LAST"
    git status --short 2>/dev/null | head -10
fi

# ── Runtimes ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Runtimes ==="
python3 --version 2>/dev/null | xargs echo "  Python3:"  || echo "  Python3: not found"
node --version    2>/dev/null | xargs echo "  Node:   " || echo "  Node: not found"
git --version     2>/dev/null | xargs echo "  Git:    " || echo "  Git: not found"

# ── Project type detection ────────────────────────────────────────────────────
if [ -f "package.json" ]; then
    NAME=$(python3 -c "import json; d=json.load(open('package.json')); print(d.get('name','?'))" 2>/dev/null || echo "?")
    echo ""
    echo "=== Project: Node.js ($NAME) ==="
fi
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    echo ""
    echo "=== Project: Python ==="
    [ -f "requirements.txt" ] && echo "  requirements.txt: $(wc -l < requirements.txt) deps"
fi
if [ -f "Makefile" ]; then
    echo ""
    echo "=== Makefile targets ==="
    grep -E '^[a-zA-Z0-9_-]+:' Makefile 2>/dev/null | sed 's/:.*//; s/^/  /' | head -8 || true
fi

# ── Memory summary ────────────────────────────────────────────────────────────
echo ""
echo "=== Memory ==="
if [ -x "$MEMORY" ]; then
    $MEMORY init 2>/dev/null | head -2
    echo ""
    echo "Recent context:"
    $MEMORY recent 2>/dev/null | head -30 || echo "  (no memories yet)"
else
    echo "  Memory system not available"
fi

# ── Log spawn event ───────────────────────────────────────────────────────────
if [ -x "$MEMORY" ]; then
    $MEMORY log "spawn" "session=$SESSION cwd=$PWD" 2>/dev/null || true
fi

# ── Quick health check (non-blocking) ─────────────────────────────────────────
if [ -x "$HEAL" ]; then
    ISSUES=0
    for script in "$HOME/.kiro/tools/nation-"*.sh "$HOME/.kiro/hooks/nation-"*.sh; do
        [ -x "$script" ] || ISSUES=$((ISSUES+1))
    done
    if [ $ISSUES -gt 0 ]; then
        echo ""
        echo "⚠ $ISSUES tool(s) not executable — run: nation-heal.sh fix permissions"
    fi
fi

exit 0
