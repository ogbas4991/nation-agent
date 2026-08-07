#!/bin/bash
# NATION AGENT — Browser / App Launcher
# Opens URLs, apps, and files automatically across platforms.
# Usage: nation-launch.sh <command> [args...]
# Commands:
#   url    <url>              Open URL in browser
#   app    <package|name>     Launch an Android app by package name
#   file   <path>             Open a file with default app
#   map    <address>          Open location in maps
#   call   <number>           Make a phone call
#   sms    <number> [msg]     Send SMS
#   email  <addr> [subject]   Open email composer
#   share  <text>             Share text via Android share sheet
#   notify <title> <body>     Show system notification
#   vibrate [ms]              Vibrate device
#   list                      List installed apps (Android)
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [LAUNCH] $*" >> "$LOG" 2>/dev/null || true; }

open_url() {
    local URL="$1"
    log "open url: $URL"
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "$URL" && return 0
    fi
    if command -v xdg-open &>/dev/null; then
        xdg-open "$URL" 2>/dev/null & return 0
    fi
    if command -v sensible-browser &>/dev/null; then
        sensible-browser "$URL" 2>/dev/null & return 0
    fi
    if command -v termux-open &>/dev/null; then
        termux-open "$URL" && return 0
    fi
    echo "Cannot open URL — no browser launcher found"
    echo "URL: $URL"
    return 1
}

case "$CMD" in

  url)
    [ -n "${2:-}" ] || { echo "URL required"; exit 1; }
    open_url "$2"
    echo "Opened: $2"
    ;;

  app)
    [ -n "${2:-}" ] || { echo "Package name required"; exit 1; }
    PKG="$2"
    log "launch app: $PKG"
    if command -v termux-open &>/dev/null; then
        # Try as an intent
        am start -n "$PKG" 2>/dev/null || \
        am start -a android.intent.action.MAIN -n "${PKG}/.MainActivity" 2>/dev/null || \
        termux-open "market://details?id=$PKG" 2>/dev/null || true
        echo "Launched: $PKG"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$PKG" 2>/dev/null & echo "Opened: $PKG"
    else
        echo "Cannot launch app on this platform"
    fi
    ;;

  file)
    [ -n "${2:-}" ] || { echo "File path required"; exit 1; }
    [ -e "$2" ] || { echo "File not found: $2"; exit 1; }
    log "open file: $2"
    if command -v termux-open &>/dev/null; then
        termux-open "$2"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$2" 2>/dev/null &
    else
        echo "Cannot open file on this platform"
    fi
    echo "Opened: $2"
    ;;

  map)
    [ -n "${2:-}" ] || { echo "Address required"; exit 1; }
    shift
    ADDR="$*"
    ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote_plus(sys.argv[1]))" "$ADDR")
    log "map: $ADDR"
    open_url "geo:0,0?q=$ENCODED"
    echo "Maps opened for: $ADDR"
    ;;

  call)
    [ -n "${2:-}" ] || { echo "Number required"; exit 1; }
    log "call: $2"
    if command -v termux-open-url &>/dev/null; then
        termux-open-url "tel:$2"
        echo "Calling: $2"
    else
        echo "Phone calls not supported on this platform"
    fi
    ;;

  sms)
    [ -n "${2:-}" ] || { echo "Number required"; exit 1; }
    NUM="$2"
    MSG="${3:-}"
    log "sms: $NUM"
    if command -v termux-open-url &>/dev/null; then
        ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$MSG" 2>/dev/null || echo "")
        termux-open-url "sms:$NUM?body=$ENCODED"
        echo "SMS to: $NUM"
    else
        echo "SMS not supported on this platform"
    fi
    ;;

  email)
    [ -n "${2:-}" ] || { echo "Email address required"; exit 1; }
    ADDR="$2"
    SUBJ="${3:-}"
    log "email: $ADDR"
    ENCODED_SUBJ=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SUBJ" 2>/dev/null || echo "")
    open_url "mailto:$ADDR?subject=$ENCODED_SUBJ"
    echo "Email to: $ADDR"
    ;;

  share)
    shift
    TEXT="$*"
    log "share: $TEXT"
    if command -v termux-share &>/dev/null; then
        echo "$TEXT" | termux-share -a send
    elif command -v termux-clipboard-set &>/dev/null; then
        echo "$TEXT" | termux-clipboard-set
        echo "Copied to clipboard: $TEXT"
    else
        echo "Share not available. Text: $TEXT"
    fi
    ;;

  notify)
    TITLE="${2:-NATION AGENT}"
    BODY="${3:-Notification}"
    log "notify: $TITLE — $BODY"
    if command -v termux-notification &>/dev/null; then
        termux-notification --title "$TITLE" --content "$BODY" --id 9001
        echo "Notification sent."
    else
        echo "[$TITLE] $BODY"
    fi
    ;;

  vibrate)
    MS="${2:-500}"
    log "vibrate ${MS}ms"
    command -v termux-vibrate &>/dev/null && \
        termux-vibrate -d "$MS" || echo "Vibrate not available"
    ;;

  list)
    log "list apps"
    if command -v pm &>/dev/null 2>&1; then
        pm list packages 2>/dev/null | sed 's/package://' | sort
    elif command -v termux-open &>/dev/null; then
        echo "App listing requires adb. Run: papy adb packages"
    else
        echo "App listing not available on this platform"
    fi
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-launch.sh help" ;;
esac
