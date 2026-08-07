#!/bin/bash
# NATION AGENT — Shizuku / ADB Wireless Manager
# Manages Shizuku API access and ADB wireless connections.
#
# Usage: nation-shizuku.sh <command> [args...]
#
# Commands:
#   status              Check Shizuku and ADB wireless status
#   auto                Auto-detect and connect best available method
#   wireless [ip] [port] Connect ADB over WiFi (auto-detect IP if blank)
#   pair     <ip:port> <code>  Pair new device (Android 11+)
#   disconnect          Disconnect all wireless ADB
#   shizuku-check       Check if Shizuku is running
#   shizuku-start       Start Shizuku user service
#   run      <cmd>      Run command via best available method
#   scan                Scan network for ADB devices
#   save     <ip>       Save a device IP for auto-reconnect
#   saved               Show saved device IPs
#   reconnect           Reconnect to all saved devices
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-auto}"
MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
SAVED_DEVICES="${NATION_DIR:-$HOME/.kiro}/.adb_devices"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [SHIZUKU] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Find ADB binary
ADB=""
for p in "$(command -v adb 2>/dev/null)" "$HOME/platform-tools/adb" \
          "/data/data/com.termux/files/usr/bin/adb"; do
    [ -x "$p" ] && ADB="$p" && break
done

has_adb() { [ -n "$ADB" ]; }

# Check Shizuku availability
has_shizuku() {
    # Shizuku broadcasts on Android
    [ "${NATION_ANDROID:-0}" = "1" ] || return 1
    ls /data/user/0/moe.shizuku.privileged.api/ &>/dev/null 2>&1 || \
    ls /data/user_de/0/moe.shizuku.privileged.api/ &>/dev/null 2>&1 || \
    command -v shizuku &>/dev/null || \
    [ -f "/data/data/moe.shizuku.privileged.api/files/starter" ]
}

# Get local network IP
get_local_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1 || \
    ip addr show wlan0 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1 || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    echo ""
}

# Get device network IP from ADB
get_device_ip() {
    has_adb || return 1
    "$ADB" shell ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 || \
    "$ADB" shell ifconfig wlan0 2>/dev/null | grep -oP 'inet addr:\K[0-9.]+' | head -1 || \
    echo ""
}

