#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   NATION AGENT — Full Bootstrap Installer                       ║
# ║   Handles: Termux layer + proot Ubuntu + menu + fixes           ║
# ║   Run: curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh | bash
# ╚══════════════════════════════════════════════════════════════════╝
set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; GRN=$'\033[0;32m'; YLW=$'\033[1;33m'
RED=$'\033[0;31m'; CYN=$'\033[0;36m'; NC=$'\033[0m'
ok()   { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
sec()  { echo -e "\n${BOLD}${CYN}── $* ──${NC}"; }
die()  { err "$*"; exit 1; }

REPO="https://raw.githubusercontent.com/ogbas4991/nation-agent/main"
KIRO="$HOME/.kiro"

# ── Detect layer ──────────────────────────────────────────────────────────
IN_TERMUX=0; IN_PROOT=0
[ -d "/data/data/com.termux" ] && IN_TERMUX=1
uname -r 2>/dev/null | grep -qi "proot" && IN_PROOT=1
[ -f "/etc/debian_version" ] && [ $IN_TERMUX -eq 0 ] && IN_PROOT=1

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ⚡ NATION AGENT — Full Setup               ║${NC}"
echo -e "${BOLD}║   Termux + Ubuntu + Menu + Agent + Fixes     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ $IN_TERMUX -eq 1 ] && [ $IN_PROOT -eq 0 ]; then
    echo -e "  Layer: ${BOLD}Termux${NC}"
else
    echo -e "  Layer: ${BOLD}proot-Ubuntu${NC}"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════
# PART 1 — TERMUX LAYER
# ══════════════════════════════════════════════════════════════════════════
install_termux_layer() {
    sec "Termux — core packages"
    pkg update -y 2>&1 | tail -2
    pkg install -y curl wget git python python-pip nodejs \
        proot-distro tmux jq unzip zip openssh 2>&1 | tail -5
    ok "Core packages installed"

    sec "Termux — API package"
    pkg install -y termux-api 2>&1 | tail -2
    ok "termux-api installed"

    sec "Termux — storage permission"
    termux-setup-storage 2>/dev/null &
    ok "Storage permission requested (tap Allow if prompted)"

    sec "Termux — proot Ubuntu"
    if proot-distro list 2>/dev/null | grep -qi "ubuntu"; then
        ok "Ubuntu already installed"
    else
        echo "  Installing Ubuntu (~500MB)..."
        proot-distro install ubuntu 2>&1 | tail -3
        ok "Ubuntu installed"
    fi

    sec "Termux — termux-menu.sh"
    curl -fsSL "https://raw.githubusercontent.com/ogbas4991/nation-agent/main/tools/papy" \
        -o "$HOME/termux-menu.sh" 2>/dev/null || true
    # Download our fixed menu from the agent's own copy if available
    # or write the bootstrap version that auto-launches proot setup
    cat > "$HOME/termux-menu.sh" << 'MENU_STUB'
#!/bin/bash
# Termux bootstrap menu — runs before full install inside proot
echo ""
echo "  ⚡ NATION AGENT"
echo "  ─────────────────────────────"
echo "  1) Launch Agent (proot Ubuntu)"
echo "  2) Quick Shell (proot Ubuntu)"
echo "  3) Exit to Termux"
echo ""
read -rp "  Select [1]: " c
c="${c:-1}"
case "$c" in
    2) proot-distro login ubuntu ;;
    3) exit 0 ;;
    *) proot-distro login ubuntu -- bash -c '
        export HOME=/root
        source /root/.bashrc 2>/dev/null || true
        if tmux has-session -t nation 2>/dev/null; then
            tmux attach-session -t nation
        else
            bash /root/.kiro/tools/nation-persist.sh start 2>/dev/null \
                || exec bash
        fi
    ' ;;
esac
MENU_STUB
    chmod +x "$HOME/termux-menu.sh"
    ok "termux-menu.sh ready"

    sec "Termux — .bashrc setup"
    TBASHRC="$HOME/.bashrc"
    # Remove any old/duplicate nation-agent blocks
    grep -q "NATION AGENT" "$TBASHRC" 2>/dev/null && \
        sed -i '/# NATION AGENT/,/^$/d' "$TBASHRC" 2>/dev/null || true

    # Write clean block
    cat >> "$TBASHRC" << 'TBRC'

# NATION AGENT — Termux layer
export PATH="$HOME/.local/bin:$PATH"
alias opa='proot-distro login ubuntu -- bash -c "export HOME=/root; source /root/.bashrc 2>/dev/null; exec bash"'

# Auto-attach: jump into proot Ubuntu + tmux session on new terminal
_nation_autoattach() {
    [[ $- != *i* ]] && return
    [ -n "${TMUX:-}" ] && return
    [ -n "${NATION_ATTACHED:-}" ] && return
    export NATION_ATTACHED=1
    command -v proot-distro >/dev/null 2>&1 || return
    proot-distro login ubuntu -- bash -c '
        export HOME=/root
        source /root/.bashrc 2>/dev/null || true
        if tmux has-session -t nation 2>/dev/null; then
            exec tmux attach-session -t nation
        else
            bash /root/.kiro/tools/nation-persist.sh start 2>/dev/null \
                || exec bash
        fi
    '
}
_nation_autoattach
TBRC
    ok ".bashrc updated"
}

