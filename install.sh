#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  NATION AGENT — One-Shot Installer                                      ║
# ║  Installs: Ollama + Kiro CLI + Nation Agent on Termux / Linux           ║
# ║                                                                          ║
# ║  Usage (one-liner):                                                      ║
# ║    curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/install.sh | bash
# ║                                                                          ║
# ║  Or locally:                                                             ║
# ║    bash nation-install.sh                                                ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────
NC='\033[0m'; BOLD='\033[1m'
GREEN='\033[1;32m'; YELLOW='\033[1;33m'
RED='\033[1;31m'; CYAN='\033[1;36m'; BLUE='\033[1;34m'

ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[✗]${NC} $*" >&2; }
section() { echo -e "\n${BLUE}${BOLD}══ $* ══${NC}"; }
step()    { echo -e "${CYAN}  →${NC} $*"; }

# ── Platform detection ────────────────────────────────────────────────────
detect_platform() {
    if [ -d "/data/data/com.termux" ]; then
        PLATFORM="termux"
        PKG_MGR="pkg"
        HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
    elif [ -f "/etc/debian_version" ] || [ -f "/etc/ubuntu-release" ]; then
        PLATFORM="debian"
        PKG_MGR="apt-get"
        HOME_DIR="$HOME"
    elif uname -r 2>/dev/null | grep -qi "proot\|termux"; then
        PLATFORM="termux-proot"
        PKG_MGR="apt-get"
        HOME_DIR="$HOME"
    else
        PLATFORM="linux"
        PKG_MGR="apt-get"
        HOME_DIR="$HOME"
    fi
    BIN_DIR="$HOME_DIR/.local/bin"
    KIRO_DIR="$HOME_DIR/.kiro"
    mkdir -p "$BIN_DIR" "$KIRO_DIR/logs"
}

# ── Package installer helper ──────────────────────────────────────────────
pkg_install() {
    case "$PLATFORM" in
        termux)         pkg install -y "$@" 2>/dev/null ;;
        termux-proot)   apt-get install -y "$@" 2>/dev/null || apt install -y "$@" 2>/dev/null ;;
        debian|linux)   apt-get install -y "$@" 2>/dev/null || apt install -y "$@" 2>/dev/null ;;
        *)              apt-get install -y "$@" 2>/dev/null || true ;;
    esac
}

# ── Ensure PATH contains ~/.local/bin ────────────────────────────────────
ensure_path() {
    for RC in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc" "$HOME_DIR/.profile"; do
        if [ -f "$RC" ] && ! grep -q 'local/bin' "$RC" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
            ok "Added ~/.local/bin to PATH in $RC"
        fi
    done
    export PATH="$BIN_DIR:$PATH"
}

# ── Step 1: Core deps ─────────────────────────────────────────────────────
install_core_deps() {
    section "Installing core dependencies"

    local NEED=()
    command -v curl   &>/dev/null || NEED+=("curl")
    command -v wget   &>/dev/null || NEED+=("wget")
    command -v git    &>/dev/null || NEED+=("git")
    command -v unzip  &>/dev/null || NEED+=("unzip")
    command -v python3 &>/dev/null || NEED+=("python3")

    if [ ${#NEED[@]} -gt 0 ]; then
        step "Installing: ${NEED[*]}"
        pkg_install "${NEED[@]}" && ok "Core deps installed" || warn "Some core deps failed (continuing)"
    else
        ok "Core deps already present"
    fi
}

# ── Step 2: Install Ollama ────────────────────────────────────────────────
install_ollama() {
    section "Installing Ollama"

    if command -v ollama &>/dev/null; then
        ok "Ollama already installed: $(ollama --version 2>/dev/null | head -1)"
        # Make sure it's running
        if ! pgrep -x ollama &>/dev/null; then
            step "Starting Ollama server..."
            nohup ollama serve > "$KIRO_DIR/logs/ollama.log" 2>&1 &
            sleep 2
            ok "Ollama server started (PID: $!)"
        else
            ok "Ollama already running"
        fi
        return 0
    fi

    step "Downloading Ollama installer..."

    # Try official install script first
    if curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null; then
        ok "Ollama installed via official script"
    else
        # Fallback: manual binary install for Linux/Termux
        warn "Official script failed, trying manual install..."
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  OLLAMA_ARCH="amd64" ;;
            aarch64|arm64) OLLAMA_ARCH="arm64" ;;
            armv7*)  OLLAMA_ARCH="arm" ;;
            *)       err "Unsupported arch: $ARCH"; return 1 ;;
        esac

        OLLAMA_URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-${OLLAMA_ARCH}"
        step "Downloading ollama binary for $ARCH..."
        mkdir -p "$BIN_DIR"
        if curl -fsSL "$OLLAMA_URL" -o "$BIN_DIR/ollama"; then
            chmod +x "$BIN_DIR/ollama"
            ok "Ollama binary installed to $BIN_DIR/ollama"
        else
            err "Ollama download failed. Install manually: https://ollama.com"
            return 1
        fi
    fi

    # Start Ollama server
    step "Starting Ollama server..."
    nohup ollama serve > "$KIRO_DIR/logs/ollama.log" 2>&1 &
    sleep 3

    if pgrep -x ollama &>/dev/null || curl -s http://localhost:11434/ &>/dev/null; then
        ok "Ollama server running on :11434"
    else
        warn "Ollama may not be running yet. Start manually: ollama serve"
    fi

    # Pull a default model (small, fast)
    step "Pulling default model (llama3.2:1b — ~1GB, small & fast)..."
    if ollama pull llama3.2:1b 2>/dev/null; then
        ok "Model llama3.2:1b ready"
    else
        warn "Model pull failed. Run later: ollama pull llama3.2:1b"
    fi
}

