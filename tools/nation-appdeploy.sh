#!/bin/bash
# NATION AGENT — AppDeploy Deployment Tool
# Deploy websites and apps via AppDeploy MCP (appdeploy.ai)
#
# Usage: nation-appdeploy.sh <command> [args...]
#
# Commands:
#   setup              Create API key and save it
#   deploy <dir> [name] Deploy a local directory as a live web app
#   list               List all deployed apps
#   status [app-id]    Show deployment status
#   logs   <app-id>    Show runtime logs/errors
#   rollback <app-id>  Roll back to previous version
#   open   <app-id>    Open app URL in browser
#   delete <app-id>    Delete an app
#   help               Show this help

set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
MCP="https://api-v2.appdeploy.ai/mcp"
KEY_FILE="${HOME}/.kiro/config/appdeploy.key"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$KEY_FILE")" "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [APPDEPLOY] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo -e "${RD:-}ERROR: $*${R:-}" >&2; exit 1; }

# ── Colors ────────────────────────────────────────────────────────────────
if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'
    W='\033[1;37m'; D='\033[38;5;244m'; GR='\033[38;5;82m'; RD='\033[38;5;196m'
else
    R=''; G1=''; C1=''; W=''; D=''; GR=''; RD=''
fi

hdr() { echo -e "${G1}══ $* ══${R}"; }

# ── API key helpers ───────────────────────────────────────────────────────
load_key() {
    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${RD}No API key found.${R} Run: ${W}papy appdeploy setup${R}"
        exit 1
    fi
    cat "$KEY_FILE"
}

mcp_call() {
    local key="$1" tool="$2" args_json="$3"
    curl -sf --max-time 30 \
        -X POST "$MCP" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $key" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":${args_json}},\"id\":1}" \
        2>/dev/null
}

extract_result() {
    python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    result = d.get('result', d)
    content = result.get('content', result)
    if isinstance(content, list):
        for c in content:
            if c.get('type') == 'text':
                print(c.get('text',''))
    else:
        print(json.dumps(content, indent=2))
except Exception as e:
    print(raw[:500])
"
}

# ── Commands ──────────────────────────────────────────────────────────────

do_setup() {
    hdr "AppDeploy Setup"
    echo -e "  Creating API key for NATION AGENT...\n"
    local resp
    resp=$(curl -sf --max-time 15 \
        -X POST "https://api-v2.appdeploy.ai/mcp/api-key" \
        -H "Content-Type: application/json" \
        -d '{"client_name":"nation-agent"}' 2>/dev/null) || die "Could not reach AppDeploy. Check internet connection."

    local key
    key=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('api_key', d.get('key','')))" "$resp" 2>/dev/null)
    [ -n "$key" ] || die "Failed to get API key. Response: ${resp:0:200}"

    echo "$key" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo -e "  ${GR}✓${R} API key saved to: ${D}$KEY_FILE${R}"
    echo -e "  ${D}Deploy your first app: papy appdeploy deploy ./myapp${R}"
    log "setup: API key saved"
}

