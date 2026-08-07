#!/bin/bash
# NATION AGENT — postToolUse hook
# Runs after any tool execution. Logs results and detects failures.
set -euo pipefail

LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

# Read the JSON hook event from stdin
EVENT=$(cat)

TOOL_NAME=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
SUCCESS=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_response',{}).get('success','unknown'))" 2>/dev/null || echo "unknown")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] [POST] tool=$TOOL_NAME success=$SUCCESS session=${KIRO_SESSION_ID:-unknown}" >> "$LOG"

# If a write tool succeeded, log the path that was modified
if [[ "$TOOL_NAME" == "write" || "$TOOL_NAME" == "fs_write" ]] && [[ "$SUCCESS" == "True" || "$SUCCESS" == "true" ]]; then
    WRITTEN_PATH=$(echo "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
# write tool uses 'path' key
path = inp.get('path', '')
print(path)
" 2>/dev/null || echo "")
    if [ -n "$WRITTEN_PATH" ]; then
        echo "[$TIMESTAMP] [POST] file modified: $WRITTEN_PATH" >> "$LOG"
    fi
fi

exit 0