# ── Step 3: Install Kiro CLI ──────────────────────────────────────────────
install_kiro_cli() {
    section "Installing Kiro CLI"

    # Check if already installed
    if command -v kiro-cli &>/dev/null; then
        ok "Kiro CLI already installed: $(kiro-cli --version 2>/dev/null)"
        return 0
    fi

    mkdir -p "$BIN_DIR"
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    # Map arch to Kiro CLI naming
    case "$ARCH" in
        x86_64)        KIRO_ARCH="x64" ;;
        aarch64|arm64) KIRO_ARCH="arm64" ;;
        armv7*)        KIRO_ARCH="armv7" ;;
        *)             KIRO_ARCH="x64" ;;
    esac

    # Download from Nation Agent GitHub releases
    RELEASE_BASE="https://github.com/ogbas4991/nation-agent/releases/download/v4.0.0"

    step "Downloading Kiro CLI binaries from Nation Agent releases..."

    DOWNLOAD_OK=1
    for BIN in kiro-cli kiro-cli-term kiro-cli-chat; do
        if [ -f "$BIN_DIR/$BIN" ]; then
            ok "$BIN already present, skipping"
            continue
        fi
        step "Downloading $BIN..."
        if curl -fsSL --progress-bar "${RELEASE_BASE}/${BIN}" -o "$BIN_DIR/$BIN"; then
            chmod +x "$BIN_DIR/$BIN"
            ok "$BIN installed"
        else
            err "$BIN download failed"
            DOWNLOAD_OK=0
        fi
    done

    # Also grab the q/qchat wrappers if missing
    for WRAPPER in q qchat; do
        if [ ! -f "$BIN_DIR/$WRAPPER" ]; then
            echo '#!/bin/bash' > "$BIN_DIR/$WRAPPER"
            echo 'exec "$HOME/.local/bin/kiro-cli-chat" "$@"' >> "$BIN_DIR/$WRAPPER"
            chmod +x "$BIN_DIR/$WRAPPER"
        fi
    done

    if [ $DOWNLOAD_OK -eq 0 ]; then
        warn "Some binaries failed. Trying npm fallback..."
        if command -v npm &>/dev/null; then
            npm install -g @aws/kiro-cli 2>/dev/null && ok "Kiro CLI installed via npm" || \
                warn "npm fallback also failed. Install manually: https://kiro.dev"
        else
            warn "Install Kiro CLI manually from: https://kiro.dev"
        fi
    fi

    # Verify
    if command -v kiro-cli &>/dev/null; then
        ok "Kiro CLI verified: $(kiro-cli --version 2>/dev/null)"
    else
        warn "kiro-cli not found in PATH. You may need to restart your terminal."
        warn "PATH: $PATH"
    fi
}

