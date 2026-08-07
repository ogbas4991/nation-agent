#!/bin/bash
# NATION AGENT — 24/7 Autonomous Auto-Agent Runner
# Keeps the agent running continuously with no API limits (uses local Ollama).
# Monitors tasks, executes them, retries on failure, logs everything.
#
# Usage: nation-auto.sh <command> [args...]
#
# Commands:
#   start   [task_file]   Start autonomous agent loop
#   stop                  Stop the auto-agent
#   status                Show auto-agent status
#   add     <task>        Add a task to the queue
#   queue                 Show pending tasks
#   history               Show completed tasks
#   watch   <dir>         Watch a directory and auto-process changes
#   loop    <cmd> [secs]  Repeat a command every N seconds (default 60)
#   once    <task>        Run one task autonomously then exit
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-status}"
TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
MEMORY="$TOOLS/nation-memory.sh"
HEAL="$TOOLS/nation-heal.sh"
OLLAMA="$TOOLS/nation-ollama.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
AUTO_LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-auto.log"
TASK_QUEUE="${NATION_DIR:-$HOME/.kiro}/auto/queue.jsonl"
TASK_DONE="${NATION_DIR:-$HOME/.kiro}/auto/done.jsonl"
PID_FILE="${NATION_DIR:-$HOME/.kiro}/auto/agent.pid"
mkdir -p "$(dirname "$TASK_QUEUE")" "$(dirname "$LOG")"

TS() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(TS)] [AUTO] $*" | tee -a "$AUTO_LOG" >> "$LOG" 2>/dev/null || true; }
die()  { echo "ERROR: $*" >&2; exit 1; }

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# Execute a task using Ollama (local, no API limit) or kiro-cli
execute_task() {
    local task="$1"
    log "executing: $task"

    # Try Ollama first (local, unlimited)
    if "$OLLAMA" status 2>/dev/null | grep -q "RUNNING"; then
        local port
        port=$("$OLLAMA" port 2>/dev/null || echo 11434)
        local model
        model=$(cat "${NATION_DIR:-$HOME/.kiro}/ollama.default" 2>/dev/null || echo "llama3.2")
        echo "=== Auto-Agent Task ===" >> "$AUTO_LOG"
        echo "Task: $task" >> "$AUTO_LOG"
        local response
        response=$(curl -sf "http://localhost:${port}/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model\",\"prompt\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "You are NATION AGENT. Execute this task autonomously and return results: $task"),\"stream\":false}" \
            2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))" 2>/dev/null) || response="(Ollama error)"
        echo "Response: $response" >> "$AUTO_LOG"
        echo "$response"
        return 0
    fi

    # Fallback: execute shell commands directly
    log "Ollama not running — executing as shell task"
    eval "$task" 2>&1 | tee -a "$AUTO_LOG"
}

