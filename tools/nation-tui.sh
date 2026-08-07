#!/bin/bash
# NATION AGENT — Terminal UI (TUI)
# Full interactive terminal dashboard using dialog or pure bash fallback.
# Usage: nation-tui.sh

source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
VERSION="3.0.0"
TITLE="NATION AGENT v${VERSION}"

# ── Dialog availability ───────────────────────────────────────────────────
USE_DIALOG=0
command -v dialog &>/dev/null && USE_DIALOG=1

# ── Helpers ───────────────────────────────────────────────────────────────
tui_result() { cat /tmp/nation-tui-result 2>/dev/null; rm -f /tmp/nation-tui-result; }
tui_input()  {
    if [ $USE_DIALOG -eq 1 ]; then
        dialog --inputbox "$1" 10 60 "${2:-}" 2>/tmp/nation-tui-result
        return $?
    else
        echo -n "$1 " >&2
        read -r line; echo "$line" > /tmp/nation-tui-result
    fi
}
tui_msg() {
    if [ $USE_DIALOG -eq 1 ]; then
        dialog --msgbox "$1" 12 60
    else
        echo -e "\n$1\n"
        read -rp "Press Enter..." _
    fi
}
tui_confirm() {
    if [ $USE_DIALOG -eq 1 ]; then
        dialog --yesno "$1" 8 50
        return $?
    else
        echo -n "$1 [y/N] " >&2
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]]
    fi
}

# ── Status bar content ────────────────────────────────────────────────────
get_status() {
    MEM=$(python3 -c "import sqlite3; c=sqlite3.connect('${HOME}/.kiro/memory/memory.db'); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])" 2>/dev/null || echo "?")
    TOOLS_COUNT=$(ls "${TOOLS}"/nation-*.sh 2>/dev/null | wc -l | tr -d ' ')
    SKILLS_COUNT=$(find "${HOME}/.kiro/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    echo "Platform: ${NATION_PLATFORM:-?}  |  Tools: ${TOOLS_COUNT}  |  Skills: ${SKILLS_COUNT}  |  Memories: ${MEM}"
}

# ── Pure bash fallback menu ───────────────────────────────────────────────
bash_menu() {
    while true; do
        clear
        "$TOOLS/nation-banner.sh" full 2>/dev/null || echo "=== NATION AGENT ==="
        echo ""
        STATUS=$(get_status)
        echo "  $STATUS"
        echo ""
        echo "  ┌─────────────────────────────────────────┐"
        echo "  │          NATION AGENT TUI Menu          │"
        echo "  ├─────────────────────────────────────────┤"
        echo "  │  1) Launch Agent (kiro-cli)             │"
        echo "  │  2) Health Check                        │"
        echo "  │  3) Memory Browser                      │"
        echo "  │  4) Skills Manager                      │"
        echo "  │  5) File Explorer                       │"
        echo "  │  6) Git Dashboard                       │"
        echo "  │  7) Run Python Code                     │"
        echo "  │  8) HTTP Request                        │"
        echo "  │  9) APK Tools                           │"
        echo "  │  a) ADB / Device                        │"
        echo "  │  w) Start Web Dashboard                 │"
        echo "  │  l) View Logs                           │"
        echo "  │  u) Update NATION AGENT                 │"
        echo "  │  q) Quit                                │"
        echo "  └─────────────────────────────────────────┘"
        echo ""
        read -rp "  Choose: " CHOICE
        case "$CHOICE" in
          1) bash_launch_agent ;;
          2) clear; "$TOOLS/nation-heal.sh" check; read -rp "Press Enter..." _ ;;
          3) bash_memory_menu ;;
          4) bash_skills_menu ;;
          5) bash_file_menu ;;
          6) bash_git_menu ;;
          7) bash_python_menu ;;
          8) bash_http_menu ;;
          9) bash_apk_menu ;;
          a|A) clear; "$TOOLS/nation-adb.sh" devices 2>&1; read -rp "Press Enter..." _ ;;
          w|W) "$TOOLS/nation-web.sh" & echo "Web dashboard started. PID: $!"; read -rp "Press Enter..." _ ;;
          l|L) clear; tail -50 "${HOME}/.kiro/logs/nation-agent.log" 2>/dev/null || echo "No logs"; read -rp "Press Enter..." _ ;;
          u|U) curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh | bash; read -rp "Press Enter..." _ ;;
          q|Q) echo "Goodbye."; exit 0 ;;
          *) echo "Invalid choice." ;;
        esac
    done
}

bash_launch_agent() {
    if command -v kiro-cli &>/dev/null; then
        kiro-cli chat --agent nation-agent
    else
        echo "kiro-cli not found. Install from: https://kiro.dev"
        read -rp "Press Enter..." _
    fi
}

