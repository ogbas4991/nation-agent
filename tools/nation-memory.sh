#!/bin/bash
# NATION AGENT — Persistent Memory System
# Stores and retrieves conversation context, facts, and decisions across sessions.
#
# Usage: nation-memory.sh <command> [args...]
#
# Commands:
#   init                             Initialize memory database
#   remember <type> <key> <value>    Store a memory entry
#   recall   [topic]                 Recall recent memories (optionally filtered)
#   search   <query>                 Search memories by keyword
#   context  [session_id]            Load full context for a session
#   forget   <key>                   Delete a specific memory entry
#   summary                          Show memory stats
#   export   [file]                  Export all memories to JSON
#   import   <file>                  Import memories from JSON
#   prune    [days]                  Delete memories older than N days (default 90)
#   log      <event> <detail>        Log an agent event
#   recent                           Show last 20 memories
#
# Memory types:
#   fact        - learned facts about the user/project
#   decision    - choices made during a session
#   error       - errors encountered and how they were fixed
#   preference  - user preferences discovered
#   project     - project-specific context
#   task        - completed or ongoing tasks
#   event       - agent lifecycle events
#
set -euo pipefail

MEMORY_DIR="$HOME/.kiro/memory"
DB="$MEMORY_DIR/memory.db"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [MEMORY] $*" >> "$LOG" 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$MEMORY_DIR"

