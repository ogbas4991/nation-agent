#!/bin/bash
# NATION AGENT — Banner with commands cheatsheet and tmux shortcuts
# Usage: nation-banner.sh [minimal|full|splash]
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

MODE="${1:-full}"
VERSION="3.0.0"
COLS=$(tput cols 2>/dev/null || echo 80)

# ── Colors ────────────────────────────────────────────────────────────────
if [ "${NATION_COLOR:-0}" = "1" ] || [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    R='\033[0m'
    G1='\033[38;5;214m'; G2='\033[38;5;220m'; G3='\033[38;5;226m'
    C1='\033[38;5;51m';  C2='\033[38;5;45m'
    W='\033[1;37m';      D='\033[38;5;244m'
    GR='\033[38;5;82m';  YL='\033[38;5;226m'
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot) PC='\033[38;5;82m'  ;;
        linux|debian)        PC='\033[38;5;33m'  ;;
        macos)               PC='\033[38;5;208m' ;;
        *)                   PC='\033[38;5;255m' ;;
    esac
else
    R=''; G1=''; G2=''; G3=''; C1=''; C2=''; W=''; D=''; GR=''; YL=''; PC=''
fi

hline() {
    local char="${1:-─}"
    printf "${D}"; printf "%${COLS}s" | tr ' ' "$char"; printf "${R}\n"
}