bash_memory_menu() {
    while true; do
        clear
        echo "=== Memory Browser ==="
        echo "  1) Show recent memories"
        echo "  2) Search memories"
        echo "  3) Show summary"
        echo "  4) Remember something"
        echo "  5) Export memories"
        echo "  b) Back"
        read -rp "  Choose: " C
        case "$C" in
          1) clear; "$TOOLS/nation-memory.sh" recent; read -rp "Press Enter..." _ ;;
          2) read -rp "Search query: " Q; clear; "$TOOLS/nation-memory.sh" search "$Q"; read -rp "Press Enter..." _ ;;
          3) clear; "$TOOLS/nation-memory.sh" summary; read -rp "Press Enter..." _ ;;
          4) read -rp "Type (fact/preference/project): " T
             read -rp "Key: " K
             read -rp "Value: " V
             "$TOOLS/nation-memory.sh" remember "$T" "$K" "$V"
             read -rp "Press Enter..." _ ;;
          5) OUT="${HOME}/.kiro/memory/export_$(date +%Y%m%d).json"
             "$TOOLS/nation-memory.sh" export "$OUT"
             echo "Exported to: $OUT"
             read -rp "Press Enter..." _ ;;
          b|B) return ;;
        esac
    done
}

bash_skills_menu() {
    while true; do
        clear
        echo "=== Skills Manager ==="
        echo "  1) List skills"
        echo "  2) Scan for new skills"
        echo "  3) Add skill (URL or file)"
        echo "  4) Create new skill"
        echo "  5) Update all remote skills"
        echo "  b) Back"
        read -rp "  Choose: " C
        case "$C" in
          1) clear; "$TOOLS/nation-skills.sh" list; read -rp "Press Enter..." _ ;;
          2) clear; "$TOOLS/nation-skills.sh" scan; read -rp "Press Enter..." _ ;;
          3) read -rp "Name: " N; read -rp "URL or path: " S
             "$TOOLS/nation-skills.sh" add "$N" "$S"
             read -rp "Press Enter..." _ ;;
          4) read -rp "Name: " N; read -rp "Description: " D
             "$TOOLS/nation-skills.sh" create "$N" "$D"
             read -rp "Press Enter..." _ ;;
          5) clear; "$TOOLS/nation-skills.sh" update-all; read -rp "Press Enter..." _ ;;
          b|B) return ;;
        esac
    done
}

bash_file_menu() {
    DIR="$PWD"
    while true; do
        clear
        echo "=== File Explorer: $DIR ==="
        "$TOOLS/nation-file.sh" list "$DIR" 2>/dev/null | head -30
        echo ""
        echo "  1) Change directory   2) Read file   3) Create file"
        echo "  4) Delete file        5) Find files  6) Search text"
        echo "  b) Back"
        read -rp "  Choose: " C
        case "$C" in
          1) read -rp "Directory: " D; [ -d "$D" ] && DIR="$D" || echo "Not found: $D"; sleep 1 ;;
          2) read -rp "File path: " F; clear; "$TOOLS/nation-file.sh" read "$F" 2>/dev/null | head -100; read -rp "Press Enter..." _ ;;
          3) read -rp "File path: " F; read -rp "Content: " CONTENT; "$TOOLS/nation-file.sh" write "$F" "$CONTENT"; read -rp "Press Enter..." _ ;;
          4) read -rp "File path: " F; read -rp "Type --confirm to delete: " CONF; [ "$CONF" = "--confirm" ] && "$TOOLS/nation-file.sh" delete "$F" --confirm; read -rp "Press Enter..." _ ;;
          5) read -rp "Pattern: " P; clear; "$TOOLS/nation-file.sh" find "$DIR" "$P"; read -rp "Press Enter..." _ ;;
          6) read -rp "Pattern: " P; clear; "$TOOLS/nation-search.sh" text "$P" "$DIR" 2>/dev/null | head -30; read -rp "Press Enter..." _ ;;
          b|B) return ;;
        esac
    done
}

bash_git_menu() {
    while true; do
        clear
        echo "=== Git Dashboard: $PWD ==="
        "$TOOLS/nation-git.sh" status 2>/dev/null || echo "(not a git repo)"
        echo ""
        echo "  1) Log   2) Diff   3) Add all   4) Commit   5) Push   b) Back"
        read -rp "  Choose: " C
        case "$C" in
          1) clear; "$TOOLS/nation-git.sh" log 15; read -rp "Press Enter..." _ ;;
          2) clear; "$TOOLS/nation-git.sh" diff; read -rp "Press Enter..." _ ;;
          3) "$TOOLS/nation-git.sh" add .; read -rp "Press Enter..." _ ;;
          4) read -rp "Commit message: " M; "$TOOLS/nation-git.sh" commit "$M"; read -rp "Press Enter..." _ ;;
          5) "$TOOLS/nation-git.sh" push; read -rp "Press Enter..." _ ;;
          b|B) return ;;
        esac
    done
}

