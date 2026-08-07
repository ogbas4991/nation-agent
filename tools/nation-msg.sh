#!/bin/bash
# NATION AGENT — Messaging Bridge (Telegram + WhatsApp)
# Usage: nation-msg.sh <command> [args...]
# Commands:
#   telegram send <chat_id> <message>    Send Telegram message
#   telegram bot                         Start Telegram bot listener
#   telegram status                      Check bot status
#   telegram setup <token>               Configure bot token
#   whatsapp send <number> <message>     Send WhatsApp message (requires Baileys)
#   whatsapp status                      WhatsApp connection status
#   whatsapp setup                       Setup WhatsApp connection
#   broadcast <message>                  Send to all configured channels
#   listen                               Listen for incoming messages
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
CONFIG_DIR="${NATION_DIR:-$HOME/.kiro}/config"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
MSG_LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-msg.log"
mkdir -p "$CONFIG_DIR" "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [MSG] $*" >> "$LOG" 2>/dev/null || true; }

get_tg_token() {
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && echo "$TELEGRAM_BOT_TOKEN" && return
    [ -f "$CONFIG_DIR/telegram.token" ] && cat "$CONFIG_DIR/telegram.token" && return
    echo ""
}

get_tg_chat() {
    [ -n "${TELEGRAM_CHAT_ID:-}" ] && echo "$TELEGRAM_CHAT_ID" && return
    [ -f "$CONFIG_DIR/telegram.chat_id" ] && cat "$CONFIG_DIR/telegram.chat_id" && return
    echo ""
}

case "$CMD" in

  telegram)
    SUBCMD="${2:-help}"
    case "$SUBCMD" in

      setup)
        TOKEN="${3:-}"
        if [ -z "$TOKEN" ]; then
            echo "Telegram Bot Setup"
            echo ""
            echo "1. Message @BotFather on Telegram"
            echo "2. Create a new bot: /newbot"
            echo "3. Copy the token (looks like: 1234567890:AAExxxxx)"
            echo ""
            read -rsp "Paste bot token: " TOKEN
            echo ""
        fi
        echo "$TOKEN" > "$CONFIG_DIR/telegram.token"
        chmod 600 "$CONFIG_DIR/telegram.token"
        # Persist to bashrc
        sed -i '/TELEGRAM_BOT_TOKEN/d' "$HOME/.bashrc" 2>/dev/null || true
        echo "export TELEGRAM_BOT_TOKEN=$TOKEN" >> "$HOME/.bashrc"
        export TELEGRAM_BOT_TOKEN="$TOKEN"

        # Get bot info
        INFO=$(curl -sf "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null) || true
        USERNAME=$(echo "$INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('result',{}).get('username','?'))" 2>/dev/null || echo "?")
        echo "Bot: @$USERNAME"
        echo "Token saved."

        # Auto-get chat ID
        echo ""
        echo "Now send any message to your bot @$USERNAME on Telegram..."
        echo "Waiting for first message (30s)..."
        for i in $(seq 1 6); do
            sleep 5
            UPDATES=$(curl -sf "https://api.telegram.org/bot${TOKEN}/getUpdates" 2>/dev/null || true)
            CHAT_ID=$(echo "$UPDATES" | python3 -c "
import json,sys
d=json.load(sys.stdin)
results=d.get('result',[])
if results: print(results[-1].get('message',{}).get('chat',{}).get('id',''))
" 2>/dev/null || echo "")
            if [ -n "$CHAT_ID" ]; then
                echo "$CHAT_ID" > "$CONFIG_DIR/telegram.chat_id"
                echo "export TELEGRAM_CHAT_ID=$CHAT_ID" >> "$HOME/.bashrc"
                echo "Chat ID saved: $CHAT_ID"
                [ -x "$MEMORY" ] && "$MEMORY" remember preference "telegram.chat_id" "$CHAT_ID" 2>/dev/null || true
                break
            fi
        done
        ;;

      send)
        TOKEN=$(get_tg_token)
        [ -n "$TOKEN" ] || { echo "Not configured. Run: papy msg telegram setup"; exit 1; }
        CHAT="${3:-$(get_tg_chat)}"
        [ -n "$CHAT" ] || { echo "Chat ID required. Run: papy msg telegram setup first"; exit 1; }
        shift 3 || shift $#
        TEXT="$*"
        log "telegram send to $CHAT"
        RESULT=$(curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
            -d "chat_id=$CHAT" \
            --data-urlencode "text=$TEXT" \
            --data-urlencode "parse_mode=Markdown" 2>/dev/null) || true
        OK=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ok',False))" 2>/dev/null || echo "False")
        [ "$OK" = "True" ] && echo "Sent to Telegram" || echo "Send failed: $RESULT"
        echo "[$TS] SENT telegram: $TEXT" >> "$MSG_LOG"
        ;;

      status)
        TOKEN=$(get_tg_token)
        [ -n "$TOKEN" ] || { echo "Telegram: NOT configured"; exit 0; }
        INFO=$(curl -sf "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null) || { echo "Telegram: ERROR (check token)"; exit 0; }
        echo "$INFO" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('result',{})
print(f'Telegram: ACTIVE')
print(f'Bot: @{d.get(\"username\",\"?\")} ({d.get(\"first_name\",\"?\")})')
" 2>/dev/null || echo "Telegram: parse error"
        CHAT=$(get_tg_chat)
        echo "Chat ID: ${CHAT:-not set}"
        ;;

      bot)
        TOKEN=$(get_tg_token)
        [ -n "$TOKEN" ] || { echo "Not configured. Run: papy msg telegram setup"; exit 1; }
        echo "Starting Telegram bot listener... (Ctrl+C to stop)"
        log "telegram bot started"
        python3 - "$TOKEN" "$CONFIG_DIR" << 'PYEOF'
