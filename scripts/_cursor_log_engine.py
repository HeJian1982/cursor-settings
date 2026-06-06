# Copyright (c) 2026 何健 (He Jian)
# Cursor Conversation Logger — Python engine (written by PowerShell wrapper)
import sys, json, os, sqlite3, re, time
from datetime import datetime
from pathlib import Path

TRANSCRIPT_DIR = r"C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
DB_PATH = r"d:\HJ\Web\cursor-sessions.db"
JSON_PATH = r"d:\HJ\Web\cursor-sessions.json"

# ---- Schema ----
SCHEMA = [
    "CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT UNIQUE NOT NULL, start_time TEXT NOT NULL, end_time TEXT, cwd TEXT, is_first_query INTEGER DEFAULT 0, summary TEXT, query_count INTEGER DEFAULT 0, first_query TEXT)",
    "CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, role TEXT NOT NULL, timestamp TEXT, content TEXT, content_preview TEXT, tools_used TEXT, file_path TEXT, FOREIGN KEY (session_id) REFERENCES sessions(session_id))",
    "CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_time DESC)",
    "CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id)",
]

# ---- DB helpers ----
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def init_db(conn):
    for sql in SCHEMA:
        conn.execute(sql)
    conn.commit()

# ---- Timestamp extraction from content ----
TIMESTAMP_RE = re.compile(r'<timestamp>(.*?)</timestamp>', re.DOTALL)

def extract_timestamp(content):
    if not content:
        return None
    m = TIMESTAMP_RE.search(content)
    if m:
        raw = m.group(1).strip()
        try:
            dt = datetime.strptime(raw, "%A, %b %d, %Y, %I:%M %p (UTC+8)")
            return dt.strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            try:
                dt = datetime.strptime(raw, "%Y-%m-%d %H:%M")
                return dt.strftime("%Y-%m-%d %H:%M:%S")
            except ValueError:
                return raw[:19]
    return None

