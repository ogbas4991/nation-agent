#!/bin/bash
# NATION AGENT — One-Line Installer
# curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh | bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/ogbas4991/nation-agent/main"
KIRO="$HOME/.kiro"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
section() { echo -e "\n${BOLD}── $* ──${NC}"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      NATION AGENT v2 Installer       ║${NC}"
echo -e "${BOLD}║  Local-First AI Agent for Termux     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# ── Check requirements ────────────────────────────────────────────────────────
section "Checking requirements"

command -v curl   &>/dev/null && info "curl" || { error "curl not found. Install: pkg install curl"; exit 1; }
command -v bash   &>/dev/null && info "bash" || { error "bash not found"; exit 1; }
command -v python3 &>/dev/null && info "python3 ($(python3 --version 2>&1 | cut -d' ' -f2))" || warn "python3 not found — install: pkg install python"
command -v git    &>/dev/null && info "git ($(git --version | cut -d' ' -f3))" || warn "git not found — install: pkg install git"
command -v node   &>/dev/null && info "node ($(node --version))" || warn "node not found — install: pkg install nodejs"

# ── Check for kiro-cli ────────────────────────────────────────────────────────
section "Checking Kiro CLI"
if ! command -v kiro-cli &>/dev/null; then
    warn "kiro-cli not found."
    echo "   Install Kiro CLI first from: https://kiro.dev"
    echo "   Then re-run this installer."
    echo ""
    echo "   Continuing anyway to install agent files..."
fi

# ── Create directory structure ────────────────────────────────────────────────
section "Creating directories"
mkdir -p "$KIRO/agents"
mkdir -p "$KIRO/hooks"
mkdir -p "$KIRO/tools"
mkdir -p "$KIRO/prompts"
mkdir -p "$KIRO/skills/nation-tools"
mkdir -p "$KIRO/memory"
mkdir -p "$KIRO/logs"
info "Directories created under $KIRO/"

# ── Download files ────────────────────────────────────────────────────────────
section "Downloading NATION AGENT files"

download() {
    local src="$1"
    local dst="$2"
    local name
    name=$(basename "$dst")
    if curl -fsSL "$REPO/$src" -o "$dst" 2>/dev/null; then
        info "$name"
    else
        error "Failed to download $src"
        return 1
    fi
}

# Agent config
download "agents/nation-agent.json"          "$KIRO/agents/nation-agent.json"

# System prompt
download "prompts/nation-agent.txt"          "$KIRO/prompts/nation-agent.txt"

# Skill
download "skills/nation-tools/SKILL.md"     "$KIRO/skills/nation-tools/SKILL.md"

# Hooks
download "hooks/nation-spawn.sh"             "$KIRO/hooks/nation-spawn.sh"
download "hooks/nation-pre-tool.sh"          "$KIRO/hooks/nation-pre-tool.sh"
download "hooks/nation-post-tool.sh"         "$KIRO/hooks/nation-post-tool.sh"
download "hooks/nation-stop.sh"              "$KIRO/hooks/nation-stop.sh"

# Tools
for tool in \
    nation-file.sh nation-shell.sh nation-git.sh nation-search.sh \
    nation-python.sh nation-sqlite.sh nation-browser.sh nation-http.sh \
    nation-docker.sh nation-ssh.sh nation-rest.sh \
    nation-memory.sh nation-heal.sh; do
    download "tools/$tool" "$KIRO/tools/$tool"
done

# ── Set permissions ───────────────────────────────────────────────────────────
section "Setting permissions"
chmod +x "$KIRO/hooks"/nation-*.sh
chmod +x "$KIRO/tools"/nation-*.sh
info "All scripts marked executable"

# ── Initialize memory DB ──────────────────────────────────────────────────────
section "Initializing memory system"
if command -v python3 &>/dev/null; then
    "$KIRO/tools/nation-memory.sh" init
    info "Memory database initialized"
else
    warn "python3 not found — skipping memory init (run later: nation-memory.sh init)"
fi

# ── Install MCP servers ───────────────────────────────────────────────────────
section "Installing MCP servers"
if command -v npm &>/dev/null; then
    echo "Installing mcp-server-filesystem..."
    npm install -g @modelcontextprotocol/server-filesystem 2>&1 | grep -E "(added|error|warn)" | head -5 || true
    info "mcp-server-filesystem installed"

    echo "Installing mcp-server-github..."
    npm install -g @modelcontextprotocol/server-github 2>&1 | grep -E "(added|error|warn)" | head -5 || true
    info "mcp-server-github installed"
else
    warn "npm not found — skipping MCP server install"
    warn "Install Node.js first: pkg install nodejs"
    warn "Then run: npm install -g @modelcontextprotocol/server-filesystem @modelcontextprotocol/server-github"
fi

# ── Git config ────────────────────────────────────────────────────────────────
section "Git configuration"
if command -v git &>/dev/null; then
    CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    if [ -z "$CURRENT_NAME" ]; then
        git config --global user.name "nation-agent-user"
        info "Set git user.name = nation-agent-user (update with: git config --global user.name 'Your Name')"
    else
        info "git user.name already set: $CURRENT_NAME"
    fi
    if [ -z "$CURRENT_EMAIL" ]; then
        git config --global user.email "user@localhost"
        info "Set git user.email = user@localhost (update with: git config --global user.email 'you@example.com')"
    else
        info "git user.email already set: $CURRENT_EMAIL"
    fi
    git config --global init.defaultBranch main
fi

# ── Run health check ──────────────────────────────────────────────────────────
section "Health check"
"$KIRO/tools/nation-heal.sh" check 2>&1 || true

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   NATION AGENT v2 — Install Complete!    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start Kiro CLI:"
echo "       kiro-cli chat"
echo ""
echo "  2. Switch to NATION AGENT:"
echo "       /agent nation-agent"
echo "     or press: Ctrl+Shift+N"
echo ""
echo "  3. (Optional) Set GitHub token for MCP GitHub server:"
echo "       export GITHUB_TOKEN=ghp_yourtoken"
echo "       echo 'export GITHUB_TOKEN=ghp_yourtoken' >> ~/.bashrc"
echo ""
echo "  4. Update git identity:"
echo "       git config --global user.name 'Your Name'"
echo "       git config --global user.email 'you@example.com'"
echo ""
echo "  Source: https://github.com/ogbas4991/nation-agent"
echo ""