do_deploy() {
    local dir="${2:-}"
    local appname="${3:-}"
    [ -n "$dir" ] || die "Usage: papy appdeploy deploy <directory> [app-name]"
    [ -d "$dir"  ] || die "Directory not found: $dir"
    local key; key=$(load_key)

    # Default app name from directory
    [ -z "$appname" ] && appname=$(basename "$(realpath "$dir")")
    log "deploy: $dir as $appname"
    hdr "AppDeploy: $appname"
    echo ""

    # Collect files into JSON
    echo -e "  ${D}Scanning files in $dir...${R}"
    local files_json
    files_json=$(python3 - "$dir" << 'PY'
import os, sys, base64, json, mimetypes

root = sys.argv[1]
files = []
skip_dirs = {'.git', 'node_modules', '__pycache__', '.DS_Store'}
max_files = 100
count = 0

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    for fname in filenames:
        if count >= max_files:
            break
        fpath = os.path.join(dirpath, fname)
        rel = os.path.relpath(fpath, root)
        try:
            size = os.path.getsize(fpath)
            if size > 5 * 1024 * 1024:  # skip files > 5MB
                continue
            with open(fpath, 'rb') as f:
                content = f.read()
            mime = mimetypes.guess_type(fpath)[0] or 'application/octet-stream'
            # Try text first
            try:
                text = content.decode('utf-8')
                files.append({"path": rel, "content": text})
            except UnicodeDecodeError:
                files.append({"path": rel, "content": base64.b64encode(content).decode(), "encoding": "base64"})
            count += 1
        except Exception:
            pass
print(json.dumps(files))
PY
    )

    local file_count
    file_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$files_json")
    echo -e "  ${D}Found $file_count files${R}"
    echo -e "  ${D}Deploying to AppDeploy...${R}"

    # Build deploy args
    local args_json
    args_json=$(python3 -c "
import json, sys
name = sys.argv[1]
files = json.loads(sys.argv[2])
print(json.dumps({'app_name': name, 'files': files}))
" "$appname" "$files_json")

    local resp
    resp=$(mcp_call "$key" "deploy_app" "$args_json")
    [ -n "$resp" ] || die "No response from AppDeploy. Check API key: papy appdeploy setup"

    # Extract app ID and poll status
    local app_id
    app_id=$(python3 -c "
import json, sys
raw = sys.argv[1]
try:
    d = json.loads(raw)
    r = d.get('result', d)
    content = r.get('content', r)
    if isinstance(content, list):
        for c in content:
            t = c.get('text','')
            import re
            m = re.search(r'app[_-]?id[\":\s]+([a-zA-Z0-9_-]+)', t, re.I)
            if m: print(m.group(1)); break
    elif isinstance(content, dict):
        print(content.get('app_id', content.get('id','')))
except: pass
" "$resp" 2>/dev/null)

    echo -e "  ${GR}✓${R} Deployment submitted"
    [ -n "$app_id" ] && echo -e "  ${D}App ID: $app_id${R}"

    # Poll status
    if [ -n "$app_id" ]; then
        echo -e "  ${D}Polling status...${R}"
        local status_resp url
        for i in $(seq 1 12); do
            sleep 5
            status_resp=$(mcp_call "$key" "get_app_status" "{\"app_id\":\"$app_id\"}")
            url=$(python3 -c "
import json, sys, re
try:
    d = json.loads(sys.argv[1])
    r = d.get('result', d)
    content = r.get('content', r)
    text = ''
    if isinstance(content, list):
        for c in content:
            text += c.get('text','')
    else:
        text = json.dumps(content)
    m = re.search(r'https://[^\s\"]+appdeploy[^\s\"]+', text)
    if m: print(m.group(0))
    elif 'ready' in text.lower(): print('ready')
    elif 'failed' in text.lower(): print('failed')
except: pass
" "$status_resp" 2>/dev/null)
            if [[ "$url" == https://* ]]; then
                echo ""
                echo -e "  ${GR}✓ LIVE${R}: ${W}$url${R}"
                echo -e "  ${D}Open: papy appdeploy open $app_id${R}"
                log "deployed: $appname app_id=$app_id url=$url"
                break
            elif [ "$url" = "failed" ]; then
                echo -e "  ${RD}✗ Deployment failed.${R} Check logs: papy appdeploy logs $app_id"
                break
            else
                printf "  ${D}.${R}"
            fi
        done
        echo ""
    else
        echo "$resp" | extract_result
    fi
}

do_list() {
    local key; key=$(load_key)
    log "list apps"
    hdr "Deployed Apps"
    echo ""
    local resp
    resp=$(mcp_call "$key" "get_apps" "{}")
    echo "$resp" | extract_result
}

do_status() {
    local app_id="${2:-}"
    local key; key=$(load_key)
    log "status: $app_id"
    if [ -n "$app_id" ]; then
        hdr "App Status: $app_id"
        local resp
        resp=$(mcp_call "$key" "get_app_status" "{\"app_id\":\"$app_id\"}")
        echo "$resp" | extract_result
    else
        do_list
    fi
}

do_logs() {
    local app_id="${2:-}"
    [ -n "$app_id" ] || die "Usage: papy appdeploy logs <app-id>"
    local key; key=$(load_key)
    log "logs: $app_id"
    hdr "App Logs: $app_id"
    echo ""
    local resp
    resp=$(mcp_call "$key" "get_app_status" "{\"app_id\":\"$app_id\",\"include_errors\":true}")
    echo "$resp" | extract_result
}

do_rollback() {
    local app_id="${2:-}"
    [ -n "$app_id" ] || die "Usage: papy appdeploy rollback <app-id>"
    local key; key=$(load_key)
    log "rollback: $app_id"
    echo -e "${G1}◆ Rolling back: ${W}$app_id${R}"
    local versions
    versions=$(mcp_call "$key" "get_app_versions" "{\"app_id\":\"$app_id\"}")
    echo "$versions" | extract_result
    echo ""
    echo -e "${D}To apply a specific version: provide version ID when prompted${R}"
    read -rp "Enter version ID to roll back to (or Enter to cancel): " ver_id
    [ -z "$ver_id" ] && { echo "Cancelled."; return; }
    local resp
    resp=$(mcp_call "$key" "apply_app_version" "{\"app_id\":\"$app_id\",\"version_id\":\"$ver_id\"}")
    echo "$resp" | extract_result
    log "rollback done: $app_id version=$ver_id"
}

do_open() {
    local app_id="${2:-}"
    [ -n "$app_id" ] || die "Usage: papy appdeploy open <app-id>"
    local key; key=$(load_key)
    local resp
    resp=$(mcp_call "$key" "get_app_status" "{\"app_id\":\"$app_id\"}")
    local url
    url=$(python3 -c "
import json, sys, re
try:
    d = json.loads(sys.argv[1])
    r = d.get('result', d)
    content = r.get('content', r)
    text = ''
    if isinstance(content, list):
        for c in content: text += c.get('text','')
    else: text = json.dumps(content)
    m = re.search(r'https://[^\s\"]+appdeploy[^\s\"]+', text)
    if m: print(m.group(0))
except: pass
" "$resp" 2>/dev/null)
    if [ -n "$url" ]; then
        echo -e "${GR}Opening:${R} $url"
        bash "${NATION_TOOLS:-$HOME/.kiro/tools}/nation-launch.sh" url "$url" 2>/dev/null || \
            xdg-open "$url" 2>/dev/null || \
            termux-open-url "$url" 2>/dev/null || \
            echo "Open manually: $url"
    else
        echo -e "${RD}Could not find app URL.${R}"
        echo "$resp" | extract_result
    fi
}

do_delete() {
    local app_id="${2:-}"
    [ -n "$app_id" ] || die "Usage: papy appdeploy delete <app-id>"
    local key; key=$(load_key)
    read -rp "Delete app $app_id? This cannot be undone. [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; return; }
    log "delete: $app_id"
    local resp
    resp=$(mcp_call "$key" "delete_app" "{\"app_id\":\"$app_id\"}")
    echo "$resp" | extract_result
    echo -e "${GR}✓ App deleted.${R}"
}

# ── Dispatch ──────────────────────────────────────────────────────────────
case "$CMD" in
    setup)          do_setup ;;
    deploy)         do_deploy "$@" ;;
    list)           do_list ;;
    status)         do_status "$@" ;;
    logs)           do_logs "$@" ;;
    rollback)       do_rollback "$@" ;;
    open)           do_open "$@" ;;
    delete)         do_delete "$@" ;;
    help|--help|-h)
        grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
        ;;
    *)
        echo -e "${RD}Unknown: $CMD${R}  Run: papy appdeploy help"
        exit 1
        ;;
esac
