#!/bin/bash
# NATION AGENT — GitHub Auth & Operations Manager
# Handles GitHub authentication and common git/GitHub operations.
#
# Usage: nation-github.sh <command> [args...]
#
# Commands:
#   login   [token]        Save GitHub token (prompts if not given)
#   logout                 Remove stored token
#   status                 Show auth status and user info
#   push    [remote] [branch]  Commit all + push to GitHub
#   pull    [remote] [branch]  Pull latest
#   pr      [title]        Open a pull request (requires gh CLI or API)
#   clone   <repo>         Clone a repo (user/repo or full URL)
#   repos                  List your repos
#   whoami                 Show authenticated user
#   token                  Show stored token (masked)
#   set-remote <url>       Update remote origin with token auth
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-status}"
MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
TOKEN_FILE="${NATION_DIR:-$HOME/.kiro}/.github_token"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [GITHUB] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

get_token() {
    # Priority: env var > token file > git credential
    if [ -n "${GITHUB_TOKEN:-}" ]; then echo "$GITHUB_TOKEN"; return; fi
    if [ -f "$TOKEN_FILE" ]; then cat "$TOKEN_FILE"; return; fi
    echo ""
}

require_token() {
    TOKEN=$(get_token)
    [ -n "$TOKEN" ] || die "Not authenticated. Run: papy github login"
    echo "$TOKEN"
}

gh_api() {
    local endpoint="$1"; shift
    local TOKEN
    TOKEN=$(require_token)
    curl -sf \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$@" \
        "https://api.github.com/$endpoint"
}

case "$CMD" in

  login)
    TOKEN="${2:-}"
    if [ -z "$TOKEN" ]; then
        echo "GitHub Personal Access Token Setup"
        echo ""
        echo "Create one at: https://github.com/settings/tokens/new"
        echo "Required scopes: repo, read:user"
        echo ""
        read -rsp "Paste token (hidden): " TOKEN
        echo ""
    fi
    [ -n "$TOKEN" ] || die "No token provided"

    # Validate token
    echo "Validating token..."
    USER_INFO=$(curl -sf \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user" 2>/dev/null) || die "Token validation failed — check the token"

    USERNAME=$(echo "$USER_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('login','?'))")
    EMAIL=$(echo "$USER_INFO"    | python3 -c "import json,sys; print(json.load(sys.stdin).get('email') or 'noreply@github.com')")

    # Save token
    echo "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"

    # Set git config
    git config --global user.name "$USERNAME"
    git config --global user.email "${USERNAME}@users.noreply.github.com"

    # Save to bashrc for persistence
    if ! grep -q "GITHUB_TOKEN" "$HOME/.bashrc" 2>/dev/null; then
        echo "export GITHUB_TOKEN=$TOKEN" >> "$HOME/.bashrc"
    else
        sed -i "s|export GITHUB_TOKEN=.*|export GITHUB_TOKEN=$TOKEN|" "$HOME/.bashrc"
    fi
    export GITHUB_TOKEN="$TOKEN"

    # Update all git remotes to use token auth
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ "$REMOTE_URL" == https://github.com/* ]]; then
            REPO_PATH=$(echo "$REMOTE_URL" | sed 's|https://github.com/||; s|https://.*@github.com/||')
            NEW_URL="https://${TOKEN}@github.com/${REPO_PATH}"
            git remote set-url origin "$NEW_URL"
            echo "Updated remote origin with token auth"
        fi
    fi

    # Store in memory
    [ -x "$MEMORY" ] && "$MEMORY" remember fact "github.user" "$USERNAME" 2>/dev/null || true
    [ -x "$MEMORY" ] && "$MEMORY" remember preference "github.email" "$EMAIL" 2>/dev/null || true

    log "login: $USERNAME"
    echo ""
    echo "✓ Authenticated as: $USERNAME"
    echo "✓ Token saved to: $TOKEN_FILE"
    echo "✓ Git config updated"
    ;;

  logout)
    rm -f "$TOKEN_FILE"
    sed -i '/GITHUB_TOKEN/d' "$HOME/.bashrc" 2>/dev/null || true
    unset GITHUB_TOKEN 2>/dev/null || true
    log "logout"
    echo "Logged out. Token removed."
    ;;

  status)
    TOKEN=$(get_token)
    if [ -z "$TOKEN" ]; then
        echo "GitHub: NOT authenticated"
        echo "Run: papy github login"
    else
        echo "GitHub: authenticating..."
        USER_INFO=$(curl -sf \
            -H "Authorization: token $TOKEN" \
            "https://api.github.com/user" 2>/dev/null) || {
            echo "GitHub: token INVALID or network error"
            exit 1
        }
        python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f'GitHub : AUTHENTICATED')
