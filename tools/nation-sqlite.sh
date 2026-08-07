#!/bin/bash
# NATION AGENT — SQLite Tool
# Usage: nation-sqlite.sh <command> [args...]
#
# Commands:
#   query   <db> <sql>               Run a SQL query
#   exec    <db> <sql>               Execute SQL (INSERT/UPDATE/DELETE/CREATE)
#   file    <db> <sql_file>          Execute SQL from a file
#   tables  <db>                     List all tables
#   schema  <db> [table]             Show schema (all or specific table)
#   import  <db> <table> <csv>       Import CSV into table
#   export  <db> <table> <csv>       Export table to CSV
#   dump    <db> [output.sql]        Dump entire database as SQL
#   info    <db>                     Show database info (size, tables, rows)
#   create  <db>                     Create a new empty database
#   vacuum  <db>                     Vacuum/optimize database
#   backup  <db> <dest>              Backup database file
#
# SQLite3 must be installed. Install with: pkg install sqlite
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [SQLITE] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Use sqlite3 if available, otherwise fall back to Python's sqlite3 module
get_sqlite() {
    if command -v sqlite3 &>/dev/null; then
        echo "sqlite3"
    else
        echo ""
    fi
}

# Run SQL via Python's built-in sqlite3 module (fallback)
py_sqlite() {
    local db="$1"
    local sql="$2"
    local mode="${3:-column}"  # column, csv, or list
    python3 - "$db" "$sql" "$mode" << 'PYEOF'
import sys, sqlite3, csv, io

db_path = sys.argv[1]
sql = sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "column"

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

statements = [s.strip() for s in sql.split(';') if s.strip()]
for stmt in statements:
    try:
        cur.execute(stmt)
        if cur.description:
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            if mode == "csv":
                writer = csv.writer(sys.stdout)
                writer.writerow(cols)
                for row in rows:
                    writer.writerow(row)
            else:
                # Column mode: auto-width
                widths = [max(len(str(c)), max((len(str(r[i])) for r in rows), default=0)) for i, c in enumerate(cols)]
                header = "  ".join(str(c).ljust(w) for c, w in zip(cols, widths))
                sep = "  ".join("-" * w for w in widths)
                print(header)
                print(sep)
                for row in rows:
                    print("  ".join(str(v if v is not None else "NULL").ljust(w) for v, w in zip(row, widths)))
                print(f"\n({len(rows)} rows)")
        else:
            conn.commit()
            print(f"OK ({cur.rowcount} rows affected)")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

conn.close()
PYEOF
}

require_db() {
    [ -n "${1:-}" ] || die "Database path required"
}

SQLITE=$(get_sqlite)

case "$CMD" in

  query)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "SQL query required"
    log "query $2"
    if [ -n "$SQLITE" ]; then
        $SQLITE -column -header "$2" "$3"
    else
        py_sqlite "$2" "$3" "column"
    fi
    ;;

  exec)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "SQL statement required"
    log "exec $2: $3"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" "$3"
        echo "OK"
    else
        py_sqlite "$2" "$3"
    fi
    ;;

  file)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "SQL file required"
    [ -f "$3" ] || die "SQL file not found: $3"
    log "file $2 < $3"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" < "$3"
    else
        py_sqlite "$2" "$(cat "$3")"
    fi
    echo "Executed: $3"
    ;;

  tables)
    require_db "${2:-}"
    log "tables $2"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" ".tables"
    else
        py_sqlite "$2" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    fi
    ;;

  schema)
    require_db "${2:-}"
    log "schema $2 ${3:-}"
    if [ -n "$SQLITE" ]; then
        if [ -n "${3:-}" ]; then
            $SQLITE "$2" ".schema $3"
        else
            $SQLITE "$2" ".schema"
        fi
    else
        TABLE_FILTER="${3:-}"
        if [ -n "$TABLE_FILTER" ]; then
            py_sqlite "$2" "SELECT sql FROM sqlite_master WHERE type='table' AND name='${TABLE_FILTER}';"
        else
            py_sqlite "$2" "SELECT sql FROM sqlite_master WHERE type='table' ORDER BY name;"
        fi
    fi
    ;;

  import)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "Table name required"
    [ -n "${4:-}" ] || die "CSV file required"
    [ -f "$4" ] || die "CSV file not found: $4"
    log "import $4 -> $2 table $3"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" ".mode csv" ".import $4 $3"
    else
        python3 - "$2" "$3" "$4" << 'PYEOF'