import sys, json, time, subprocess, datetime, urllib.request, urllib.parse

TOKEN = sys.argv[1]
CONFIG_DIR = sys.argv[2]
TOOLS = f"{__import__('os').path.expanduser('~')}/.kiro/tools"
last_update = 0

def tg_api(method, **params):
    url = f"https://api.telegram.org/bot{TOKEN}/{method}"
    data = urllib.parse.urlencode(params).encode()
    try:
        with urllib.request.urlopen(url, data=data, timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"ok": False, "error": str(e)}

def handle_message(msg):
    chat_id = msg.get("chat", {}).get("id", "")
    text = msg.get("text", "").strip()
    username = msg.get("from", {}).get("username", "?")
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] @{username}: {text}")

    if not text:
        return

    # Route to papy/agent
    if text.startswith("/"):
        cmd = text[1:].strip()
        try:
            result = subprocess.run(
                f"papy {cmd}", shell=True,
                capture_output=True, text=True, timeout=15
            )
            reply = result.stdout[:3000] or result.stderr[:1000] or "Done"
        except Exception as e:
            reply = f"Error: {e}"
    else:
        # Send to Ollama
        try:
            import urllib.request as ur
            port_file = f"{__import__('os').path.expanduser('~')}/.kiro/ollama.port"
            port = open(port_file).read().strip() if __import__('os').path.isfile(port_file) else "11434"
            req_data = json.dumps({"model":"llama3.2","prompt":text,"stream":False}).encode()
            req = ur.Request(f"http://localhost:{port}/api/generate",
                             data=req_data, headers={"Content-Type":"application/json"})
            with ur.urlopen(req, timeout=30) as r:
                resp = json.loads(r.read())
                reply = resp.get("response", "No response")[:3000]
        except Exception as e:
            reply = f"(Ollama offline) You said: {text}"

    tg_api("sendMessage", chat_id=chat_id, text=reply, parse_mode="Markdown")

print("Bot listening...")
while True:
    result = tg_api("getUpdates", offset=last_update+1, timeout=20)
    if result.get("ok"):
        for update in result.get("result", []):
            last_update = update["update_id"]
            if "message" in update:
                handle_message(update["message"])
    time.sleep(1)
PYEOF
        ;;

      *) echo "Usage: papy msg telegram [setup|send|status|bot]" ;;
    esac
    ;;

  whatsapp)
    SUBCMD="${2:-status}"
    WA_DIR="${NATION_DIR:-$HOME/.kiro}/whatsapp"
    mkdir -p "$WA_DIR"

    case "$SUBCMD" in
      setup)
        echo "WhatsApp Setup via Baileys (Node.js)"
        command -v node &>/dev/null || { echo "Node.js required. Run: pkg install nodejs"; exit 1; }
        # Create Baileys bridge
        mkdir -p "$WA_DIR"
        cat > "$WA_DIR/bridge.js" << 'JSEOF'
const { default: makeWASocket, DisconnectReason, useMultiFileAuthState } = require('@whiskeysockets/baileys')
const { Boom } = require('@hapi/boom')
const path = require('path')
const fs = require('fs')
const readline = require('readline')

const AUTH_DIR = path.join(process.env.HOME, '.kiro/whatsapp/auth')
const MSG_QUEUE = path.join(process.env.HOME, '.kiro/whatsapp/queue.jsonl')

