#!/bin/bash
# NATION AGENT — Follow-up Suggestion Engine
# Analyzes recent activity and suggests next tasks.
# Usage: nation-suggest.sh [context]
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

MEMORY="${NATION_TOOLS:-$HOME/.kiro/tools}/nation-memory.sh"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
CONTEXT="${*:-}"

python3 - "$CONTEXT" << 'PYEOF'
import sys, os, sqlite3, json, re, datetime

context = sys.argv[1] if len(sys.argv) > 1 else ""
db_path = os.path.expanduser("~/.kiro/memory/memory.db")
log_path = os.path.expanduser("~/.kiro/logs/nation-agent.log")
cwd = os.getcwd()

# ── Load recent memory ────────────────────────────────────────────────────
memories = []
try:
    conn = sqlite3.connect(db_path)
    memories = conn.execute(
        "SELECT type,key,value FROM memories ORDER BY updated DESC LIMIT 30"
    ).fetchall()
    conn.close()
except: pass

# ── Load recent log ───────────────────────────────────────────────────────
log_lines = []
try:
    with open(log_path) as f:
        log_lines = f.readlines()[-50:]
except: pass

# ── Detect project type ───────────────────────────────────────────────────
project_type = "general"
if os.path.isfile("package.json"):      project_type = "nodejs"
elif os.path.isfile("requirements.txt") or os.path.isfile("pyproject.toml"): project_type = "python"
elif os.path.isfile("Cargo.toml"):      project_type = "rust"
elif os.path.isfile("build.gradle"):    project_type = "android"
elif os.path.isfile("Makefile"):        project_type = "make"
elif os.path.isfile(".git/config"):     project_type = "git-repo"

# ── Detect recent activity from logs ─────────────────────────────────────
recent_tools = []
for line in log_lines[-20:]:
    m = re.search(r'\[(FILE|SHELL|GIT|PYTHON|HTTP|SQLITE|MEMORY|SPAWN|STOP)\]', line)
    if m: recent_tools.append(m.group(1))

recent_errors = [l for l in log_lines if 'ERROR' in l or 'FAIL' in l or 'BLOCKED' in l]
recent_writes = [l for l in log_lines if '[POST] file' in l or 'wrote:' in l.lower()]
has_git = os.path.isdir(".git")
has_uncommitted = False
if has_git:
    import subprocess
    r = subprocess.run(["git","status","--short"], capture_output=True, text=True)
    has_uncommitted = bool(r.stdout.strip())

# ── Generate suggestions ──────────────────────────────────────────────────
suggestions = []

# Based on project type
if project_type == "nodejs":
    suggestions += [
        "Run tests: npm test",
        "Check for security issues: npm audit",
        "Update dependencies: npm outdated",
    ]
elif project_type == "python":
    suggestions += [
        "Run linter: papy tool python lint <file.py>",
        "Check dependencies: papy tool python pip list",
        "Run tests: python3 -m pytest",
    ]
elif project_type == "android":
    suggestions += [
        "Build APK: papy apk build .",
        "Check ADB devices: papy adb devices",
        "Deploy to device: papy apk deploy app.apk",
    ]

# Based on git state
if has_git and has_uncommitted:
    suggestions.insert(0, "Commit changes: papy tool git commit 'your message'")
    suggestions.insert(1, "Review diff: papy tool git diff")

# Based on recent errors
if recent_errors:
    suggestions.insert(0, "Check errors: papy health")
    suggestions.insert(1, "View logs: tail -20 ~/.kiro/logs/nation-agent.log")

# Based on recent file writes
if recent_writes:
    suggestions.append("Review changes: papy tool git diff")
    suggestions.append("Run health check: papy health")

# Based on context keywords
ctx_lower = context.lower()
if any(w in ctx_lower for w in ["api","rest","http","endpoint"]):
    suggestions += ["Test API: papy tool rest ping <url>", "Mock server: papy tool rest mock 8080"]
if any(w in ctx_lower for w in ["database","sqlite","db","sql"]):
    suggestions += ["Browse DB: papy tool sqlite tables <db>", "Export data: papy tool sqlite export <db> t out.csv"]
if any(w in ctx_lower for w in ["docker","container"]):
    suggestions += ["List containers: papy tool docker ps", "View logs: papy tool docker logs <name>"]
if any(w in ctx_lower for w in ["deploy","push","release"]):
    suggestions += ["Push to GitHub: papy github push", "Tag release: papy tool git tag v1.0.0"]

# Always useful
suggestions += [
    "Browse memory: papy memory recall",
    "Add a skill: papy skills add <name> <url>",
    "Start web UI: papy web",
]

# Deduplicate and limit
seen = set()
unique = []
for s in suggestions:
    if s not in seen:
        seen.add(s)
        unique.append(s)
        if len(unique) >= 7: break

print("=== 💡 Suggested next tasks ===")
for i, s in enumerate(unique, 1):
    print(f"  {i}. {s}")
print()
PYEOF
