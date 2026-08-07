#!/bin/bash
# NATION AGENT — agentSpawn hook
# Runs when the agent initializes. Gathers environment context and injects it.
set -euo pipefail

LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] [SPAWN] Session: ${KIRO_SESSION_ID:-unknown} CWD: $PWD" >> "$LOG"

# Gather useful context for the agent
echo "=== NATION AGENT Environment ==="
echo "Time     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "CWD      : $PWD"
echo "User     : $(whoami)"
echo "Host     : $(uname -n)"
echo "Arch     : $(uname -m)"
echo "Shell    : $BASH_VERSION"

# Show git status if inside a git repo
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    echo ""
    echo "=== Git Status ==="
    git status --short --branch 2>/dev/null | head -20
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits yet")
    echo "Last commit: $LAST_COMMIT"
fi

# Show available runtimes
echo ""
echo "=== Available Runtimes ==="
python3 --version 2>/dev/null && echo "  python3 ✓" || echo "  python3 ✗"
node --version 2>/dev/null | xargs -I{} echo "  node {} ✓" || echo "  node ✗"
git --version 2>/dev/null | xargs -I{} echo "  {} ✓" || echo "  git ✗"

# Show project type hints if detectable
if [ -f "package.json" ]; then
    echo ""
    echo "=== Project: Node.js ==="
    PROJECT_NAME=$(python3 -c "import json,sys; d=json.load(open('package.json')); print(d.get('name','unknown'))" 2>/dev/null || echo "unknown")
    echo "  name: $PROJECT_NAME"
fi
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    echo ""
    echo "=== Project: Python ==="
    [ -f "requirements.txt" ] && echo "  requirements.txt found ($(wc -l < requirements.txt) lines)"
    [ -f "pyproject.toml" ] && echo "  pyproject.toml found"
fi
if [ -f "Makefile" ]; then
    echo ""
    echo "=== Makefile targets ==="
    grep -E '^[a-zA-Z0-9_-]+:' Makefile 2>/dev/null | head -10 | sed 's/:.*//; s/^/  /'
fi

exit 0
