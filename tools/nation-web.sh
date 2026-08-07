#!/bin/bash
# NATION AGENT — Web Dashboard Server
# Serves a local web UI for NATION AGENT on http://localhost:PORT
# Usage: nation-web.sh [port]
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

PORT="${1:-7070}"
WEB_DIR="${NATION_DIR:-$HOME/.kiro}/web"
TOOLS="${NATION_TOOLS:-$HOME/.kiro/tools}"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$WEB_DIR" "$(dirname "$LOG")"

echo "Starting NATION AGENT web dashboard on http://localhost:${PORT}"
echo "Press Ctrl+C to stop."

python3 - "$PORT" "$WEB_DIR" "$TOOLS" "$HOME" << 'PYEOF'
import sys, os, json, subprocess, datetime, http.server, urllib.parse, sqlite3, threading

PORT     = int(sys.argv[1])
WEB_DIR  = sys.argv[2]
TOOLS    = sys.argv[3]
HOME     = sys.argv[4]
DB_PATH  = os.path.join(HOME, ".kiro", "memory", "memory.db")
LOG_PATH = os.path.join(HOME, ".kiro", "logs", "nation-agent.log")

def run_tool(script, *args):
    tool = os.path.join(TOOLS, f"nation-{script}.sh")
    try:
        r = subprocess.run([tool] + list(args), capture_output=True, text=True, timeout=15)
        return r.stdout + r.stderr
    except Exception as e:
        return str(e)

def get_memories(limit=20):
    try:
        conn = sqlite3.connect(DB_PATH)
        rows = conn.execute(
            "SELECT type,key,value,updated FROM memories ORDER BY updated DESC LIMIT ?", (limit,)
        ).fetchall()
        conn.close()
        return [{"type":r[0],"key":r[1],"value":r[2],"updated":r[3]} for r in rows]
    except:
        return []

def get_logs(lines=40):
    try:
        with open(LOG_PATH) as f:
            return f.readlines()[-lines:]
    except:
        return []

def get_skills():
    reg = os.path.join(HOME, ".kiro", "skills", "registry.json")
    try:
        with open(reg) as f:
            return json.load(f).get("skills", {})
    except:
        return {}

def get_status():
    tools = len([f for f in os.listdir(TOOLS) if f.startswith("nation-") and f.endswith(".sh")])
    memories = len(get_memories(999))
    skills = len(get_skills())
    platform = os.environ.get("NATION_PLATFORM", "unknown")
    return {"tools": tools, "memories": memories, "skills": skills, "platform": platform,
            "time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def send_json(self, data, code=200):
        body = json.dumps(data, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html):
        body = html.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        path = p.path

        if path == "/api/status":
            self.send_json(get_status())
        elif path == "/api/memories":
            self.send_json(get_memories())
        elif path == "/api/logs":
            self.send_json({"lines": get_logs()})
        elif path == "/api/skills":
            self.send_json(get_skills())
        elif path == "/api/health":
            out = run_tool("heal", "check")
            self.send_json({"output": out})
        elif path == "/api/suggestions":
            raw = run_tool("suggest", "--json")
            try:
                import json as _json
                items = _json.loads(raw)
                self.send_json({"suggestions": items})
            except:
                self.send_json({"suggestions": []})
        elif path in ("/", "/index.html"):
            html_path = os.path.join(WEB_DIR, "index.html")
            if os.path.isfile(html_path):
                with open(html_path) as f:
                    self.send_html(f.read())
            else:
                self.send_html("<h1>index.html not found</h1><p>Run installer to generate it.</p>")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        path = self.path

        if path == "/api/run":
            tool = body.get("tool", "")
            args = body.get("args", [])
            if tool and tool.replace("-","").replace("_","").isalnum():
                out = run_tool(tool, *args)
                self.send_json({"output": out})
            else:
                self.send_json({"error": "invalid tool"}, 400)
        elif path == "/api/memory/add":
            mtype = body.get("type", "fact")
            key   = body.get("key", "")
            value = body.get("value", "")
            out = run_tool("memory", "remember", mtype, key, value)
            self.send_json({"output": out})
        elif path == "/api/exec":
            # Execute a suggestion command (limited safe set)
            cmd = body.get("cmd", "")
            ALLOWED_PREFIXES = [
                "papy ", "~/.kiro/tools/", "git ", "python3 ",
                "npm ", "node ", "ls ", "cat ", "tail ", "df ", "free "
            ]
            BLOCKED = ["rm -rf", "dd if", "mkfs", "> /dev/", "git push --force"]
            is_safe = any(cmd.startswith(p) for p in ALLOWED_PREFIXES)
            is_blocked = any(b in cmd for b in BLOCKED)
            if is_safe and not is_blocked:
                try:
                    r = subprocess.run(
                        cmd, shell=True, capture_output=True, text=True, timeout=20,
                        env={**os.environ, "PATH": os.environ.get("PATH","") + ":/usr/local/bin"}
                    )
                    self.send_json({"output": r.stdout + r.stderr, "exit": r.returncode})
                except subprocess.TimeoutExpired:
                    self.send_json({"output": "Timeout (20s)", "exit": 1})
                except Exception as e:
                    self.send_json({"output": str(e), "exit": 1})
            else:
                self.send_json({"error": "Command not allowed via web UI", "cmd": cmd}, 403)
        elif path == "/api/shell":
            cmd = body.get("cmd", "")
            # Safety: only allow safe readonly cmds via web
            safe = ["ls","pwd","uname","date","echo","cat","head","tail","df","free","python3 --version","node --version","git --version"]
            allowed = any(cmd.startswith(s) for s in safe)
            if allowed:
                try:
                    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                    self.send_json({"output": r.stdout + r.stderr})
                except Exception as e:
                    self.send_json({"output": str(e)})
            else:
                self.send_json({"error": "command not allowed via web UI (readonly only)"}, 403)
        else:
            self.send_response(404)
            self.end_headers()

server = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
print(f"Dashboard: http://localhost:{PORT}")
server.serve_forever()
PYEOF