print(f'User   : {d.get(\"login\",\"?\")}')
print(f'Name   : {d.get(\"name\",\"?\")}')
print(f'Plan   : {d.get(\"plan\",{}).get(\"name\",\"?\")}')
print(f'Repos  : {d.get(\"public_repos\",0)} public  {d.get(\"owned_private_repos\",0)} private')
print(f'Profile: https://github.com/{d.get(\"login\",\"?\")}')
" <<< "$USER_INFO"
    fi
    ;;

  push)
    REMOTE="${2:-origin}"
    BRANCH="${3:-$(git branch --show-current 2>/dev/null || echo main)}"
    TOKEN=$(get_token)
    log "push $REMOTE $BRANCH"

    # Update remote URL with token if available
    if [ -n "$TOKEN" ]; then
        REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null || echo "")
        if [[ "$REMOTE_URL" == https://github.com/* ]]; then
            REPO_PATH=$(echo "$REMOTE_URL" | sed 's|https://github.com/||; s|https://.*@github.com/||')
            git remote set-url "$REMOTE" "https://${TOKEN}@github.com/${REPO_PATH}"
        fi
    fi

    echo "Staging all changes..."
    git add -A
    echo "Staged:"
    git status --short

    read -rp "Commit message (or blank to skip commit): " MSG
    if [ -n "$MSG" ]; then
        git commit -m "$MSG" || echo "(nothing to commit)"
    fi

    echo "Pushing to $REMOTE/$BRANCH..."
    git push -u "$REMOTE" "$BRANCH"
    echo "✓ Pushed to GitHub"
    ;;

  pull)
    REMOTE="${2:-origin}"
    BRANCH="${3:-$(git branch --show-current 2>/dev/null || echo main)}"
    log "pull $REMOTE $BRANCH"
    git pull --rebase "$REMOTE" "$BRANCH"
    ;;

  clone)
    [ -n "${2:-}" ] || die "Repo required (user/repo or full URL)"
    REPO="$2"
    TOKEN=$(get_token)
    if [[ "$REPO" != http* ]]; then
        REPO="https://github.com/$REPO"
    fi
    if [ -n "$TOKEN" ]; then
        REPO=$(echo "$REPO" | sed "s|https://github.com/|https://${TOKEN}@github.com/|")
    fi
    log "clone $2"
    git clone "$REPO" "${3:-}"
    ;;

  repos)
    log "repos"
    gh_api "user/repos?per_page=30&sort=updated" | python3 -c "
import json, sys
repos = json.load(sys.stdin)
print(f'Your repositories ({len(repos)}):')
for r in repos:
    priv = '🔒' if r.get('private') else '🌐'
    print(f'  {priv} {r[\"full_name\"]:40} ⭐{r.get(\"stargazers_count\",0)}  {r.get(\"language\",\"?\") or \"?\"}')"
    ;;

  whoami)
    gh_api "user" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('login','?'))"
    ;;

  token)
    TOKEN=$(get_token)
    if [ -n "$TOKEN" ]; then
        echo "Token: ${TOKEN:0:8}...${TOKEN: -4} (${#TOKEN} chars)"
    else
        echo "No token stored."
    fi
    ;;

  set-remote)
    [ -n "${2:-}" ] || die "Remote URL required"
    TOKEN=$(require_token)
    URL="$2"
    if [[ "$URL" == https://github.com/* ]]; then
        REPO_PATH=$(echo "$URL" | sed 's|https://github.com/||')
        URL="https://${TOKEN}@github.com/${REPO_PATH}"
    fi
    git remote set-url origin "$URL"
    echo "Remote origin updated with token auth"
    ;;

  pr)
    TITLE="${2:-$(git log --oneline -1 2>/dev/null | cut -c8-)}"
    log "pr: $TITLE"
    TOKEN=$(require_token)
    REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com/||; s|\.git$||; s|.*@github.com/||')
    BRANCH=$(git branch --show-current)
    gh_api "repos/$REPO/pulls" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\":\"$TITLE\",\"head\":\"$BRANCH\",\"base\":\"main\",\"body\":\"Created by NATION AGENT\"}" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print('PR:', d.get('html_url','error'))"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) die "Unknown: $CMD. Run: nation-github.sh help" ;;
esac
