#!/bin/bash
# NATION AGENT — agentSpawn hook v5
set -uo pipefail
source "$HOME/.kiro/lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
MEMORY="$TOOLS/nation-memory.sh"
SKILLS="$TOOLS/nation-skills.sh"
OLLAMA="$TOOLS/nation-ollama.sh"
SPEECH="$TOOLS/nation-speech.sh"
AUTOSAVE="$TOOLS/nation-autosave.sh"
SUGGEST="$TOOLS/nation-suggest.sh"
CONFIG="$TOOLS/nation-config.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
SESSION="${KIRO_SESSION_ID:-unknown}"
echo "[$TS] [SPAWN] v5 Session=$SESSION Platform=${NATION_PLATFORM:-?} CWD=$PWD" >> "$LOG"

# ── Banner ────────────────────────────────────────────────────────────────
[ -x "$TOOLS/nation-banner.sh" ] && "$TOOLS/nation-banner.sh" full 2>/dev/null || true

# ── Info ──────────────────────────────────────────────────────────────────
echo ""
echo "Platform : ${NATION_PLATFORM:-unknown}  $(uname -m)  $(date '+%H:%M:%S')"
echo "CWD      : $PWD"
git rev-parse --is-inside-work-tree &>/dev/null 2>&1 && \
    echo "Git      : $(git branch --show-current 2>/dev/null) ($(git status --short 2>/dev/null | wc -l | tr -d ' ') changes) — $(git log --oneline -1 2>/dev/null)"

# ── Background services (non-blocking) ────────────────────────────────────
echo ""
echo "=== Starting services ==="

# Ollama
if [ -x "$OLLAMA" ]; then
    curl -sf "http://localhost:$(cat "${NATION_DIR:-$HOME/.kiro}/ollama.port" 2>/dev/null || echo 11434)/api/tags" \
        >/dev/null 2>&1 && echo "  ✓ Ollama running" || {
        "$OLLAMA" auto >/dev/null 2>&1 &
        echo "  ○ Ollama starting..."
    }
fi

# AutoSave
if [ -x "$AUTOSAVE" ]; then
    "$AUTOSAVE" status 2>/dev/null | grep -q "RUNNING" && \
        echo "  ✓ AutoSave active" || {
        "$AUTOSAVE" start >/dev/null 2>&1 &
        echo "  ○ AutoSave starting..."
    }
fi

# Voice listener
if [ -x "$CONFIG" ] && [ -x "$TOOLS/nation-voice.sh" ]; then
    VOICE_EN=$("$CONFIG" get voice.enabled 2>/dev/null || echo "false")
    if [ "$VOICE_EN" = "true" ]; then
        "$TOOLS/nation-voice.sh" status 2>/dev/null | grep -q "RUNNING" && \
            echo "  ✓ Voice listener active" || {
            "$TOOLS/nation-voice.sh" listen >/dev/null 2>&1 &
            echo "  ○ Voice listener starting..."
        }
        WAKE=$("$CONFIG" get agent.wake_word 2>/dev/null || echo "hey papy")
        echo "    Wake word: '$WAKE'"
    else
        echo "  ○ Voice: disabled (papy config set voice.enabled true to enable)"
    fi
fi

# ── Skills ────────────────────────────────────────────────────────────────
echo ""
echo "=== Skills ==="
if [ -x "$SKILLS" ]; then
    NEW=$("$SKILLS" scan 2>/dev/null | grep -c "Registered:" 2>/dev/null || echo "0")
    TOTAL=$(python3 -c "
import json,os
r=os.path.expanduser('~/.kiro/skills/registry.json')
try: d=json.load(open(r)); print(len(d.get('skills',{})))
except: print(0)" 2>/dev/null || echo "?")
    echo "  $TOTAL skill(s)${NEW:+, $NEW new}"
fi

# ── Memory ────────────────────────────────────────────────────────────────
echo ""
echo "=== Memory ==="
if [ -x "$MEMORY" ]; then
    COUNT=$(python3 -c "
import sqlite3,os
db=os.path.expanduser('~/.kiro/memory/memory.db')
try: c=sqlite3.connect(db); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])
except: print(0)" 2>/dev/null || echo "?")
    echo "  $COUNT memories"
    "$MEMORY" recent 2>/dev/null | head -15 || true
    "$MEMORY" log "spawn" "v5 session=$SESSION" 2>/dev/null || true
fi

# ── Auto-save now ─────────────────────────────────────────────────────────
[ -x "$AUTOSAVE" ] && "$AUTOSAVE" save >/dev/null 2>&1 || true

# ── Suggestions ───────────────────────────────────────────────────────────
echo ""
if [ -x "$SUGGEST" ]; then
    SUGG_EN=$("$CONFIG" get suggest.on_spawn 2>/dev/null || echo "true")
    [ "$SUGG_EN" = "true" ] && "$SUGGEST" 2>/dev/null || true
fi

# ── TTS Welcome ───────────────────────────────────────────────────────────
[ -x "$SPEECH" ] && "$SPEECH" welcome >/dev/null 2>&1 & true

exit 0