import sys, sqlite3, csv

db_path, table, csv_path = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(db_path)

with open(csv_path, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    if not rows:
        print("No rows found in CSV")
        sys.exit(0)
    cols = list(rows[0].keys())
    placeholders = ','.join('?' * len(cols))
    col_defs = ','.join(f'"{c}" TEXT' for c in cols)
    conn.execute(f'CREATE TABLE IF NOT EXISTS "{table}" ({col_defs})')
    conn.executemany(
        f'INSERT INTO "{table}" VALUES ({placeholders})',
        [tuple(r[c] for c in cols) for r in rows]
    )
    conn.commit()
    print(f"Imported {len(rows)} rows into {table}")

conn.close()
PYEOF
    fi
    ;;

  export)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "Table name required"
    [ -n "${4:-}" ] || die "Output CSV file required"
    log "export $2 table $3 -> $4"
    if [ -n "$SQLITE" ]; then
        $SQLITE -csv -header "$2" "SELECT * FROM $3;" > "$4"
    else
        python3 - "$2" "$3" "$4" << 'PYEOF'
import sys, sqlite3, csv

db_path, table, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur = conn.execute(f'SELECT * FROM "{table}"')
rows = cur.fetchall()

with open(out_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    if rows:
        writer.writerow(rows[0].keys())
        writer.writerows(rows)

print(f"Exported {len(rows)} rows to {out_path}")
conn.close()
PYEOF
    fi
    ;;

  dump)
    require_db "${2:-}"
    OUTPUT="${3:-}"
    log "dump $2 -> ${OUTPUT:-stdout}"
    if [ -n "$SQLITE" ]; then
        if [ -n "$OUTPUT" ]; then
            $SQLITE "$2" .dump > "$OUTPUT"
            echo "Dumped to: $OUTPUT"
        else
            $SQLITE "$2" .dump
        fi
    else
        python3 - "$2" "${OUTPUT:-}" << 'PYEOF'
import sys, sqlite3

db_path = sys.argv[1]
output = sys.argv[2] if len(sys.argv) > 2 else ""

conn = sqlite3.connect(db_path)
dump = '\n'.join(conn.iterdump())
conn.close()

if output:
    with open(output, 'w') as f:
        f.write(dump)
    print(f"Dumped to: {output}")
else:
    print(dump)
PYEOF
    fi
    ;;

  info)
    require_db "${2:-}"
    log "info $2"
    [ -f "$2" ] || die "Database not found: $2"
    echo "Database : $2"
    echo "Size     : $(du -sh "$2" | cut -f1)"
    echo ""
    echo "Tables:"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" "SELECT name, (SELECT count(*) FROM main.sqlite_master WHERE type='table' AND name=m.name) FROM sqlite_master m WHERE type='table' ORDER BY name;"
    else
        py_sqlite "$2" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
    fi
    ;;

  create)
    require_db "${2:-}"
    [ -f "$2" ] && die "Database already exists: $2. Delete it first if you want to recreate."
    log "create $2"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" "SELECT 1;" > /dev/null
    else
        python3 -c "import sqlite3; sqlite3.connect('$2').close()"
    fi
    echo "Created: $2"
    ;;

  vacuum)
    require_db "${2:-}"
    log "vacuum $2"
    if [ -n "$SQLITE" ]; then
        $SQLITE "$2" "VACUUM;"
    else
        py_sqlite "$2" "VACUUM;"
    fi
    echo "Vacuumed: $2"
    ;;

  backup)
    require_db "${2:-}"
    [ -n "${3:-}" ] || die "Destination path required"
    log "backup $2 -> $3"
    cp "$2" "$3"
    echo "Backed up: $2 -> $3"
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-sqlite.sh help"
    ;;
esac
