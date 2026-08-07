#!/bin/bash
# NATION AGENT — ClawHub Skill Marketplace
# Browse, search, and install skills from clawhub.ai
#
# Usage: nation-clawhub.sh <command> [args...]
#
# Commands:
#   search  <query>    Search ClawHub for skills
#   browse  [sort]     Browse skills (trending|top|new, default: trending)
#   install <slug>     Download and install a skill
#   info    <slug>     Show skill details + security status
#   update  <slug>     Re-download an installed skill
#   update-all         Update all ClawHub-sourced skills
#   list               List installed ClawHub skills
#   remove  <slug>     Remove an installed skill
#   help               Show this help

set -uo pipefail
source "$(dirname "$0")/../lib/nation-platform.sh" 2>/dev/null || true

CMD="${1:-help}"
API="https://clawhub.ai/api/v1"
SKILLS_DIR="${NATION_SKILLS:-$HOME/.kiro/skills}"
REGISTRY="$SKILLS_DIR/registry.json"
LOG="${NATION_LOGS:-$HOME/.kiro/logs}/nation-agent.log"
mkdir -p "$SKILLS_DIR" "$(dirname "$LOG")"

TS=$(date '+%Y-%m-%d %H:%M:%S')
log() { echo "[$TS] [CLAWHUB] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo -e "${R:-}ERROR: $*" >&2; exit 1; }

# ── Colors ────────────────────────────────────────────────────────────────
if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'
    W='\033[1;37m'; D='\033[38;5;244m'; GR='\033[38;5;82m'
    RD='\033[38;5;196m'; YL='\033[38;5;226m'
else
    R=''; G1=''; C1=''; W=''; D=''; GR=''; RD=''; YL=''
fi

hdr() { echo -e "${G1}══ $* ══${R}"; }

# ── Registry helpers ──────────────────────────────────────────────────────
init_registry() {
    [ -f "$REGISTRY" ] || echo '{"skills":{}}' > "$REGISTRY"
}

reg_get() {
    python3 -c "
import json, sys
with open('$REGISTRY') as f: d = json.load(f)
print(json.dumps(d.get('skills',{}).get(sys.argv[1],{})))
" "$1" 2>/dev/null || echo "{}"
}

reg_set() {
    local name="$1" path="$2" desc="$3" src="$4"
    python3 - "$name" "$path" "$desc" "$src" << 'PY'
import json, sys, datetime, os
name, path, desc, src = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
d['skills'][name] = {"path": path, "description": desc,
    "source": src, "added": datetime.datetime.now().isoformat()[:19]}
with open(reg, 'w') as f: json.dump(d, f, indent=2)
PY
}

# ── API helpers ───────────────────────────────────────────────────────────
api_get() {
    local url="$1"
    curl -sf --max-time 15 \
        -H "Accept: application/json" \
        -H "User-Agent: nation-agent/3.0" \
        "$url" 2>/dev/null
}

# ── Commands ──────────────────────────────────────────────────────────────

do_search() {
    local query="${*:-}"
    [ -n "$query" ] || die "Usage: papy clawhub search <query>"
    log "search: $query"
    hdr "ClawHub Search: $query"
    echo ""
    local url="${API}/search?q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")&limit=15&nonSuspiciousOnly=true"
    local raw; raw=$(api_get "$url") || die "Network error — check connection"
    python3 - "$raw" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
results = data.get('results', [])
if not results:
    print("  No results found.")
    sys.exit(0)
R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'; W='\033[1;37m'; D='\033[38;5;244m'
for r in results:
    slug = r.get('slug','')
    name = r.get('displayName', slug)
    summary = r.get('summary','')[:80]
    owner = r.get('ownerHandle','')
    ver = r.get('version','')
    print(f"  {G1}{name}{R}  {D}@{owner}  v{ver}{R}")
    print(f"    {summary}")
    print(f"    {C1}Install:{R} papy clawhub install {slug}")
    print()
PY
}

do_browse() {
    local sort="${2:-trending}"
    case "$sort" in
        top|stars)    sort_param="stars" ;;
        new|newest)   sort_param="createdAt" ;;
        trending|*)   sort_param="trending" ;;
    esac
    log "browse: $sort_param"
    hdr "ClawHub — $(echo "$sort_param" | tr '[:lower:]' '[:upper:]')"
    echo ""
    local raw; raw=$(api_get "${API}/skills?sort=${sort_param}&limit=20&nonSuspiciousOnly=true") || die "Network error"
    python3 - "$raw" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
items = data.get('items', [])
if not items:
    print("  No skills found.")
    sys.exit(0)
