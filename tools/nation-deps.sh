#!/bin/bash
# NATION AGENT — Dependency Auto-Installer
# Installs ALL missing tools automatically. Never stops on failure — logs and continues.
# Usage: nation-deps.sh [--silent] [--check-only] [category...]
# Categories: core audio tts voice messaging browser python node all
set -uo pipefail  # No -e: we never stop on error

source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

SILENT=0; CHECK_ONLY=0; CATEGORIES=()
for arg in "$@"; do
    case "$arg" in
        --silent)     SILENT=1 ;;
        --check-only) CHECK_ONLY=1 ;;
        *)            CATEGORIES+=("$arg") ;;
    esac
done
[ ${#CATEGORIES[@]} -eq 0 ] && CATEGORIES=("all")

LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
DEPS_LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-deps.log"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
INSTALLED=0; FAILED=0; SKIPPED=0

log()  { echo "[$TS] [DEPS] $*" >> "$LOG" 2>/dev/null || true; }
info() { [ $SILENT -eq 0 ] && echo -e "  ${BGREEN:-}[✓]${NC:-} $*" || true; }
warn() { [ $SILENT -eq 0 ] && echo -e "  ${BYELLOW:-}[!]${NC:-} $*" || true; }
fail() { [ $SILENT -eq 0 ] && echo -e "  ${BRED:-}[✗]${NC:-} $*" || true
         echo "[$TS] FAIL: $*" >> "$DEPS_LOG" 2>/dev/null || true
         FAILED=$((FAILED+1)); }

# ── Install function — NEVER exits on failure ─────────────────────────────
try_install() {
    local name="$1"; local install_cmd="$2"; local check_cmd="${3:-$1}"
    if command -v $check_cmd &>/dev/null 2>&1; then
        [ $SILENT -eq 0 ] && echo "  ○ $name (already installed)"
        SKIPPED=$((SKIPPED+1))
        return 0
    fi
    if [ $CHECK_ONLY -eq 1 ]; then
        warn "MISSING: $name"
        return 0
    fi
    [ $SILENT -eq 0 ] && echo -n "  Installing $name..."
    if eval "$install_cmd" >> "$DEPS_LOG" 2>&1; then
        info "$name installed"
        log "installed: $name"
        INSTALLED=$((INSTALLED+1))
    else
        fail "$name (install failed — continuing)"
        log "failed: $name via: $install_cmd"
    fi
}

try_pip() {
    local pkg="$1"; local import="${2:-$1}"
    python3 -c "import $import" &>/dev/null 2>&1 && {
        [ $SILENT -eq 0 ] && echo "  ○ python:$pkg (already installed)"
        SKIPPED=$((SKIPPED+1)); return 0
    }
    [ $CHECK_ONLY -eq 1 ] && { warn "MISSING: python:$pkg"; return 0; }
    [ $SILENT -eq 0 ] && echo -n "  pip install $pkg..."
    pip3 install --quiet "$pkg" >> "$DEPS_LOG" 2>&1 && {
        info "python:$pkg installed"
        INSTALLED=$((INSTALLED+1))
    } || {
        fail "python:$pkg"
    }
}

try_npm() {
    local pkg="$1"; local bin="${2:-$1}"
    command -v $bin &>/dev/null 2>&1 && {
        [ $SILENT -eq 0 ] && echo "  ○ npm:$pkg (already installed)"
        SKIPPED=$((SKIPPED+1)); return 0
    }
    [ $CHECK_ONLY -eq 1 ] && { warn "MISSING: npm:$pkg"; return 0; }
    [ $SILENT -eq 0 ] && echo -n "  npm install -g $pkg..."
    npm install -g "$pkg" >> "$DEPS_LOG" 2>&1 && {
        info "npm:$pkg installed"
        INSTALLED=$((INSTALLED+1))
    } || {
        fail "npm:$pkg"
    }
}

pkg_install() {
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot) pkg install -y "$@" ;;
        debian|linux)        apt-get install -y "$@" 2>/dev/null || apt install -y "$@" ;;
        arch)                pacman -S --noconfirm "$@" ;;
        macos)               brew install "$@" ;;
        *)                   apt-get install -y "$@" 2>/dev/null || true ;;
    esac
}

# ── Dependency categories ─────────────────────────────────────────────────

install_core() {
    [ $SILENT -eq 0 ] && echo "--- Core tools ---"
    try_install "curl"    "pkg_install curl"
    try_install "git"     "pkg_install git"
    try_install "python3" "pkg_install python" "python3"
    try_install "node"    "pkg_install nodejs"
    try_install "npm"     "pkg_install nodejs"
    try_install "jq"      "pkg_install jq"
    try_install "sqlite3" "pkg_install sqlite" "sqlite3"
    try_install "unzip"   "pkg_install unzip"
    try_install "wget"    "pkg_install wget"
    try_install "ssh"     "pkg_install openssh" "ssh"
}

install_audio() {
    [ $SILENT -eq 0 ] && echo "--- Audio tools ---"
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot)
            try_install "termux-api"    "pkg install -y termux-api" "termux-tts-speak"
            try_install "sox"           "pkg install -y sox"
            ;;
        linux|debian)
            try_install "alsa-utils"    "apt-get install -y alsa-utils" "aplay"
            try_install "sox"           "apt-get install -y sox"
            try_install "pulseaudio"    "apt-get install -y pulseaudio" "paplay"
            ;;
    esac
    try_pip "pyaudio" "pyaudio"
    try_pip "sounddevice" "sounddevice"
    try_pip "playsound" "playsound"
}