# Python-based SQLite operations (no sqlite3 binary needed)
py_db() {
    python3 - "$DB" "$@" << 'PYEOF'
import sys, sqlite3, json, datetime, os

db_path = sys.argv[1]
args = sys.argv[2:]
cmd = args[0] if args else "help"

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("""
CREATE TABLE IF NOT EXISTS memories (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    session   TEXT,
    type      TEXT NOT NULL,
    key       TEXT NOT NULL,
    value     TEXT NOT NULL,
    tags      TEXT DEFAULT '',
    created   TEXT NOT NULL,
    updated   TEXT NOT NULL,
    UNIQUE(type, key) ON CONFLICT REPLACE
)""")
conn.execute("""
CREATE TABLE IF NOT EXISTS events (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    session  TEXT,
    event    TEXT NOT NULL,
    detail   TEXT,
    ts       TEXT NOT NULL
)""")
conn.commit()

now = datetime.datetime.now().isoformat(timespec='seconds')
session = os.environ.get('KIRO_SESSION_ID', 'unknown')

def fmt_rows(rows):
    if not rows:
        print("(no results)")
        return
    for row in rows:
        d = dict(row)
        ts = d.get('created','')[:16]
        print(f"[{ts}] [{d.get('type','?'):10}] {d.get('key','?')}")
        val = d.get('value','')
        for line in val.splitlines()[:3]:
            print(f"           {line}")
        if len(val.splitlines()) > 3:
            print(f"           ... ({len(val.splitlines())-3} more lines)")
        print()

if cmd == "remember":
    mtype = args[1] if len(args) > 1 else "fact"
    key   = args[2] if len(args) > 2 else die("key required")
    value = args[3] if len(args) > 3 else die("value required")
    conn.execute(
        "INSERT OR REPLACE INTO memories(session,type,key,value,created,updated) VALUES(?,?,?,?,?,?)",
        (session, mtype, key, value, now, now)
    )
    conn.commit()
    print(f"Remembered [{mtype}] {key}")

elif cmd == "recall":
    topic = args[1] if len(args) > 1 else None
    if topic:
        rows = conn.execute(
            "SELECT * FROM memories WHERE key LIKE ? OR value LIKE ? OR type=? ORDER BY updated DESC LIMIT 30",
            (f"%{topic}%", f"%{topic}%", topic)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM memories ORDER BY updated DESC LIMIT 30"
        ).fetchall()
    fmt_rows(rows)

elif cmd == "search":
    q = args[1] if len(args) > 1 else ""
    rows = conn.execute(
        "SELECT * FROM memories WHERE key LIKE ? OR value LIKE ? OR tags LIKE ? ORDER BY updated DESC LIMIT 20",
        (f"%{q}%", f"%{q}%", f"%{q}%")
    ).fetchall()
    fmt_rows(rows)

elif cmd == "context":
    sid = args[1] if len(args) > 1 else session
    rows = conn.execute(
        "SELECT * FROM memories WHERE session=? ORDER BY updated DESC",
        (sid,)
    ).fetchall()
    fmt_rows(rows)
    events = conn.execute(
        "SELECT * FROM events WHERE session=? ORDER BY ts DESC LIMIT 10",
        (sid,)
    ).fetchall()
    if events:
        print("=== Events ===")
        for e in events:
            print(f"  [{e['ts'][:16]}] {e['event']}: {e['detail']}")

elif cmd == "forget":
    key = args[1] if len(args) > 1 else die("key required")
    cur = conn.execute("DELETE FROM memories WHERE key=?", (key,))
    conn.commit()
    print(f"Forgotten: {key} ({cur.rowcount} entries removed)")

elif cmd == "summary":
    total = conn.execute("SELECT COUNT(*) FROM memories").fetchone()[0]
    types = conn.execute("SELECT type, COUNT(*) as n FROM memories GROUP BY type ORDER BY n DESC").fetchall()
    oldest = conn.execute("SELECT MIN(created) FROM memories").fetchone()[0]
    newest = conn.execute("SELECT MAX(updated) FROM memories").fetchone()[0]
    print(f"=== Memory Summary ===")
    print(f"Total entries : {total}")
    print(f"Oldest memory : {oldest}")
    print(f"Newest memory : {newest}")
    print(f"\nBy type:")
    for row in types:
        print(f"  {row['type']:15} {row['n']}")
    events_count = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    print(f"\nEvent log entries: {events_count}")

elif cmd == "export":
    out = args[1] if len(args) > 1 else None
    memories = [dict(r) for r in conn.execute("SELECT * FROM memories ORDER BY created").fetchall()]
    events   = [dict(r) for r in conn.execute("SELECT * FROM events ORDER BY ts").fetchall()]
    data = {"memories": memories, "events": events, "exported": now}
    if out:
        with open(out, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Exported {len(memories)} memories and {len(events)} events to {out}")
    else:
        print(json.dumps(data, indent=2))

elif cmd == "import":
    src = args[1] if len(args) > 1 else die("file required")
    with open(src) as f:
        data = json.load(f)
    imported = 0
    for m in data.get("memories", []):
        conn.execute(
            "INSERT OR REPLACE INTO memories(session,type,key,value,tags,created,updated) VALUES(?,?,?,?,?,?,?)",
            (m.get('session',''), m.get('type','fact'), m['key'], m['value'], m.get('tags',''), m.get('created',now), now)
        )
        imported += 1
    conn.commit()
    print(f"Imported {imported} memories from {src}")

elif cmd == "prune":
    days = int(args[1]) if len(args) > 1 else 90
    cutoff = (datetime.datetime.now() - datetime.timedelta(days=days)).isoformat(timespec='seconds')
    cur = conn.execute(
        "DELETE FROM memories WHERE updated < ? AND type NOT IN ('preference','fact','project')",
        (cutoff,)
    )
    conn.commit()
    print(f"Pruned {cur.rowcount} memories older than {days} days (kept preferences, facts, project memories)")

elif cmd == "log":
    event  = args[1] if len(args) > 1 else "event"
    detail = args[2] if len(args) > 2 else ""
    conn.execute(
        "INSERT INTO events(session,event,detail,ts) VALUES(?,?,?,?)",
        (session, event, detail, now)
    )
    conn.commit()

elif cmd == "recent":
    rows = conn.execute("SELECT * FROM memories ORDER BY updated DESC LIMIT 20").fetchall()
    fmt_rows(rows)

elif cmd == "init":
    print(f"Memory database ready: {db_path}")
    c = conn.execute("SELECT COUNT(*) FROM memories").fetchone()[0]
    e = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    print(f"Entries: {c} memories, {e} events")

conn.close()
PYEOF
}

CMD="${1:-help}"
log "$CMD $*"

case "$CMD" in
  init|remember|recall|search|context|forget|summary|export|import|prune|log|recent)
    py_db "$@"
    ;;
  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;
  *)
    die "Unknown command: $CMD. Run: nation-memory.sh help"
    ;;
esac
