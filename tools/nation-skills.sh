#!/bin/bash
# NATION AGENT — Skill Auto-Loader & Registry Manager
# Manages skills: auto-loads all SKILL.md files, lets you add/remove/list skills.
#
# Usage: nation-skills.sh <command> [args...]
#
# Commands:
#   list                         List all registered skills
#   load    [name]               Load a skill into context (or all if no name)
#   add     <name> <path_or_url> Add a new skill (local file or GitHub URL)
#   remove  <name>               Remove a skill from registry
#   create  <name> <description> Scaffold a new SKILL.md template
#   update  <name>               Re-download a skill from its source URL
#   update-all                   Re-download all remotely-sourced skills
#   scan                         Scan skills/ dir and auto-register any new SKILL.md
#   info    <name>               Show details about a skill
#   edit    <name>               Open a skill for editing
#   registry                     Show the full skill registry (JSON)
#
set -euo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-list}"
SKILLS_DIR="${NATION_SKILLS:-$HOME/.kiro/skills}"
REGISTRY="$SKILLS_DIR/registry.json"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$SKILLS_DIR"
mkdir -p "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [SKILLS] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Registry helpers ──────────────────────────────────────────────────────
init_registry() {
    if [ ! -f "$REGISTRY" ]; then
        echo '{"skills":{}}' > "$REGISTRY"
    fi
}

reg_get() { python3 -c "import json,sys; d=json.load(open('$REGISTRY')); print(json.dumps(d.get('skills',{}).get(sys.argv[1],{})))" "$1" 2>/dev/null || echo "{}"; }

reg_set() {
    local name="$1" path="$2" desc="$3" src="${4:-local}"
    python3 - "$name" "$path" "$desc" "$src" << 'PYEOF'
import json, sys, datetime
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open('/dev/stdin', 'r') if False else open(sys.argv[0]) as _: pass
import os
reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc, "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
print(f"Registered: {name}")
PYEOF
}

reg_del() {
    python3 -c "
import json, sys
reg = '$REGISTRY'
with open(reg) as f: d = json.load(f)
name = sys.argv[1]
if name in d.get('skills',{}):
    del d['skills'][name]
    with open(reg, 'w') as f: json.dump(d, f, indent=2)
    print(f'Removed: {name}')
else:
    print(f'Not found: {name}', file=sys.stderr)
    sys.exit(1)
" "$1"
}

case "$CMD" in

  list)
    init_registry
    log "list skills"
    echo "=== NATION AGENT Skills ==="
    echo ""
    python3 - "$SKILLS_DIR" "$REGISTRY" << 'PYEOF'
import json, os, sys

skills_dir = sys.argv[1]
reg_path = sys.argv[2]

with open(reg_path) as f:
    reg = json.load(f)

skills = reg.get('skills', {})
if not skills:
    print("  No skills registered. Run: nation-skills.sh scan")
    sys.exit(0)

for name, info in sorted(skills.items()):
    path = info.get('path', '')
    desc = info.get('description', '(no description)')
    src  = info.get('source', 'local')
    exists = '✓' if os.path.isfile(path) else '✗'
    print(f"  {exists} [{name}]")
    print(f"      {desc}")
    print(f"      path: {path}  source: {src}")
    print()
PYEOF
    ;;

  load)
    init_registry
    SKILL_NAME="${2:-}"
    log "load $SKILL_NAME"

    if [ -n "$SKILL_NAME" ]; then
        INFO=$(reg_get "$SKILL_NAME")
        PATH_VAL=$(echo "$INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('path',''))")
        [ -n "$PATH_VAL" ] || die "Skill not found: $SKILL_NAME. Run: nation-skills.sh list"
        [ -f "$PATH_VAL" ] || die "Skill file missing: $PATH_VAL"
        echo "=== Skill: $SKILL_NAME ==="
        cat "$PATH_VAL"
    else
        # Load all skills
        echo "=== All Loaded Skills ==="
        python3 -c "
import json, os, sys
with open('$REGISTRY') as f: d = json.load(f)
for name, info in sorted(d.get('skills',{}).items()):
    path = info.get('path','')
    if os.path.isfile(path):
        print(f'\\n--- SKILL: {name} ---')
        with open(path) as sf: print(sf.read())