install_tts() {
    [ $SILENT -eq 0 ] && echo "--- TTS (Text-to-Speech) ---"
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot)
            # termux-tts-speak is part of Termux:API
            try_install "termux-api" "pkg install -y termux-api" "termux-tts-speak"
            ;;
        linux|debian)
            try_install "espeak-ng"  "apt-get install -y espeak-ng" "espeak-ng"
            try_install "festival"   "apt-get install -y festival"
            ;;
        macos)
            info "macOS: 'say' command built-in"
            ;;
    esac
    try_pip "pyttsx3" "pyttsx3"
    try_pip "gtts"    "gtts"
}

install_voice() {
    [ $SILENT -eq 0 ] && echo "--- Voice recognition ---"
    try_pip "SpeechRecognition" "speech_recognition"
    try_pip "pyaudio"           "pyaudio"
    try_pip "vosk"              "vosk"
    try_pip "pvporcupine"       "pvporcupine"
    # Vosk model (small English)
    MODEL_DIR="${NATION_DIR:-$HOME/.kiro}/voice/models"
    MODEL_PATH="$MODEL_DIR/vosk-model-small-en-us"
    if [ ! -d "$MODEL_PATH" ] && [ $CHECK_ONLY -eq 0 ]; then
        [ $SILENT -eq 0 ] && echo -n "  Downloading Vosk model (small-en)..."
        mkdir -p "$MODEL_DIR"
        curl -fsSL \
            "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip" \
            -o "/tmp/vosk-model.zip" >> "$DEPS_LOG" 2>&1 && \
        python3 -c "import zipfile; zipfile.ZipFile('/tmp/vosk-model.zip').extractall('$MODEL_DIR')" >> "$DEPS_LOG" 2>&1 && \
        rm -f /tmp/vosk-model.zip && \
        info "Vosk model downloaded" || fail "Vosk model download"
    elif [ -d "$MODEL_PATH" ]; then
        [ $SILENT -eq 0 ] && echo "  ○ Vosk model (already present)"
        SKIPPED=$((SKIPPED+1))
    fi
}

install_messaging() {
    [ $SILENT -eq 0 ] && echo "--- Messaging ---"
    try_pip "python-telegram-bot" "telegram"
    try_pip "requests"            "requests"
    try_npm "@whiskeysockets/baileys" "node" # WhatsApp
    # Check for Telegram token
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
        [ $SILENT -eq 0 ] && warn "TELEGRAM_BOT_TOKEN not set. Run: papy config set telegram.token <token>"
    fi
}

install_browser() {
    [ $SILENT -eq 0 ] && echo "--- Browser/launcher ---"
    case "${NATION_PLATFORM:-linux}" in
        termux|termux-proot)
            try_install "termux-api"   "pkg install -y termux-api" "termux-open-url"
            ;;
        linux|debian)
            try_install "xdg-utils"    "apt-get install -y xdg-utils" "xdg-open"
            try_install "chromium"     "apt-get install -y chromium-browser" "chromium"
            ;;
    esac
    try_pip "selenium"   "selenium"
    try_pip "playwright" "playwright"
}

install_python() {
    [ $SILENT -eq 0 ] && echo "--- Python packages ---"
    for pkg_import in \
        "requests:requests" \
        "flask:flask" \
        "pyyaml:yaml" \
        "python-dotenv:dotenv" \
        "colorama:colorama" \
        "rich:rich" \
        "httpx:httpx" \
        "aiohttp:aiohttp"; do
        PKG=$(echo "$pkg_import" | cut -d: -f1)
        IMP=$(echo "$pkg_import" | cut -d: -f2)
        try_pip "$PKG" "$IMP"
    done
}

install_node() {
    [ $SILENT -eq 0 ] && echo "--- Node packages ---"
    try_npm "nodemon"
    try_npm "pm2"
    try_npm "http-server"
    try_npm "@modelcontextprotocol/server-filesystem" "mcp-server-filesystem"
    try_npm "@modelcontextprotocol/server-github"     "mcp-server-github"
}

# ── Main dispatch ─────────────────────────────────────────────────────────
[ $SILENT -eq 0 ] && echo "=== NATION AGENT Dependency Installer ==="
[ $SILENT -eq 0 ] && echo "Platform: ${NATION_PLATFORM:-unknown}"
[ $SILENT -eq 0 ] && echo ""

for CAT in "${CATEGORIES[@]}"; do
    case "$CAT" in
        core|all)      install_core      ;;
    esac
    case "$CAT" in
        audio|all)     install_audio     ;;
    esac
    case "$CAT" in
        tts|all)       install_tts       ;;
    esac
    case "$CAT" in
        voice|all)     install_voice     ;;
    esac
    case "$CAT" in
        messaging|all) install_messaging ;;
    esac
    case "$CAT" in
        browser|all)   install_browser   ;;
    esac
    case "$CAT" in
        python|all)    install_python    ;;
    esac
    case "$CAT" in
        node|all)      install_node      ;;
    esac
done

[ $SILENT -eq 0 ] && echo ""
[ $SILENT -eq 0 ] && echo "=== Done: $INSTALLED installed, $SKIPPED already present, $FAILED failed ==="
[ $SILENT -eq 0 ] && [ $FAILED -gt 0 ] && echo "  Failed items logged to: $DEPS_LOG"
log "deps complete: installed=$INSTALLED skipped=$SKIPPED failed=$FAILED"
exit 0  # Always exit 0 — never block the agent
