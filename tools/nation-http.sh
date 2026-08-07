#!/bin/bash
# NATION AGENT — HTTP Tool
# Usage: nation-http.sh <command> [args...]
#
# Commands:
#   get     <url> [headers...]           HTTP GET request
#   post    <url> <body> [headers...]    HTTP POST with body
#   put     <url> <body> [headers...]    HTTP PUT with body
#   patch   <url> <body> [headers...]    HTTP PATCH with body
#   delete  <url> [headers...]           HTTP DELETE request
#   head    <url>                        HTTP HEAD (headers only)
#   upload  <url> <file> [field]         Upload file via multipart
#   download <url> <file>                Download file to disk
#   ws      <url>                        WebSocket connect (requires wscat)
#
# Header format: "Key: Value" (multiple allowed)
# Body can be JSON string or @filename to read from file
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log()  { echo "[$TS] [HTTP] $*" >> "$LOG"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

command -v curl &>/dev/null || die "curl not installed. Install with: pkg install curl"

require_url() {
    [ -n "${1:-}" ] || die "URL required"
}

# Pretty-print JSON if possible
pretty_json() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2, ensure_ascii=False))
except:
    sys.exit(1)
" 2>/dev/null && return 0
    cat  # fallback: output raw
}

# Parse extra header args into curl -H flags
# Everything after index $1 onwards that matches "Key: Value"
build_headers() {
    local start_idx=$1
    shift
    local args=("$@")
    for ((i=start_idx; i<${#args[@]}; i++)); do
        echo "-H" "${args[$i]}"
    done
}

CURL_BASE=(curl --silent --location --max-time 30
           --write-out "\n--- HTTP %{http_code} | %{size_download} bytes | %{time_total}s ---\n"
           --show-error)

case "$CMD" in

  get)
    require_url "${2:-}"
    URL="$2"
    shift 2
    log "GET $URL"
    HEADERS=()
    for h in "$@"; do HEADERS+=(-H "$h"); done
    "${CURL_BASE[@]}" "${HEADERS[@]}" "$URL" | pretty_json
    ;;

  post)
    require_url "${2:-}"
    URL="$2"
    BODY="${3:-}"
    shift 3 || shift $#
    log "POST $URL"
    HEADERS=()
    # Auto-detect JSON body and set Content-Type if not overridden
    CT_SET=0
    for h in "$@"; do
        HEADERS+=(-H "$h")
        [[ "${h,,}" == content-type* ]] && CT_SET=1
    done
    [ $CT_SET -eq 0 ] && HEADERS+=(-H "Content-Type: application/json")
    if [[ "$BODY" == @* ]]; then
        # Read from file
        FILE="${BODY:1}"
        [ -f "$FILE" ] || die "Body file not found: $FILE"
        "${CURL_BASE[@]}" -X POST "${HEADERS[@]}" --data @"$FILE" "$URL" | pretty_json
    else
        "${CURL_BASE[@]}" -X POST "${HEADERS[@]}" --data "$BODY" "$URL" | pretty_json
    fi
    ;;

  put)
    require_url "${2:-}"
    URL="$2"
    BODY="${3:-}"
    shift 3 || shift $#
    log "PUT $URL"
    HEADERS=(-H "Content-Type: application/json")
    for h in "$@"; do HEADERS+=(-H "$h"); done
    if [[ "$BODY" == @* ]]; then
        FILE="${BODY:1}"
        [ -f "$FILE" ] || die "Body file not found: $FILE"
        "${CURL_BASE[@]}" -X PUT "${HEADERS[@]}" --data @"$FILE" "$URL" | pretty_json
    else
        "${CURL_BASE[@]}" -X PUT "${HEADERS[@]}" --data "$BODY" "$URL" | pretty_json
    fi
    ;;

  patch)
    require_url "${2:-}"
    URL="$2"
    BODY="${3:-}"
    shift 3 || shift $#
    log "PATCH $URL"
    HEADERS=(-H "Content-Type: application/json")
    for h in "$@"; do HEADERS+=(-H "$h"); done
    if [[ "$BODY" == @* ]]; then
        FILE="${BODY:1}"
        [ -f "$FILE" ] || die "Body file not found: $FILE"
        "${CURL_BASE[@]}" -X PATCH "${HEADERS[@]}" --data @"$FILE" "$URL" | pretty_json
    else
        "${CURL_BASE[@]}" -X PATCH "${HEADERS[@]}" --data "$BODY" "$URL" | pretty_json
    fi
    ;;

  delete)
    require_url "${2:-}"
    URL="$2"
    shift 2
    log "DELETE $URL"
    HEADERS=()
    for h in "$@"; do HEADERS+=(-H "$h"); done
    "${CURL_BASE[@]}" -X DELETE "${HEADERS[@]}" "$URL" | pretty_json
    ;;

  head)
    require_url "${2:-}"
    log "HEAD $2"
    curl --silent --head --location --max-time 15 "$2"
    ;;

  upload)
    require_url "${2:-}"
    [ -n "${3:-}" ] || die "File path required"
    [ -f "$3" ] || die "File not found: $3"
    FIELD="${4:-file}"
    log "UPLOAD $3 -> $2 (field=$FIELD)"
    curl --silent --location --max-time 120 \
         --write-out "\n--- HTTP %{http_code} ---\n" \
         -F "${FIELD}=@$3" "$2" | pretty_json
    ;;

  download)
    require_url "${2:-}"
    [ -n "${3:-}" ] || die "Output file path required"
    log "DOWNLOAD $2 -> $3"
    mkdir -p "$(dirname "$3")"
    curl --location --max-time 300 --progress-bar -o "$3" "$2"
    echo "Downloaded: $3 ($(du -sh "$3" | cut -f1))"
    ;;

  ws)
    require_url "${2:-}"
    if command -v wscat &>/dev/null; then
        log "WS $2"
        wscat -c "$2"
    elif command -v websocat &>/dev/null; then
        log "WS $2 (websocat)"
        websocat "$2"
    else
        die "WebSocket client not found. Install with: npm install -g wscat"
    fi
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-http.sh help"
    ;;
esac
