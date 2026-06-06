# Copyright (c) 2026 何健 (He Jian)
# Cursor Session Query & Analysis Helper
# Query sessions from SQLite or JSON store with multiple views
param(
    [string]$DBPath    = "d:\HJ\Web\cursor-sessions.db",
    [string]$JSONPath  = "d:\HJ\Web\cursor-sessions.json",
    [int]$Limit       = 20,
    [string]$Query     = "",
    [string]$Since     = "",
    [string]$Until     = "",
    [int]$DayCount     = 0,
    [switch]$ShowMessages,
    [switch]$Stats,
    [switch]$ByDay,
    [switch]$ByTool,
    [switch]$TopTools,
    [switch]$ExportCSV,
    [string]$CSVPath   = ""
)

$ErrorActionPreference = "Continue"

# =====================================================================
# Python query engine
# =====================================================================
$pythonQueryScript = @"
import sys, json, os, sqlite3, csv
from datetime import datetime, timedelta
from pathlib import Path

DB_PATH  = r"${DBPath}"
JSON_PATH = r"${JSONPath}"
LIMIT    = ${Limit}
QUERY    = r"${Query}".strip()
SINCE    = r"${Since}".strip()
UNTIL    = r"${Until}".strip()
DAY_COUNT = ${DayCount}
EXPORT_CSV = r"${CSVPath}".strip()

# ---- Detect storage type ----
def get_conn():
    if not os.path.exists(DB_PATH):
        return None
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("PRAGMA journal_mode=WAL")
        return conn
    except:
        return None

def load_json():
    if not os.path.exists(JSON_PATH):
        return None
    try:
        with open(JSON_PATH, encoding="utf-8") as f:
            return json.load(f)
    except:
        return None

# ---- SQLite query helpers ----
def sqlite_query(conn, sql, params=None):
    if params is None:
        params = ()
    cur = conn.cursor()
    cur.execute(sql, params)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    return cols, rows

def sqlite_scalar(conn, sql, params=None):
    if params is None:
        params = ()
    cur = conn.cursor()
    cur.execute(sql, params)
    r = cur.fetchone()
    return r[0] if r else None

# ---- JSON query helpers ----
def json_sessions(store):
    sessions = store.get("sessions", {})
    return sessions

def json_query(store, sql_like, limit, since, until):
    sessions = json_sessions(store)
    results = []
    for sid, s in sessions.items():
        st = s.get("start_time", "")
        et = s.get("end_time", "")
        fq = s.get("first_query", "")
        # filter
        if since and st < since:
            continue
        if until and st > until:
            continue
        if QUERY:
            combined = (st + et + fq + s.get("summary", "")).lower()
            if QUERY.lower() not in combined:
                continue
        results.append(s)
    results.sort(key=lambda x: x.get("start_time", ""), reverse=True)
    return results[:limit]

# ---- Output formatters ----
def fmt_ts(ts):
    if not ts:
        return "N/A"
    try:
        return datetime.strptime(ts[:19], "%Y-%m-%d %H:%M:%S").strftime("%m/%d %H:%M")
    except:
        return ts[:16]

def fmt_preview(text, length=120):
    if not text:
        return ""
    # strip timestamp tag
    text = text.replace(r"<timestamp>", "").replace(r"</timestamp>", "")
    text = text.replace(r"<user_query>", "").replace(r"</user_query>", "")
    text = text.strip()
    if len(text) > length:
        return text[:length] + "..."
    return text

def print_sessions_table(results, has_messages=False):
    # Print header
    if has_messages:
        header = "{0:<38} {1:<14} {2:<6} {3:<8} {4:<6} {5:<50}".format(
            "SESSION_ID", "STARTED", "QS", "MSGS", "1ST?", "FIRST QUERY")
    else:
        header = "{0:<38} {1:<14} {2:<6} {3:<8} {4:<6} {5:<50}".format(
            "SESSION_ID", "STARTED", "QS", "END", "1ST?", "FIRST QUERY")
    print(header)
    print("-" * 120)
    for s in results:
        sid   = s.get("session_id", "")[:38]
        start = fmt_ts(s.get("start_time", ""))
        qc    = s.get("query_count", 0)
        msgs  = s.get("msg_count", "?")
        end   = fmt_ts(s.get("end_time", ""))
        fq    = s.get("first_query", "")
        flag  = "YES" if s.get("is_first_query") == 1 else ""
        preview = fmt_preview(fq, 48)
        row = "{0:<38} {1:<14} {2:>5} {3:<8} {4:>5}   {5:<50}".format(
            sid, start, qc, (str(msgs) if has_messages else end), flag, preview)
        print(row)
    print("")
    print("  Total: {0} sessions".format(len(results)))

