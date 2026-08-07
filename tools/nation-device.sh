#!/bin/bash
# NATION AGENT — Device Control
# Full Android/Linux device control via Termux API and ADB.
# Usage: nation-device.sh <command> [args...]
# Commands:
#   info                    Show device info (battery, network, location)
#   battery                 Battery status
#   brightness <0-255>      Set screen brightness
#   volume <0-15> [stream]  Set volume (music/alarm/ring)
#   wifi [on|off|info]      WiFi control
#   bluetooth [on|off|scan] Bluetooth control
#   screen [on|off|lock]    Screen control
#   clipboard [get|set txt] Clipboard access
#   camera [photo|video]    Take photo or video
#   location                Get GPS location
#   contacts [list|search]  Access contacts
#   sms list                List recent SMS
#   files <path>            Browse files
#   run <app>               Run an app/command
#   toast <message>         Show toast notification
#   keyevent <code>         Send key event
#   input <text>            Type text on device
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-info}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [DEVICE] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Try ADB if available
ADB=""
for p in "$(command -v adb 2>/dev/null)" "$HOME/platform-tools/adb"; do
    [ -x "${p:-}" ] && ADB="$p" && break
done

termux_api() { command -v "termux-$1" &>/dev/null; }

case "$CMD" in

  info)
    log "info"
    echo "=== Device Info ==="
    termux_api "battery-status" && termux-battery-status 2>/dev/null || true
    echo ""
    termux_api "wifi-connectioninfo" && echo "--- WiFi ---" && termux-wifi-connectioninfo 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    echo ""
    if [ -n "$ADB" ]; then
        echo "--- ADB Info ---"
        "$ADB" shell getprop ro.product.model 2>/dev/null | xargs echo "Model:"
        "$ADB" shell getprop ro.build.version.release 2>/dev/null | xargs echo "Android:"
    fi
    ;;

  battery)
    log "battery"
    termux_api "battery-status" && termux-battery-status 2>/dev/null | python3 -m json.tool || \
    [ -n "$ADB" ] && "$ADB" shell dumpsys battery 2>/dev/null | grep -E "level|status|health" || \
    echo "Battery info not available"
    ;;

  brightness)
    [ -n "${2:-}" ] || die "Value 0-255 required"
    log "brightness $2"
    if [ -n "$ADB" ]; then
        "$ADB" shell settings put system screen_brightness "$2"
        echo "Brightness set to $2"
    elif [ -w "/sys/class/backlight" ]; then
        for f in /sys/class/backlight/*/brightness; do
            echo "$2" > "$f" 2>/dev/null || true
        done
        echo "Brightness set to $2"
    else
        echo "Cannot set brightness without ADB or root"
    fi
    ;;

  volume)
    [ -n "${2:-}" ] || die "Value 0-15 required"
    VOL="$2"; STREAM="${3:-music}"
    log "volume $VOL ($STREAM)"
    STREAM_ID=3  # music
    case "$STREAM" in alarm) STREAM_ID=4 ;; ring) STREAM_ID=2 ;; notification) STREAM_ID=5 ;; esac
    if [ -n "$ADB" ]; then
        "$ADB" shell media volume --stream "$STREAM_ID" --set "$VOL" 2>/dev/null && \
            echo "Volume ($STREAM) set to $VOL" || echo "Volume control failed"
    elif termux_api "volume"; then
        termux-volume "$STREAM" "$VOL" 2>/dev/null && echo "Volume set to $VOL" || \
            echo "Volume not available"
    else
        echo "Volume control requires ADB"
    fi
    ;;

  wifi)
    SUBCMD="${2:-info}"
    log "wifi $SUBCMD"
    case "$SUBCMD" in
      info)
        termux_api "wifi-connectioninfo" && termux-wifi-connectioninfo 2>/dev/null | python3 -m json.tool || \
        [ -n "$ADB" ] && "$ADB" shell dumpsys wifi 2>/dev/null | grep -E "mWifiInfo|SSID" | head -5 || \
        ip addr show wlan0 2>/dev/null | head -10 || echo "WiFi info not available"
        ;;
      on)
        [ -n "$ADB" ] && "$ADB" shell svc wifi enable 2>/dev/null && echo "WiFi enabled" || \
            echo "WiFi control requires ADB"
        ;;
      off)
        [ -n "$ADB" ] && "$ADB" shell svc wifi disable 2>/dev/null && echo "WiFi disabled" || \
            echo "WiFi control requires ADB"
        ;;
      scan)
        termux_api "wifi-scaninfo" && termux-wifi-scaninfo 2>/dev/null | python3 -c "
import json,sys
nets=json.load(sys.stdin)
for n in nets[:20]: print(f'  {n.get(\"ssid\",\"?\"):30} {n.get(\"rssi\",\"?\")}dBm')
" 2>/dev/null || echo "WiFi scan not available"
        ;;
    esac
    ;;

  bluetooth)
    SUBCMD="${2:-status}"
    log "bluetooth $SUBCMD"
    case "$SUBCMD" in
      status|info)
        termux_api "bluetooth-connect" && echo "Bluetooth: available" || echo "Bluetooth: not available"
        [ -n "$ADB" ] && "$ADB" shell settings get global bluetooth_on 2>/dev/null | xargs echo "State:" || true
        ;;
      on)
        [ -n "$ADB" ] && "$ADB" shell am broadcast -a android.bluetooth.adapter.action.REQUEST_ENABLE 2>/dev/null && \
            echo "Bluetooth enable requested" || echo "BT control requires ADB"
        ;;
      off)
        [ -n "$ADB" ] && "$ADB" shell am broadcast -a android.bluetooth.adapter.action.REQUEST_DISABLE 2>/dev/null && \
            echo "Bluetooth disable requested" || echo "BT control requires ADB"
        ;;
    esac
    ;;

  screen)
    SUBCMD="${2:-status}"
    log "screen $SUBCMD"
    case "$SUBCMD" in
      on)
        termux_api "turn-screen-on" && termux-turn-screen-on 2>/dev/null && echo "Screen on" || \
        [ -n "$ADB" ] && "$ADB" shell input keyevent 26 2>/dev/null && echo "Screen on" || \
            echo "Screen control not available"
        ;;
      off)
        termux_api "turn-screen-off" && termux-turn-screen-off 2>/dev/null && echo "Screen off" || \
        [ -n "$ADB" ] && "$ADB" shell input keyevent 26 2>/dev/null && echo "Screen toggled" || \
            echo "Screen control not available"
        ;;
      lock)
        [ -n "$ADB" ] && "$ADB" shell input keyevent 82 2>/dev/null && echo "Screen locked" || \
        termux_api "turn-screen-off" && termux-turn-screen-off 2>/dev/null || \
            echo "Lock not available"
        ;;
    esac
    ;;

  clipboard)
    SUBCMD="${2:-get}"
    case "$SUBCMD" in
      get)
        log "clipboard get"
        termux_api "clipboard-get" && termux-clipboard-get 2>/dev/null || \
        [ -n "$ADB" ] && "$ADB" shell am broadcast -a clipper.GET 2>/dev/null || \
            echo "Clipboard not available"
        ;;
      set)
        shift 2
        TEXT="$*"
        log "clipboard set"
        termux_api "clipboard-set" && echo "$TEXT" | termux-clipboard-set 2>/dev/null && echo "Clipboard set" || \
        [ -n "$ADB" ] && "$ADB" shell am broadcast -a clipper.SET --es text "$TEXT" 2>/dev/null || \
            echo "Clipboard set not available"
        ;;
    esac
    ;;

  camera)
    SUBCMD="${2:-photo}"
    OUTFILE="${3:-$HOME/nation_$(date +%Y%m%d_%H%M%S)}"
    log "camera $SUBCMD"
    case "$SUBCMD" in
      photo)
        OUTFILE="${OUTFILE}.jpg"
        termux_api "camera-photo" && termux-camera-photo -c 0 "$OUTFILE" 2>/dev/null && \
            echo "Photo saved: $OUTFILE" || echo "Camera not available"
        ;;
      video)
        echo "Video recording: use ADB screenrecord"
        [ -n "$ADB" ] && "$ADB" shell screenrecord "${OUTFILE}.mp4" || echo "Video not available"
        ;;
    esac
    ;;

  location)
    log "location"
    termux_api "location" && termux-location 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f'Lat: {d.get(\"latitude\",\"?\")}')
print(f'Lon: {d.get(\"longitude\",\"?\")}')
print(f'Alt: {d.get(\"altitude\",\"?\")}m')
print(f'https://maps.google.com/?q={d.get(\"latitude\")},{d.get(\"longitude\")}')
" 2>/dev/null || echo "Location not available (enable in Termux:API)"
    ;;

  contacts)
    log "contacts ${2:-list}"
    termux_api "contact-list" && {
        if [ "${2:-list}" = "search" ] && [ -n "${3:-}" ]; then
            termux-contact-list 2>/dev/null | python3 -c "
import json,sys; q=sys.argv[1]
cs=json.load(sys.stdin)
for c in cs:
    name=c.get('name','')
    if q.lower() in name.lower():
        print(f'{name}: {c.get(\"number\",\"?\")}')
" "$3" 2>/dev/null || echo "No matches"
        else
            termux-contact-list 2>/dev/null | python3 -c "
import json,sys
for c in json.load(sys.stdin)[:30]:
    print(f'{c.get(\"name\",\"?\"):30} {c.get(\"number\",\"?\")}')
" 2>/dev/null | head -30
        fi
    } || echo "Contacts not available"
    ;;

  sms)
    log "sms list"
    termux_api "sms-list" && termux-sms-list -l 20 2>/dev/null | python3 -c "
import json,sys
msgs=json.load(sys.stdin)
for m in msgs[:20]:
    print(f'[{m.get(\"received\",\"?\")[:16]}] {m.get(\"address\",\"?\"):15} {m.get(\"body\",\"\")[:60]}')
" 2>/dev/null || echo "SMS not available"
    ;;

  toast)
    shift
    MSG="$*"
    log "toast: $MSG"
    termux_api "toast" && termux-toast -s "$MSG" 2>/dev/null && echo "Toast shown" || \
    command -v notify-send &>/dev/null && notify-send "NATION AGENT" "$MSG" || \
        echo "Toast: $MSG"
    ;;

  keyevent)
    [ -n "${2:-}" ] || die "Key code required"
    log "keyevent $2"
    [ -n "$ADB" ] && "$ADB" shell input keyevent "$2" && echo "Key event sent: $2" || \
        echo "keyevent requires ADB"
    ;;

  input)
    shift
    TEXT="$*"
    log "input text"
    [ -n "$ADB" ] && "$ADB" shell input text "${TEXT// /%s}" && echo "Input typed" || \
        echo "Text input requires ADB"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-device.sh help" ;;
esac