case "$CMD" in

  status)
    log "status"
    echo "=== Shizuku / ADB Wireless Status ==="
    echo ""

    # ADB check
    if has_adb; then
        echo "ADB binary: $ADB"
        echo "ADB version: $("$ADB" version 2>/dev/null | head -1)"
        echo ""
        echo "Connected devices:"
        "$ADB" devices -l 2>/dev/null || echo "  (none)"
    else
        echo "ADB: not installed"
        echo "  Install: nation-adb.sh install-tools"
    fi

    echo ""
    # Shizuku check
    if has_shizuku; then
        echo "Shizuku: AVAILABLE"
    else
        echo "Shizuku: not detected"
        echo "  (Shizuku app required on Android for root-free ADB)"
    fi

    echo ""
    # Saved devices
    if [ -f "$SAVED_DEVICES" ] && [ -s "$SAVED_DEVICES" ]; then
        echo "Saved devices:"
        while IFS= read -r ip; do
            [ -n "$ip" ] && echo "  - $ip"
        done < "$SAVED_DEVICES"
    else
        echo "Saved devices: none"
        echo "  Save with: papy shizuku save <ip>"
    fi
    ;;

  auto)
    log "auto"
    CONNECTED=0

    # Try to reconnect saved devices first
    if [ -f "$SAVED_DEVICES" ] && [ -s "$SAVED_DEVICES" ] && has_adb; then
        echo "Trying saved ADB devices..."
        while IFS= read -r ip; do
            [ -z "$ip" ] && continue
            if "$ADB" connect "$ip" 2>/dev/null | grep -q "connected"; then
                echo "  ✓ Reconnected: $ip"
                CONNECTED=1
            fi
        done < "$SAVED_DEVICES"
    fi

    # Check if USB device connected
    if has_adb; then
        USB_DEVICES=$("$ADB" devices 2>/dev/null | grep -c "device$" || echo 0)
        if [ "$USB_DEVICES" -gt 0 ]; then
            echo "USB device connected — attempting wireless..."
            DEVICE_IP=$(get_device_ip)
            if [ -n "$DEVICE_IP" ]; then
                "$ADB" tcpip 5555 2>/dev/null || true
                sleep 1
                if "$ADB" connect "${DEVICE_IP}:5555" 2>/dev/null | grep -q "connected"; then
                    echo "  ✓ ADB wireless enabled: $DEVICE_IP:5555"
                    # Save IP
                    grep -q "${DEVICE_IP}:5555" "$SAVED_DEVICES" 2>/dev/null || \
                        echo "${DEVICE_IP}:5555" >> "$SAVED_DEVICES"
                    CONNECTED=1
                fi
            fi
        fi
    fi

    if [ $CONNECTED -eq 1 ]; then
        echo "ADB wireless: READY"
        [ -x "$MEMORY" ] && "$MEMORY" log "adb-connected" "auto" 2>/dev/null || true
    else
        echo "ADB wireless: no devices (use USB first, then 'papy shizuku wireless')"
    fi
    ;;

  wireless)
    has_adb || die "ADB not installed. Run: papy adb install-tools"
    IP="${2:-}"
    PORT="${3:-5555}"

    if [ -z "$IP" ]; then
        # Try to auto-detect from connected USB device
        IP=$(get_device_ip)
        [ -n "$IP" ] || die "Cannot detect device IP. Connect via USB first, or pass IP manually."
        echo "Detected device IP: $IP"
    fi

    log "wireless $IP:$PORT"

    # Enable TCP/IP on the device (requires USB connection first)
    echo "Enabling ADB over TCP/IP on port $PORT..."
    "$ADB" tcpip "$PORT" 2>/dev/null || true
    sleep 2

    echo "Connecting to $IP:$PORT..."
    if "$ADB" connect "${IP}:${PORT}" 2>/dev/null | grep -q "connected"; then
        echo "✓ Connected: $IP:$PORT"
        # Save device
        grep -q "${IP}:${PORT}" "$SAVED_DEVICES" 2>/dev/null || \
            echo "${IP}:${PORT}" >> "$SAVED_DEVICES"
        [ -x "$MEMORY" ] && "$MEMORY" remember fact "adb.wireless" "${IP}:${PORT}" 2>/dev/null || true
    else
        echo "✗ Connection failed. Make sure device is on same network."
        echo "  Manual steps:"
        echo "  1. Connect device via USB"
        echo "  2. Enable ADB over WiFi in developer options"
        echo "  3. Or use: papy shizuku pair <ip:port> <code>"
    fi
    ;;

  pair)
    has_adb || die "ADB not installed"
    [ -n "${2:-}" ] || die "Usage: pair <ip:port> <pairing_code>"
    [ -n "${3:-}" ] || die "Pairing code required"
    log "pair $2"
    echo "Pairing with $2..."
    "$ADB" pair "$2" "$3"
    echo "After pairing, connect with: papy shizuku wireless <ip>"
    ;;

  disconnect)
    has_adb || die "ADB not installed"
    log "disconnect"
    "$ADB" disconnect
    echo "All ADB wireless connections closed."
    ;;

  shizuku-check)
    if has_shizuku; then
        echo "Shizuku: AVAILABLE"
    else
        echo "Shizuku: NOT FOUND"
        echo ""
        echo "To use Shizuku:"
        echo "  1. Install Shizuku from Play Store or GitHub"
        echo "  2. Start Shizuku via: ADB (papy adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh)"
        echo "  3. Or via USB debugging in developer options"
    fi
    ;;

  shizuku-start)
    has_adb || die "ADB not installed"
    log "shizuku-start"
    echo "Starting Shizuku user service..."
    "$ADB" shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh 2>/dev/null || \
    "$ADB" shell "am start -n moe.shizuku.privileged.api/.MainActivity" 2>/dev/null || \
    die "Could not start Shizuku. Install it first."
    ;;

  run)
    shift
    [ $# -gt 0 ] || die "Command required"
    CMD_TO_RUN="$*"
    log "run: $CMD_TO_RUN"

    if has_adb; then
        DEVICES=$("$ADB" devices 2>/dev/null | grep -c "device$" || echo 0)
        if [ "$DEVICES" -gt 0 ]; then
            echo "Running via ADB shell: $CMD_TO_RUN"
            "$ADB" shell "$CMD_TO_RUN"
            exit 0
        fi
    fi

    # Fallback: run locally
    echo "No ADB device — running locally"
    eval "$CMD_TO_RUN"
    ;;

  scan)
    log "scan"
    echo "Scanning for ADB devices on local network..."
    LOCAL_IP=$(get_local_ip)
    [ -n "$LOCAL_IP" ] || die "Cannot detect local IP"
    SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    echo "Subnet: $SUBNET.0/24"
    echo "Scanning ports 5555, 5556, 5037..."
    for i in $(seq 1 254); do
        IP="$SUBNET.$i"
        if timeout 0.5 bash -c "echo >/dev/tcp/$IP/5555" 2>/dev/null; then
            echo "  Found: $IP:5555"
        fi
    done
    echo "Scan complete."
    ;;

  save)
    [ -n "${2:-}" ] || die "IP:port required"
    grep -q "$2" "$SAVED_DEVICES" 2>/dev/null || echo "$2" >> "$SAVED_DEVICES"
    echo "Saved: $2"
    ;;

  saved)
    if [ -f "$SAVED_DEVICES" ] && [ -s "$SAVED_DEVICES" ]; then
        echo "Saved ADB devices:"
        cat "$SAVED_DEVICES"
    else
        echo "No saved devices."
    fi
    ;;

  reconnect)
    has_adb || die "ADB not installed"
    log "reconnect"
    [ -f "$SAVED_DEVICES" ] && [ -s "$SAVED_DEVICES" ] || die "No saved devices. Use: papy shizuku save <ip:port>"
    echo "Reconnecting to saved devices..."
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        RESULT=$("$ADB" connect "$ip" 2>/dev/null || echo "failed")
        echo "  $ip: $RESULT"
    done < "$SAVED_DEVICES"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) die "Unknown: $CMD. Run: nation-shizuku.sh help" ;;
esac
