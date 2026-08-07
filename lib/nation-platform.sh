#!/bin/bash
# NATION AGENT — Platform Detection Library
# Source this file: source ~/.kiro/lib/nation-platform.sh
# Then use: $NATION_PLATFORM, $NATION_HOME, $NATION_PKG, etc.

# ── Detect platform ────────────────────────────────────────────────────────
if [ -d "/data/data/com.termux" ]; then
    export NATION_PLATFORM="termux"
    export NATION_TERMUX=1
    export NATION_LINUX=0
    export NATION_HOME="${HOME:-/data/data/com.termux/files/home}"
    export NATION_USR="${PREFIX:-/data/data/com.termux/files/usr}"
    export NATION_PKG="pkg"
    export NATION_APT="apt"
    export NATION_TMP="/data/local/tmp"
    export NATION_ANDROID=1
    # Detect if running inside proot-distro
    if uname -r 2>/dev/null | grep -q "PRoot"; then
        export NATION_PROOT=1
        export NATION_PLATFORM="termux-proot"
    else
        export NATION_PROOT=0
    fi
elif [ -f "/etc/debian_version" ] || [ -f "/etc/ubuntu-release" ]; then
    export NATION_PLATFORM="debian"
    export NATION_TERMUX=0
    export NATION_LINUX=1
    export NATION_ANDROID=0
    export NATION_PROOT=0
    export NATION_HOME="$HOME"
    export NATION_USR="/usr"
    export NATION_PKG="apt-get"
    export NATION_APT="apt-get"
    export NATION_TMP="/tmp"
elif [ -f "/etc/arch-release" ]; then
    export NATION_PLATFORM="arch"
    export NATION_TERMUX=0
    export NATION_LINUX=1
    export NATION_ANDROID=0
    export NATION_PROOT=0
    export NATION_HOME="$HOME"
    export NATION_USR="/usr"
    export NATION_PKG="pacman -S --noconfirm"
    export NATION_APT="pacman"
    export NATION_TMP="/tmp"
elif [ "$(uname)" = "Darwin" ]; then
    export NATION_PLATFORM="macos"
    export NATION_TERMUX=0
    export NATION_LINUX=0
    export NATION_ANDROID=0
    export NATION_PROOT=0
    export NATION_HOME="$HOME"
    export NATION_USR="/usr/local"
    export NATION_PKG="brew"
    export NATION_APT="brew"
    export NATION_TMP="/tmp"
else
    export NATION_PLATFORM="linux"
    export NATION_TERMUX=0
    export NATION_LINUX=1
    export NATION_ANDROID=0
    export NATION_PROOT=0
    export NATION_HOME="$HOME"
    export NATION_USR="/usr"
    export NATION_PKG="apt-get"
    export NATION_APT="apt-get"
    export NATION_TMP="/tmp"
fi

# ── Paths ──────────────────────────────────────────────────────────────────
export NATION_DIR="${NATION_HOME}/.kiro"
export NATION_TOOLS="${NATION_DIR}/tools"
export NATION_HOOKS="${NATION_DIR}/hooks"
export NATION_SKILLS="${NATION_DIR}/skills"
export NATION_MEMORY="${NATION_DIR}/memory"
export NATION_LOGS="${NATION_DIR}/logs"
export NATION_LIB="${NATION_DIR}/lib"
export NATION_WEB="${NATION_DIR}/web"

# ── ADB / platform-tools detection ────────────────────────────────────────
if command -v adb &>/dev/null; then
    export NATION_ADB=$(command -v adb)
    export NATION_HAS_ADB=1
elif [ -x "${NATION_HOME}/platform-tools/adb" ]; then
    export NATION_ADB="${NATION_HOME}/platform-tools/adb"
    export NATION_HAS_ADB=1
    export PATH="$PATH:${NATION_HOME}/platform-tools"
elif [ -x "/data/data/com.termux/files/usr/bin/adb" ]; then
    export NATION_ADB="/data/data/com.termux/files/usr/bin/adb"
    export NATION_HAS_ADB=1
else
    export NATION_ADB=""
    export NATION_HAS_ADB=0
fi

# ── Java / build tools ─────────────────────────────────────────────────────
if command -v java &>/dev/null; then
    export NATION_JAVA=$(command -v java)
    export NATION_HAS_JAVA=1
else
    export NATION_JAVA=""
    export NATION_HAS_JAVA=0
fi

if command -v gradle &>/dev/null; then
    export NATION_GRADLE=$(command -v gradle)
    export NATION_HAS_GRADLE=1
else
    export NATION_GRADLE=""
    export NATION_HAS_GRADLE=0
fi

# ── Color support ──────────────────────────────────────────────────────────
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    export NATION_COLOR=1
    export NC='\033[0m'
    export BOLD='\033[1m'
    export DIM='\033[2m'
    export RED='\033[0;31m'
    export GREEN='\033[0;32m'
    export YELLOW='\033[1;33m'
    export BLUE='\033[0;34m'
    export MAGENTA='\033[0;35m'
    export CYAN='\033[0;36m'
    export WHITE='\033[1;37m'
    export BRED='\033[1;31m'
    export BGREEN='\033[1;32m'
    export BYELLOW='\033[1;33m'
    export BBLUE='\033[1;34m'
    export BMAGENTA='\033[1;35m'
    export BCYAN='\033[1;36m'
else
    export NATION_COLOR=0
    export NC='' BOLD='' DIM='' RED='' GREEN='' YELLOW=''
    export BLUE='' MAGENTA='' CYAN='' WHITE=''
    export BRED='' BGREEN='' BYELLOW='' BBLUE='' BMAGENTA='' BCYAN=''
fi

# ── Helper functions ───────────────────────────────────────────────────────
nation_info()    { echo -e "${BGREEN}[✓]${NC} $*"; }
nation_warn()    { echo -e "${BYELLOW}[!]${NC} $*"; }
nation_error()   { echo -e "${BRED}[✗]${NC} $*" >&2; }
nation_section() { echo -e "\n${BBLUE}══${NC} ${BOLD}$*${NC} ${BBLUE}══${NC}"; }

nation_require() {
    local bin="$1"
    command -v "$bin" &>/dev/null && return 0
    nation_error "Required: $bin not found"
    [ -n "${2:-}" ] && echo "  Install: $2"
    return 1
}

nation_install_pkg() {
    local pkg="$1"
    case "$NATION_PLATFORM" in
        termux|termux-proot) pkg install -y "$pkg" ;;
        debian|linux)        apt-get install -y "$pkg" 2>/dev/null || apt install -y "$pkg" ;;
        arch)                pacman -S --noconfirm "$pkg" ;;
        macos)               brew install "$pkg" ;;
        *)                   echo "Cannot auto-install on $NATION_PLATFORM. Install manually: $pkg" ;;
    esac
}

# Export summary for debugging
nation_platform_info() {
    echo "Platform : $NATION_PLATFORM"
    echo "Home     : $NATION_HOME"
    echo "PKG mgr  : $NATION_PKG"
    echo "Android  : $NATION_ANDROID"
    echo "ADB      : ${NATION_ADB:-not found}"
    echo "Java     : ${NATION_JAVA:-not found}"
    echo "Colors   : $NATION_COLOR"
}
