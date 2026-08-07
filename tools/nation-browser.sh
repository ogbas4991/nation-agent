#!/bin/bash
# NATION AGENT — Browser / Web Tool
# Usage: nation-browser.sh <command> [args...]
#
# Commands:
#   fetch   <url> [--raw]            Fetch a URL, extract readable text
#   html    <url>                    Fetch raw HTML source
#   links   <url>                    Extract all links from a page
#   title   <url>                    Get page title
#   headers <url>                    Show HTTP response headers
#   save    <url> <file>             Save page content to file
#   json    <url>                    Fetch URL and parse as JSON
#   screenshot  <url>                Take screenshot (requires cutycapt/wkhtmltopdf)
#   search  <query>                  Web search via DuckDuckGo HTML
#   status  <url>                    Check HTTP status code
#
# Requires: curl (available). Optionally: lynx, w3m, python3 (for text extraction)
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [BROWSER] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_url() {
    [ -n "${1:-}" ] || die "URL required"
    [[ "$1" == http://* ]] || [[ "$1" == https://* ]] || die "URL must start with http:// or https://"
}

CURL_OPTS=(--silent --location --max-time 30 --user-agent "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36")

# Extract readable text from HTML using Python
html_to_text() {
    python3 - << 'PYEOF'
import sys, re, html

content = sys.stdin.read()

# Remove scripts and styles
content = re.sub(r'<script[^>]*>.*?</script>', '', content, flags=re.DOTALL | re.IGNORECASE)
content = re.sub(r'<style[^>]*>.*?</style>', '', content, flags=re.DOTALL | re.IGNORECASE)
content = re.sub(r'<head[^>]*>.*?</head>', '', content, flags=re.DOTALL | re.IGNORECASE)

# Convert block elements to newlines
content = re.sub(r'<(br|p|div|li|h[1-6]|tr|blockquote)[^>]*>', '\n', content, flags=re.IGNORECASE)
content = re.sub(r'</(p|div|li|h[1-6]|tr|blockquote)>', '\n', content, flags=re.IGNORECASE)

# Remove all remaining tags
content = re.sub(r'<[^>]+>', '', content)

# Decode HTML entities
content = html.unescape(content)

# Clean whitespace
lines = [line.strip() for line in content.splitlines()]
lines = [line for line in lines if line]
# Deduplicate consecutive blank lines
result = []
prev_blank = False
for line in lines:
    if line:
        result.append(line)
        prev_blank = False
    elif not prev_blank:
        result.append('')
        prev_blank = True

print('\n'.join(result[:500]))  # Limit to 500 lines
PYEOF
}

case "$CMD" in

  fetch)
    require_url "${2:-}"
    RAW="${3:-}"
    log "fetch $2"
    if [ "$RAW" = "--raw" ]; then
        curl "${CURL_OPTS[@]}" "$2"
    elif command -v lynx &>/dev/null; then
        lynx -dump -nolist "$2" 2>/dev/null | head -300
    elif command -v w3m &>/dev/null; then
        w3m -dump "$2" 2>/dev/null | head -300
    else
        # Python HTML-to-text extraction
        curl "${CURL_OPTS[@]}" "$2" | html_to_text
    fi
    ;;

  html)
    require_url "${2:-}"
    log "html $2"
    curl "${CURL_OPTS[@]}" "$2"
    ;;

  links)
    require_url "${2:-}"
    log "links $2"
    curl "${CURL_OPTS[@]}" "$2" | python3 - "$2" << 'PYEOF'
import sys, re, html, urllib.parse

base_url = sys.argv[1] if len(sys.argv) > 1 else ""
content = sys.stdin.read()

# Find all href and src attributes
pattern = r'(?:href|src)=["\']([^"\']+)["\']'
links = re.findall(pattern, content, re.IGNORECASE)

seen = set()
for link in links:
    link = html.unescape(link)
    if link.startswith('#') or link.startswith('javascript:') or link.startswith('mailto:'):
        continue
    if base_url and not link.startswith(('http://', 'https://', '//')):
        link = urllib.parse.urljoin(base_url, link)
    if link not in seen:
        seen.add(link)
        print(link)