center() {
    local text="$1"
    local clean; clean=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#clean}
    local pad=$(( (COLS - len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "%${pad}s"; echo -e "$text"
}

# ── Minimal ───────────────────────────────────────────────────────────────
show_minimal() {
    echo -e "${G1}[NATION AGENT${R} ${D}v${VERSION}${R}${G1}]${R} ${PC}${NATION_PLATFORM}${R} ${D}·${R} ${W}$(date '+%H:%M:%S')${R}"
}

# ── Logo (shared) ─────────────────────────────────────────────────────────
show_logo() {
    echo ""
    echo -e "${G1}  ███╗   ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗  ${C1}█████╗  ██████╗ ███████╗███╗   ██╗████████╗${R}"
    echo -e "${G2}  ████╗  ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║  ${C2}██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝${R}"
    echo -e "${G3}  ██╔██╗ ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║  ${C1}███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║${R}"
    echo -e "${G2}  ██║╚██╗██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║  ${C2}██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║${R}"
    echo -e "${G1}  ██║ ╚████║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║  ${C1}██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║${R}"
    echo -e "${D}  ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝ v${VERSION}${R}"
    echo ""
}

# ── Status line ───────────────────────────────────────────────────────────
show_status() {
    local MEM_COUNT TOOL_COUNT SKILL_COUNT
    MEM_COUNT=$(python3 -c "import sqlite3; c=sqlite3.connect('${NATION_DIR:-$HOME/.kiro}/memory/memory.db'); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])" 2>/dev/null || echo "?")
    TOOL_COUNT=$(ls "${NATION_TOOLS:-$HOME/.kiro/tools}"/nation-*.sh 2>/dev/null | wc -l | tr -d ' ')
    SKILL_COUNT=$(find "${NATION_SKILLS:-$HOME/.kiro/skills}" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${PC}Platform${R}:${W} ${NATION_PLATFORM}${R}  ${PC}Tools${R}:${W} ${TOOL_COUNT}${R}  ${PC}Skills${R}:${W} ${SKILL_COUNT}${R}  ${PC}Memories${R}:${W} ${MEM_COUNT}${R}  ${PC}$(date '+%a %H:%M')${R}"
}

# ── Commands cheatsheet ───────────────────────────────────────────────────
show_cheatsheet() {
    # Two-column layout — left = papy commands, right = tmux shortcuts
    echo ""
    echo -e "  ${G1}┌─ COMMANDS ─────────────────────────────────────┐  ┌─ TMUX ─────────────────────────────────┐${R}"

    local cmds=(
        "papy                  Launch agent"
        "papy tui              TUI navigation"
        "papy web [port]       Web dashboard"
        "papy status           System status"
        "papy health           Health check"
        "papy session attach   Rejoin session"
        "papy session detach   Keep running"
        "papy ollama [cmd]     Ollama models"
        "papy voice [cmd]      Voice listener"
        "papy speech [cmd]     Text-to-speech"
        "papy config [cmd]     Agent config"
        "papy device [cmd]     Device control"
        "papy clawhub search Q Search skills"
        "papy clawhub install S Install skill"
        "papy appdeploy deploy D Deploy app"
        "papy appdeploy list   Live apps"
        "papy skills [cmd]     Skill registry"
        "papy memory [cmd]     Memory"
        "papy github [cmd]     GitHub"
        "papy apk [cmd]        APK build/deploy"
        "papy msg [cmd]        Telegram/WA"
        "papy suggest          AI suggestions"
        "papy heal [cmd]       Self-heal"
        "papy update           Update agent"
    )

    local tmux=(
        "Ctrl+B  D    Detach (keeps running)"
        "Ctrl+B  0    Window: services"
        "Ctrl+B  1    Window: papy shell"
        "Ctrl+B  2    Window: logs"
        "Ctrl+B  c    New window"
        "Ctrl+B  ,    Rename window"
        "Ctrl+B  %    Split vertical"
        'Ctrl+B  "    Split horizontal'
        "Ctrl+B  →←   Move between panes"
        "Ctrl+B  [    Scroll mode (q=exit)"
        "Ctrl+B  z    Zoom pane"
        "Ctrl+B  &    Kill window"
        "Ctrl+B  ?    All shortcuts"
    )

    local max=${#cmds[@]}
    [ ${#tmux[@]} -gt $max ] && max=${#tmux[@]}

    for i in $(seq 0 $((max - 1))); do
        local left="${cmds[$i]:-}"
        local right="${tmux[$i]:-}"
        # Left column: 50 chars, right: 42 chars
        if [ -n "$left" ]; then
            local cmd_part key_part
            cmd_part=$(echo "$left" | cut -c1-22)
            key_part=$(echo "$left" | cut -c23-)
            printf "  ${G1}│${R} ${C1}%-22s${R}${D}%-28s${R}" "$cmd_part" "$key_part"
        else
            printf "  ${G1}│${R} %-50s" " "
        fi
        if [ -n "$right" ]; then
            local rkey rdesc
            rkey=$(echo "$right" | awk '{print $1" "$2" "$3}')
            rdesc=$(echo "$right" | cut -d' ' -f4-)
            printf "  ${G1}│${R} ${YL}%-14s${R}${D}%s${R}\n" "$rkey" "$rdesc"
        else
            printf "  ${G1}│${R}\n"
        fi
    done

    echo -e "  ${G1}└────────────────────────────────────────────────┘  └────────────────────────────────────────┘${R}"
}

# ── Full mode ─────────────────────────────────────────────────────────────
show_full() {
    show_logo
    hline "─"
    show_status
    hline "─"
    show_cheatsheet
    echo ""
    hline "─"
    echo -e "  ${D}Wake word: ${W}hey papy${D} · Session: ${W}papy session attach${D} · Docs: ${W}papy help${R}"
    hline "─"
    echo ""
}

# ── Splash mode ───────────────────────────────────────────────────────────
show_splash() {
    clear
    show_logo
    hline "═"
    center "${W}Self-Healing · Persistent Memory · MCP Bridge · ClawHub Skills${R}"
    center "${D}v${VERSION} · Local-First AI Agent · $(uname -m)${R}"
    hline "═"
    echo ""
    center "${PC}Platform: ${NATION_PLATFORM:-unknown}${R}"
    center "${D}$(date '+%A, %B %d %Y  %H:%M:%S')${R}"
    echo ""
    hline "─"
    echo ""
    echo -e "  ${G1}Quick Start:${R}"
    echo -e "  ${C1}papy${R}                    Launch agent"
    echo -e "  ${C1}papy tui${R}                TUI interface"
    echo -e "  ${C1}papy clawhub browse${R}     Browse skills marketplace"
    echo -e "  ${C1}papy appdeploy deploy${R}   Deploy a web app"
    echo -e "  ${C1}papy session attach${R}     Rejoin running session"
    echo -e "  ${C1}papy help${R}               All commands"
    echo ""
    echo -e "  ${D}Tmux: ${W}Ctrl+B D${D} detach · ${W}Ctrl+B 1${D} papy · ${W}Ctrl+B [${D} scroll${R}"
    echo ""
    hline "─"
    echo ""
}

# ── Dispatch ──────────────────────────────────────────────────────────────
case "$MODE" in
    splash)  show_splash ;;
    full)    show_full   ;;
    minimal) show_minimal ;;
    *)       show_full   ;;
esac
