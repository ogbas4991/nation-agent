#!/bin/bash
# NATION AGENT v3 — One-Line Installer
# curl -fsSL https://raw.githubusercontent.com/ogbas4991/nation-agent/main/install.sh | bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/ogbas4991/nation-agent/main"
KIRO="$HOME/.kiro"
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }
sec() { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Detect platform ───────────────────────────────────────────────────────
if [ -d "/data/data/com.termux" ]; then PLATFORM="termux"; PKG="pkg"
elif [ -f "/etc/debian_version" ];  then PLATFORM="debian"; PKG="apt-get"
elif [ -f "/etc/arch-release" ];    then PLATFORM="arch";   PKG="pacman -S --noconfirm"
elif [ "$(uname)" = "Darwin" ];     then PLATFORM="macos";  PKG="brew"
else PLATFORM="linux"; PKG="apt-get"; fi

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     ⚡ NATION AGENT v3 Installer          ║${NC}"
echo -e "${BOLD}║   Cross-Platform Local-First AI Agent     ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════╝${NC}"
echo -e "Platform: ${BOLD}$PLATFORM${NC}"
echo ""

# ── Requirements ──────────────────────────────────────────────────────────
sec "Checking requirements"
command -v curl   &>/dev/null && ok "curl" || { err "curl required. Install: $PKG install curl"; exit 1; }
command -v bash   &>/dev/null && ok "bash"
command -v python3 &>/dev/null && ok "python3 ($(python3 --version 2>&1 | cut -d' ' -f2))" || warn "python3 not found — install: $PKG install python"
command -v git    &>/dev/null && ok "git"    || warn "git not found — install: $PKG install git"
command -v node   &>/dev/null && ok "node"   || warn "node not found — install: $PKG install nodejs"

# ── Directories ───────────────────────────────────────────────────────────
sec "Creating directories"
for d in agents hooks tools prompts "skills/nation-tools" memory logs lib web build auto; do
    mkdir -p "$KIRO/$d"
done
ok "Directories under $KIRO/"

# ── Download files ────────────────────────────────────────────────────────
sec "Downloading files"
dl() {
    local src="$1" dst="$2"
    curl -fsSL "$REPO/$src" -o "$dst" 2>/dev/null && ok "$(basename $dst)" || { err "Failed: $src"; return 1; }
}

dl "agents/nation-agent.json"         "$KIRO/agents/nation-agent.json"
dl "prompts/nation-agent.txt"         "$KIRO/prompts/nation-agent.txt"
dl "skills/nation-tools/SKILL.md"     "$KIRO/skills/nation-tools/SKILL.md"
dl "lib/nation-platform.sh"           "$KIRO/lib/nation-platform.sh"
dl "web/index.html"                   "$KIRO/web/index.html"

for h in nation-spawn nation-pre-tool nation-post-tool nation-stop; do
    dl "hooks/${h}.sh" "$KIRO/hooks/${h}.sh"
done

for t in nation-file nation-shell nation-git nation-search nation-python \
          nation-sqlite nation-browser nation-http nation-docker nation-ssh \
          nation-rest nation-memory nation-heal nation-adb nation-apk \
          nation-banner nation-skills nation-tui nation-web nation-apk-app \
          nation-ollama nation-suggest nation-github nation-shizuku nation-auto; do
    dl "tools/${t}.sh" "$KIRO/tools/${t}.sh"
done
dl "tools/papy" "$KIRO/tools/papy"

# ── Permissions ───────────────────────────────────────────────────────────
sec "Setting permissions"
chmod +x "$KIRO"/hooks/nation-*.sh
chmod +x "$KIRO"/tools/nation-*.sh
chmod +x "$KIRO/tools/papy"
ok "All scripts executable"

# ── Install papy to PATH ──────────────────────────────────────────────────
sec "Installing papy alias"
PAPY_DEST=""
for bin_dir in /usr/local/bin /usr/bin "$HOME/.local/bin" "${PREFIX:-}/bin"; do
    if [ -d "$bin_dir" ] && [ -w "$bin_dir" ]; then
        ln -sf "$KIRO/tools/papy" "$bin_dir/papy" 2>/dev/null && PAPY_DEST="$bin_dir/papy" && break
    fi
done

if [ -n "$PAPY_DEST" ]; then
    ok "papy installed at $PAPY_DEST"
else
    # Fallback: add to bashrc
    grep -q "alias papy" "$HOME/.bashrc" 2>/dev/null || \
        echo -e "\n# NATION AGENT\nalias papy='$KIRO/tools/papy'\nexport PATH=\"\$PATH:$KIRO/tools\"" >> "$HOME/.bashrc"
    warn "papy alias added to ~/.bashrc (run: source ~/.bashrc)"
fi

# ── Initialize memory ─────────────────────────────────────────────────────
sec "Initializing memory"
if command -v python3 &>/dev/null; then
    "$KIRO/tools/nation-memory.sh" init && ok "Memory database ready"
    "$KIRO/tools/nation-memory.sh" remember fact "install.platform" "$PLATFORM" 2>/dev/null || true
    "$KIRO/tools/nation-memory.sh" remember fact "install.date" "$(date '+%Y-%m-%d')" 2>/dev/null || true
else
    warn "python3 not found — memory init skipped"
fi

# ── Scan skills ───────────────────────────────────────────────────────────
sec "Registering skills"
"$KIRO/tools/nation-skills.sh" scan && ok "Skills registered"

# ── Install MCP servers ───────────────────────────────────────────────────
sec "Installing MCP servers"
if command -v npm &>/dev/null; then
    npm install -g @modelcontextprotocol/server-filesystem 2>&1 | tail -1 && ok "mcp-server-filesystem"
    npm install -g @modelcontextprotocol/server-github 2>&1 | tail -1 && ok "mcp-server-github"
else
    warn "npm not found — MCP servers skipped. Install node: $PKG install nodejs"
fi

# ── Git config ────────────────────────────────────────────────────────────
sec "Git configuration"
if command -v git &>/dev/null; then
    [ -n "$(git config --global user.name 2>/dev/null)" ] || \
        git config --global user.name "nation-agent-user" && ok "git user.name set"
    [ -n "$(git config --global user.email 2>/dev/null)" ] || \
        git config --global user.email "user@localhost" && ok "git user.email set"
    git config --global init.defaultBranch main 2>/dev/null || true
fi

# ── Health check ──────────────────────────────────────────────────────────
sec "Health check"
"$KIRO/tools/nation-heal.sh" check 2>&1 || true

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ⚡ NATION AGENT v3 — Install Complete!     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "Usage:"
echo "  papy              Launch agent (kiro-cli)"
echo "  papy tui          Terminal UI"
echo "  papy web          Web dashboard (localhost:7070)"
echo "  papy health       Health check"
echo "  papy status       Full status"
echo ""
echo "Activate in Kiro: /agent nation-agent  or  Ctrl+Shift+N"
echo ""
echo "GitHub: https://github.com/ogbas4991/nation-agent"
echo ""
[ -z "$PAPY_DEST" ] && echo -e "${YELLOW}Run: source ~/.bashrc  (to activate papy alias)${NC}\n"