PYEOF
    ;;

  title)
    require_url "${2:-}"
    log "title $2"
    curl "${CURL_OPTS[@]}" "$2" | python3 -c "
import sys, re, html
content = sys.stdin.read()
m = re.search(r'<title[^>]*>(.*?)</title>', content, re.IGNORECASE | re.DOTALL)
if m:
    print(html.unescape(m.group(1).strip()))
else:
    print('(no title found)')
"
    ;;

  headers)
    require_url "${2:-}"
    log "headers $2"
    curl --silent --head --location --max-time 15 "$2"
    ;;

  save)
    require_url "${2:-}"
    [ -n "${3:-}" ] || die "Output file path required"
    log "save $2 -> $3"
    mkdir -p "$(dirname "$3")"
    curl "${CURL_OPTS[@]}" -o "$3" "$2"
    echo "Saved: $3 ($(du -sh "$3" | cut -f1))"
    ;;

  json)
    require_url "${2:-}"
    log "json $2"
    curl "${CURL_OPTS[@]}" -H "Accept: application/json" "$2" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2, ensure_ascii=False))
except json.JSONDecodeError as e:
    print(f'Not valid JSON: {e}', file=sys.stderr)
    sys.exit(1)
"
    ;;

  screenshot)
    log "screenshot ${2:-}"
    if command -v cutycapt &>/dev/null; then
        require_url "${2:-}"
        OUTPUT="${3:-screenshot.png}"
        cutycapt --url="$2" --out="$OUTPUT"
        echo "Screenshot saved: $OUTPUT"
    elif command -v wkhtmltoimage &>/dev/null; then
        require_url "${2:-}"
        OUTPUT="${3:-screenshot.png}"
        wkhtmltoimage "$2" "$OUTPUT"
        echo "Screenshot saved: $OUTPUT"
    else
        die "Screenshot requires cutycapt or wkhtmltoimage. Install with: pkg install cutycapt"
    fi
    ;;

  search)
    [ -n "${2:-}" ] || die "Search query required"
    shift
    QUERY="$*"
    # URL-encode the query
    ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote_plus(sys.argv[1]))" "$QUERY")
    log "search: $QUERY"
    echo "=== DuckDuckGo search: $QUERY ==="
    curl "${CURL_OPTS[@]}" "https://html.duckduckgo.com/html/?q=${ENCODED}" | python3 - << 'PYEOF'
import sys, re, html

content = sys.stdin.read()

# Extract result titles and URLs from DDG HTML
results = re.findall(
    r'class="result__title"[^>]*>.*?<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
    content, re.DOTALL | re.IGNORECASE
)

snippets = re.findall(
    r'class="result__snippet"[^>]*>(.*?)</div>',
    content, re.DOTALL | re.IGNORECASE
)

# Strip tags helper
def strip_tags(s):
    s = re.sub(r'<[^>]+>', '', s)
    return html.unescape(s).strip()

if not results:
    print("No results found (may be rate-limited or DDG HTML structure changed)")
    sys.exit(0)

for i, ((url, title), snippet) in enumerate(zip(results[:10], snippets[:10] + [''] * 10), 1):
    clean_title = strip_tags(title)
    clean_url = html.unescape(url)
    clean_snippet = strip_tags(snippet)
    print(f"{i}. {clean_title}")
    print(f"   {clean_url}")
    if clean_snippet:
        print(f"   {clean_snippet[:200]}")
    print()
PYEOF
    ;;

  status)
    require_url "${2:-}"
    log "status $2"
    HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 15 "$2")
    echo "URL   : $2"
    echo "Status: $HTTP_CODE"
    case "$HTTP_CODE" in
        2*) echo "Result: OK" ;;
        3*) echo "Result: Redirect" ;;
        4*) echo "Result: Client Error" ;;
        5*) echo "Result: Server Error" ;;
        *)  echo "Result: Unknown/Unreachable" ;;
    esac
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-browser.sh help"
    ;;
esac