bash_python_menu() {
    clear
    echo "=== Python Execution ==="
    echo "  1) Run inline code   2) Run file   3) Install package   b) Back"
    read -rp "  Choose: " C
    case "$C" in
      1) read -rp "Python code: " CODE; clear; "$TOOLS/nation-python.sh" exec "$CODE"; read -rp "Press Enter..." _ ;;
      2) read -rp "File path: " F; clear; "$TOOLS/nation-python.sh" run "$F"; read -rp "Press Enter..." _ ;;
      3) read -rp "Package name: " P; "$TOOLS/nation-python.sh" pip install "$P"; read -rp "Press Enter..." _ ;;
      b|B) return ;;
    esac
}

bash_http_menu() {
    clear
    echo "=== HTTP Request ==="
    echo "  1) GET   2) POST   3) Check status   b) Back"
    read -rp "  Choose: " C
    case "$C" in
      1) read -rp "URL: " U; clear; "$TOOLS/nation-http.sh" get "$U"; read -rp "Press Enter..." _ ;;
      2) read -rp "URL: " U; read -rp "JSON body: " B; clear; "$TOOLS/nation-http.sh" post "$U" "$B"; read -rp "Press Enter..." _ ;;
      3) read -rp "URL: " U; "$TOOLS/nation-browser.sh" status "$U"; read -rp "Press Enter..." _ ;;
      b|B) return ;;
    esac
}

bash_apk_menu() {
    clear
    echo "=== APK Tools ==="
    echo "  1) New project   2) Build   3) Host/serve APK   4) Deploy via ADB   5) Check deps   b) Back"
    read -rp "  Choose: " C
    case "$C" in
      1) read -rp "App name: " N; "$TOOLS/nation-apk.sh" new "$N"; read -rp "Press Enter..." _ ;;
      2) read -rp "Project dir (Enter for .): " D; D="${D:-.}"; "$TOOLS/nation-apk.sh" build "$D"; read -rp "Press Enter..." _ ;;
      3) read -rp "APK path or dir: " P; read -rp "Port [8080]: " PORT; PORT="${PORT:-8080}"; "$TOOLS/nation-apk.sh" host "$P" "$PORT" & echo "Hosting at :$PORT (PID $!)"; read -rp "Press Enter..." _ ;;
      4) read -rp "APK path: " P; "$TOOLS/nation-apk.sh" deploy "$P"; read -rp "Press Enter..." _ ;;
      5) "$TOOLS/nation-apk.sh" deps; read -rp "Press Enter..." _ ;;
      b|B) return ;;
    esac
}

# ── Dialog-based menu (richer UI) ─────────────────────────────────────────
dialog_menu() {
    while true; do
        CHOICE=$(dialog --clear --backtitle "$TITLE" \
            --title "Main Menu" \
            --menu "$(get_status)" 22 65 14 \
            "1" "Launch Agent (kiro-cli)" \
            "2" "Health Check" \
            "3" "Memory Browser" \
            "4" "Skills Manager" \
            "5" "File Explorer" \
            "6" "Git Dashboard" \
            "7" "Run Python Code" \
            "8" "HTTP Request" \
            "9" "APK Tools" \
            "a" "ADB / Android Device" \
            "w" "Start Web Dashboard" \
            "l" "View Logs" \
            "u" "Update NATION AGENT" \
            "q" "Quit" \
            2>&1 >/dev/tty) || break

        clear
        case "$CHOICE" in
          1) bash_launch_agent ;;
          2) "$TOOLS/nation-heal.sh" check; read -rp "Press Enter..." _ ;;
          3) bash_memory_menu ;;
          4) bash_skills_menu ;;
          5) bash_file_menu ;;
          6) bash_git_menu ;;
          7) bash_python_menu ;;
          8) bash_http_menu ;;
          9) bash_apk_menu ;;
          a) "$TOOLS/nation-adb.sh" devices 2>&1; read -rp "Press Enter..." _ ;;
          w) "$TOOLS/nation-web.sh" & echo "Web started. PID: $!"; read -rp "Press Enter..." _ ;;
          l) tail -50 "${HOME}/.kiro/logs/nation-agent.log" 2>/dev/null; read -rp "Press Enter..." _ ;;
          u) curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh | bash; read -rp "Press Enter..." _ ;;
          q) break ;;
        esac
    done
    clear
}

# ── Entry point ───────────────────────────────────────────────────────────
if [ $USE_DIALOG -eq 1 ]; then
    dialog_menu
else
    bash_menu
fi
