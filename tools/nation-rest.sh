#!/bin/bash
# NATION AGENT — REST API Tool
# Usage: nation-rest.sh <command> [args...]
#
# Commands:
#   call    <method> <url> [body] [headers...]   Generic REST call
#   auth    basic <url> <user> <pass>            Basic auth GET
#   auth    bearer <url> <token>                 Bearer token GET
#   auth    apikey <url> <key> [header]          API key GET (default X-API-Key)
#   mock    <port> [responses_file]              Start a local mock API server
#   test    <spec_file>                          Run API tests from spec file
#   encode  <string>                             URL-encode a string
#   decode  <string>                             URL-decode a string
#   jwt     decode <token>                       Decode (not verify) a JWT
#   jwt     encode <payload> <secret>            Encode a JWT (HS256)
#   openapi <url_or_file>                        Parse and summarize OpenAPI spec
#   ping    <base_url>                           Ping a REST API health endpoint
#
# REST spec file format (YAML-like, each test on its own lines):
#   METHOD URL [body_json]
#   EXPECT <status_code>
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [REST] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v curl &>/dev/null || die "curl not installed. Install with: pkg install curl"

CURL_OPTS=(--silent --location --max-time 30 --show-error)

pretty_json() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2, ensure_ascii=False))
except:
    pass
" 2>/dev/null || cat
}

show_response() {
    echo "=== Response ==="
    cat
}

case "$CMD" in

  call)
    [ -n "${2:-}" ] || die "HTTP method required (GET, POST, PUT, PATCH, DELETE)"
    [ -n "${3:-}" ] || die "URL required"
    METHOD="${2^^}"
    URL="$3"
    BODY="${4:-}"
    shift 4 || shift $#
    log "$METHOD $URL"
    HEADERS=(-H "Accept: application/json")
    CT_SET=0
    for h in "$@"; do
        HEADERS+=(-H "$h")
        [[ "${h,,}" == content-type* ]] && CT_SET=1
    done
    [ $CT_SET -eq 0 ] && [ -n "$BODY" ] && HEADERS+=(-H "Content-Type: application/json")
    CURL_ARGS=("${CURL_OPTS[@]}" -X "$METHOD" "${HEADERS[@]}")
    echo ">>> $METHOD $URL"
    if [ -n "$BODY" ]; then
        if [[ "$BODY" == @* ]]; then
            FILE="${BODY:1}"
            [ -f "$FILE" ] || die "Body file not found: $FILE"
            RESPONSE=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" --data @"$FILE" "$URL")
        else
            RESPONSE=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" --data "$BODY" "$URL")
        fi
    else
        RESPONSE=$(curl "${CURL_ARGS[@]}" -w "\n%{http_code}" "$URL")
    fi
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY_RESPONSE=$(echo "$RESPONSE" | head -n -1)
    echo "<<< HTTP $HTTP_CODE"
    echo "$BODY_RESPONSE" | pretty_json
    ;;

  auth)
    SUBCMD="${2:-}"
    case "$SUBCMD" in
      basic)
        [ -n "${3:-}" ] || die "URL required"
        [ -n "${4:-}" ] || die "Username required"
        [ -n "${5:-}" ] || die "Password required"
        log "auth basic $3 (user=$4)"
        curl "${CURL_OPTS[@]}" -u "${4}:${5}" -H "Accept: application/json" "$3" | pretty_json
        ;;
      bearer)
        [ -n "${3:-}" ] || die "URL required"
        [ -n "${4:-}" ] || die "Token required"
        log "auth bearer $3"
        curl "${CURL_OPTS[@]}" \
             -H "Authorization: Bearer $4" \
             -H "Accept: application/json" "$3" | pretty_json
        ;;
      apikey)
        [ -n "${3:-}" ] || die "URL required"
        [ -n "${4:-}" ] || die "API key required"
        HEADER="${5:-X-API-Key}"
        log "auth apikey $3 (header=$HEADER)"
        curl "${CURL_OPTS[@]}" \
             -H "${HEADER}: $4" \
             -H "Accept: application/json" "$3" | pretty_json
        ;;
      *)
        die "Unknown auth type: $SUBCMD. Use: basic, bearer, apikey"
        ;;
    esac
    ;;

  mock)
    PORT="${2:-8080}"
    RESPONSES_FILE="${3:-}"
    log "mock server on :$PORT"
    echo "Starting mock REST API on port $PORT..."
    echo "Press Ctrl+C to stop."
    python3 - "$PORT" "$RESPONSES_FILE" << 'PYEOF'
