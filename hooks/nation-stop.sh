#!/bin/bash
# NATION AGENT — stop hook (v2)
# Runs when the assistant finishes a response turn.
# - Logs turn completion to memory
# - Extracts key decisions from the response
# - Persists session context for future sessions
set -euo pipefail

MEMORY="$HOME/.kiro/tools/nation-memory.sh"
LOG="$HOME/.kiro/logs/nation-agent.log"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
SESSION="${KIRO_SESSION_ID:-unknown}"

echo "[$TS] [STOP] Turn complete. Session: $SESSION" >> "$LOG"

# Read the hook event (contains assistant_response)
EVENT=$(cat 2>/dev/null || echo "{}")

# Extract decisions/facts from the response text
RESPONSE=$(echo "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('assistant_response', '')[:2000])
" 2>/dev/null || echo "")

if [ -x "$MEMORY" ] && [ -n "$RESPONSE" ]; then
    # Log turn completion
    $MEMORY log "turn-complete" "session=$SESSION" 2>/dev/null || true

    # Extract and store any file paths that were mentioned as created/modified
    echo "$RESPONSE" | python3 - << 'PYEOF' 2>/dev/null || true
import sys, re, subprocess, os

response = sys.stdin.read()
memory = os.path.expanduser("~/.kiro/tools/nation-memory.sh")

# Find file paths that were created or modified
patterns = [
    r'[Cc]reated[: ]+([~/][^\s,\)]+\.[a-z]{1,6})',
    r'[Mm]odified[: ]+([~/][^\s,\)]+\.[a-z]{1,6})',
    r'[Ww]rote[: ]+([~/][^\s,\)]+\.[a-z]{1,6})',
]
found = set()
for pat in patterns:
    for m in re.findall(pat, response):
        if len(m) > 3 and not m.startswith('http'):
            found.add(m)

for path in list(found)[:5]:
    subprocess.run(
        [memory, 'remember', 'task', f'file.created.{path.split("/")[-1]}', f'Created/modified: {path}'],
        capture_output=True
    )
PYEOF
fi

exit 0
