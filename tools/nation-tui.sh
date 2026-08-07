#!/bin/bash
# NATION AGENT — TUI v4 with keyboard navigation
# Arrow keys / vim keys (j/k), Enter to select, q to quit, ? for help
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
VERSION="4.0.0"

# ── Colors ────────────────────────────────────────────────────────────────
if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    R=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m'
    GOLD=$'\033[38;5;214m' CYAN=$'\033[38;5;51m' GREEN=$'\033[38;5;82m'
    RED=$'\033[38;5;196m'  BLUE=$'\033[38;5;33m'  GRAY=$'\033[38;5;244m'
    SEL_BG=$'\033[48;5;235m' SEL_FG=$'\033[38;5;214m'
else
    R='' BOLD='' DIM='' GOLD='' CYAN='' GREEN='' RED='' BLUE='' GRAY=''
    SEL_BG='' SEL_FG=''
fi

# ── Terminal setup ────────────────────────────────────────────────────────
ROWS=$(tput lines 2>/dev/null || echo 24)
COLS=$(tput cols  2>/dev/null || echo 80)

hide_cursor() { tput civis 2>/dev/null || true; }
show_cursor() { tput cnorm 2>/dev/null || true; }
clear_screen() { tput clear 2>/dev/null || clear; }
move() { tput cup "$1" "$2" 2>/dev/null || true; }  # row col
save_term() { stty -echo -icanon min 1 time 0 2>/dev/null || true; }
restore_term() { stty sane 2>/dev/null || true; }

cleanup() { restore_term; show_cursor; tput rmcup 2>/dev/null || true; echo ""; }
trap cleanup EXIT INT TERM

# ── Read a single keypress ────────────────────────────────────────────────
read_key() {
    local key
    IFS= read -r -s -n1 key 2>/dev/null || true
    # Handle escape sequences (arrow keys)
    if [ "$key" = $'\x1b' ]; then
        local seq
        IFS= read -r -s -n2 seq -t 0.1 2>/dev/null || true
        case "$seq" in
            '[A') key="UP"   ;;
            '[B') key="DOWN" ;;
            '[C') key="RIGHT";;
            '[D') key="LEFT" ;;
            '[5') key="PGUP"; IFS= read -r -s -n1 -t 0.1 2>/dev/null || true ;;
            '[6') key="PGDN"; IFS= read -r -s -n1 -t 0.1 2>/dev/null || true ;;
            *) key="ESC" ;;
        esac
    fi
    echo "$key"
}

# ── Menu data ─────────────────────────────────────────────────────────────
MENU_ITEMS=(
    "🚀  Launch Agent (kiro-cli)"
    "🤖  Ollama Status / Models"
    "❤️   Health Check"
    "🧠  Memory Browser"
    "📚  Skills Manager"
    "💡  Follow-up Suggestions"
    "📁  File Explorer"
    "🌿  Git Dashboard"
    "🐍  Python Runner"
    "🌐  HTTP Request"
    "📱  APK Tools"
    "🔌  ADB / Android"
    "🔐  GitHub Auth"
    "🛡️   Shizuku / Wireless ADB"
    "🤖  Auto Agent (24/7)"
    "🌍  Start Web Dashboard"
    "📋  View Logs"
    "⚙️   Settings"
    "🔄  Update NATION AGENT"
    "❓  Help"
    "🚪  Quit"
)

MENU_ACTIONS=(
    "launch_agent"
    "ollama_menu"
    "run_health"
    "memory_menu"
    "skills_menu"
    "run_suggestions"
    "file_menu"
    "git_menu"
    "python_menu"
    "http_menu"
    "apk_menu"
    "adb_menu"
    "github_menu"
    "shizuku_menu"
    "auto_menu"
    "start_web"
    "view_logs"
    "settings_menu"
    "do_update"
    "show_help"
    "do_quit"
)

