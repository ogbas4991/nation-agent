#!/bin/bash
# NATION AGENT — Ollama Manager
# Starts, stops, and manages Ollama in the background.
# Auto-selects a free port if default is taken.
#
# Usage: nation-ollama.sh <command> [args...]
#
# Commands:
#   start   [model]     Start Ollama in background (default model: llama3.2)
#   stop                Stop Ollama
#   status              Check if Ollama is running
#   pull    <model>     Pull/download a model
#   list                List installed models
#   run     <model>     Run interactive Ollama session
#   chat    <model> <prompt>  One-shot chat with a model
#   port                Show current Ollama port
#   auto                Start if not running, find free port automatically
#   models              List available models (local + popular remote)
#   set-default <model> Set default model
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-auto}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
OLLAMA_PID_FILE="${NATION_DIR:-$HOME/.kiro}/ollama.pid"
OLLAMA_PORT_FILE="${NATION_DIR:-$HOME/.kiro}/ollama.port"
DEFAULT_MODEL_FILE="${NATION_DIR:-$HOME/.kiro}/ollama.default"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [OLLAMA] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

OLLAMA_BIN=$(command -v ollama 2>/dev/null || echo "")
[ -n "$OLLAMA_BIN" ] || die "Ollama not installed. Install: curl -fsSL https://ollama.com/install.sh | sh"

get_default_model() {
    [ -f "$DEFAULT_MODEL_FILE" ] && cat "$DEFAULT_MODEL_FILE" || echo "llama3.2"
}

get_port() {
    [ -f "$OLLAMA_PORT_FILE" ] && cat "$OLLAMA_PORT_FILE" || echo "11434"
}

find_free_port() {
    local start="${1:-11434}"
    local port=$start
    while ss -tlnp 2>/dev/null | grep -q ":$port " || \
          netstat -tln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
        [ $port -gt 11500 ] && break
    done
    echo "$port"
}

is_running() {
    local port
    port=$(get_port)
    curl -sf "http://localhost:${port}/api/tags" >/dev/null 2>&1
}

case "$CMD" in

  start)
    MODEL="${2:-$(get_default_model)}"
    log "start (model=$MODEL)"

    if is_running; then
        PORT=$(get_port)
        echo "Ollama already running on port $PORT"
        exit 0
    fi

    # Find a free port
    PORT=$(find_free_port 11434)
    echo "$PORT" > "$OLLAMA_PORT_FILE"
    log "using port $PORT"

    echo "Starting Ollama on port $PORT (background)..."
    export OLLAMA_HOST="0.0.0.0:$PORT"
    nohup "$OLLAMA_BIN" serve > "$LOG.ollama" 2>&1 &
    PID=$!
    echo "$PID" > "$OLLAMA_PID_FILE"
    log "started PID=$PID port=$PORT"

    # Wait up to 15s for ready
    echo -n "Waiting for Ollama..."
    for i in $(seq 1 15); do
        sleep 1
        if is_running; then
            echo " ready! (${i}s)"
            break
        fi
        echo -n "."
    done

    is_running || { echo " TIMEOUT — check logs: $LOG.ollama"; exit 1; }
    echo "Ollama running: http://localhost:${PORT}"

    # Store in memory
    [ -x "$MEMORY" ] && \
        "$MEMORY" remember fact "ollama.port" "$PORT" 2>/dev/null || true
    [ -x "$MEMORY" ] && \
        "$MEMORY" remember fact "ollama.model" "$MODEL" 2>/dev/null || true
    ;;

  stop)
    log "stop"
    if [ -f "$OLLAMA_PID_FILE" ]; then
        PID=$(cat "$OLLAMA_PID_FILE")
        kill "$PID" 2>/dev/null && echo "Stopped Ollama (PID $PID)" || echo "Process $PID not found"
        rm -f "$OLLAMA_PID_FILE"
    else
        pkill -f "ollama serve" 2>/dev/null && echo "Ollama stopped" || echo "Ollama not running"
    fi
    ;;

  status)
    PORT=$(get_port)
    if is_running; then
        echo "Ollama: RUNNING on port $PORT"
        # List models
        curl -sf "http://localhost:${PORT}/api/tags" 2>/dev/null | \
            python3 -c "
import json,sys
d=json.load(sys.stdin)
models=d.get('models',[])
print(f'Models loaded: {len(models)}')
for m in models: print(f'  - {m.get(\"name\",\"?\")}')
" 2>/dev/null || true
    else
        echo "Ollama: STOPPED"
    fi
    ;;

  pull)
    [ -n "${2:-}" ] || die "Model name required (e.g. llama3.2, mistral, codellama)"
    log "pull $2"
    "$OLLAMA_BIN" pull "$2"
    ;;

  list)
    log "list"
    if is_running; then
        PORT=$(get_port)
        curl -sf "http://localhost:${PORT}/api/tags" | \
            python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('models',[]):
    size=m.get('size',0)
    size_gb=size/1024**3
    print(f\"{m['name']:40} {size_gb:.1f}GB\")
" 2>/dev/null || "$OLLAMA_BIN" list
    else
        "$OLLAMA_BIN" list
    fi
    ;;

  run)
    MODEL="${2:-$(get_default_model)}"
    log "run $MODEL"
    "$OLLAMA_BIN" run "$MODEL"
    ;;

  chat)
    MODEL="${2:-$(get_default_model)}"
    [ -n "${3:-}" ] || die "Prompt required"
    shift 2
    PROMPT="$*"
    PORT=$(get_port)
    log "chat $MODEL"
    if is_running; then
        curl -sf "http://localhost:${PORT}/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL\",\"prompt\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT"),\"stream\":false}" | \
            python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))"
    else
        die "Ollama not running. Start with: nation-ollama.sh start"
    fi
    ;;

  port)
    get_port
    ;;

  auto)
    # Start if not running, use existing port or find new one
    if is_running; then
        PORT=$(get_port)
        echo "Ollama already running on port $PORT"
    else
        "$0" start "${2:-$(get_default_model)}"
    fi
    ;;

  models)
    echo "=== Installed models ==="
    "$OLLAMA_BIN" list 2>/dev/null || echo "(none)"
    echo ""
    echo "=== Popular models (pull to install) ==="
    echo "  llama3.2        - Meta Llama 3.2 (3B, fast)"
    echo "  llama3.2:1b     - Llama 3.2 1B (very fast, small)"
    echo "  mistral         - Mistral 7B (great for coding)"
    echo "  codellama       - Code Llama (code-focused)"
    echo "  gemma2          - Google Gemma 2 (9B)"
    echo "  qwen2.5-coder   - Qwen 2.5 Coder (best for code)"
    echo "  phi3            - Microsoft Phi-3 (small, fast)"
    echo ""
    echo "Pull with: papy ollama pull <model>"
    ;;

  set-default)
    [ -n "${2:-}" ] || die "Model name required"
    echo "$2" > "$DEFAULT_MODEL_FILE"
    echo "Default model set: $2"
    [ -x "$MEMORY" ] && "$MEMORY" remember preference "ollama.default" "$2" 2>/dev/null || true
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) die "Unknown: $CMD. Run: nation-ollama.sh help" ;;
esac