# ── Step 4: Setup Nation Agent ────────────────────────────────────────────
setup_nation_agent() {
    section "Setting up Nation Agent"

    KIRO_TOOLS="$KIRO_DIR/tools"

    if [ -d "$KIRO_TOOLS" ] && [ -f "$KIRO_TOOLS/papy" ]; then
        ok "Nation Agent already installed at $KIRO_DIR"
    else
        warn "Nation Agent not found at $KIRO_DIR"
        warn "Run the Nation Agent installer separately or clone the repo."
        return 0
    fi

    # Make sure papy is in PATH
    if [ ! -L "$BIN_DIR/papy" ] && [ ! -f "$BIN_DIR/papy" ]; then
        ln -sf "$KIRO_TOOLS/papy" "$BIN_DIR/papy" 2>/dev/null || \
            cp "$KIRO_TOOLS/papy" "$BIN_DIR/papy" && chmod +x "$BIN_DIR/papy"
        ok "papy command linked to $BIN_DIR/papy"
    else
        ok "papy command already available"
    fi

    # Run nation-deps for core tools
    if [ -f "$KIRO_TOOLS/nation-deps.sh" ]; then
        step "Running dependency check..."
        bash "$KIRO_TOOLS/nation-deps.sh" --silent core 2>/dev/null || true
        ok "Dependencies checked"
    fi

    # Start autosave if available
    if [ -f "$KIRO_TOOLS/nation-autosave.sh" ]; then
        if ! pgrep -f "nation-autosave" &>/dev/null; then
            step "Starting autosave daemon..."
            nohup bash "$KIRO_TOOLS/nation-autosave.sh" start > /dev/null 2>&1 &
            ok "Autosave daemon started"
        else
            ok "Autosave already running"
        fi
    fi
}

# ── Step 5: Shell RC setup ────────────────────────────────────────────────
setup_shell() {
    section "Configuring shell"

    NATION_INIT_BLOCK='
# ── NATION AGENT ──────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
export NATION_DIR="$HOME/.kiro"
# Auto-start Ollama if not running (uncomment to enable)
# pgrep -x ollama &>/dev/null || nohup ollama serve > ~/.kiro/logs/ollama.log 2>&1 &
alias papy="$HOME/.kiro/tools/papy"
alias nation="kiro-cli-chat --agent nation-agent"
# ──────────────────────────────────────────────────────────────────────────'

    for RC in "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc"; do
        if [ -f "$RC" ] && ! grep -q 'NATION AGENT' "$RC" 2>/dev/null; then
            echo "$NATION_INIT_BLOCK" >> "$RC"
            ok "Nation Agent shell config added to $RC"
        fi
    done
}

# ── Summary ───────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════KeepAlive════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║       NATION AGENT — Install Complete!        ║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Ollama${NC}     : $(command -v ollama &>/dev/null && echo "✓ $(ollama --version 2>/dev/null | head -1)" || echo "⚠ not found")"
    echo -e "  ${CYAN}Kiro CLI${NC}   : $(command -v kiro-cli &>/dev/null && echo "✓ $(kiro-cli --version 2>/dev/null)" || echo "⚠ not found")"
    echo -e "  ${CYAN}papy${NC}       : $(command -v papy &>/dev/null && echo "✓ ready" || echo "⚠ restart terminal")"
    echo -e "  ${CYAN}Nation Dir${NC} : $KIRO_DIR"
    echo ""
    echo -e "  ${BOLD}To start Nation Agent:${NC}"
    echo -e "    ${CYAN}kiro-cli-chat --agent nation-agent${NC}"
    echo -e "  ${BOLD}Or shortcut:${NC}"
    echo -e "    ${CYAN}nation${NC}   (after restarting terminal)"
    echo ""
    echo -e "  ${YELLOW}Restart your terminal (or run: source ~/.bashrc) to apply PATH changes.${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────
main() {
    echo -e "${BLUE}${BOLD}"
    echo "  ███╗   ██╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗"
    echo "  ████╗  ██║██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║"
    echo "  ██╔██╗ ██║███████║   ██║   ██║██║   ██║██╔██╗ ██║"
    echo "  ██║╚██╗██║██╔══██║   ██║   ██║██║   ██║██║╚██╗██║"
    echo "  ██║ ╚████║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║"
    echo "  ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝"
    echo -e "  AGENT v4 — Auto Installer${NC}"
    echo ""

    detect_platform
    echo -e "  Platform: ${CYAN}$PLATFORM${NC} | Home: ${CYAN}$HOME_DIR${NC}"
    echo ""

    ensure_path
    install_core_deps
    install_ollama
    install_kiro_cli
    setup_nation_agent
    setup_shell
    print_summary
}

main "$@"
