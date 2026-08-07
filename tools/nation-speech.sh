#!/bin/bash
# NATION AGENT — Speech / TTS System
# Text-to-speech, welcome messages, and audio feedback.
# Usage: nation-speech.sh <command> [args...]
# Commands:
#   speak   <text>          Speak text aloud
#   welcome                 Speak the configured welcome message
#   say     <text>          Alias for speak
#   tone    [type]          Play audio tone (start/success/error/alert)
#   test                    Test TTS with a sample message
#   engines                 List available TTS engines
#   set-engine <name>       Set preferred TTS engine
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-welcome}"
CONFIG="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-config.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$(dirname "$LOG")"
TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [SPEECH] $*" >> "$LOG" 2>/dev/null || true; }

get_cfg() { [ -x "$CONFIG" ] && "$CONFIG" get "$1" 2>/dev/null || echo "${2:-}"; }

SPEECH_ENABLED=$(get_cfg "speech.enabled" "true")
SPEECH_RATE=$(get_cfg "speech.rate" "150")
SPEECH_VOICE=$(get_cfg "speech.voice" "auto")

speak_text() {
    local TEXT="$1"
    [ "$SPEECH_ENABLED" = "false" ] && return 0
    [ -z "$TEXT" ] && return 0
    log "speak: $TEXT"

    # Priority order: termux-tts > espeak-ng > espeak > festival > pyttsx3 > gtts > say(mac)
    if command -v termux-tts-speak &>/dev/null; then
        termux-tts-speak "$TEXT" 2>/dev/null &
        return 0
    fi
    if command -v espeak-ng &>/dev/null; then
        espeak-ng -s "$SPEECH_RATE" -v "${SPEECH_VOICE:-en}" "$TEXT" 2>/dev/null &
        return 0
    fi
    if command -v espeak &>/dev/null; then
        espeak -s "$SPEECH_RATE" "$TEXT" 2>/dev/null &
        return 0
    fi
    if command -v festival &>/dev/null; then
        echo "$TEXT" | festival --tts 2>/dev/null &
        return 0
    fi
    if python3 -c "import pyttsx3" 2>/dev/null; then
        python3 -c "
import pyttsx3, sys
e=pyttsx3.init()
e.setProperty('rate',int('$SPEECH_RATE'))
e.say(sys.argv[1])
e.runAndWait()
" "$TEXT" 2>/dev/null &
        return 0
    fi
    if python3 -c "import gtts" 2>/dev/null && command -v ffplay &>/dev/null; then
        python3 -c "
import gtts, sys, tempfile, os
t=gtts.gTTS(sys.argv[1])
f=tempfile.mktemp(suffix='.mp3')
t.save(f)
os.system(f'ffplay -nodisp -autoexit {f} 2>/dev/null')
os.unlink(f)
" "$TEXT" 2>/dev/null &
        return 0
    fi
    if [ "$(uname)" = "Darwin" ] && command -v say &>/dev/null; then
        say "$TEXT" 2>/dev/null &
        return 0
    fi
    # Fallback: just print
    echo "[SPEECH] $TEXT"
}

play_tone() {
    local TYPE="${1:-start}"
    command -v termux-vibrate &>/dev/null && {
        case "$TYPE" in
            start)   termux-vibrate -d 200 2>/dev/null ;;
            success) termux-vibrate -d 100 2>/dev/null; sleep 0.1; termux-vibrate -d 100 2>/dev/null ;;
            error)   termux-vibrate -d 500 2>/dev/null ;;
            alert)   termux-vibrate -d 300 2>/dev/null ;;
        esac
    }
    # Audio tone via sox if available
    command -v play &>/dev/null && {
        case "$TYPE" in
            start)   play -q -n synth 0.2 sine 880 2>/dev/null & ;;
            success) play -q -n synth 0.1 sine 1200 : synth 0.1 sine 1600 2>/dev/null & ;;
            error)   play -q -n synth 0.3 sine 400 2>/dev/null & ;;
        esac
    }
}

case "$CMD" in

  speak|say)
    shift
    TEXT="$*"
    [ -n "$TEXT" ] || { echo "Text required"; exit 1; }
    speak_text "$TEXT"
    echo "Speaking: $TEXT"
    ;;

  welcome)
    WELCOME=$(get_cfg "speech.welcome" "Welcome back. NATION AGENT is online and ready.")
    USER_NAME=$(get_cfg "agent.name" "")
    HOUR=$(date +%H)
    GREETING="Good morning"
    [ "$HOUR" -ge 12 ] && GREETING="Good afternoon"
    [ "$HOUR" -ge 17 ] && GREETING="Good evening"
    [ "$HOUR" -ge 21 ] && GREETING="Good night"
    FULL_MSG="${GREETING}. ${WELCOME}"
    log "welcome"
    play_tone start
    speak_text "$FULL_MSG"
    echo "$FULL_MSG"
    ;;

  tone)
    TYPE="${2:-start}"
    log "tone $TYPE"
    play_tone "$TYPE"
    echo "Tone: $TYPE"
    ;;

  test)
    log "test"
    echo "Testing TTS engines..."
    speak_text "NATION AGENT speech test. Hello, I am ready."
    echo "Test message sent to TTS engine."
    ;;

  engines)
    echo "=== Available TTS Engines ==="
    command -v termux-tts-speak &>/dev/null && echo "  ✓ termux-tts (Termux:API)" || echo "  ✗ termux-tts"
    command -v espeak-ng        &>/dev/null && echo "  ✓ espeak-ng" || echo "  ✗ espeak-ng"
    command -v espeak           &>/dev/null && echo "  ✓ espeak"    || echo "  ✗ espeak"
    command -v festival         &>/dev/null && echo "  ✓ festival"  || echo "  ✗ festival"
    python3 -c "import pyttsx3" 2>/dev/null && echo "  ✓ pyttsx3 (Python)" || echo "  ✗ pyttsx3"
    python3 -c "import gtts"    2>/dev/null && echo "  ✓ gTTS (Python, needs internet)" || echo "  ✗ gTTS"
    command -v say              &>/dev/null && echo "  ✓ say (macOS)" || true
    echo ""
    echo "Install: papy deps tts"
    ;;

  set-engine)
    [ -n "${2:-}" ] || { echo "Engine name required"; exit 1; }
    [ -x "$CONFIG" ] && "$CONFIG" set speech.voice "$2"
    echo "Speech engine set to: $2"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-speech.sh help" ;;
esac
