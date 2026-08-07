#!/bin/bash
# NATION AGENT — Persistent Session Manager
# Keeps NATION AGENT alive in a named tmux session inside proot.
# Even when Termux is closed, the session survives (Android keeps proot alive
# as long as it was started with termux-wake-lock).
#
# Usage: nation-persist.sh <command>
# Commands:
#   start       Start or reattach persistent tmux session
#   attach      Attach to existing session (interactive)
#   detach      Detach from session (keeps it running)
#   status      Show session status
#   stop        Kill the persistent session
#   restart     Stop then start
#   logs        Show agent background logs

set -uo pipefail

SESSION="nation"
LOG_DIR="${HOME}/.kiro/logs"
PERSIST_LOG="${LOG_DIR}/nation-persist.log"
AGENT_LOG="${LOG_DIR}/nation-agent.log"
KIRO_TOOLS="${HOME}/.kiro/tools"

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PERSIST] $*" | tee -a "$PERSIST_LOG"; }

CMD="${1:-start}"

# ── Check if session is alive ─────────────────────────────────────────────
session_alive() {
    tmux has-session -t "$SESSION" 2>/dev/null
}

# ── Start background services (non-interactive window) ───────────────────
start_services() {
    # Window 0: services (ollama + autosave + voice listener)
    tmux send-keys -t "${SESSION}:0" "" C-m  # no-op ping
    # Start ollama if not running
    tmux send-keys -t "${SESSION}:0" \
        'pgrep -x ollama >/dev/null || (ollama serve >/tmp/ollama.log 2>&1 & disown && sleep 2 && echo "[ollama] started")' C-m
    sleep 1
    # Start autosave if not running
    tmux send-keys -t "${SESSION}:0" \
        "bash ${KIRO_TOOLS}/nation-autosave.sh status 2>/dev/null | grep -q RUNNING || bash ${KIRO_TOOLS}/nation-autosave.sh start 2>/dev/null" C-m
    # Start voice listener if enabled and not running
    tmux send-keys -t "${SESSION}:0" \
        "bash ${KIRO_TOOLS}/nation-config.sh get voice.enabled 2>/dev/null | grep -q true && (bash ${KIRO_TOOLS}/nation-voice.sh status 2>/dev/null | grep -q RUNNING || bash ${KIRO_TOOLS}/nation-voice.sh listen 2>/dev/null)" C-m
    # Log ready
    tmux send-keys -t "${SESSION}:0" \
        "echo '[nation] services ready' | tee -a $PERSIST_LOG" C-m
}

# ── Create a fresh persistent session ────────────────────────────────────
create_session() {
    log "Creating new tmux session: $SESSION"

    # Window 0: background services (hidden)
    tmux new-session -d -s "$SESSION" -n "services" -x 220 -y 50

    # Window 1: main papy shell (this is what you interact with)
    tmux new-window -t "${SESSION}" -n "papy"

    # Window 2: logs tail
    tmux new-window -t "${SESSION}" -n "logs"
    tmux send-keys -t "${SESSION}:logs" "tail -f $AGENT_LOG" C-m

    # Start background services in window 0
    start_services

    # In window 1, show the welcome banner + kiro shell
    tmux send-keys -t "${SESSION}:papy" \
        "source /root/.bashrc 2>/dev/null; bash ${KIRO_TOOLS}/nation-banner.sh 2>/dev/null; echo ''; echo '  Type: papy help  for commands'; echo '  Type: kiro       to chat with AI'; echo ''" C-m

    # Select the main papy window for when user attaches
    tmux select-window -t "${SESSION}:papy"

    log "Session '$SESSION' created with windows: services | papy | logs"
}

# ── Commands ─────────────────────────────────────────────────────────────
case "$CMD" in

start)
    if session_alive; then
        log "Session '$SESSION' already running — attaching"
        exec tmux attach-session -t "$SESSION"
    else
        create_session
        # Ensure services are up even if session was just created
        sleep 1
        log "Session ready. Attaching..."
        exec tmux attach-session -t "$SESSION"
    fi
    ;;

attach)
    if session_alive; then
        exec tmux attach-session -t "$SESSION"
    else
        echo "No session found. Starting one..."
        create_session
        sleep 1
        exec tmux attach-session -t "$SESSION"
    fi
    ;;

detach)
    if session_alive; then
        tmux detach-client -s "$SESSION" 2>/dev/null || true
        echo "Detached from '$SESSION'. Session still running in background."
    else
        echo "No active session to detach from."
    fi
    ;;

status)
    echo "=== NATION AGENT Persistent Session ==="
    if session_alive; then
        echo "  Session : $SESSION [RUNNING]"
        tmux list-windows -t "$SESSION" 2>/dev/null | while read line; do
            echo "  Window  : $line"
        done
        echo ""
        # Check background services
        pgrep -x ollama >/dev/null && echo "  Ollama  : RUNNING" || echo "  Ollama  : stopped"
        bash "${KIRO_TOOLS}/nation-autosave.sh" status 2>/dev/null | grep -q RUNNING \
            && echo "  AutoSave: RUNNING" || echo "  AutoSave: stopped"
        bash "${KIRO_TOOLS}/nation-voice.sh" status 2>/dev/null | grep -q RUNNING \
            && echo "  Voice   : RUNNING" || echo "  Voice   : stopped"
    else
        echo "  Session : $SESSION [NOT RUNNING]"
        echo ""
        echo "  Start with: papy session start"
    fi
    echo "======================================="
    ;;

stop)
    if session_alive; then
        log "Stopping session '$SESSION'"
        # Gracefully stop services first
        bash "${KIRO_TOOLS}/nation-autosave.sh" stop 2>/dev/null || true
        bash "${KIRO_TOOLS}/nation-voice.sh" stop 2>/dev/null || true
        tmux kill-session -t "$SESSION"
        log "Session stopped."
        echo "NATION AGENT session stopped."
    else
        echo "No running session found."
    fi
    ;;

restart)
    "$0" stop 2>/dev/null || true
    sleep 1
    "$0" start
    ;;

bg|background)
    # Start session detached (no attach) — used by boot script
    if session_alive; then
        log "Session '$SESSION' already running in background"
        # Ensure services are up
        start_services
    else
        create_session
        # Detach immediately — running in background
        tmux detach-client -s "$SESSION" 2>/dev/null || true
        log "Session '$SESSION' started in background (no attach)"
        echo "NATION AGENT running in background. Run: papy session attach"
    fi
    ;;

logs)
    if [ -f "$AGENT_LOG" ]; then
        tail -50 "$AGENT_LOG"
    else
        echo "No logs found at $AGENT_LOG"
    fi
    ;;

*)
    echo "Usage: nation-persist.sh <command>"
    echo "Commands: start | attach | detach | status | stop | restart | bg | logs"
    ;;
esac