# ══════════════════════════════════════════════════════════════════════════
# PART 2 — PROOT UBUNTU LAYER (runs inside proot or directly on Ubuntu)
# ══════════════════════════════════════════════════════════════════════════
install_ubuntu_layer() {
    export HOME=/root
    export DEBIAN_FRONTEND=noninteractive

    sec "Ubuntu — system packages"
    apt-get update -qq 2>&1 | tail -2
    apt-get install -y --no-install-recommends \
        curl wget git python3 python3-pip python3-dev \
        nodejs npm tmux jq unzip zip openssh-client \
        portaudio19-dev gcc build-essential \
        2>&1 | tail -5
    ok "System packages installed"

    sec "Ubuntu — pip packages"
    pip3 install --break-system-packages --upgrade \
        requests gtts 2>&1 | tail -3
    # PyAudio needs gcc (just installed)
    pip3 install --break-system-packages PyAudio 2>&1 | tail -3 || \
        warn "PyAudio failed — voice features may not work"
    ok "pip packages installed"

    sec "Nation Agent — download & install"
    curl -fsSL "$REPO/install.sh" | bash 2>&1
    ok "Nation Agent installed"

    sec "Nation Agent — termux-menu.sh (fixed version)"
    curl -fsSL "https://raw.githubusercontent.com/ogbas4991/nation-agent/main/tools/papy" \
        -o /root/termux-menu.sh 2>/dev/null || true

    # Download the FIXED termux-menu from the saved version if available
    if [ -f "/root/termux-menu.sh" ]; then
        ok "termux-menu.sh present"
    fi
    chmod +x /root/termux-menu.sh 2>/dev/null || true

    sec "Ubuntu — .bashrc setup (clean)"
    cat > /root/.bashrc << 'UBRC'
# ~/.bashrc — Nation Agent Ubuntu (proot)
[ -z "$PS1" ] && return

# History
HISTCONTROL=ignoredups:ignorespace
HISTSIZE=2000; HISTFILESIZE=4000
shopt -s histappend checkwinsize

# Prompt
PS1='\[\033[01;32m\]\u@nation\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Colors
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# NATION AGENT
export PATH="$HOME/.local/bin:$HOME/.kiro/tools:$PATH"
alias papy='/root/.kiro/tools/papy'
alias opa='papy'

# Termux Menu — auto-start on new terminal
if [ -t 1 ] && [ -z "${TERMUX_MENU_STARTED:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    export TERMUX_MENU_STARTED=1
    [ -x "$HOME/termux-menu.sh" ] && bash "$HOME/termux-menu.sh"
fi
UBRC
    ok ".bashrc written"

    sec "Ubuntu — .profile setup"
    cat > /root/.profile << 'UPROF'
# ~/.profile — login shells
if [ "$BASH" ]; then
    [ -f ~/.bashrc ] && . ~/.bashrc
fi
# PATH and aliases for NATION AGENT are set in ~/.bashrc
UPROF
    ok ".profile written"

    sec "Nation Agent — health check"
    /root/.kiro/tools/nation-heal.sh check 2>&1 || true
}

# ══════════════════════════════════════════════════════════════════════════
# DISPATCH — which layer are we in?
# ══════════════════════════════════════════════════════════════════════════
if [ $IN_TERMUX -eq 1 ] && [ $IN_PROOT -eq 0 ]; then
    # ── Running directly in Termux ─────────────────────────────────────
    install_termux_layer

    sec "Running Ubuntu layer inside proot"
    echo "  (This will take a few minutes on first run)"
    echo ""

    # Pass this script into proot Ubuntu to run Part 2
    SCRIPT_URL="https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh"
    proot-distro login ubuntu -- bash -c "
        export HOME=/root
        export IN_TERMUX=0
        export IN_PROOT=1
        curl -fsSL '$SCRIPT_URL' | bash
    " 2>&1 || {
        warn "Proot install step had warnings — checking manually..."
        proot-distro login ubuntu -- bash -c "
            export HOME=/root
            [ -x /root/.kiro/tools/papy ] && echo 'papy: OK' || echo 'papy: MISSING'
            [ -f /root/termux-menu.sh ]   && echo 'menu: OK' || echo 'menu: MISSING'
        "
    }
else
    # ── Running inside proot Ubuntu ────────────────────────────────────
    install_ubuntu_layer
fi

# ══════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ✅  NATION AGENT — Setup Complete!                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
if [ $IN_TERMUX -eq 1 ] && [ $IN_PROOT -eq 0 ]; then
echo "  Close this terminal and open a NEW one to start."
echo ""
echo "  On every new terminal you will auto-connect to:"
echo "    proot Ubuntu → tmux session → Nation Agent"
echo ""
echo "  Manual commands (from Termux):"
echo "    opa                              Enter Ubuntu shell"
echo "    proot-distro login ubuntu        Raw Ubuntu shell"
echo ""
else
echo "  From inside Ubuntu (proot):"
echo "    papy                             Launch agent"
echo "    papy tui                         Terminal UI"
echo "    papy web                         Web dashboard (port 7070)"
echo "    papy device info                 Device status"
echo "    papy health                      Health check"
echo ""
echo "  Keyboard:"
echo "    Ctrl+B D  → detach tmux (keeps agent running)"
echo "    Ctrl+B 1  → switch to agent window"
echo ""
fi
echo "  GitHub: https://github.com/ogbas4991/nation-agent"
echo ""