TOTAL=${#MENU_ITEMS[@]}
SELECTED=0
PAGE_SIZE=$((ROWS - 12))
[ $PAGE_SIZE -lt 5 ] && PAGE_SIZE=5

# ── Status line ───────────────────────────────────────────────────────────
get_status_line() {
    local mem_count tools_count ollama_status
    mem_count=$(python3 -c "import sqlite3; c=sqlite3.connect('$HOME/.kiro/memory/memory.db'); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])" 2>/dev/null || echo "?")
    tools_count=$(ls "$TOOLS"/nation-*.sh 2>/dev/null | wc -l | tr -d ' ')
    if curl -sf "http://localhost:$(cat $HOME/.kiro/ollama.port 2>/dev/null || echo 11434)/api/tags" >/dev/null 2>&1; then
        ollama_status="${GREEN}●${R}"
    else
        ollama_status="${GRAY}●${R}"
    fi
    echo "Tools:${CYAN}${tools_count}${R} Mem:${CYAN}${mem_count}${R} Ollama:${ollama_status} Platform:${CYAN}${NATION_PLATFORM:-?}${R}"
}

# ── Draw the menu ─────────────────────────────────────────────────────────
draw_menu() {
    clear_screen
    hide_cursor

    # Header
    move 0 0
    echo -e "${GOLD}${BOLD}  ⚡ NATION AGENT v${VERSION}${R}  ${GRAY}$(date '+%H:%M:%S')${R}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 $COLS))${R}"
    echo -e "  $(get_status_line)"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 $COLS))${R}"
    echo -e "  ${GRAY}↑/k up  ↓/j down  Enter select  gg top  G bottom  q quit  ? help${R}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 $COLS))${R}"

    # Calculate visible window
    local page_start=$(( SELECTED / PAGE_SIZE * PAGE_SIZE ))
    local page_end=$(( page_start + PAGE_SIZE ))
    [ $page_end -gt $TOTAL ] && page_end=$TOTAL

    local row=7
    for ((i=page_start; i<page_end; i++)); do
        move $row 0
        if [ $i -eq $SELECTED ]; then
            printf "${SEL_BG}${SEL_FG}${BOLD}  ▶ %-$((COLS-4))s${R}" "${MENU_ITEMS[$i]}"
        else
            printf "    ${GRAY}%-$((COLS-4))s${R}" "${MENU_ITEMS[$i]}"
        fi
        row=$((row+1))
    done

    # Footer
    move $((ROWS-2)) 0
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 $COLS))${R}"
    move $((ROWS-1)) 0
    printf "${GRAY}Item $((SELECTED+1))/$TOTAL  Page $((SELECTED/PAGE_SIZE+1))/$((( TOTAL + PAGE_SIZE - 1 ) / PAGE_SIZE))${R}"
}

# ── Action handlers ───────────────────────────────────────────────────────
launch_agent() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    if command -v kiro-cli &>/dev/null; then
        kiro-cli chat --agent nation-agent
    else
        echo "kiro-cli not found."
        read -rp "Press Enter..." _
    fi
    tput smcup 2>/dev/null || true
}

run_pager() {
    local title="$1"; shift
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== $title ===${R}"
    "$@" 2>&1 | head -80
    echo ""
    read -rp "Press Enter to return..." _
    tput smcup 2>/dev/null || true
    save_term
}

run_input_action() {
    local prompt="$1"; local action="$2"
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== $prompt ===${R}"
    read -rp "> " INPUT
    if [ -n "$INPUT" ]; then
        eval "$action \"$INPUT\"" 2>&1
    fi
    echo ""
    read -rp "Press Enter to return..." _
    tput smcup 2>/dev/null || true
    save_term
}