R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'; W='\033[1;37m'; D='\033[38;5;244m'; GR='\033[38;5;82m'
for i, item in enumerate(items, 1):
    slug = item.get('slug','')
    name = item.get('displayName', slug)
    summary = (item.get('summary') or '')[:75]
    topics = ', '.join(item.get('topics', [])[:3])
    ver = (item.get('latestVersion') or {}).get('version','')
    print(f"  {D}{i:2}.{R} {G1}{name}{R}  {D}v{ver}  [{topics}]{R}")
    if summary:
        print(f"       {summary}")
    print(f"       {C1}papy clawhub install {slug}{R}")
    print()
PY
}

do_info() {
    local slug="${2:-}"
    [ -n "$slug" ] || die "Usage: papy clawhub info <slug>"
    log "info: $slug"
    local raw; raw=$(api_get "${API}/skills/${slug}") || die "Skill not found: $slug"
    hdr "ClawHub Skill: $slug"
    echo ""
    python3 - "$raw" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
skill = data.get('skill', {})
ver   = data.get('latestVersion', {})
owner = data.get('owner', {})
mod   = data.get('moderation', {})
R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'; W='\033[1;37m'; D='\033[38;5;244m'
GR='\033[38;5;82m'; RD='\033[38;5;196m'; YL='\033[38;5;226m'
print(f"  {W}Name   :{R} {skill.get('displayName', skill.get('slug',''))}")
print(f"  {W}Slug   :{R} {skill.get('slug','')}")
print(f"  {W}Owner  :{R} @{owner.get('handle','')}  ({owner.get('displayName','')})")
print(f"  {W}Version:{R} {ver.get('version','')}")
print(f"  {W}Topics :{R} {', '.join(skill.get('topics', []))}")
print()
summary = skill.get('summary') or ''
if summary:
    print(f"  {summary}")
    print()
if mod:
    verdict  = mod.get('verdict','unknown')
    suspic   = mod.get('isSuspicious', False)
    malware  = mod.get('isMalwareBlocked', False)
    if malware:
        color = RD; icon = '✗ BLOCKED'
    elif suspic:
        color = YL; icon = '⚠ SUSPICIOUS'
    else:
        color = GR; icon = '✓ CLEAN'
    print(f"  {W}Security:{R} {color}{icon}{R}  (verdict: {verdict})")
    print()
url = f"https://clawhub.ai/{owner.get('handle','')}/skills/{skill.get('slug','')}"
print(f"  {C1}URL    :{R} {url}")
print(f"  {C1}Install:{R} papy clawhub install {skill.get('slug','')}")
PY
}

do_install() {
    local slug="${2:-}"
    [ -n "$slug" ] || die "Usage: papy clawhub install <slug>"
    log "install: $slug"
    init_registry
    echo -e "${G1}◆ Installing skill: ${W}${slug}${R}"

    # Get metadata
    local meta; meta=$(api_get "${API}/skills/${slug}") || die "Skill not found: $slug"

    # Check security
    local verdict; verdict=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
mod = d.get('moderation', {})
blocked = mod.get('isMalwareBlocked', False)
print('blocked' if blocked else 'ok')
" "$meta")
    [ "$verdict" = "blocked" ] && die "Skill '$slug' is blocked for malware. Aborting."

    local name desc owner
    name=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('skill',{}).get('displayName',sys.argv[2]))" "$meta" "$slug")
    desc=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print((d.get('skill',{}).get('summary') or '')[:120])" "$meta")
    owner=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('owner',{}).get('handle',''))" "$meta")

    # Create skill dir
    local skill_dir="$SKILLS_DIR/$slug"
    mkdir -p "$skill_dir"

    # Download SKILL.md
    echo -e "  ${D}Downloading SKILL.md...${R}"
    local skill_url="${API}/skills/${slug}/file?path=SKILL.md"
    if curl -sf --max-time 30 -H "User-Agent: nation-agent/3.0" \
        "$skill_url" -o "$skill_dir/SKILL.md" 2>/dev/null && [ -s "$skill_dir/SKILL.md" ]; then
        echo -e "  ${GR}✓${R} SKILL.md downloaded"
    else
        # Fallback: write a basic SKILL.md from metadata
        python3 - "$meta" "$slug" << 'PY'
import json, sys, os
data = json.loads(sys.argv[1])
slug = sys.argv[2]
skill = data.get('skill', {})
ver = data.get('latestVersion', {})
owner = data.get('owner', {})
skill_dir = os.path.expanduser(f'~/.kiro/skills/{slug}')
with open(f'{skill_dir}/SKILL.md', 'w') as f:
    f.write(f"---\nname: {skill.get('displayName', slug)}\ndescription: {skill.get('summary','')}\n---\n\n")
    f.write(f"# {skill.get('displayName', slug)}\n\n")
    f.write(f"{skill.get('summary','')}\n\n")
    f.write(f"**Version:** {ver.get('version','')}\n")
    f.write(f"**Publisher:** @{owner.get('handle','')}\n")
    f.write(f"**URL:** https://clawhub.ai/{owner.get('handle','')}/skills/{slug}\n")
PY
        echo -e "  ${YL}⚠${R} Generated basic SKILL.md from metadata"
    fi

    # Register in registry
    local src="https://clawhub.ai/${owner}/skills/${slug}"
    reg_set "$slug" "$skill_dir/SKILL.md" "$desc" "$src"

    echo -e "  ${GR}✓${R} Skill ${W}${name}${R} installed"
    echo -e "  ${D}Path: $skill_dir/SKILL.md${R}"
    echo -e "  ${D}Load: papy skills load ${slug}${R}"
    log "installed: $slug"
}

do_update() {
    local slug="${2:-}"
    [ -n "$slug" ] || die "Usage: papy clawhub update <slug>"
    log "update: $slug"
    # Re-run install (overwrites)
    do_install "" "$slug"
}

do_update_all() {
    log "update-all"
    init_registry
    echo -e "${G1}◆ Updating all ClawHub skills...${R}\n"
    python3 - "$REGISTRY" << 'PY'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
skills = d.get('skills', {})
clawhub = [(name, info) for name, info in skills.items()
           if 'clawhub.ai' in info.get('source', '')]
if not clawhub:
    print("  No ClawHub skills installed.")
else:
    for name, _ in clawhub:
        print(name)
PY
    local slugs
    slugs=$(python3 -c "
import json, sys
with open('$REGISTRY') as f: d = json.load(f)
for n, i in d.get('skills',{}).items():
    if 'clawhub.ai' in i.get('source',''):
        print(n)
")
    [ -n "$slugs" ] || { echo "  No ClawHub skills to update."; return; }
    while IFS= read -r s; do
        [ -n "$s" ] && do_install "" "$s"
    done <<< "$slugs"
    echo -e "\n${GR}✓ All ClawHub skills updated.${R}"
}

do_list() {
    init_registry
    hdr "Installed ClawHub Skills"
    echo ""
    python3 - "$REGISTRY" << 'PY'
import json, sys, os
with open(sys.argv[1]) as f: d = json.load(f)
R='\033[0m'; G1='\033[38;5;214m'; C1='\033[38;5;51m'
W='\033[1;37m'; D='\033[38;5;244m'; GR='\033[38;5;82m'; RD='\033[38;5;196m'
skills = {n: i for n, i in d.get('skills',{}).items()
          if 'clawhub.ai' in i.get('source','')}
if not skills:
    print("  No ClawHub skills installed.")
    print(f"  Browse: {C1}papy clawhub browse{R}")
    print(f"  Search: {C1}papy clawhub search <query>{R}")
else:
    for name, info in sorted(skills.items()):
        exists = os.path.isfile(info.get('path',''))
        icon = f'{GR}✓{R}' if exists else f'{RD}✗{R}'
        print(f"  {icon} {W}{name}{R}")
        print(f"      {info.get('description','')[:80]}")
        print(f"      {D}{info.get('source','')}{R}")
        print()
PY
}

do_remove() {
    local slug="${2:-}"
    [ -n "$slug" ] || die "Usage: papy clawhub remove <slug>"
    log "remove: $slug"
    init_registry
    python3 - "$slug" << 'PY'
import json, sys, os
slug = sys.argv[1]
reg = os.path.expanduser('~/.kiro/skills/registry.json')
with open(reg) as f: d = json.load(f)
if slug in d.get('skills', {}):
    del d['skills'][slug]
    with open(reg, 'w') as f: json.dump(d, f, indent=2)
    print(f"Removed '{slug}' from registry.")
else:
    print(f"Not found: {slug}", file=sys.stderr)
    sys.exit(1)
PY
    echo -e "  ${D}Files kept at: $SKILLS_DIR/$slug/${R}"
    echo -e "  ${D}To also delete files: rm -rf $SKILLS_DIR/$slug${R}"
}

# ── Dispatch ──────────────────────────────────────────────────────────────
case "$CMD" in
    search)         do_search "$@" ;;
    browse)         do_browse "$@" ;;
    install)        do_install "$@" ;;
    info)           do_info "$@" ;;
    update)         do_update "$@" ;;
    update-all)     do_update_all ;;
    list)           do_list ;;
    remove)         do_remove "$@" ;;
    help|--help|-h)
        grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
        ;;
    *)
        echo -e "${RD}Unknown command: $CMD${R}  Run: papy clawhub help"
        exit 1
        ;;
esac