# ---- Parse a JSONL file ----
def parse_jsonl(file_path, session_id, is_subagent=False, parent_id=None):
    lines = []
    try:
        with open(file_path, encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        return None, [], str(e)

    if not lines:
        return None, [], "empty file"

    messages = []
    first_ts = None
    last_ts = None
    user_count = 0
    first_query = None
    first_query_idx = None

    for idx, raw in enumerate(lines):
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except:
            continue

        role = obj.get("role", "")
        msg = obj.get("message", {})
        content_items = msg.get("content", [])
        if not isinstance(content_items, list):
            content_items = []

        text_parts = []
        tools_used = []
        file_paths = []
        for item in content_items:
            if not isinstance(item, dict):
                continue
            t = item.get("type", "")
            if t == "text":
                txt = item.get("text", "")
                text_parts.append(txt)
            elif t == "tool_use":
                name = item.get("name", "")
                inp = item.get("input", {})
                if isinstance(inp, dict):
                    tools_used.append(name)
                    p = inp.get("path")
                    if p and isinstance(p, str):
                        file_paths.append(p)

        content = "".join(text_parts)
        content_preview = content[:200] if content else ""
        ts = extract_timestamp(content)

        # first query: the VERY FIRST user message in the entire session
        if role == "user" and user_count == 0:
            first_query = content
            first_query_idx = idx
            user_count = 1
        elif role == "user":
            user_count += 1

        if ts:
            if first_ts is None:
                first_ts = ts
            last_ts = ts

        msg_rec = {
            "session_id": session_id,
            "role": role,
            "timestamp": ts,
            "content": content,
            "content_preview": content_preview,
            "tools_used": "|".join(tools_used) if tools_used else "",
            "file_path": "|".join(file_paths) if file_paths else "",
        }
        messages.append(msg_rec)

    if first_ts is None:
        first_ts = datetime.fromtimestamp(os.path.getmtime(file_path)).strftime("%Y-%m-%d %H:%M:%S")

    session_rec = {
        "session_id": session_id,
        "start_time": first_ts,
        "end_time": last_ts,
        "is_first_query": 1 if first_query_idx == 0 else 0,
        "summary": "",
        "query_count": user_count,
        "first_query": first_query[:1000] if first_query else "",
        "cwd": "",
    }
    return session_rec, messages, None

# ---- Upsert to SQLite ----
def upsert_session(conn, session_rec):
    conn.execute("""
        INSERT INTO sessions (session_id, start_time, end_time, cwd, is_first_query, summary, query_count, first_query)
        VALUES (:session_id, :start_time, :end_time, :cwd, :is_first_query, :summary, :query_count, :first_query)
        ON CONFLICT(session_id) DO UPDATE SET
            end_time = :end_time,
            cwd = :cwd,
            is_first_query = :is_first_query,
            summary = :summary,
            query_count = :query_count,
            first_query = :first_query
    """, session_rec)

def upsert_messages(conn, session_id, messages):
    conn.execute("DELETE FROM messages WHERE session_id = ?", (session_id,))
    for m in messages:
        conn.execute("""
            INSERT INTO messages (session_id, role, timestamp, content, content_preview, tools_used, file_path)
            VALUES (:session_id, :role, :timestamp, :content, :content_preview, :tools_used, :file_path)
        """, m)

# ---- JSON fallback storage ----
def load_json_store():
    if not os.path.exists(JSON_PATH):
        return {"sessions": {}, "messages": {}}
    try:
        with open(JSON_PATH, encoding="utf-8") as f:
            return json.load(f)
    except:
        return {"sessions": {}, "messages": {}}

def save_json_store(store):
    tmp = JSON_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(store, f, ensure_ascii=False, indent=2)
    os.replace(tmp, JSON_PATH)

def upsert_json_store(session_rec, messages):
    store = load_json_store()
    sid = session_rec["session_id"]
    session_js = {k: v for k, v in session_rec.items() if k not in ("is_subagent", "parent_id")}
    store["sessions"][sid] = session_js
    store["messages"][sid] = messages
    save_json_store(store)

# ---- Walk transcripts ----
def walk_transcripts():
    base = Path(TRANSCRIPT_DIR)
    if not base.exists():
        return []
    results = []
    for uuid_dir in sorted(base.iterdir()):
        if not uuid_dir.is_dir():
            continue
        uuid_name = uuid_dir.name
        main_file = uuid_dir / (uuid_name + ".jsonl")
        if main_file.exists():
            results.append((str(main_file), uuid_name, False, None))
        sub_dir = uuid_dir / "subagents"
        if sub_dir.exists() and sub_dir.is_dir():
            for sub_file in sorted(sub_dir.iterdir()):
                if sub_file.suffix == ".jsonl":
                    results.append((str(sub_file), sub_file.stem, True, uuid_name))
    return results

# ---- Main ----
def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--sync", action="store_true")
    ap.add_argument("--recent-hours", type=int, default=0)
    ap.add_argument("--session-id", default="")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    results = walk_transcripts()

    # Filter by session-id
    if args.session_id:
        results = [(fp, sid, is_sub, pid) for fp, sid, is_sub, pid in results if sid == args.session_id]

    # Filter by recent-hours (file mtime)
    elif args.recent_hours > 0:
        cutoff = time.time() - args.recent_hours * 3600
        filtered = []
        for fp, sid, is_sub, pid in results:
            if fp.endswith(sid + ".jsonl") and Path(fp).stat().st_mtime >= cutoff:
                filtered.append((fp, sid, is_sub, pid))
        results = filtered

    # Load existing session_ids for sync-skip
    existing = set()
    use_json = False
    try:
        conn = get_conn()
        init_db(conn)
        for row in conn.execute("SELECT session_id FROM sessions"):
            existing.add(row[0])
        conn.close()
    except Exception as e:
        print("[WARN] SQLite unavailable ({0}), using JSON fallback".format(e), file=sys.stderr)
        use_json = True
        store = load_json_store()
        for sid in store.get("sessions", {}).keys():
            existing.add(sid)

    stats = {"sessions": 0, "messages": 0, "first_queries": 0, "skipped": 0}
    errors = []

    for file_path, session_id, is_subagent, parent_id in results:
        # Sync skip: skip if already processed and no filter
        if args.sync and not args.session_id and session_id in existing:
            stats["skipped"] += 1
            continue

        session_rec, messages, err = parse_jsonl(file_path, session_id, is_subagent, parent_id)
        if err:
            errors.append("{0}: {1}".format(session_id, err))
            continue

        if session_rec is None:
            stats["skipped"] += 1
            continue

        if args.dry_run:
            label = "[SUB] " if is_subagent else ""
            fq_preview = session_rec["first_query"][:80] if session_rec["first_query"] else "(none)"
            print("  DRYRUN: {0}{1} | msgs={2} | queries={3} | first={4}".format(
                label, session_id, len(messages), session_rec["query_count"], fq_preview))
            continue

        if session_rec["is_first_query"] == 1:
            stats["first_queries"] += 1

        stats["sessions"] += 1
        stats["messages"] += len(messages)

        if use_json:
            upsert_json_store(session_rec, messages)
        else:
            try:
                conn = get_conn()
                upsert_session(conn, session_rec)
                upsert_messages(conn, session_id, messages)
                conn.commit()
                conn.close()
            except Exception as e:
                errors.append("{0} DB error: {1}".format(session_id, e))
                use_json = True
                upsert_json_store(session_rec, messages)

    print("JSON_STORE={0}".format(use_json))
    print("STATS={0}".format(json.dumps(stats, ensure_ascii=False)))
    if errors:
        print("ERRORS={0}".format(json.dumps(errors[:20], ensure_ascii=False)))

if __name__ == "__main__":
    main()