ollama_menu()    { run_pager "Ollama" "$TOOLS/nation-ollama.sh" status; }
run_health()     { run_pager "Health Check" "$TOOLS/nation-heal.sh" check; }
run_suggestions(){ run_pager "Suggestions" "$TOOLS/nation-suggest.sh"; }
start_web()      {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    PORT=$("$TOOLS/papy" web --get-port 2>/dev/null || echo 7070)
    "$TOOLS/nation-web.sh" "$PORT" &
    echo "Web dashboard started: http://localhost:$PORT (PID $!)"
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}
view_logs()      { run_pager "Logs" tail -60 "$HOME/.kiro/logs/nation-agent.log"; }
do_update()      { run_pager "Update" curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh; }
do_quit()        { cleanup; exit 0; }

memory_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    while true; do
        echo -e "${GOLD}=== Memory Browser ===${R}"
        echo "  1) Recent   2) Search   3) Add   4) Summary   b) Back"
        read -rp "  > " C
        case "$C" in
          1) "$TOOLS/nation-memory.sh" recent 2>/dev/null | head -40 ;;
          2) read -rp "Query: " Q; "$TOOLS/nation-memory.sh" search "$Q" 2>/dev/null ;;
          3) read -rp "Type: " T; read -rp "Key: " K; read -rp "Value: " V
             "$TOOLS/nation-memory.sh" remember "$T" "$K" "$V" ;;
          4) "$TOOLS/nation-memory.sh" summary 2>/dev/null ;;
          b|B|q) break ;;
        esac
        echo ""
    done
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

skills_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== Skills ===${R}"
    "$TOOLS/nation-skills.sh" list 2>/dev/null
    echo ""; echo "  1) Scan   2) Add from URL   3) Create   b) Back"
    read -rp "  > " C
    case "$C" in
      1) "$TOOLS/nation-skills.sh" scan ;;
      2) read -rp "Name: " N; read -rp "URL: " U; "$TOOLS/nation-skills.sh" add "$N" "$U" ;;
      3) read -rp "Name: " N; read -rp "Desc: " D; "$TOOLS/nation-skills.sh" create "$N" "$D" ;;
    esac
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

file_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== File Explorer: $PWD ===${R}"
    ls -lah "$PWD" 2>/dev/null | head -30
    echo ""; echo "  Enter path to read (or blank to return):"
    read -rp "  > " F
    [ -n "$F" ] && [ -f "$F" ] && cat "$F" 2>/dev/null | head -60
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

git_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== Git Dashboard ===${R}"
    "$TOOLS/nation-git.sh" status 2>/dev/null || echo "(not a git repo)"
    echo ""; echo "  1) Log   2) Diff   3) Add all   4) Commit   5) Push   b) Back"
    read -rp "  > " C
    case "$C" in
      1) "$TOOLS/nation-git.sh" log 15 2>/dev/null ;;
      2) "$TOOLS/nation-git.sh" diff 2>/dev/null ;;
      3) "$TOOLS/nation-git.sh" add . 2>/dev/null ;;
      4) read -rp "Message: " M; "$TOOLS/nation-git.sh" commit "$M" 2>/dev/null ;;
      5) "$TOOLS/nation-git.sh" push 2>/dev/null ;;
    esac
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

python_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== Python ===${R}"
    echo "  1) Run code   2) Run file   3) Pip install   b) Back"
    read -rp "  > " C
    case "$C" in
      1) read -rp "Code: " CODE; python3 -c "$CODE" 2>&1 ;;
      2) read -rp "File: " F; python3 "$F" 2>&1 ;;
      3) read -rp "Package: " P; pip3 install "$P" 2>&1 ;;
    esac
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

http_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== HTTP ===${R}"
    echo "  1) GET   2) POST   3) Status check   b) Back"
    read -rp "  > " C
    case "$C" in
      1) read -rp "URL: " U; "$TOOLS/nation-http.sh" get "$U" 2>&1 | head -40 ;;
      2) read -rp "URL: " U; read -rp "Body JSON: " B; "$TOOLS/nation-http.sh" post "$U" "$B" 2>&1 | head -40 ;;
      3) read -rp "URL: " U; "$TOOLS/nation-browser.sh" status "$U" 2>&1 ;;
    esac
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

