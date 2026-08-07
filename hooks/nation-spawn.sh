#!/bin/bash
# NATION AGENT — agentSpawn hook v3
set -euo pipefail
source "$HOME/.kiro/lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
MEMORY="$TOOLS/nation-memory.sh"
SKILLS="$TOOLS/nation-skills.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
SESSION="${KIRO_SESSION_ID:-unknown}"
echo "[$TS] [SPAWN] Session: $SESSION Platform: ${NATION_PLATFORM:-?} CWD: $PWD" >> "$LOG"

# ── Banner ────────────────────────────────────────────────────────────────
[ -x "$TOOLS/nation-banner.sh" ] && "$TOOLS/nation-banner.sh" full 2>/dev/null || true

# ── Environment ───────────────────────────────────────────────────────────
echo ""
nation_platform_info 2>/dev/null || true
echo "Time : $TS"
echo "CWD  : $PWD"

# ── Git context ───────────────────────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    LAST=$(git log --oneline -1 2>/dev/null || echo "no commits")
    CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    echo ""
    echo "=== Git: $BRANCH ($CHANGES changed) — $LAST ==="
fi

# ── Runtimes ──────────────────────────────────────────────────────────────
echo ""
echo "=== Runtimes ==="
for bin in python3 node git curl; do
    command -v "$bin" &>/dev/null && { echo "  ✓ $bin $({ $bin --version 2>&1 || true; } | head -1 | cut -c1-30)"; } || echo "  ✗ $bin not found"
done

# ── Skills auto-load ──────────────────────────────────────────────────────
echo ""
echo "=== Skills ==="
if [ -x "$SKILLS" ]; then
    "$SKILLS" scan 2>/dev/null | grep -v "^Scanning" || true
    "$SKILLS" list 2>/dev/null | head -20 || true
else
    echo "  Skills manager not found"
fi

# ── Memory ────────────────────────────────────────────────────────────────
echo ""
echo "=== Memory ==="
if [ -x "$MEMORY" ]; then
    "$MEMORY" init 2>/dev/null | head -1 || true
    echo "Recent context:"
    "$MEMORY" recent 2>/dev/null | head -25 || echo "  (empty)"
    "$MEMORY" log "spawn" "session=$SESSION platform=${NATION_PLATFORM:-?}" 2>/dev/null || true
fi

# ── Quick health ──────────────────────────────────────────────────────────
BAD=0
for s in "$TOOLS"/nation-*.sh "$HOME/.kiro/hooks"/nation-*.sh; do
    [ -x "$s" ] || BAD=$((BAD+1))
done
[ $BAD -gt 0 ] && echo "" && echo "⚠ $BAD script(s) not executable — run: papy heal fix permissions"

exit 0