async function connectWA() {
    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR)
    const sock = makeWASocket({ auth: state, printQRInTerminal: true })

    sock.ev.on('creds.update', saveCreds)
    sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
        if (qr) console.log('Scan QR code above with WhatsApp')
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect?.error?.output?.statusCode !== DisconnectReason.loggedOut
            if (shouldReconnect) setTimeout(connectWA, 3000)
        }
        if (connection === 'open') {
            console.log('WhatsApp connected!')
            fs.writeFileSync(path.join(process.env.HOME, '.kiro/whatsapp/status'), 'connected')
        }
    })

    sock.ev.on('messages.upsert', async ({ messages }) => {
        for (const msg of messages) {
            if (!msg.message || msg.key.fromMe) continue
            const from = msg.key.remoteJid
            const text = msg.message.conversation || msg.message.extendedTextMessage?.text || ''
            console.log(`[WA] ${from}: ${text}`)
            fs.appendFileSync(MSG_QUEUE, JSON.stringify({from, text, ts: new Date().toISOString()}) + '\n')
        }
    })

    // Send queue processor
    setInterval(() => {
        const sendFile = path.join(process.env.HOME, '.kiro/whatsapp/send.jsonl')
        if (!fs.existsSync(sendFile)) return
        const lines = fs.readFileSync(sendFile, 'utf8').split('\n').filter(Boolean)
        fs.unlinkSync(sendFile)
        for (const line of lines) {
            try {
                const { to, text } = JSON.parse(line)
                const jid = to.includes('@') ? to : `${to}@s.whatsapp.net`
                sock.sendMessage(jid, { text })
            } catch(e) {}
        }
    }, 2000)
}

connectWA()
JSEOF
        cd "$WA_DIR" && npm init -y > /dev/null 2>&1
        npm install @whiskeysockets/baileys @hapi/boom 2>&1 | tail -3
        echo ""
        echo "Starting WhatsApp bridge — scan the QR code with your phone:"
        echo "(WhatsApp > Linked Devices > Link a Device)"
        node "$WA_DIR/bridge.js"
        ;;

      send)
        [ -n "${3:-}" ] || { echo "Number required (e.g. 15551234567)"; exit 1; }
        [ -n "${4:-}" ] || { echo "Message required"; exit 1; }
        TO="$3"; shift 3; MSG="$*"
        log "whatsapp send to $TO"
        WA_SEND="${WA_DIR}/send.jsonl"
        echo "{\"to\":\"$TO\",\"text\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$MSG")}" >> "$WA_SEND"
        echo "Queued WhatsApp to $TO"
        ;;

      status)
        STATUS_FILE="${WA_DIR}/status"
        if [ -f "$STATUS_FILE" ]; then
            echo "WhatsApp: $(cat "$STATUS_FILE")"
        else
            echo "WhatsApp: NOT connected (run: papy msg whatsapp setup)"
        fi
        ;;

      *) echo "Usage: papy msg whatsapp [setup|send|status]" ;;
    esac
    ;;

  broadcast)
    shift
    MSG="$*"
    [ -n "$MSG" ] || { echo "Message required"; exit 1; }
    log "broadcast: $MSG"
    echo "Broadcasting: $MSG"
    # Telegram
    TOKEN=$(get_tg_token)
    CHAT=$(get_tg_chat)
    if [ -n "$TOKEN" ] && [ -n "$CHAT" ]; then
        curl -sf "https://api.telegram.org/bot${TOKEN}/sendMessage" \
            -d "chat_id=$CHAT" \
            --data-urlencode "text=📢 $MSG" >/dev/null 2>&1 && \
            echo "  ✓ Telegram" || echo "  ✗ Telegram"
    fi
    # Notification
    command -v termux-notification &>/dev/null && \
        termux-notification --title "NATION AGENT" --content "$MSG" --id 9002 && \
        echo "  ✓ Device notification" || true
    echo "[$TS] BROADCAST: $MSG" >> "$MSG_LOG"
    ;;

  listen)
    log "listen mode"
    echo "Listening for messages... (Ctrl+C to stop)"
    QUEUE="${NATION_DIR:-$HOME/.kiro}/whatsapp/queue.jsonl"
    LAST_SIZE=0
    while true; do
        if [ -f "$QUEUE" ]; then
            CUR_SIZE=$(wc -c < "$QUEUE" 2>/dev/null || echo 0)
            if [ "$CUR_SIZE" -gt "$LAST_SIZE" ]; then
                tail -1 "$QUEUE" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
print(f'[WA] {d.get(\"from\",\"?\")} @ {d.get(\"ts\",\"?\")[:16]}: {d.get(\"text\",\"?\")}')
" 2>/dev/null || true
                LAST_SIZE=$CUR_SIZE
            fi
        fi
        sleep 2
    done
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-msg.sh help" ;;
esac
