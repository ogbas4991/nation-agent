#!/bin/bash
# NATION AGENT — Auto-Save System
# Continuously saves context, memory, session state, and workspace snapshots.
# Usage: nation-autosave.sh [start|stop|status|save|restore [id]]
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-save}"
SAVE_DIR="${NATION_DIR:-$HOME/.kiro}/autosave"
MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
PID_FILE="${NATION_DIR:-$HOME/.kiro}/autosave.pid"
INTERVAL="${AUTOSAVE_INTERVAL:-60}"  # seconds between saves
mkdir -p "$SAVE_DIR" "$(dirname "$LOG")"

TS() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(TS)] [AUTOSAVE] $*" >> "$LOG" 2>/dev/null || true; }

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# ── Perform one save cycle ────────────────────────────────────────────────
do_save() {
    local SLOT="${1:-current}"
    local SLOT_DIR="$SAVE_DIR/$SLOT"
    mkdir -p "$SLOT_DIR"
    local TS_NOW
    TS_NOW=$(date '+%Y%m%d_%H%M%S')

    # 1. Save memory DB snapshot
    if [ -f "${NATION_DIR:-$HOME/.kiro}/memory/memory.db" ]; then
        cp "${NATION_DIR:-$HOME/.kiro}/memory/memory.db" \
           "$SLOT_DIR/memory_${TS_NOW}.db" 2>/dev/null || true
        # Keep only last 5 DB snapshots
        ls -t "$SLOT_DIR"/memory_*.db 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi

    # 2. Save git state (if in a repo)
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        {
            echo "=== Git State: $(TS) ==="
            echo "Branch: $(git branch --show-current 2>/dev/null)"
            echo "Status:"
            git status --short 2>/dev/null
            echo "Last commit:"
            git log --oneline -1 2>/dev/null
        } > "$SLOT_DIR/git_state.txt"

        # Auto-stash uncommitted work (non-destructive)
        CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
        if [ "$CHANGES" -gt 0 ]; then
            git stash push -m "autosave_$(date +%s)" --include-untracked \
                &>/dev/null 2>&1 || true
            log "stashed $CHANGES changes"
        fi
    fi

    # 3. Save session context to memory
    if [ -x "$MEMORY" ]; then
        "$MEMORY" remember event "autosave.$(date +%s)" \
            "AutoSave at $(TS): cwd=$PWD" 2>/dev/null || true
        # Export memory to JSON backup
        "$MEMORY" export "$SLOT_DIR/memory_export.json" 2>/dev/null || true
    fi

    # 4. Save environment snapshot
    {
        echo "Timestamp : $(TS)"
        echo "CWD       : $PWD"
        echo "Platform  : ${NATION_PLATFORM:-?}"
        echo "Session   : ${KIRO_SESSION_ID:-?}"
        echo "Git branch: $(git branch --show-current 2>/dev/null || echo N/A)"
        echo "Ollama    : $(curl -sf http://localhost:$(cat ${NATION_DIR:-$HOME/.kiro}/ollama.port 2>/dev/null || echo 11434)/api/tags >/dev/null 2>&1 && echo running || echo stopped)"
    } > "$SLOT_DIR/session_state.txt"

    # 5. Save agent config snapshot
    cp "${NATION_DIR:-$HOME/.kiro}/agents/nation-agent.json" \
       "$SLOT_DIR/agent_config.json" 2>/dev/null || true

    log "saved slot=$SLOT dir=$SLOT_DIR"
    echo "$(TS) — AutoSaved to $SLOT_DIR"
}

# ── Background loop ───────────────────────────────────────────────────────
autosave_loop() {
    log "AutoSave loop started (PID $$, interval=${INTERVAL}s)"
    echo $$ > "$PID_FILE"
    local cycle=0
    while true; do
        cycle=$((cycle + 1))
        do_save "current"
        # Hourly named snapshot
        if [ $((cycle % $((3600 / INTERVAL)))) -eq 0 ]; then
            do_save "hourly_$(date '+%Y%m%d_%H')"
            # Keep only last 24 hourly snapshots
            ls -dt "$SAVE_DIR"/hourly_* 2>/dev/null | tail -n +25 | xargs rm -rf 2>/dev/null || true
        fi
        sleep "$INTERVAL"
    done
}

case "$CMD" in

  start)
    if is_running; then
        echo "AutoSave already running (PID $(cat "$PID_FILE"))"
    else
        log "starting autosave"
        nohup bash -c "
$(declare -f do_save autosave_loop log TS is_running)
SAVE_DIR='$SAVE_DIR'
MEMORY='$MEMORY'
LOG='$LOG'
PID_FILE='$PID_FILE'
INTERVAL='$INTERVAL'
NATION_DIR='${NATION_DIR:-$HOME/.kiro}'
NATION_PLATFORM='${NATION_PLATFORM:-linux}'
autosave_loop" >> "${NATION_LOGS:-$HOME/.kiro/logs}/nation-autosave.log" 2>&1 &
        sleep 1
        is_running && echo "AutoSave started (interval: ${INTERVAL}s)" || echo "Start failed"
    fi
    ;;

  stop)
    if is_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null && rm -f "$PID_FILE"
        echo "AutoSave stopped."
    else
        echo "AutoSave not running."
    fi
    ;;

  status)
    if is_running; then
        echo "AutoSave: RUNNING (PID $(cat "$PID_FILE"), interval=${INTERVAL}s)"
    else
        echo "AutoSave: STOPPED"
    fi
    echo "Save dir: $SAVE_DIR"
    [ -f "$SAVE_DIR/current/session_state.txt" ] && \
        echo "Last save:" && cat "$SAVE_DIR/current/session_state.txt"
    ;;

  save)
    SLOT="${2:-current}"
    do_save "$SLOT"
    ;;

  restore)
    SLOT="${2:-current}"
    SLOT_DIR="$SAVE_DIR/$SLOT"
    [ -d "$SLOT_DIR" ] || { echo "No save found: $SLOT"; exit 1; }
    echo "Restoring from: $SLOT_DIR"
    # Restore memory
    LATEST_DB=$(ls -t "$SLOT_DIR"/memory_*.db 2>/dev/null | head -1)
    if [ -n "$LATEST_DB" ]; then
        cp "$LATEST_DB" "${NATION_DIR:-$HOME/.kiro}/memory/memory.db"
        echo "  Memory restored from: $LATEST_DB"
    fi
    cat "$SLOT_DIR/session_state.txt" 2>/dev/null && echo "State restored."
    ;;

  list)
    echo "=== AutoSave Slots ==="
    for d in "$SAVE_DIR"/*/; do
        [ -d "$d" ] || continue
        SLOT=$(basename "$d")
        MTIME=$(stat -c '%y' "$d" 2>/dev/null | cut -d. -f1)
        echo "  $SLOT — $MTIME"
    done
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Usage: nation-autosave.sh [start|stop|status|save|restore|list]" ;;
esac