def print_messages_for_session(conn, store, session_id):
    if conn:
        cols, rows = sqlite_query(conn,
            "SELECT role, timestamp, content_preview, tools_used, file_path FROM messages WHERE session_id=? ORDER BY id",
            (session_id,))
        print("  Messages for session {0}:".format(session_id))
        print("  {0:<10} {1:<14} {2:<50} {3}".format("ROLE", "TIME", "PREVIEW", "TOOLS"))
        print("  " + "-" * 110)
        for row in rows:
            role = row[0][:10]
            ts = fmt_ts(row[1])
            preview = fmt_preview(row[2] or "", 48)
            tools = (row[3] or "").replace("|", ", ")
            print("  {0:<10} {1:<14} {2:<50} {3}".format(role, ts, preview[:48], tools[:40]))
    else:
        s = store["sessions"].get(session_id, {})
        msgs = store["messages"].get(session_id, [])
        print("  Messages for session {0} ({1} messages):".format(session_id, len(msgs)))
        for m in msgs:
            role = m.get("role", "")[:10]
            ts = fmt_ts(m.get("timestamp", ""))
            preview = fmt_preview(m.get("content_preview", ""), 48)
            tools = m.get("tools_used", "").replace("|", ", ")
            print("  {0:<10} {1:<14} {2:<50} {3}".format(role, ts, preview[:48], tools[:40]))
    print("")

def print_stats(conn, store):
    if conn:
        total_sessions  = sqlite_scalar(conn, "SELECT COUNT(*) FROM sessions")
        total_messages  = sqlite_scalar(conn, "SELECT COUNT(*) FROM messages")
        first_queries   = sqlite_scalar(conn, "SELECT COUNT(*) FROM sessions WHERE is_first_query=1")
        avg_queries     = sqlite_scalar(conn, "SELECT AVG(query_count) FROM sessions") or 0
        avg_msgs        = sqlite_scalar(conn, "SELECT AVG(msg_count) FROM (SELECT COUNT(*) as msg_count FROM messages GROUP BY session_id)") or 0
        sql = "SELECT strftime('%Y-%m-%d', start_time) as day, COUNT(*) FROM sessions GROUP BY day ORDER BY day DESC LIMIT 10"
        cols, days = sqlite_query(conn, sql)
        first_session   = sqlite_scalar(conn, "SELECT MIN(start_time) FROM sessions")
        last_session    = sqlite_scalar(conn, "SELECT MAX(start_time) FROM sessions")
    else:
        s = store["sessions"]
        m = store["messages"]
        total_sessions = len(s)
        total_messages = sum(len(v) for v in m.values())
        first_queries  = sum(1 for v in s.values() if v.get("is_first_query") == 1)
        avg_queries    = sum(v.get("query_count", 0) for v in s.values()) / max(len(s), 1)
        avg_msgs       = total_messages / max(len(s), 1)
        day_counts = {}
        for v in s.values():
            d = v.get("start_time", "")[:10]
            if d:
                day_counts[d] = day_counts.get(d, 0) + 1
        days = sorted(day_counts.items(), key=lambda x: x[0], reverse=True)[:10]
        days = [(d, c) for d, c in days]
        first_session = min((v.get("start_time", "") for v in s.values()), default="")
        last_session  = max((v.get("start_time", "") for v in s.values()), default="")

    print("")
    print("  =============================================")
    print("  CURSOR SESSION DATABASE SUMMARY")
    print("  =============================================")
    print("  Total sessions    : {0:>6}".format(total_sessions))
    print("  Total messages    : {0:>6}".format(total_messages))
    print("  First queries     : {0:>6}".format(first_queries))
    print("  Avg queries/session: {0:>6.1f}".format(float(avg_queries)))
    print("  Avg messages/session: {0:>5.1f}".format(float(avg_msgs)))
    print("  First session     : {0}".format(fmt_ts(first_session)))
    print("  Last session      : {0}".format(fmt_ts(last_session)))
    print("  =============================================")
    print("  Sessions by day (last 10 days):")
    print("  {0:<12} {1:>6}".format("DATE", "COUNT"))
    print("  " + "-" * 20)
    for day, count in days:
        print("  {0:<12} {1:>6}".format(day, count))
    print("  =============================================")

def print_by_day(conn, store):
    if conn:
        sql = """
            SELECT strftime('%Y-%m-%d', start_time) as day,
                   COUNT(*) as sess_cnt,
                   SUM(query_count) as query_cnt
            FROM sessions
            GROUP BY day
            ORDER BY day DESC
        """
        cols, rows = sqlite_query(conn, sql)
        limit_int = int(LIMIT) if str(LIMIT).isdigit() else 20
        if len(rows) > limit_int:
            rows = rows[:limit_int]
    else:
        s = store["sessions"]
        day_data = {}
        for v in s.values():
            d = v.get("start_time", "")[:10]
            if d:
                if d not in day_data:
                    day_data[d] = {"sessions": 0, "queries": 0}
                day_data[d]["sessions"] += 1
                day_data[d]["queries"] += v.get("query_count", 0)
        rows = sorted(day_data.items(), key=lambda x: x[0], reverse=True)[:LIMIT]
        rows = [(d, v["sessions"], v["queries"]) for d, v in rows]

    print("")
    print("  {0:<12} {1:>8} {2:>8} {3:>8}".format("DATE", "SESSIONS", "QUERIES", "AVG/DAY"))
    print("  " + "-" * 44)
    for row in rows:
        day = row[0]
        sess = row[1]
        queries = row[2] or 0
        avg = queries / max(sess, 1)
        print("  {0:<12} {1:>8} {2:>8} {3:>8.1f}".format(day, sess, queries, avg))

