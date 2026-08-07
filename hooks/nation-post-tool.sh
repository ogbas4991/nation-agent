#!/bin/bash
# NATION AGENT — postToolUse hook (v2)
# Runs after every tool execution.
# - Detects errors in tool output
# - Stores errors in memory for learning
# - Injects healing suggestions on known error patterns
set -euo pipefail

MEMORY="$HOME/.kiro/tools/nation-memory.sh"
HEAL="$HOME/.kiro/tools/nation-heal.sh"
LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

EVENT=$(cat)
TS=$(date '+%Y-%m-%d %H:%M:%S')

TOOL_NAME=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
SUCCESS=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('tool_response',{}).get('success',True)).lower())" 2>/dev/null || echo "true")

echo "[$TS] [POST] tool=$TOOL_NAME success=$SUCCESS session=${KIRO_SESSION_ID:-?}" >> "$LOG"

# ── On failure: extract error and run self-healer ─────────────────────────────
if [[ "$SUCCESS" == "false" ]]; then
    ERROR_TEXT=$(echo "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
resp = d.get('tool_response', {})
# Try to get error message from various fields
err = resp.get('error', resp.get('message', resp.get('result', '')))
if isinstance(err, list):
    err = ' '.join(str(e) for e in err)
print(str(err)[:500])
" 2>/dev/null || echo "unknown error")

    echo "[$TS] [POST] ERROR in $TOOL_NAME: $ERROR_TEXT" >> "$LOG"

    # Store error in memory
    if [ -x "$MEMORY" ]; then
        $MEMORY remember error "error.${TOOL_NAME}.$(date +%s)" \
            "Tool: $TOOL_NAME | Error: $ERROR_TEXT" 2>/dev/null || true
    fi

    # Output healing advice to agent context
    if [ -x "$HEAL" ] && [ -n "$ERROR_TEXT" ]; then
        echo ""
        echo "=== NATION AGENT Self-Healing ==="
        $HEAL diagnose "$ERROR_TEXT" 2>/dev/null || true
    fi
fi

# ── Log successful file writes ────────────────────────────────────────────────
if [[ "$SUCCESS" == "true" ]] && [[ "$TOOL_NAME" == "write" || "$TOOL_NAME" == "fs_write" ]]; then
    WRITTEN=$(echo "$EVENT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('path',''))
" 2>/dev/null || echo "")
    if [ -n "$WRITTEN" ]; then
        echo "[$TS] [POST] wrote: $WRITTEN" >> "$LOG"
        if [ -x "$MEMORY" ]; then
            $MEMORY log "file-written" "$WRITTEN" 2>/dev/null || true
        fi
    fi
fi

exit 0
