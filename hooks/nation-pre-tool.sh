#!/bin/bash
# NATION AGENT — preToolUse hook (v2)
# Runs before every tool execution.
# - Blocks dangerous commands
# - Logs tool usage to memory
# - Triggers self-healing on known error patterns
set -euo pipefail

MEMORY="$HOME/.kiro/tools/nation-memory.sh"
LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

EVENT=$(cat)
TS=$(date '+%Y-%m-%d %H:%M:%S')

TOOL_NAME=$(echo "$EVENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")

echo "[$TS] [PRE] tool=$TOOL_NAME session=${KIRO_SESSION_ID:-?}" >> "$LOG"

# ── Shell safety check ────────────────────────────────────────────────────────
if [[ "$TOOL_NAME" == "shell" || "$TOOL_NAME" == "execute_bash" || "$TOOL_NAME" == "execute_cmd" ]]; then
    COMMAND=$(echo "$EVENT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('command',''))
" 2>/dev/null || echo "")

    echo "[$TS] [PRE] shell: $COMMAND" >> "$LOG"

    DANGEROUS=(
        "rm -rf /"
        "rm -rf \$HOME"
        "rm -rf ~/"
        "dd if="
        "mkfs"
        ":(){:|:&};:"
        "chmod -R 777 /"
        "> /dev/sda"
        "git push --force"
        "git reset --hard"
        "DROP TABLE"
        "DROP DATABASE"
        "truncate /dev"
    )
    for PATTERN in "${DANGEROUS[@]}"; do
        if echo "$COMMAND" | grep -qF "$PATTERN" 2>/dev/null; then
            MSG="NATION AGENT BLOCKED: '$PATTERN' matched in command. This is a dangerous operation. If you really need this, explain why and I will ask for confirmation."
            echo "$MSG" >&2
            # Store the block in memory
            if [ -x "$MEMORY" ]; then
                $MEMORY log "blocked-command" "$COMMAND" 2>/dev/null || true
            fi
            exit 2
        fi
    done
fi

# ── Log write operations to memory ────────────────────────────────────────────
if [[ "$TOOL_NAME" == "write" || "$TOOL_NAME" == "fs_write" ]]; then
    FILE_PATH=$(echo "$EVENT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('tool_input',{}).get('path',''))
" 2>/dev/null || echo "")
    if [ -n "$FILE_PATH" ] && [ -x "$MEMORY" ]; then
        $MEMORY log "file-write" "$FILE_PATH" 2>/dev/null || true
    fi
fi

exit 0
