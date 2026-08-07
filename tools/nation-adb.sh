#!/bin/bash
# NATION AGENT — ADB / Platform-Tools
# Manages Android Debug Bridge operations and platform-tools installation.
#
# Usage: nation-adb.sh <command> [args...]
#
# Commands:
#   install-tools              Download & install platform-tools (adb, fastboot)
#   devices                    List connected devices
#   shell     [cmd]            ADB shell (interactive or single command)
#   push      <local> <remote> Push file to device
#   pull      <remote> <local> Pull file from device
#   install   <apk>            Install APK on device
#   uninstall <package>        Uninstall app by package name
#   logcat    [filter]         Stream device logs
#   reboot    [bootloader|recovery] Reboot device
#   screenshot [file]          Take device screenshot
#   screenrecord [file] [secs] Record screen
#   packages  [filter]         List installed packages
#   forward   <local> <remote> Port forward
#   reverse   <local> <remote> Reverse port forward
#   wifi      <ip> [port]      Connect to device over WiFi
#   disconnect                 Disconnect all wireless
#   pair      <ip:port> <code> Pair with wireless device (Android 11+)
#   info                       Show device info
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [ADB] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo -e "${BRED:-}ERROR:${NC:-} $*" >&2; exit 1; }

# ── ADB locator ────────────────────────────────────────────────────────────
find_adb() {
    if [ "${NATION_HAS_ADB:-0}" = "1" ] && [ -n "${NATION_ADB:-}" ]; then
        echo "$NATION_ADB"; return 0
    fi
    for p in \
        "$(command -v adb 2>/dev/null)" \
        "$HOME/platform-tools/adb" \
        "/data/data/com.termux/files/usr/bin/adb" \
        "/usr/bin/adb" "/usr/local/bin/adb"; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    echo ""
}

ADB=$(find_adb)

require_adb() {
    [ -n "$ADB" ] || die "adb not found. Run: nation-adb.sh install-tools"
}

