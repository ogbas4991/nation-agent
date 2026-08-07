#!/bin/bash
# NATION AGENT — preToolUse hook
# Runs before any tool execution. Logs the event. Blocks dangerous shell commands.
set -euo pipefail

LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

# Read the JSON hook event from stdin
EVENT=$(cat)

TOOL_NAME=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] [PRE] tool=$TOOL_NAME session=${KIRO_SESSION_ID:-unknown}" >> "$LOG"

# Only apply safety checks to shell/execute tools
if [[ "$TOOL_NAME" == "shell" || "$TOOL_NAME" == "execute_bash" || "$TOOL_NAME" == "execute_cmd" ]]; then
    COMMAND=$(echo "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
# shell tool uses 'command' key
cmd = inp.get('command', '')
print(cmd)
" 2>/dev/null || echo "")

    # Log the command
    echo "[$TIMESTAMP] [PRE] shell command: $COMMAND" >> "$LOG"

    # Block known destructive patterns
    DANGEROUS_PATTERNS=(
        "rm -rf /"
        "rm -rf \$HOME"
        "rm -rf ~"
        "dd if="
        "mkfs"
        ":(){:|:&};:"
        "chmod -R 777 /"
        "chown -R"
        "> /dev/sda"
    )

    for PATTERN in "${DANGEROUS_PATTERNS[@]}"; do
        if echo "$COMMAND" | grep -qF "$PATTERN" 2>/dev/null; then
            echo "NATION AGENT safety check BLOCKED: command matches dangerous pattern: '$PATTERN'" >&2
            echo "Command was: $COMMAND" >&2
            exit 2
        fi
    done
fi

exit 0
