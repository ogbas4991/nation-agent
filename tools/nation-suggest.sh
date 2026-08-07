#!/bin/bash
# NATION AGENT — Follow-up Suggestion Engine
# Generates context-aware suggestions and lets you pick/execute them.
#
# Usage: nation-suggest.sh [--pick] [--json] [--tui] [context]
#   --pick      Interactive numbered picker (type number to execute)
#   --json      Output suggestions as JSON array
#   --tui       TUI arrow-key selector
#   (none)      Print suggestions list (default)
#   context     Optional context string for better suggestions
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
MODE="print"
CONTEXT=""

for arg in "$@"; do
    case "$arg" in
        --pick) MODE="pick" ;;
        --json) MODE="json" ;;
        --tui)  MODE="tui"  ;;
        *)      CONTEXT="$CONTEXT $arg" ;;
    esac
done
CONTEXT="${CONTEXT# }"

# ── Generate suggestions via Python ──────────────────────────────────────
SUGGESTIONS=$(python3 - "$CONTEXT" << 'PYEOF'
import sys, os, sqlite3, json, re, subprocess, datetime

context = sys.argv[1] if len(sys.argv) > 1 else ""
db_path = os.path.expanduser("~/.kiro/memory/memory.db")
log_path = os.path.expanduser("~/.kiro/logs/nation-agent.log")
cwd = os.getcwd()

memories = []
try:
    conn = sqlite3.connect(db_path)
    memories = conn.execute(
        "SELECT type,key,value FROM memories ORDER BY updated DESC LIMIT 30"
    ).fetchall()
    conn.close()
except: pass

log_lines = []
try:
    with open(log_path) as f:
        log_lines = f.readlines()[-60:]
except: pass

# Detect project type
project_type = "general"
if os.path.isfile("package.json"):      project_type = "nodejs"
elif os.path.isfile("requirements.txt") or os.path.isfile("pyproject.toml"): project_type = "python"
elif os.path.isfile("Cargo.toml"):      project_type = "rust"
elif os.path.isfile("build.gradle"):    project_type = "android"
elif os.path.isfile("Makefile"):        project_type = "make"

# Git state
has_git = os.path.isdir(".git")
has_uncommitted = False
has_untracked = False
if has_git:
    try:
        r = subprocess.run(["git","status","--short"], capture_output=True, text=True, timeout=3)
        has_uncommitted = bool(r.stdout.strip())
        has_untracked = any(l.startswith('??') for l in r.stdout.splitlines())
    except: pass

# Recent errors
recent_errors = [l for l in log_lines if 'ERROR' in l or '[✗]' in l]
recent_writes = [l for l in log_lines if 'wrote:' in l.lower() or 'file-written' in l]

# Build suggestions as (label, command) pairs
suggestions = []

# Git-based
if has_git and has_uncommitted:
    suggestions.append(("Commit changes", "papy tool git add . && papy tool git commit 'update'"))
    suggestions.append(("Review diff", "papy tool git diff"))
if has_git:
    suggestions.append(("Push to GitHub", "papy github push"))
    suggestions.append(("View git log", "papy tool git log 10"))

# Project-based
if project_type == "nodejs":
    suggestions += [
        ("Run tests", "npm test"),
        ("Security audit", "npm audit"),
        ("Check outdated", "npm outdated"),
    ]
elif project_type == "python":
    suggestions += [
        ("Run tests", "python3 -m pytest"),
        ("List packages", "papy tool python pip list"),
        ("Check syntax", "python3 -m py_compile *.py 2>&1"),
    ]
elif project_type == "android":
    suggestions += [
        ("Build APK", "papy apk build ."),
        ("Check ADB devices", "papy adb devices"),
        ("Deploy APK", "papy apk deploy app-debug.apk"),
    ]

# Error-based
if recent_errors:
    suggestions.insert(0, ("Fix errors (health check)", "papy health"))
    suggestions.insert(1, ("View recent logs", "tail -30 ~/.kiro/logs/nation-agent.log"))

# Context-based
ctx_lower = context.lower()
if any(w in ctx_lower for w in ["api","rest","http"]):
    suggestions += [("Test API endpoint", "papy tool rest ping <url>"), ("Start mock server", "papy tool rest mock 8080")]
if any(w in ctx_lower for w in ["database","db","sqlite"]):
    suggestions += [("Browse database", "papy tool sqlite tables <db>")]
if any(w in ctx_lower for w in ["deploy","release"]):
    suggestions += [("Tag release", "papy tool git tag v1.0.0"), ("Host APK", "papy apk host . 8080")]

# Always useful
suggestions += [
    ("Browse memory", "papy memory recall"),
    ("Get suggestions", "papy suggest --pick"),
    ("Open web UI", "papy web"),
    ("Run health check", "papy health"),
    ("Start Ollama", "papy ollama auto"),
    ("List skills", "papy skills list"),
]

# Deduplicate and limit to 8
seen_cmds = set()
unique = []
for label, cmd in suggestions:
    if cmd not in seen_cmds:
        seen_cmds.add(cmd)
        unique.append({"label": label, "cmd": cmd})
        if len(unique) >= 8: break

print(json.dumps(unique))
PYEOF
)