import sys, json, http.server, urllib.parse, datetime

port = int(sys.argv[1])
responses_file = sys.argv[2] if len(sys.argv) > 2 else ""

# Load custom responses if provided
custom = {}
if responses_file:
    try:
        with open(responses_file) as f:
            custom = json.load(f)
        print(f"Loaded {len(custom)} custom responses from {responses_file}")
    except Exception as e:
        print(f"Warning: could not load responses file: {e}")

class MockHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ts = datetime.datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] {fmt % args}")

    def send_json(self, code, data):
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def handle_request(self):
        path = self.path
        method = self.command
        key = f"{method} {path}"

        # Read body for POST/PUT/PATCH
        body = None
        length = int(self.headers.get("Content-Length", 0))
        if length:
            try:
                body = json.loads(self.rfile.read(length))
            except Exception:
                body = {}

        # Check custom responses
        if key in custom:
            resp = custom[key]
            self.send_json(resp.get("status", 200), resp.get("body", {}))
            return

        # Default responses
        self.send_json(200, {
            "path": path,
            "method": method,
            "body": body,
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "message": "Mock response from NATION AGENT"
        })

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_request

server = http.server.HTTPServer(("0.0.0.0", port), MockHandler)
print(f"Mock API running at http://localhost:{port}")
print("Endpoints: any path/method returns 200 JSON by default")
server.serve_forever()
PYEOF
    ;;

  test)
    [ -n "${2:-}" ] || die "Test spec file required"
    [ -f "$2" ] || die "Spec file not found: $2"
    log "test $2"
    echo "=== REST API Tests: $2 ==="
    python3 - "$2" << 'PYEOF'
import sys, json, urllib.request, urllib.error

spec_file = sys.argv[1]
passed = 0
failed = 0

with open(spec_file) as f:
    lines = [l.strip() for l in f if l.strip() and not l.startswith('#')]

i = 0
while i < len(lines):
    line = lines[i]
    parts = line.split(' ', 2)
    if len(parts) < 2:
        i += 1
        continue

    method = parts[0].upper()
    url = parts[1]
    body = parts[2].encode() if len(parts) > 2 else None
    expected_status = 200

    # Check for EXPECT line
    if i + 1 < len(lines) and lines[i+1].startswith('EXPECT '):
        expected_status = int(lines[i+1].split(' ')[1])
        i += 2
    else:
        i += 1

    try:
        req = urllib.request.Request(
            url, data=body, method=method,
            headers={"Content-Type": "application/json", "Accept": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
            resp_body = resp.read().decode(errors='replace')[:200]
    except urllib.error.HTTPError as e:
        status = e.code
        resp_body = str(e)
    except Exception as e:
        status = 0
        resp_body = str(e)

    ok = status == expected_status
    symbol = "✓" if ok else "✗"
    if ok:
        passed += 1
    else:
        failed += 1

    print(f"  {symbol} {method} {url} -> {status} (expected {expected_status})")
    if not ok:
        print(f"    Response: {resp_body}")

print(f"\nResults: {passed} passed, {failed} failed")
sys.exit(0 if failed == 0 else 1)
PYEOF
    ;;

  encode)
    [ -n "${2:-}" ] || die "String to encode required"
    log "encode"
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "$2"
    ;;

  decode)
    [ -n "${2:-}" ] || die "String to decode required"
    log "decode"
    python3 -c "import urllib.parse, sys; print(urllib.parse.unquote_plus(sys.argv[1]))" "$2"
    ;;

  jwt)
    SUBCMD="${2:-}"
    case "$SUBCMD" in
      decode)
        [ -n "${3:-}" ] || die "JWT token required"
        log "jwt decode"
        python3 - "$3" << 'PYEOF'
import sys, json, base64

