#!/bin/bash
# NATION AGENT — agentSpawn hook v4
set -euo pipefail
source "$HOME/.kiro/lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
MEMORY="$TOOLS/nation-memory.sh"
SKILLS="$TOOLS/nation-skills.sh"
OLLAMA="$TOOLS/nation-ollama.sh"
SHIZUKU="$TOOLS/nation-shizuku.sh"
SUGGEST="$TOOLS/nation-suggest.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
SESSION="${KIRO_SESSION_ID:-unknown}"
echo "[$TS] [SPAWN] v4 Session=$SESSION Platform=${NATION_PLATFORM:-?} CWD=$PWD" >> "$LOG"

# ── Banner ────────────────────────────────────────────────────────────────
[ -x "$TOOLS/nation-banner.sh" ] && "$TOOLS/nation-banner.sh" full 2>/dev/null || true

# ── Platform info ─────────────────────────────────────────────────────────
echo ""
echo "Platform : ${NATION_PLATFORM:-unknown}  |  $(uname -m)  |  $(date '+%H:%M:%S')"
echo "CWD      : $PWD"

# ── Git context ───────────────────────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    LAST=$(git log --oneline -1 2>/dev/null || echo "no commits")
    echo "Git      : $BRANCH ($CHANGES changed) — $LAST"
fi

# ── Runtimes ──────────────────────────────────────────────────────────────
echo ""
echo "=== Runtimes ==="
for bin in python3 node git curl ollama; do
    if command -v "$bin" &>/dev/null; then
        VER=$({ "$bin" --version 2>&1 || true; } | head -1 | cut -c1-35)
        echo "  ✓ $bin — $VER"
    else
        echo "  ✗ $bin"
    fi
done

# ── Start Ollama in background ────────────────────────────────────────────
echo ""
echo "=== Ollama ==="
if [ -x "$OLLAMA" ]; then
    if "$OLLAMA" status 2>/dev/null | grep -q "RUNNING"; then
        PORT=$(cat "${NATION_DIR:-$HOME/.kiro}/ollama.port" 2>/dev/null || echo 11434)
        echo "  ● Running on port $PORT"
    else
        echo "  Starting Ollama in background..."
        "$OLLAMA" auto >/dev/null 2>&1 &
        echo "  ○ Starting... (use 'papy ollama status' to check)"
    fi
else
    echo "  Ollama tool not found"
fi

# ── Shizuku / ADB wireless check (non-blocking) ───────────────────────────
echo ""
echo "=== Connectivity ==="
if [ -x "$SHIZUKU" ]; then
    "$SHIZUKU" auto >/dev/null 2>&1 &
    SHIZUKU_STATUS=$("$SHIZUKU" status 2>/dev/null | head -3 || echo "checking...")
    echo "$SHIZUKU_STATUS" | head -3
else
    echo "  ADB/Shizuku tools not found"
fi

# ── Skills auto-scan ──────────────────────────────────────────────────────
echo ""
echo "=== Skills ==="
if [ -x "$SKILLS" ]; then
    NEW=$("$SKILLS" scan 2>/dev/null | grep "Registered:" | wc -l | tr -d ' ')
    TOTAL=$(python3 -c "
import json,os
r=os.path.expanduser('~/.kiro/skills/registry.json')
try: d=json.load(open(r)); print(len(d.get('skills',{})))
except: print(0)
" 2>/dev/null || echo "?")
    echo "  $TOTAL skill(s) loaded${NEW:+, $NEW new}"
else
    echo "  Skills manager not found"
fi

# ── Memory ────────────────────────────────────────────────────────────────
echo ""
echo "=== Memory ==="
if [ -x "$MEMORY" ]; then
    COUNT=$(python3 -c "
import sqlite3,os
db=os.path.expanduser('~/.kiro/memory/memory.db')
try: c=sqlite3.connect(db); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])
except: print(0)
" 2>/dev/null || echo "?")
    echo "  $COUNT memories stored"
    echo ""
    echo "  Recent context:"
    "$MEMORY" recent 2>/dev/null | head -20 || echo "  (empty)"
    "$MEMORY" log "spawn" "v4 session=$SESSION" 2>/dev/null || true
fi

# ── Follow-up suggestions ─────────────────────────────────────────────────
echo ""
if [ -x "$SUGGEST" ]; then
    "$SUGGEST" 2>/dev/null || true
fi

# ── Health quick-check ────────────────────────────────────────────────────
BAD=0
for s in "$TOOLS"/nation-*.sh "$HOME/.kiro/hooks"/nation-*.sh \
          "$TOOLS/papy"; do
    [ -x "$s" ] || BAD=$((BAD+1))
done
[ $BAD -gt 0 ] && echo "" && echo "⚠ $BAD script(s) not executable — run: papy heal fix permissions"

exit 0
