#!/bin/bash
# NATION AGENT — Behavior Configuration System
# Control exactly how the agent behaves.
# Usage: nation-config.sh <command> [key] [value]
# Commands:
#   set   <key> <value>     Set a config value
#   get   <key>             Get a config value
#   list                    List all config values
#   reset [key]             Reset to defaults (key or all)
#   show                    Show current config in readable format
#   edit                    Open config in editor
#   import <file>           Import config from JSON file
#   export [file]           Export config to JSON
#
# Config keys:
#   agent.name              Agent display name (default: NATION AGENT)
#   agent.wake_word         Wake word (default: hey papy)
#   agent.language          Language (default: en)
#   speech.enabled          Enable TTS (default: true)
#   speech.voice            TTS voice/engine
#   speech.welcome          Welcome message text
#   speech.rate             Speech rate (default: 150)
#   voice.enabled           Enable voice listener (default: false)
#   voice.model             Vosk model path
#   auto_save.enabled       Auto-save (default: true)
#   auto_save.interval      Seconds between saves (default: 60)
#   messaging.telegram      Telegram enabled (default: false)
#   messaging.whatsapp      WhatsApp enabled (default: false)
#   ollama.model            Default Ollama model
#   ollama.auto_start       Start Ollama on launch (default: true)
#   adb.auto_connect        Auto-connect ADB wireless (default: true)
#   suggest.enabled         Show suggestions (default: true)
#   suggest.on_spawn        Show on startup (default: true)
#   theme.color             Banner color scheme (default: gold)
set -uo pipefail

CONFIG_FILE="${HOME}/.kiro/config/nation.conf"
mkdir -p "$(dirname "$CONFIG_FILE")"

CMD="${1:-show}"

# ── Defaults ──────────────────────────────────────────────────────────────
declare -A DEFAULTS=(
    ["agent.name"]="NATION AGENT"
    ["agent.wake_word"]="hey papy"
    ["agent.language"]="en"
    ["speech.enabled"]="true"
    ["speech.voice"]="auto"
    ["speech.welcome"]="Welcome back. NATION AGENT is online and ready."
    ["speech.rate"]="150"
    ["voice.enabled"]="false"
    ["voice.model"]="auto"
    ["auto_save.enabled"]="true"
    ["auto_save.interval"]="60"
    ["messaging.telegram"]="false"
    ["messaging.whatsapp"]="false"
    ["ollama.model"]="llama3.2"
    ["ollama.auto_start"]="true"
    ["adb.auto_connect"]="true"
    ["suggest.enabled"]="true"
    ["suggest.on_spawn"]="true"
    ["theme.color"]="gold"
)

# ── Config read/write via Python ──────────────────────────────────────────
conf_get() {
    local KEY="$1"
    python3 - "$CONFIG_FILE" "$KEY" "${DEFAULTS[$KEY]:-}" << 'PYEOF'
import sys, json, os
cfg_file, key, default = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
try:
    with open(cfg_file) as f: cfg = json.load(f)
    print(cfg.get(key, default))
except:
    print(default)
PYEOF
}

conf_set() {
    local KEY="$1" VAL="$2"
    python3 - "$CONFIG_FILE" "$KEY" "$VAL" << 'PYEOF'
import sys, json, os
cfg_file, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = {}
try:
    with open(cfg_file) as f: cfg = json.load(f)
except: pass
cfg[key] = val
with open(cfg_file, 'w') as f: json.dump(cfg, f, indent=2)
print(f"Set: {key} = {val}")
PYEOF
}

conf_list() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import sys, json, os
cfg_file = sys.argv[1]
cfg = {}
try:
    with open(cfg_file) as f: cfg = json.load(f)
except: pass
DEFAULTS = {
    "agent.name":"NATION AGENT","agent.wake_word":"hey papy","agent.language":"en",
    "speech.enabled":"true","speech.voice":"auto","speech.rate":"150",
    "speech.welcome":"Welcome back. NATION AGENT is online and ready.",
    "voice.enabled":"false","voice.model":"auto",
    "auto_save.enabled":"true","auto_save.interval":"60",
    "messaging.telegram":"false","messaging.whatsapp":"false",
    "ollama.model":"llama3.2","ollama.auto_start":"true",
    "adb.auto_connect":"true","suggest.enabled":"true","suggest.on_spawn":"true",
    "theme.color":"gold"
}
all_keys = sorted(set(list(DEFAULTS.keys()) + list(cfg.keys())))
prev_section = ""
for key in all_keys:
    section = key.split('.')[0]
    if section != prev_section:
        print(f"\n  [{section}]")
        prev_section = section
    val = cfg.get(key, DEFAULTS.get(key,''))
    origin = "" if key in cfg else " (default)"
    print(f"    {key:<30} = {val}{origin}")
PYEOF
}

case "$CMD" in

  set)
    [ -n "${2:-}" ] || { echo "Key required"; exit 1; }
    [ -n "${3:-}" ] || { echo "Value required"; exit 1; }
    conf_set "$2" "$3"
    # Apply immediately for some keys
    case "$2" in
      ollama.model)
        echo "${3}" > "${HOME}/.kiro/ollama.default"
        ;;
      auto_save.interval)
        export AUTOSAVE_INTERVAL="$3"
        ;;
      agent.wake_word)
        echo "Wake word updated. Restart voice listener: papy voice restart"
        ;;
      speech.welcome)
        echo "Welcome message updated. Test: papy speech welcome"
        ;;
    esac
    ;;

  get)
    [ -n "${2:-}" ] || { echo "Key required"; exit 1; }
    conf_get "$2"
    ;;

  list)
    echo "=== NATION AGENT Configuration ==="
    conf_list
    echo ""
    echo "  Config file: $CONFIG_FILE"
    echo "  Change with: papy config set <key> <value>"
    ;;

  show)
    echo "=== NATION AGENT Active Config ==="
    conf_list
    ;;

  reset)
    KEY="${2:-}"
    if [ -n "$KEY" ]; then
        python3 - "$CONFIG_FILE" "$KEY" << 'PYEOF'
import sys, json
cfg_file, key = sys.argv[1], sys.argv[2]
try:
    with open(cfg_file) as f: cfg = json.load(f)
    cfg.pop(key, None)
    with open(cfg_file, 'w') as f: json.dump(cfg, f, indent=2)
    print(f"Reset: {key}")
except: print(f"Key not found: {key}")
PYEOF
    else
        echo "{}" > "$CONFIG_FILE"
        echo "All config reset to defaults."
    fi
    ;;

  edit)
    EDITOR="${EDITOR:-nano}"
    "$EDITOR" "$CONFIG_FILE"
    ;;

  import)
    [ -n "${2:-}" ] || { echo "File required"; exit 1; }
    [ -f "$2" ] || { echo "File not found: $2"; exit 1; }
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak" 2>/dev/null || true
    python3 - "$CONFIG_FILE" "$2" << 'PYEOF'
import sys, json
cfg_file, src = sys.argv[1], sys.argv[2]
with open(src) as f: new = json.load(f)
cfg = {}
try:
    with open(cfg_file) as f: cfg = json.load(f)
except: pass
cfg.update(new)
with open(cfg_file,'w') as f: json.dump(cfg, f, indent=2)
print(f"Imported {len(new)} settings from {src}")
PYEOF
    ;;

  export)
    OUT="${2:-}"
    if [ -n "$OUT" ]; then
        cp "$CONFIG_FILE" "$OUT" && echo "Exported to: $OUT"
    else
        cat "$CONFIG_FILE" 2>/dev/null | python3 -m json.tool || echo "{}"
    fi
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-config.sh help" ;;
esac