# Process task queue
process_queue() {
    [ -f "$TASK_QUEUE" ] || return 0
    [ -s "$TASK_QUEUE" ] || return 0

    # Read first task
    TASK_JSON=$(head -1 "$TASK_QUEUE")
    TASK=$(echo "$TASK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task',''))" 2>/dev/null)
    [ -n "$TASK" ] || return 0

    # Remove from queue
    TMPQ="${TASK_QUEUE}.tmp"
    tail -n +2 "$TASK_QUEUE" > "$TMPQ" && mv "$TMPQ" "$TASK_QUEUE"

    log "processing task: $TASK"

    # Execute with retry
    SUCCESS=0
    for attempt in 1 2 3; do
        if execute_task "$TASK"; then
            SUCCESS=1
            break
        fi
        log "attempt $attempt failed, retrying..."
        sleep $((attempt * 2))
    done

    # Record result
    RESULT_JSON=$(python3 -c "
import json, datetime, sys
print(json.dumps({
    'task': sys.argv[1],
    'success': sys.argv[2]=='1',
    'ts': datetime.datetime.now().isoformat()[:19]
}))" "$TASK" "$SUCCESS")
    echo "$RESULT_JSON" >> "$TASK_DONE"

    [ -x "$MEMORY" ] && "$MEMORY" log "auto-task" "$TASK" 2>/dev/null || true
}

# Main loop
auto_loop() {
    log "Auto-agent loop started (PID $$)"
    echo $$ > "$PID_FILE"

    # Start Ollama if available
    if command -v ollama &>/dev/null; then
        "$OLLAMA" auto 2>/dev/null || true
    fi

    local cycle=0
    while true; do
        cycle=$((cycle + 1))
        log "cycle $cycle"

        # Process task queue
        process_queue

        # Run health check every 10 cycles
        if [ $((cycle % 10)) -eq 0 ]; then
            "$HEAL" check >> "$AUTO_LOG" 2>&1 || true
        fi

        # Generate suggestions every 5 cycles
        if [ $((cycle % 5)) -eq 0 ] && [ -x "$TOOLS/nation-suggest.sh" ]; then
            "$TOOLS/nation-suggest.sh" >> "$AUTO_LOG" 2>&1 || true
        fi

        sleep 30
    done
}

case "$CMD" in

  start)
    if is_running; then
        echo "Auto-agent already running (PID $(cat "$PID_FILE"))"
        exit 0
    fi
    TASK_FILE="${2:-}"
    log "start"

    # Load initial tasks from file if provided
    if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
        echo "Loading tasks from: $TASK_FILE"
        while IFS= read -r task; do
            [ -z "$task" ] || [ "${task:0:1}" = "#" ] && continue
            echo "{\"task\":\"$task\",\"added\":\"$(TS)\"}" >> "$TASK_QUEUE"
            echo "  Queued: $task"
        done < "$TASK_FILE"
    fi

    echo "Starting auto-agent in background..."
    nohup bash -c "$(declare -f auto_loop process_queue execute_task log TS is_running); auto_loop" \
        >> "$AUTO_LOG" 2>&1 &
    BG_PID=$!
    echo "$BG_PID" > "$PID_FILE"
    sleep 1
    is_running && echo "Auto-agent started (PID $BG_PID)" || echo "Start failed — check: $AUTO_LOG"
    ;;

  stop)
    if is_running; then
        PID=$(cat "$PID_FILE")
        kill "$PID" 2>/dev/null
        rm -f "$PID_FILE"
        log "stopped (PID $PID)"
        echo "Auto-agent stopped."
    else
        echo "Auto-agent not running."
    fi
    ;;

  status)
    echo "=== Auto-Agent Status ==="
    if is_running; then
        PID=$(cat "$PID_FILE")
        echo "Status : RUNNING (PID $PID)"
        UPTIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ' || echo "?")
        echo "Uptime : $UPTIME"
    else
        echo "Status : STOPPED"
    fi
    echo ""
    QLEN=$(wc -l < "$TASK_QUEUE" 2>/dev/null | tr -d ' ') ; QLEN="${QLEN:-0}"
    DLEN=$(wc -l < "$TASK_DONE"  2>/dev/null | tr -d ' ') ; DLEN="${DLEN:-0}"
    echo "Queue  : $QLEN pending"
    echo "Done   : $DLEN completed"
    echo ""
    echo "Last log entries:"
    tail -5 "$AUTO_LOG" 2>/dev/null || echo "(no log)"
    ;;

  add)
    shift
    [ $# -gt 0 ] || die "Task description required"
    TASK="$*"
    echo "{\"task\":\"$TASK\",\"added\":\"$(TS)\"}" >> "$TASK_QUEUE"
    log "task added: $TASK"
    echo "Task queued: $TASK"
    QLEN=$(wc -l < "$TASK_QUEUE" | tr -d ' ')
    echo "Queue depth: $QLEN"
    ;;

  queue)
    echo "=== Task Queue ==="
    if [ -f "$TASK_QUEUE" ] && [ -s "$TASK_QUEUE" ]; then
        python3 -c "
import json, sys
with open('$TASK_QUEUE') as f:
    for i, line in enumerate(f,1):
        try:
            d=json.loads(line)
            print(f'  {i}. [{d.get(\"added\",\"?\")[:16]}] {d.get(\"task\",\"?\")}')
        except: pass
"
    else
        echo "  (empty)"
    fi
    ;;

  history)
    echo "=== Completed Tasks ==="
    if [ -f "$TASK_DONE" ] && [ -s "$TASK_DONE" ]; then
        tail -20 "$TASK_DONE" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        d=json.loads(line)
        ok='✓' if d.get('success') else '✗'
        print(f'  {ok} [{d.get(\"ts\",\"?\")[:16]}] {d.get(\"task\",\"?\")}')
    except: pass
"
    else
        echo "  (none)"
    fi
    ;;

  watch)
    DIR="${2:-.}"
    [ -d "$DIR" ] || die "Directory not found: $DIR"
    log "watch $DIR"
    echo "Watching: $DIR (Ctrl+C to stop)"
    if command -v inotifywait &>/dev/null; then
        inotifywait -m -r -e modify,create,delete "$DIR" 2>/dev/null | \
        while IFS= read -r event; do
            log "change: $event"
            echo "Change: $event" | tee -a "$AUTO_LOG"
            [ -x "$TOOLS/nation-suggest.sh" ] && \
                "$TOOLS/nation-suggest.sh" "file changed: $event" 2>/dev/null || true
        done
    else
        echo "inotifywait not found. Using polling (5s)..."
        HASH=""
        while true; do
            NEW_HASH=$(find "$DIR" -newer "$DIR" -type f 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1)
            if [ "$NEW_HASH" != "$HASH" ] && [ -n "$HASH" ]; then
                log "directory changed: $DIR"
                echo "Change detected in $DIR"
            fi
            HASH="$NEW_HASH"
            sleep 5
        done
    fi
    ;;

  loop)
    shift
    CMD_TO_LOOP="${1:-echo heartbeat}"
    INTERVAL="${2:-60}"
    log "loop: $CMD_TO_LOOP every ${INTERVAL}s"
    echo "Looping every ${INTERVAL}s: $CMD_TO_LOOP (Ctrl+C to stop)"
    while true; do
        echo "[$(TS)] Running: $CMD_TO_LOOP"
        eval "$CMD_TO_LOOP" 2>&1 | tee -a "$AUTO_LOG" || log "loop error"
        sleep "$INTERVAL"
    done
    ;;

  once)
    shift
    TASK="$*"
    [ -n "$TASK" ] || die "Task required"
    log "once: $TASK"
    "$OLLAMA" auto 2>/dev/null || true
    execute_task "$TASK"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) die "Unknown: $CMD. Run: nation-auto.sh help" ;;
esac
