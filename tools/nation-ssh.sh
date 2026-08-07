#!/bin/bash
# NATION AGENT — SSH Tool
# Usage: nation-ssh.sh <command> [args...]
#
# Commands:
#   connect  <host> [user] [port]         Open interactive SSH session
#   run      <host> <cmd> [user] [port]   Run single command over SSH
#   copy-to  <host> <local> <remote> [user] [port]   Copy file to remote (scp)
#   copy-from <host> <remote> <local> [user] [port]  Copy file from remote (scp)
#   tunnel   <host> <local_port> <remote_port> [user] [port]  SSH tunnel
#   keygen   [name] [type]                Generate SSH key pair
#   keys                                  List SSH keys in ~/.ssh/
#   config   [host]                       Show SSH config
#   known                                 List known hosts
#   test     <host> [user] [port]         Test SSH connectivity
#   add-host <host> <ip> [user] [port]    Add host to ~/.ssh/config
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [SSH] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v ssh &>/dev/null || die "ssh not installed. Install with: pkg install openssh"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)
SSH_CONFIG="$HOME/.ssh/config"
SSH_DIR="$HOME/.ssh"

ensure_ssh_dir() {
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
}

case "$CMD" in

  connect)
    [ -n "${2:-}" ] || die "Host required"
    HOST="$2"
    USER="${3:-}"
    PORT="${4:-22}"
    log "connect $HOST (user=${USER:-default} port=$PORT)"
    SSH_ARGS=(-p "$PORT" "${SSH_OPTS[@]//-o BatchMode=yes/}")
    if [ -n "$USER" ]; then
        SSH_ARGS+=("${USER}@${HOST}")
    else
        SSH_ARGS+=("$HOST")
    fi
    # Remove BatchMode for interactive sessions
    ssh -p "$PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        ${USER:+"${USER}@"}${HOST}
    ;;

  run)
    [ -n "${2:-}" ] || die "Host required"
    [ -n "${3:-}" ] || die "Command required"
    HOST="$2"
    REMOTE_CMD="$3"
    USER="${4:-}"
    PORT="${5:-22}"
    log "run on $HOST: $REMOTE_CMD"
    TARGET="${USER:+${USER}@}${HOST}"
    ssh "${SSH_OPTS[@]}" -p "$PORT" "$TARGET" "$REMOTE_CMD"
    ;;

  copy-to)
    [ -n "${2:-}" ] || die "Host required"
    [ -n "${3:-}" ] || die "Local path required"
    [ -n "${4:-}" ] || die "Remote path required"
    HOST="$2"
    LOCAL="$3"
    REMOTE="$4"
    USER="${5:-}"
    PORT="${6:-22}"
    [ -e "$LOCAL" ] || die "Local path not found: $LOCAL"
    log "copy-to $LOCAL -> $HOST:$REMOTE"
    TARGET="${USER:+${USER}@}${HOST}"
    scp -P "$PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -r "$LOCAL" "${TARGET}:${REMOTE}"
    echo "Copied: $LOCAL -> ${TARGET}:${REMOTE}"
    ;;

  copy-from)
    [ -n "${2:-}" ] || die "Host required"
    [ -n "${3:-}" ] || die "Remote path required"
    [ -n "${4:-}" ] || die "Local path required"
    HOST="$2"
    REMOTE="$3"
    LOCAL="$4"
    USER="${5:-}"
    PORT="${6:-22}"
    log "copy-from $HOST:$REMOTE -> $LOCAL"
    TARGET="${USER:+${USER}@}${HOST}"
    mkdir -p "$(dirname "$LOCAL")"
    scp -P "$PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -r "${TARGET}:${REMOTE}" "$LOCAL"
    echo "Copied: ${TARGET}:${REMOTE} -> $LOCAL"
    ;;

  tunnel)
    [ -n "${2:-}" ] || die "Host required"
    [ -n "${3:-}" ] || die "Local port required"
    [ -n "${4:-}" ] || die "Remote port required"
    HOST="$2"
    LOCAL_PORT="$3"
    REMOTE_PORT="$4"
    USER="${5:-}"
    PORT="${6:-22}"
    log "tunnel $LOCAL_PORT -> $HOST:$REMOTE_PORT"
    TARGET="${USER:+${USER}@}${HOST}"
    echo "SSH tunnel: localhost:$LOCAL_PORT -> $HOST:$REMOTE_PORT"
    echo "Press Ctrl+C to stop."
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -N -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" -p "$PORT" "$TARGET"
    ;;

  keygen)
    ensure_ssh_dir
    NAME="${2:-id_ed25519}"
    TYPE="${3:-ed25519}"
    KEY_PATH="$SSH_DIR/$NAME"
    log "keygen $KEY_PATH type=$TYPE"
    if [ -f "$KEY_PATH" ]; then
        die "Key already exists: $KEY_PATH. Delete it first or use a different name."
    fi
    ssh-keygen -t "$TYPE" -f "$KEY_PATH" -C "nation-agent@$(hostname)-$(date +%Y%m%d)" -N ""
    echo ""
    echo "Key pair generated:"
    echo "  Private: $KEY_PATH"
    echo "  Public : ${KEY_PATH}.pub"
    echo ""
    echo "Public key:"
    cat "${KEY_PATH}.pub"
    ;;

  keys)
    ensure_ssh_dir
    log "keys"
    echo "=== SSH Keys in $SSH_DIR ==="
    PUB_FILES=("$SSH_DIR"/*.pub)
    if [ -e "${PUB_FILES[0]}" ]; then
        for pubkey in "${PUB_FILES[@]}"; do
            echo ""
            echo "Key: $pubkey"
            ssh-keygen -l -f "$pubkey" 2>/dev/null || true
            cat "$pubkey"
        done
    else
        echo "No public keys found."
        echo "Generate one with: nation-ssh.sh keygen"
    fi
    ;;

  config)
    HOST_FILTER="${2:-}"
    log "config $HOST_FILTER"
    if [ ! -f "$SSH_CONFIG" ]; then
        echo "No SSH config found at $SSH_CONFIG"
        exit 0
    fi
    if [ -n "$HOST_FILTER" ]; then
        grep -A 20 "^Host $HOST_FILTER" "$SSH_CONFIG" | head -25 || echo "Host '$HOST_FILTER' not found in config"
    else
        cat "$SSH_CONFIG"
    fi
    ;;

  known)
    log "known"
    KNOWN="$SSH_DIR/known_hosts"
    if [ -f "$KNOWN" ]; then
        cat "$KNOWN"
    else
        echo "No known_hosts file found."
    fi
    ;;

  test)
    [ -n "${2:-}" ] || die "Host required"
    HOST="$2"
    USER="${3:-}"
    PORT="${4:-22}"
    TARGET="${USER:+${USER}@}${HOST}"
    log "test $TARGET:$PORT"
    echo "Testing SSH connectivity to $TARGET (port $PORT)..."
    if ssh "${SSH_OPTS[@]}" -p "$PORT" "$TARGET" "echo 'SSH OK'" 2>/dev/null; then
        echo "Connection: SUCCESS"
    else
        EXIT=$?
        echo "Connection: FAILED (exit $EXIT)"
        # Try without BatchMode to show real error
        ssh -p "$PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
            "$TARGET" "echo test" 2>&1 | head -5 || true
        exit $EXIT
    fi
    ;;

  add-host)
    ensure_ssh_dir
    [ -n "${2:-}" ] || die "Host alias required"
    [ -n "${3:-}" ] || die "Hostname/IP required"
    ALIAS="$2"
    HOSTNAME="$3"
    USER="${4:-}"
    PORT="${5:-22}"
    log "add-host $ALIAS -> $HOSTNAME"
    # Check for duplicate
    if grep -q "^Host $ALIAS$" "$SSH_CONFIG" 2>/dev/null; then
        die "Host '$ALIAS' already exists in $SSH_CONFIG"
    fi
    cat >> "$SSH_CONFIG" << EOF

Host $ALIAS
    HostName $HOSTNAME
    Port $PORT
${USER:+    User $USER
}    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    chmod 600 "$SSH_CONFIG"
    echo "Added host '$ALIAS' to $SSH_CONFIG"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-ssh.sh help"
    ;;
esac
