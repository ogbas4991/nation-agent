#!/bin/bash
# NATION AGENT — stop hook
# Runs when the assistant finishes a response turn.
# Logs the turn completion and optionally auto-formats modified files.
set -euo pipefail

LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] [STOP] Turn complete. Session: ${KIRO_SESSION_ID:-unknown}" >> "$LOG"

exit 0