apk_menu()     { run_pager "APK Tools" "$TOOLS/nation-apk.sh" deps; }
adb_menu()     { run_pager "ADB Devices" "$TOOLS/nation-adb.sh" devices; }
github_menu()  { run_pager "GitHub" "$TOOLS/nation-github.sh" status 2>/dev/null || echo "Run: papy github login"; }
shizuku_menu() { run_pager "Shizuku" "$TOOLS/nation-shizuku.sh" status 2>/dev/null || echo "Shizuku not available"; }
auto_menu()    { run_pager "Auto Agent" "$TOOLS/nation-auto.sh" status 2>/dev/null; }

settings_menu() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    echo -e "${GOLD}=== Settings ===${R}"
    echo "  1) Set Ollama default model"
    echo "  2) Set GitHub token"
    echo "  3) View agent config"
    echo "  b) Back"
    read -rp "  > " C
    case "$C" in
      1) read -rp "Model (e.g. llama3.2): " M; "$TOOLS/nation-ollama.sh" set-default "$M" ;;
      2) read -rp "GitHub token (ghp_...): " T
         echo "export GITHUB_TOKEN=$T" >> "$HOME/.bashrc"
         "$TOOLS/nation-memory.sh" remember preference "github.token_set" "yes" 2>/dev/null || true
         echo "Token saved to ~/.bashrc" ;;
      3) cat "$HOME/.kiro/agents/nation-agent.json" 2>/dev/null | python3 -m json.tool | head -40 ;;
    esac
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

show_help() {
    restore_term; show_cursor; tput rmcup 2>/dev/null || true
    cat << 'HELP'
=== NATION AGENT TUI — Keyboard Navigation ===

Navigation:
  ↑ / k        Move up
  ↓ / j        Move down
  PgUp / u     Page up
  PgDn / d     Page down
  gg / Home    Jump to top
  G  / End     Jump to bottom
  Enter        Select item

General:
  q / Esc      Quit TUI
  ?            Show this help
  r            Refresh screen

Quick access (anywhere):
  papy tui     Open TUI
  papy         Launch full agent
  papy web     Web dashboard
  papy health  Health check
HELP
    read -rp "Press Enter..." _
    tput smcup 2>/dev/null || true
    save_term
}

# ── Main event loop ───────────────────────────────────────────────────────
tput smcup 2>/dev/null || true
save_term
PREV_G=0

while true; do
    draw_menu

    KEY=$(read_key)

    case "$KEY" in
        # Movement
        UP|k|K)
            SELECTED=$(( SELECTED > 0 ? SELECTED - 1 : TOTAL - 1 ))
            ;;
        DOWN|j|J)
            SELECTED=$(( SELECTED < TOTAL - 1 ? SELECTED + 1 : 0 ))
            ;;
        PGUP|u|U)
            SELECTED=$(( SELECTED - PAGE_SIZE > 0 ? SELECTED - PAGE_SIZE : 0 ))
            ;;
        PGDN|d|D)
            SELECTED=$(( SELECTED + PAGE_SIZE < TOTAL ? SELECTED + PAGE_SIZE : TOTAL - 1 ))
            ;;
        g)
            if [ $PREV_G -eq 1 ]; then SELECTED=0; PREV_G=0
            else PREV_G=1; fi
            continue
            ;;
        G)   SELECTED=$((TOTAL - 1)) ;;
        r|R) ;;  # just redraw
        # Select
        ""|$'\n'|$'\r')
            ACTION="${MENU_ACTIONS[$SELECTED]}"
            restore_term; show_cursor
            "$ACTION" 2>/dev/null || true
            save_term; hide_cursor
            ;;
        # Quit
        q|Q|ESC)
            cleanup; exit 0
            ;;
        "?")
            show_help
            ;;
    esac
    PREV_G=0
done