# ── Output modes ──────────────────────────────────────────────────────────

case "$MODE" in

  json)
    echo "$SUGGESTIONS"
    ;;

  print)
    echo "=== 💡 Suggested next tasks ==="
    echo "$SUGGESTIONS" | python3 -c "
import json, sys
items = json.load(sys.stdin)
for i, s in enumerate(items, 1):
    print(f'  {i}. {s[\"label\"]}: {s[\"cmd\"]}')
"
    echo ""
    echo "  Run interactively: papy suggest --pick"
    ;;

  pick)
    # Print suggestions and let user type a number to execute
    echo ""
    echo "=== 💡 Suggested next tasks — type number to run ==="
    echo ""
    ITEMS=$(echo "$SUGGESTIONS" | python3 -c "
import json, sys
items = json.load(sys.stdin)
for i, s in enumerate(items, 1):
    print(f'{i}|{s[\"label\"]}|{s[\"cmd\"]}')
")
    while IFS='|' read -r NUM LABEL CMD_ITEM; do
        printf "  ${NUM}) %-30s  %s\n" "$LABEL" "$CMD_ITEM"
    done <<< "$ITEMS"
    echo ""
    echo "  0) Cancel"
    echo ""
    read -rp "  Choose [0-8]: " CHOICE
    echo ""

    if [ "$CHOICE" = "0" ] || [ -z "$CHOICE" ]; then
        echo "Cancelled."
        exit 0
    fi

    # Find the selected command
    SELECTED_CMD=$(echo "$ITEMS" | awk -F'|' -v n="$CHOICE" 'NR==n {print $3}')
    if [ -z "$SELECTED_CMD" ]; then
        echo "Invalid choice."
        exit 1
    fi

    echo "Running: $SELECTED_CMD"
    echo ""
    eval "$SELECTED_CMD"
    ;;

  tui)
    # Arrow-key selector inside TUI
    if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        GOLD=$'\033[38;5;214m' CYAN=$'\033[38;5;51m' R=$'\033[0m' BOLD=$'\033[1m'
        SEL=$'\033[48;5;235m\033[38;5;214m'
    else
        GOLD='' CYAN='' R='' BOLD='' SEL=''
    fi

    # Build arrays
    mapfile -t LABELS < <(echo "$SUGGESTIONS" | python3 -c "import json,sys; [print(s['label']) for s in json.load(sys.stdin)]")
    mapfile -t CMDS   < <(echo "$SUGGESTIONS" | python3 -c "import json,sys; [print(s['cmd'])   for s in json.load(sys.stdin)]")
    TOTAL=${#LABELS[@]}
    SEL_IDX=0

    # Save/restore terminal
    OLD_STTY=$(stty -g 2>/dev/null || echo "")
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    tput civis 2>/dev/null || true
    tput smcup 2>/dev/null || true

    cleanup_tui() {
        [ -n "$OLD_STTY" ] && stty "$OLD_STTY" 2>/dev/null || stty sane 2>/dev/null || true
        tput cnorm 2>/dev/null || true
        tput rmcup 2>/dev/null || true
    }
    trap cleanup_tui EXIT INT TERM

    draw() {
        tput clear
        echo -e "${GOLD}${BOLD}  💡 Suggestions — ↑/↓ navigate · Enter run · q cancel${R}"
        echo -e "  $(printf '─%.0s' $(seq 1 50))"
        echo ""
        for ((i=0; i<TOTAL; i++)); do
            if [ $i -eq $SEL_IDX ]; then
                printf "${SEL}  ▶ %-28s  %s${R}\n" "${LABELS[$i]}" "${CMDS[$i]}"
            else
                printf "    %-28s  ${CYAN}%s${R}\n" "${LABELS[$i]}" "${CMDS[$i]}"
            fi
        done
        echo ""
        echo -e "  ${GOLD}▶${R} ${CMDS[$SEL_IDX]}"
    }

    while true; do
        draw
        IFS= read -r -s -n1 KEY 2>/dev/null || KEY=""
        if [ "$KEY" = $'\x1b' ]; then
            IFS= read -r -s -n2 SEQ -t 0.1 2>/dev/null || SEQ=""
            case "$SEQ" in
                '[A') KEY="UP"   ;;
                '[B') KEY="DOWN" ;;
            esac
        fi
        case "$KEY" in
            UP|k|K)   SEL_IDX=$(( SEL_IDX > 0 ? SEL_IDX - 1 : TOTAL - 1 )) ;;
            DOWN|j|J) SEL_IDX=$(( SEL_IDX < TOTAL-1 ? SEL_IDX + 1 : 0 )) ;;
            q|Q)      cleanup_tui; exit 0 ;;
            ""|$'\n'|$'\r')
                CMD_TO_RUN="${CMDS[$SEL_IDX]}"
                cleanup_tui
                echo "Running: $CMD_TO_RUN"
                echo ""
                eval "$CMD_TO_RUN"
                exit $?
                ;;
        esac
    done
    ;;

esac