"
    fi
    ;;

  add)
    init_registry
    [ -n "${2:-}" ] || die "Skill name required"
    [ -n "${3:-}" ] || die "Path or URL required"
    NAME="$2"
    SOURCE="$3"
    SKILL_DIR="$SKILLS_DIR/$NAME"
    SKILL_FILE="$SKILL_DIR/SKILL.md"
    mkdir -p "$SKILL_DIR"
    log "add skill $NAME from $SOURCE"

    if [[ "$SOURCE" == http* ]]; then
        echo "Downloading skill: $NAME from $SOURCE"
        curl -fsSL "$SOURCE" -o "$SKILL_FILE" || die "Failed to download: $SOURCE"
        echo "Downloaded: $SKILL_FILE"
        DESC=$(python3 -c "
import re
with open('$SKILL_FILE') as f: content = f.read()
m = re.search(r'description:\s*(.+)', content)
print(m.group(1).strip() if m else 'No description')
" 2>/dev/null || echo "Downloaded skill")
        # Store source URL in registry for future updates
        python3 - "$NAME" "$SKILL_FILE" "$DESC" "$SOURCE" << 'PYEOF'
import json, sys, datetime
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
import os; reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc, "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
print(f"Registered skill: {name}")
PYEOF
    elif [ -f "$SOURCE" ]; then
        cp "$SOURCE" "$SKILL_FILE"
        DESC=$(python3 -c "
import re
with open('$SKILL_FILE') as f: content = f.read()
m = re.search(r'description:\s*(.+)', content)
print(m.group(1).strip() if m else 'Local skill')
" 2>/dev/null || echo "Local skill")
        python3 - "$NAME" "$SKILL_FILE" "$DESC" "local:$SOURCE" << 'PYEOF'
import json, sys, datetime
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
import os; reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc, "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
print(f"Registered skill: {name}")
PYEOF
    else
        die "Source not found: $SOURCE (must be a URL or existing file path)"
    fi
    echo "Skill '$NAME' added. Run: nation-skills.sh list"
    ;;

  remove)
    init_registry
    [ -n "${2:-}" ] || die "Skill name required"
    log "remove $2"
    reg_del "$2"
    echo "Skill removed from registry (files kept at $SKILLS_DIR/$2/)"
    echo "To also delete files: rm -rf $SKILLS_DIR/$2"
    ;;

  create)
    [ -n "${2:-}" ] || die "Skill name required"
    [ -n "${3:-}" ] || die "Description required"
    NAME="$2"
    DESC="${*:3}"
    SKILL_DIR="$SKILLS_DIR/$NAME"
    SKILL_FILE="$SKILL_DIR/SKILL.md"
    mkdir -p "$SKILL_DIR"
    log "create skill $NAME"

    cat > "$SKILL_FILE" << EOF
---
name: $NAME
description: $DESC
---

# $NAME

## Overview

Describe what this skill is for and when to use it.

## Usage

\`\`\`bash
# Example commands or code
\`\`\`

## Details

Add detailed instructions, examples, and notes here.
EOF

    # Register it
    init_registry
    python3 - "$NAME" "$SKILL_FILE" "$DESC" "local" << 'PYEOF'
import json, sys, datetime
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
import os; reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc, "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
PYEOF

    echo "Skill template created: $SKILL_FILE"
    echo "Edit it: nano $SKILL_FILE"
    ;;

  update)
    init_registry
    [ -n "${2:-}" ] || die "Skill name required"
    NAME="$2"
    INFO=$(reg_get "$NAME")
    SRC=$(echo "$INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('source',''))")
    PATH_VAL=$(echo "$INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('path',''))")
    [[ "$SRC" == http* ]] || die "Skill '$NAME' has no remote source URL to update from. Source: $SRC"
    log "update $NAME from $SRC"
    echo "Updating $NAME from $SRC..."
    curl -fsSL "$SRC" -o "$PATH_VAL" || die "Update failed"
    echo "Updated: $NAME"
    ;;

  update-all)
    init_registry
    log "update-all"
    python3 -c "
import json, subprocess, sys
with open('$REGISTRY') as f: d = json.load(f)
for name, info in d.get('skills',{}).items():
    src = info.get('source','')
    path = info.get('path','')
    if src.startswith('http'):
        print(f'Updating {name}...')
        r = subprocess.run(['curl','-fsSL',src,'-o',path], capture_output=True)
        print('  OK' if r.returncode == 0 else f'  FAIL: {r.stderr.decode().strip()}')
print('Done.')
"
    ;;

  scan)
    init_registry
    log "scan"
    echo "Scanning $SKILLS_DIR for SKILL.md files..."
    FOUND=0
    while IFS= read -r -d '' skill_file; do
        DIR=$(dirname "$skill_file")
        NAME=$(basename "$DIR")
        # Extract description from frontmatter
        DESC=$(python3 -c "
import re
with open('$skill_file') as f: content = f.read()
m = re.search(r'description:\s*(.+)', content)
print(m.group(1).strip()[:100] if m else 'No description')
" 2>/dev/null || echo "No description")
        # Register if not already
        EXISTING=$(reg_get "$NAME")
        if [ "$EXISTING" = "{}" ]; then
            python3 - "$NAME" "$skill_file" "$DESC" "local" << 'PYEOF'
import json, sys, datetime
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
import os; reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc, "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
PYEOF
            echo "  Registered: $NAME"
            FOUND=$((FOUND+1))
        else
            echo "  Already registered: $NAME"
        fi
    done < <(find "$SKILLS_DIR" -name "SKILL.md" -print0 2>/dev/null)
    echo "Scan complete. $FOUND new skill(s) registered."
    ;;

  info)
    init_registry
    [ -n "${2:-}" ] || die "Skill name required"
    log "info $2"
    INFO=$(reg_get "$2")
    echo "=== Skill: $2 ==="
    echo "$INFO" | python3 -c "
import json, sys, os
d = json.load(sys.stdin)
if not d:
    print('Not found in registry')
    sys.exit(1)
for k,v in d.items():
    print(f'{k:15}: {v}')
path = d.get('path','')
if os.path.isfile(path):
    print(f'\\nFile exists: yes ({os.path.getsize(path)} bytes)')
    with open(path) as f: content = f.read()
    lines = content.splitlines()
    print(f'Lines: {len(lines)}')
    print('\\n--- First 10 lines ---')
    print('\\n'.join(lines[:10]))
"
    ;;

  edit)
    [ -n "${2:-}" ] || die "Skill name required"
    SKILL_FILE="$SKILLS_DIR/$2/SKILL.md"
    [ -f "$SKILL_FILE" ] || die "Skill file not found: $SKILL_FILE"
    EDITOR="${EDITOR:-nano}"
    log "edit $2"
    "$EDITOR" "$SKILL_FILE"
    ;;

  registry)
    init_registry
    cat "$REGISTRY" | python3 -m json.tool
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-skills.sh help"
    ;;
esac