token = sys.argv[1]
parts = token.split('.')
if len(parts) != 3:
    print("ERROR: not a valid JWT (expected 3 parts)", file=sys.stderr)
    sys.exit(1)

def decode_part(s):
    # Add padding
    s += '=' * (4 - len(s) % 4)
    return json.loads(base64.urlsafe_b64decode(s))

try:
    header = decode_part(parts[0])
    payload = decode_part(parts[1])
    print("=== Header ===")
    print(json.dumps(header, indent=2))
    print("\n=== Payload ===")
    print(json.dumps(payload, indent=2))
    print("\n=== Signature ===")
    print(f"(not verified) {parts[2][:32]}...")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        ;;
      encode)
        [ -n "${3:-}" ] || die "Payload JSON required"
        [ -n "${4:-}" ] || die "Secret required"
        log "jwt encode"
        python3 - "$3" "$4" << 'PYEOF'
import sys, json, base64, hmac, hashlib, time

payload_str = sys.argv[1]
secret = sys.argv[2]

try:
    payload = json.loads(payload_str)
except json.JSONDecodeError as e:
    print(f"ERROR: invalid JSON payload: {e}", file=sys.stderr)
    sys.exit(1)

# Add standard claims if missing
payload.setdefault('iat', int(time.time()))
payload.setdefault('exp', int(time.time()) + 3600)

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(',', ':')))
body = b64url(json.dumps(payload, separators=(',', ':')))
sig_input = f"{header}.{body}"
sig = hmac.new(secret.encode(), sig_input.encode(), hashlib.sha256).digest()

token = f"{sig_input}.{b64url(sig)}"
print(token)
PYEOF
        ;;
      *)
        die "Unknown jwt subcommand: $SUBCMD. Use: decode, encode"
        ;;
    esac
    ;;

  openapi)
    [ -n "${2:-}" ] || die "OpenAPI spec URL or file path required"
    SPEC="$2"
    log "openapi $SPEC"
    python3 - "$SPEC" << 'PYEOF'
import sys, json, urllib.request

spec_src = sys.argv[1]

# Load spec
if spec_src.startswith('http'):
    with urllib.request.urlopen(spec_src, timeout=30) as resp:
        content = resp.read().decode()
else:
    with open(spec_src) as f:
        content = f.read()

# Try JSON first, then YAML
try:
    spec = json.loads(content)
except json.JSONDecodeError:
    try:
        import yaml
        spec = yaml.safe_load(content)
    except ImportError:
        print("ERROR: YAML spec requires PyYAML. Install: pip3 install pyyaml", file=sys.stderr)
        sys.exit(1)

info = spec.get('info', {})
print(f"=== OpenAPI Spec ===")
print(f"Title  : {info.get('title', 'N/A')}")
print(f"Version: {info.get('version', 'N/A')}")
print(f"OAS    : {spec.get('openapi', spec.get('swagger', 'N/A'))}")
print()

# List paths/endpoints
paths = spec.get('paths', {})
print(f"=== Endpoints ({len(paths)} paths) ===")
for path, methods in sorted(paths.items()):
    for method, details in methods.items():
        if method in ('get','post','put','patch','delete','head','options'):
            summary = details.get('summary', details.get('description', ''))[:60]
            print(f"  {method.upper():7} {path}  {summary}")

# List tags
tags = spec.get('tags', [])
if tags:
    print(f"\n=== Tags ===")
    for tag in tags:
        print(f"  {tag.get('name','')} - {tag.get('description','')}")
PYEOF
    ;;

  ping)
    [ -n "${2:-}" ] || die "Base URL required"
    BASE="${2%/}"  # strip trailing slash
    log "ping $BASE"
    ENDPOINTS=("/health" "/healthz" "/ping" "/status" "/api/health" "/_health")
    echo "Probing: $BASE"
    for ep in "${ENDPOINTS[@]}"; do
        CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 5 "${BASE}${ep}" 2>/dev/null)
        if [[ "$CODE" == 2* ]]; then
            echo "  ✓ ${BASE}${ep} -> HTTP $CODE"
        else
            echo "  ✗ ${BASE}${ep} -> HTTP $CODE"
        fi
    done
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-rest.sh help"
    ;;
esac
