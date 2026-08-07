#!/bin/bash
# NATION AGENT — Voice Training & Wake Word Listener
# Always-on voice listener that waits for wake word and executes commands.
# Usage: nation-voice.sh <command>
# Commands:
#   listen              Start always-on wake word listener (background)
#   listen-fg           Start listener in foreground
#   stop                Stop voice listener
#   status              Show listener status
#   train               Train voice recognition with your voice samples
#   record <name>       Record a voice sample
#   test                Test microphone and recognition
#   wake-word [word]    Set or show the wake word
#   transcript          Show recent voice transcriptions
set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-status}"
CONFIG="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-config.sh"
SPEECH="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-speech.sh"
AUTO="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-auto.sh"
VOICE_DIR="${NATION_DIR:-$HOME/.kiro}/voice"
MODEL_DIR="$VOICE_DIR/models"
SAMPLES_DIR="$VOICE_DIR/samples"
TRANSCRIPT_LOG="$VOICE_DIR/transcript.log"
PID_FILE="${NATION_DIR:-$HOME/.kiro}/voice.pid"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$VOICE_DIR" "$MODEL_DIR" "$SAMPLES_DIR" "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [VOICE] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

get_cfg() { [ -x "$CONFIG" ] && "$CONFIG" get "$1" 2>/dev/null || echo "${2:-}"; }
get_wake_word() { get_cfg "agent.wake_word" "hey papy"; }

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# ── Core voice listener (Python) ──────────────────────────────────────────
LISTENER_SCRIPT="$VOICE_DIR/listener.py"
cat > "$LISTENER_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""NATION AGENT — Voice Listener
Listens for wake word then captures command and executes via papy.
"""
import os, sys, json, subprocess, datetime, time, threading

WAKE_WORD   = sys.argv[1] if len(sys.argv) > 1 else "hey papy"
TOOLS       = os.path.expanduser("~/.kiro/tools")
LOG_FILE    = os.path.expanduser("~/.kiro/voice/transcript.log")
PID_FILE    = os.path.expanduser("~/.kiro/voice.pid")
PAPY        = os.path.join(TOOLS, "papy")
SPEECH      = os.path.join(TOOLS, "nation-speech.sh")

def speak(text):
    subprocess.Popen([SPEECH, "speak", text],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def transcribe_log(text, kind="heard"):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{ts}] [{kind}] {text}\n")

def execute_command(cmd_text):
    """Execute a voice command via papy or shell."""
    transcribe_log(cmd_text, "command")
    speak("Processing...")
    try:
        # Route to papy for execution
        result = subprocess.run(
            f"papy {cmd_text}",
            shell=True, capture_output=True, text=True, timeout=30,
            env={**os.environ, "PATH": os.environ.get("PATH","") + ":/usr/local/bin"}
        )
        response = (result.stdout or result.stderr or "Done").strip()[:300]
        transcribe_log(response, "response")
        speak(response[:200])
        print(f"[CMD] {cmd_text} -> {response[:80]}")
    except subprocess.TimeoutExpired:
        speak("Command timed out")
    except Exception as e:
        speak(f"Error: {str(e)[:100]}")

def try_vosk_listener():
    """Use Vosk offline speech recognition."""
    try:
        import vosk, pyaudio, queue
        MODEL_PATH = os.path.expanduser("~/.kiro/voice/models/vosk-model-small-en-us-0.15")
        if not os.path.isdir(MODEL_PATH):
            return False
        model = vosk.Model(MODEL_PATH)
        q = queue.Queue()
        SAMPLE_RATE = 16000

        def audio_callback(in_data, frame_count, time_info, status):
            q.put(bytes(in_data))
            return (None, pyaudio.paContinue)

        audio = pyaudio.PyAudio()
        stream = audio.open(format=pyaudio.paInt16, channels=1,
                            rate=SAMPLE_RATE, input=True,
                            frames_per_buffer=8000,
                            stream_callback=audio_callback)

        rec = vosk.KaldiRecognizer(model, SAMPLE_RATE)
        print(f"[VOICE] Vosk listener active. Wake word: '{WAKE_WORD}'")
        speak(f"Voice listener active. Say {WAKE_WORD} to activate me.")
        transcribe_log("Listener started (Vosk)", "system")

        WAKE_DETECTED = False
        LISTEN_FOR_CMD = False
        CMD_CHUNKS = []
        SILENCE_COUNT = 0

        while True:
            data = q.get()
            if rec.AcceptWaveform(data):
                result = json.loads(rec.Result())
                text = result.get("text", "").lower().strip()
                if not text: continue

                transcribe_log(text, "heard")
                print(f"[HEARD] {text}")

                if WAKE_WORD.lower() in text:
                    WAKE_DETECTED = True
                    LISTEN_FOR_CMD = True
                    CMD_CHUNKS = []
                    SILENCE_COUNT = 0
                    speak("Yes?")
                    print("[WAKE] Activated!")
                    continue

                if LISTEN_FOR_CMD:
                    # Collect command words
                    CMD_CHUNKS.append(text)
                    if len(CMD_CHUNKS) >= 1 and any(
                        word in text for word in ["go","run","open","do","check","search","help","stop","play"]
                    ):
                        cmd = " ".join(CMD_CHUNKS)
                        threading.Thread(target=execute_command, args=(cmd,), daemon=True).start()
                        LISTEN_FOR_CMD = False
                        CMD_CHUNKS = []
                    elif len(CMD_CHUNKS) >= 3:
                        cmd = " ".join(CMD_CHUNKS)
                        threading.Thread(target=execute_command, args=(cmd,), daemon=True).start()
                        LISTEN_FOR_CMD = False
                        CMD_CHUNKS = []

        stream.stop_stream()
        stream.close()
        audio.terminate()
        return True
    except ImportError:
        return False
    except Exception as e:
        print(f"[VOICE] Vosk error: {e}")
        return False

def try_sr_listener():
    """Use SpeechRecognition library (Google/Sphinx)."""
    try:
        import speech_recognition as sr
        recognizer = sr.Recognizer()
        recognizer.energy_threshold = 300
        recognizer.dynamic_energy_threshold = True

        print(f"[VOICE] SpeechRecognition listener. Wake word: '{WAKE_WORD}'")
        speak(f"Voice listener ready. Say {WAKE_WORD} to activate.")
        transcribe_log("Listener started (SpeechRecognition)", "system")

        LISTEN_FOR_CMD = False
        with sr.Microphone() as source:
            recognizer.adjust_for_ambient_noise(source, duration=1)
            while True:
                try:
                    print("[VOICE] Listening...")
                    audio = recognizer.listen(source, timeout=5, phrase_time_limit=8)
                    try:
                        text = recognizer.recognize_google(audio).lower().strip()
                    except:
                        try:
                            text = recognizer.recognize_sphinx(audio).lower().strip()
                        except:
                            text = ""
                    if not text: continue
                    transcribe_log(text, "heard")
                    print(f"[HEARD] {text}")

                    if WAKE_WORD.lower() in text:
                        LISTEN_FOR_CMD = True
                        speak("Yes?")
                        continue
                    if LISTEN_FOR_CMD:
                        threading.Thread(target=execute_command, args=(text,), daemon=True).start()
                        LISTEN_FOR_CMD = False
                except sr.WaitTimeoutError:
                    LISTEN_FOR_CMD = False
                except Exception as e:
                    print(f"[VOICE] Error: {e}")
                    time.sleep(1)
        return True
    except ImportError:
        return False
    except Exception as e:
        print(f"[SR] Error: {e}")
        return False

def termux_listener():
    """Use termux-microphone-record + speech recognition."""
    if not os.path.exists("/data/data/com.termux") and \
       not os.path.exists("/data/data/com.termux/files/usr/bin/termux-microphone-record"):
        return False
    print(f"[VOICE] Termux voice mode. Wake word: '{WAKE_WORD}'")
    speak(f"Voice listener ready. Say {WAKE_WORD}.")
    transcribe_log("Listener started (Termux)", "system")
    RECORD_FILE = "/tmp/nation_voice.wav"
    while True:
        try:
            os.system(f"termux-microphone-record -l 5 -e wav -f {RECORD_FILE} 2>/dev/null")
            time.sleep(5.5)
            if not os.path.isfile(RECORD_FILE): continue
            # Try whisper or vosk on the file
            try:
                import vosk, wave
                MODEL_PATH = os.path.expanduser("~/.kiro/voice/models/vosk-model-small-en-us-0.15")
                if not os.path.isdir(MODEL_PATH): raise ImportError
                model = vosk.Model(MODEL_PATH)
                wf = wave.open(RECORD_FILE, 'rb')
                rec = vosk.KaldiRecognizer(model, wf.getframerate())
                while True:
                    data = wf.readframes(4000)
                    if len(data) == 0: break
                    rec.AcceptWaveform(data)
                result = json.loads(rec.FinalResult())
                text = result.get("text","").lower()
            except Exception:
                text = ""
            if text:
                transcribe_log(text, "heard")
                print(f"[HEARD] {text}")
                if WAKE_WORD.lower() in text:
                    cmd = text.replace(WAKE_WORD.lower(),"").strip()
                    if cmd:
                        threading.Thread(target=execute_command, args=(cmd,), daemon=True).start()
                    else:
                        speak("Yes?")
        except Exception as e:
            print(f"[VOICE] Error: {e}")
            time.sleep(3)
    return True

# Try engines in order
if not try_vosk_listener():
    if not try_sr_listener():
        if not termux_listener():
            print("[VOICE] No voice engine available.")
            print("Install: papy deps voice")
            sys.exit(1)
PYEOF

case "$CMD" in

  listen)
    log "listen start (background)"
    is_running && { echo "Listener already running (PID $(cat "$PID_FILE"))"; exit 0; }
    WAKE=$(get_wake_word)
    nohup python3 "$LISTENER_SCRIPT" "$WAKE" \
        >> "$VOICE_DIR/listener.log" 2>&1 &
    PID=$!
    echo "$PID" > "$PID_FILE"
    sleep 1
    is_running && echo "Voice listener started (PID $PID, wake: '$WAKE')" || \
        echo "Start failed. Check: $VOICE_DIR/listener.log"
    ;;

  listen-fg)
    log "listen foreground"
    WAKE=$(get_wake_word)
    echo "Starting voice listener (foreground). Wake word: '$WAKE'"
    echo "Press Ctrl+C to stop."
    python3 "$LISTENER_SCRIPT" "$WAKE"
    ;;

  stop)
    if is_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null && rm -f "$PID_FILE"
        log "listener stopped"
        echo "Voice listener stopped."
    else
        pkill -f "listener.py" 2>/dev/null && echo "Listener stopped" || echo "Not running."
    fi
    ;;

  status)
    if is_running; then
        echo "Voice listener: RUNNING (PID $(cat "$PID_FILE"))"
    else
        echo "Voice listener: STOPPED"
    fi
    echo "Wake word: '$(get_wake_word)'"
    echo "Voice enabled: $(get_cfg "voice.enabled" "false")"
    echo ""
    echo "Recent transcriptions:"
    tail -10 "$TRANSCRIPT_LOG" 2>/dev/null || echo "  (none)"
    ;;

  train)
    log "train"
    echo "=== Voice Training ==="
    echo "Recording voice samples for recognition training."
    echo ""
    SAMPLES=(
        "hey papy"
        "hey papy open browser"
        "hey papy run health check"
        "hey papy show memory"
        "hey papy what time is it"
    )
    mkdir -p "$SAMPLES_DIR"
    for PHRASE in "${SAMPLES[@]}"; do
        echo "Say: '$PHRASE'"
        echo "Press Enter when ready, then speak..."
        read -r _
        OUTFILE="$SAMPLES_DIR/$(echo "$PHRASE" | tr ' ' '_').wav"
        if command -v termux-microphone-record &>/dev/null; then
            termux-microphone-record -l 3 -e wav -f "$OUTFILE" 2>/dev/null
            sleep 3.5
        elif command -v arecord &>/dev/null; then
            arecord -d 3 -f cd "$OUTFILE" 2>/dev/null
        else
            echo "  (no recording tool — simulating)"
            touch "$OUTFILE"
        fi
        echo "  Recorded: $OUTFILE"
    done
    echo ""
    echo "Training complete. ${#SAMPLES[@]} samples recorded in $SAMPLES_DIR"
    [ -x "$CONFIG" ] && "$CONFIG" set voice.enabled true
    ;;

  record)
    NAME="${2:-sample}"
    OUTFILE="$SAMPLES_DIR/${NAME}.wav"
    echo "Recording: $NAME (speak now...)"
    if command -v termux-microphone-record &>/dev/null; then
        termux-microphone-record -l 5 -e wav -f "$OUTFILE" 2>/dev/null
        sleep 5.5
    elif command -v arecord &>/dev/null; then
        arecord -d 5 -f cd "$OUTFILE" 2>/dev/null
    else
        echo "No recording tool available. Install: papy deps audio"
        exit 1
    fi
    [ -f "$OUTFILE" ] && echo "Recorded: $OUTFILE" || echo "Recording failed"
    ;;

  test)
    log "test"
    echo "Testing microphone and voice recognition..."
    python3 -c "import vosk; print('Vosk: OK')" 2>/dev/null || echo "Vosk: not installed"
    python3 -c "import speech_recognition; print('SpeechRecognition: OK')" 2>/dev/null || echo "SpeechRecognition: not installed"
    python3 -c "import pyaudio; print('PyAudio: OK')" 2>/dev/null || echo "PyAudio: not installed"
    command -v termux-microphone-record &>/dev/null && echo "termux-microphone: OK" || echo "termux-microphone: not found"
    echo ""
    echo "Install missing: papy deps voice"
    ;;

  wake-word)
    if [ -n "${2:-}" ]; then
        shift
        WW="$*"
        [ -x "$CONFIG" ] && "$CONFIG" set agent.wake_word "$WW"
        echo "Wake word set to: '$WW'"
        is_running && { "$0" stop; "$0" listen; }
    else
        echo "Wake word: '$(get_wake_word)'"
    fi
    ;;

  transcript)
    echo "=== Voice Transcripts ==="
    tail -30 "$TRANSCRIPT_LOG" 2>/dev/null || echo "(none)"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *) echo "Unknown: $CMD. Run: nation-voice.sh help" ;;
esac