def print_by_tool(conn, store):
    if conn:
        sql = """
            SELECT tools_used, COUNT(*) as cnt
            FROM messages
            WHERE tools_used != '' AND tools_used IS NOT NULL
            GROUP BY tools_used
            ORDER BY cnt DESC
            LIMIT ?
        """
        cols, rows = sqlite_query(conn, sql, (LIMIT,))
    else:
        tool_counts = {}
        for msgs in store.get("messages", {}).values():
            for m in msgs:
                t = m.get("tools_used", "")
                if t:
                    for tool in t.split("|"):
                        tool = tool.strip()
                        if tool:
                            tool_counts[tool] = tool_counts.get(tool, 0) + 1
        rows = sorted(tool_counts.items(), key=lambda x: x[1], reverse=True)[:LIMIT]
        rows = [(t, c) for t, c in rows]

    print("")
    print("  {0:<30} {1:>8}".format("TOOL", "COUNT"))
    print("  " + "-" * 40)
    for row in rows:
        tool, cnt = row
        print("  {0:<30} {1:>8}".format(tool, cnt))

def export_csv(conn, store, path):
    rows_out = []
    if conn:
        cols, rows = sqlite_query(conn, "SELECT * FROM sessions ORDER BY start_time DESC LIMIT ?", (LIMIT * 10,))
        for row in rows:
            rows_out.append(dict(zip(cols, row)))
    else:
        sessions = store["sessions"]
        rows_out = sorted(sessions.values(), key=lambda x: x.get("start_time", ""), reverse=True)[:LIMIT * 10]

    if not rows_out:
        print("[WARN] No data to export")
        return

    with open(path, "w", encoding="utf-8", newline="") as f:
        if rows_out:
            writer = csv.DictWriter(f, fieldnames=rows_out[0].keys())
            writer.writeheader()
            writer.writerows(rows_out)
    print("[OK] Exported {0} sessions to {1}".format(len(rows_out), path))

# =====================================================================
# Main
# =====================================================================
def main():
    conn = get_conn()
    store = load_json() if not conn else None

    # Stats view
    if "${Stats}" == "True":
        print_stats(conn, store)
        return

    # By-day view
    if "${ByDay}" == "True":
        print_by_day(conn, store)
        return

    # By-tool view
    if "${ByTool}" == "True" or "${TopTools}" == "True":
        print_by_tool(conn, store)
        return

    # Export CSV
    if "${ExportCSV}" == "True" and EXPORT_CSV:
        export_csv(conn, store, EXPORT_CSV)
        return

    # Default: list sessions
    limit_int = int(LIMIT) if str(LIMIT).isdigit() else 20
    if conn:
        where_parts = []
        params_list = []
        if SINCE:
            where_parts.append("start_time >= ?")
            params_list.append(SINCE)
        if UNTIL:
            where_parts.append("start_time <= ?")
            params_list.append(UNTIL)
        if QUERY:
            where_parts.append("(first_query LIKE ? OR session_id LIKE ? OR summary LIKE ?)")
            like = "%" + QUERY + "%"
            params_list.extend([like, like, like])
        where_clause = " WHERE " + " AND ".join(where_parts) if where_parts else ""
        sql = "SELECT * FROM sessions" + where_clause + " ORDER BY start_time DESC LIMIT " + str(limit_int)
        cols, rows = sqlite_query(conn, sql, params_list)
        results = [dict(zip(cols, r)) for r in rows]

        # add message count
        mc = {}
        c2, r2 = sqlite_query(conn, "SELECT session_id, COUNT(*) FROM messages GROUP BY session_id")
        for sid, cnt in r2:
            mc[sid] = cnt
        for r in results:
            r["msg_count"] = mc.get(r["session_id"], 0)
    else:
        results = json_query(store, QUERY, LIMIT, SINCE, UNTIL)
        for r in results:
            r["msg_count"] = len(store["messages"].get(r["session_id"], []))

    print("")
    print_sessions_table(results, has_messages=True)

    if "${ShowMessages}" == "True" and results:
        print("")
        for s in results[:5]:
            print_messages_for_session(conn, store, s["session_id"])

if __name__ == "__main__":
    main()
"@

# --- Run ---
$tempPy = Join-Path $env:TEMP ("cursor-query-" + [Guid]::NewGuid().ToString("N") + ".py")
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempPy, $pythonQueryScript, $utf8NoBom)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = "python"
$psi.Arguments              = $tempPy
$psi.UseShellExecute       = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow         = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

$proc   = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

Write-Host $stdout
if ($stderr -and $stderr.Trim()) {
    Write-Host "[STDERR] $stderr" -ForegroundColor Yellow
}

if (Test-Path $tempPy) {
    Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
}