case "$CMD" in

  install-tools)
    log "install platform-tools"
    echo "Installing Android platform-tools (adb, fastboot)..."
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64) PT_ARCH="linux-aarch64" ; FALLBACK="arm64-v8a" ;;
        armv7l|armhf)  PT_ARCH="linux-arm"     ; FALLBACK="armeabi-v7a" ;;
        x86_64)        PT_ARCH="linux-x86_64"  ; FALLBACK="x86_64" ;;
        *)             PT_ARCH="linux-x86_64"  ; FALLBACK="x86_64" ;;
    esac

    # Try pkg install first (Termux)
    if [ "${NATION_TERMUX:-0}" = "1" ] || [ "${NATION_PROOT:-0}" = "0" ]; then
        if command -v pkg &>/dev/null; then
            echo "Trying: pkg install android-tools..."
            pkg install -y android-tools 2>/dev/null && {
                echo "Installed via pkg."
                ADB=$(command -v adb)
                echo "ADB: $ADB"
                exit 0
            } || echo "pkg install failed, trying manual download..."
        fi
    fi

    # Manual download from Google
    DEST="$HOME/platform-tools"
    mkdir -p "$DEST"
    URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    echo "Downloading from: $URL"
    curl -L --progress-bar -o /tmp/platform-tools.zip "$URL" || die "Download failed"
    echo "Extracting..."
    if command -v unzip &>/dev/null; then
        unzip -o /tmp/platform-tools.zip -d "$HOME/" > /dev/null
    else
        python3 -c "import zipfile,sys; zipfile.ZipFile('/tmp/platform-tools.zip').extractall('$HOME/')"
    fi
    chmod +x "$DEST"/adb "$DEST"/fastboot 2>/dev/null || true
    rm -f /tmp/platform-tools.zip

    # Add to PATH
    if ! grep -q "platform-tools" "${HOME}/.bashrc" 2>/dev/null; then
        echo "export PATH=\"\$PATH:\$HOME/platform-tools\"" >> "$HOME/.bashrc"
        echo "Added platform-tools to ~/.bashrc PATH"
    fi
    export PATH="$PATH:$DEST"
    ADB="$DEST/adb"

    echo ""
    echo "Platform-tools installed at: $DEST"
    "$ADB" version
    echo ""
    echo "Reload shell: source ~/.bashrc"
    ;;

  devices)
    require_adb
    log "devices"
    echo "=== Connected Android Devices ==="
    "$ADB" devices -l
    echo ""
    COUNT=$("$ADB" devices | grep -c "device$" 2>/dev/null || echo 0)
    echo "Devices online: $COUNT"
    ;;

  shell)
    require_adb
    shift
    log "shell $*"
    if [ $# -eq 0 ]; then
        "$ADB" shell
    else
        "$ADB" shell "$@"
    fi
    ;;

  push)
    require_adb
    [ -n "${2:-}" ] || die "Local path required"
    [ -n "${3:-}" ] || die "Remote path required"
    [ -e "$2" ] || die "Local file not found: $2"
    log "push $2 -> $3"
    "$ADB" push "$2" "$3"
    echo "Pushed: $2 -> $3"
    ;;

  pull)
    require_adb
    [ -n "${2:-}" ] || die "Remote path required"
    [ -n "${3:-}" ] || die "Local path required"
    log "pull $2 -> $3"
    mkdir -p "$(dirname "$3")"
    "$ADB" pull "$2" "$3"
    echo "Pulled: $2 -> $3"
    ;;

  install)
    require_adb
    [ -n "${2:-}" ] || die "APK path required"
    [ -f "$2" ] || die "APK not found: $2"
    log "install apk $2"
    echo "Installing: $2"
    "$ADB" install -r "$2"
    echo "Installation complete."
    ;;

  uninstall)
    require_adb
    [ -n "${2:-}" ] || die "Package name required (e.g. com.example.app)"
    log "uninstall $2"
    "$ADB" uninstall "$2"
    echo "Uninstalled: $2"
    ;;

  logcat)
    require_adb
    FILTER="${2:-}"
    log "logcat $FILTER"
    echo "Starting logcat (Ctrl+C to stop)..."
    if [ -n "$FILTER" ]; then
        "$ADB" logcat -v time "$FILTER"
    else
        "$ADB" logcat -v time
    fi
    ;;

  reboot)
    require_adb
    MODE="${2:-}"
    log "reboot $MODE"
    case "$MODE" in
        bootloader) "$ADB" reboot bootloader ;;
        recovery)   "$ADB" reboot recovery ;;
        "")         "$ADB" reboot ;;
        *)          die "Unknown mode: $MODE. Use: bootloader, recovery, or empty for normal reboot" ;;
    esac
    echo "Rebooting..."
    ;;

  screenshot)
    require_adb
    OUTFILE="${2:-screenshot_$(date +%Y%m%d_%H%M%S).png}"
    log "screenshot -> $OUTFILE"
    "$ADB" shell screencap -p /sdcard/nation_screenshot.png
    "$ADB" pull /sdcard/nation_screenshot.png "$OUTFILE"
    "$ADB" shell rm /sdcard/nation_screenshot.png
    echo "Screenshot saved: $OUTFILE"
    ;;

  screenrecord)
    require_adb
    OUTFILE="${2:-screenrecord_$(date +%Y%m%d_%H%M%S).mp4}"
    SECS="${3:-30}"
    log "screenrecord $OUTFILE ${SECS}s"
    echo "Recording screen for ${SECS}s (Ctrl+C to stop early)..."
    "$ADB" shell screenrecord --time-limit "$SECS" /sdcard/nation_rec.mp4
    "$ADB" pull /sdcard/nation_rec.mp4 "$OUTFILE"
    "$ADB" shell rm /sdcard/nation_rec.mp4
    echo "Recording saved: $OUTFILE"
    ;;

  packages)
    require_adb
    FILTER="${2:-}"
    log "packages $FILTER"
    if [ -n "$FILTER" ]; then
        "$ADB" shell pm list packages | grep "$FILTER" | sed 's/package://' | sort
    else
        "$ADB" shell pm list packages | sed 's/package://' | sort
    fi
    ;;

  forward)
    require_adb
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || die "Usage: forward <local_port> <remote_port>"
    log "forward $2 -> $3"
    "$ADB" forward "tcp:$2" "tcp:$3"
    echo "Port forward: localhost:$2 -> device:$3"
    ;;

  reverse)
    require_adb
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || die "Usage: reverse <device_port> <host_port>"
    log "reverse $2 -> $3"
    "$ADB" reverse "tcp:$2" "tcp:$3"
    echo "Reverse: device:$2 -> host:$3"
    ;;

  wifi)
    require_adb
    [ -n "${2:-}" ] || die "IP address required"
    IP="$2"
    PORT="${3:-5555}"
    log "wifi connect $IP:$PORT"
    "$ADB" connect "${IP}:${PORT}"
    echo "Connected to $IP:$PORT"
    ;;

  disconnect)
    require_adb
    log "disconnect all"
    "$ADB" disconnect
    ;;

  pair)
    require_adb
    [ -n "${2:-}" ] || die "IP:port required"
    [ -n "${3:-}" ] || die "Pairing code required"
    log "pair $2"
    "$ADB" pair "$2" "$3"
    ;;

  info)
    require_adb
    log "device info"
    echo "=== Device Information ==="
    echo "Model   : $("$ADB" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    echo "Brand   : $("$ADB" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')"
    echo "Android : $("$ADB" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
    echo "SDK     : $("$ADB" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    echo "Serial  : $("$ADB" get-serialno 2>/dev/null | tr -d '\r')"
    echo "Battery : $("$ADB" shell dumpsys battery 2>/dev/null | grep level | head -1 | tr -d ' \r')"
    echo ""
    echo "=== Storage ==="
    "$ADB" shell df /sdcard 2>/dev/null | tail -1 || echo "(not available)"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-adb.sh help"
    ;;
esac
