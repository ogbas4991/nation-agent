#!/bin/bash
# NATION AGENT — Custom Banner
# Usage: nation-banner.sh [minimal|full|splash]
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

MODE="${1:-full}"
VERSION="3.0.0"
COLS=$(tput cols 2>/dev/null || echo 60)

# ── Color palette (256-color where available) ──────────────────────────────
if [ "${NATION_COLOR:-0}" = "1" ] || [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    R='\033[0m'
    # Gold/amber for logo
    G1='\033[38;5;214m'   # bright orange-gold
    G2='\033[38;5;220m'   # yellow-gold
    G3='\033[38;5;226m'   # bright yellow
    # Cyan for accents
    C1='\033[38;5;51m'    # bright cyan
    C2='\033[38;5;45m'    # medium cyan
    # White / gray
    W='\033[1;37m'
    D='\033[38;5;244m'    # dim gray
    # Platform colors
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot) PC='\033[38;5;82m'  ;;  # green
        linux|debian)        PC='\033[38;5;33m'  ;;  # blue
        macos)               PC='\033[38;5;208m' ;;  # orange
        *)                   PC='\033[38;5;255m' ;;
    esac
else
    R='' G1='' G2='' G3='' C1='' C2='' W='' D='' PC=''
fi

# ── Helpers ────────────────────────────────────────────────────────────────
center() {
    local text="$1"
    local clean
    # Strip ANSI codes to get real length
    clean=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#clean}
    local pad=$(( (COLS - len) / 2 ))
    [ $pad -lt 0 ] && pad=0
    printf "%${pad}s" ""
    echo -e "$text"
}

hline() {
    local char="${1:-─}"
    printf "${D}"
    printf "%${COLS}s" | tr ' ' "$char"
    printf "${R}\n"
}

# ── Splash mode (first-run / startup) ─────────────────────────────────────
show_splash() {
    clear
    echo ""
    # ASCII art logo — NATION in block letters
    echo -e "${G1}  ███╗   ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗${R}"
    echo -e "${G1}  ████╗  ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║${R}"
    echo -e "${G2}  ██╔██╗ ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║${R}"
    echo -e "${G2}  ██║╚██╗██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║${R}"
    echo -e "${G3}  ██║ ╚████║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║${R}"
    echo -e "${G3}  ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝${R}"
    echo ""
    echo -e "${C1}        █████╗  ██████╗ ███████╗███╗   ██╗████████╗${R}"
    echo -e "${C1}       ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝${R}"
    echo -e "${C2}       ███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║${R}"
    echo -e "${C2}       ██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║${R}"
    echo -e "${C1}       ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║${R}"
    echo -e "${C1}       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝${R}"
    echo ""
    hline "═"
    center "${W}Self-Healing · Persistent Memory · MCP Bridge${R}"
    center "${D}v${VERSION} · Local-First AI Coding Agent${R}"
    hline "═"
    echo ""
    center "${PC}Platform: ${NATION_PLATFORM:-unknown} · $(uname -m)${R}"
    center "${D}$(date '+%A, %B %d %Y  %H:%M:%S')${R}"
    echo ""
    hline "─"
    echo ""
}

# ── Full mode (agent startup) ──────────────────────────────────────────────
show_full() {
    echo ""
    echo -e "${G1}  ███╗   ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗  ${C1}█████╗  ██████╗ ███████╗███╗   ██╗████████╗${R}"
    echo -e "${G2}  ████╗  ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║  ${C2}██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝${R}"
    echo -e "${G3}  ██╔██╗ ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║  ${C1}███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║${R}"
    echo -e "${G2}  ██║╚██╗██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║  ${C2}██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║${R}"
    echo -e "${G1}  ██║ ╚████║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║  ${C1}██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║${R}"
    echo -e "${D}  ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝ v${VERSION}${R}"
    echo ""
    hline "─"
    # Status line
    local MEM_COUNT
    MEM_COUNT=$(python3 -c "import sqlite3; c=sqlite3.connect('${NATION_DIR}/memory/memory.db'); print(c.execute('SELECT COUNT(*) FROM memories').fetchone()[0])" 2>/dev/null || echo "?")
    local TOOL_COUNT
    TOOL_COUNT=$(ls "${NATION_TOOLS}"/nation-*.sh 2>/dev/null | wc -l | tr -d ' ')
    local SKILL_COUNT
    SKILL_COUNT=$(find "${NATION_SKILLS}" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${PC}Platform${R}: ${W}${NATION_PLATFORM}${R}  ${PC}Tools${R}: ${W}${TOOL_COUNT}${R}  ${PC}Skills${R}: ${W}${SKILL_COUNT}${R}  ${PC}Memories${R}: ${W}${MEM_COUNT}${R}  ${PC}ADB${R}: ${W}$([ "${NATION_HAS_ADB:-0}" = "1" ] && echo "yes" || echo "no")${R}"
    echo -e "  ${D}alias: papy · TUI: papy tui · Web: papy web · Ctrl+Shift+N to activate${R}"
    hline "─"
    echo ""
}

# ── Minimal mode (compact, for hooks) ─────────────────────────────────────
show_minimal() {
    echo -e "${G1}[NATION AGENT${R} ${D}v${VERSION}${R}${G1}]${R} ${PC}${NATION_PLATFORM}${R} ${D}·${R} ${W}$(date '+%H:%M:%S')${R}"
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$MODE" in
    splash)  show_splash ;;
    full)    show_full ;;
    minimal) show_minimal ;;
    *)       show_full ;;
esac
