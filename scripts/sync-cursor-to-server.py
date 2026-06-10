#!/usr/bin/env python3
"""
sync-cursor-to-server.py
End-to-end sync: parses local transcripts + uploads to hj1982.cn via HTTPS POST.

Usage:
  python sync-cursor-to-server.py              # full sync
  python sync-cursor-to-server.py --dry-run    # preview only
  python sync-cursor-to-server.py --check      # show sessions only
  python sync-cursor-to-server.py --since 2026-06-01  # sync from date
"""
import subprocess, json, sys, os, re, hashlib, socket, time, hmac as _hmac, hashlib as _hashlib, base64 as _base64, urllib.request, urllib.error
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
sys.stderr.reconfigure(encoding='utf-8', errors='replace')

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TRANSCRIPT_DIR = r"C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
PARSER_PY = os.path.join(SCRIPT_DIR, "_parse_transcripts.py")
API_ENDPOINT = "https://www.hj1982.cn/api/cursor/sessions/upload"
LOG_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "logs")

def log(msg, level="INFO"):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] [{level}] {msg}"
    print(line)
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        log_file = os.path.join(LOG_DIR, f"cursor-sync-{time.strftime('%Y-%m-%d')}.log")
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# --- Bearer Token via SSH + Python ---
def get_bearer_token():
    """SSH to server, read ADMIN_TOKEN_SECRET, generate JWT locally."""
    log("Getting bearer token from server...", "STEP")

    # Step 1: SSH read secret
    # Use Python subprocess to SSH — avoids PowerShell process overhead and proxy issues
    import subprocess
    env = dict(os.environ)
    for k in list(env.keys()):
        if "proxy" in k.lower():
            del env[k]
    proc = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
         "-o", "ConnectTimeout=10", "-o", "ProxyCommand=none",
         "hj1982", "grep ADMIN_TOKEN_SECRET /etc/hj-secrets"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=20, env=env, stdin=subprocess.DEVNULL
    )
    secret = None
    for line in proc.stdout.split("\n"):
        if line.startswith("ADMIN_TOKEN_SECRET="):
            secret = line.split("=", 1)[1].strip()
            break
    if not secret:
        log(f"ADMIN_TOKEN_SECRET not found in server secrets", "FAIL")
        return None

    # Step 2: Generate JWT with Python
    now_ms = int(time.time() * 1000)
    payload = {"iat": now_ms, "exp": now_ms + 900000, "type": "admin"}
    pb = _base64.urlsafe_b64encode(json.dumps(payload, separators=(",", ":")).encode()).decode().rstrip("=")
    sig = _base64.urlsafe_b64encode(_hmac.new(secret.encode(), pb.encode(), _hashlib.sha256).digest()).decode().rstrip("=")
    token = pb + "." + sig
    return token

# --- Parse transcripts ---
def get_sessions(since=None):
    """Call Python parser, return list of session objects."""
    cmd = [sys.executable, PARSER_PY, TRANSCRIPT_DIR]
    if since:
        cmd.append(since)
    log(f"Running parser: {' '.join(cmd[-2:])}", "STEP")
    penv = dict(os.environ)
    for k in list(penv.keys()):
        if "proxy" in k.lower():
            del penv[k]
    penv["PYTHONIOENCODING"] = "utf-8"
    penv["PYTHONUTF8"] = "1"
    proc = subprocess.run(
        cmd,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        env=penv, stdin=subprocess.DEVNULL
    )
    if proc.stderr.strip():
        for line in proc.stderr.strip().split("\n")[:3]:
            log(f"Parser stderr: {line}", "WARN")
    if not proc.stdout.strip():
        log("No sessions found", "WARN")
        return []
    try:
        sessions = json.loads(proc.stdout.strip())
    except json.JSONDecodeError as e:
        log(f"JSON parse error: {e}", "FAIL")
        return []
    return sessions

# --- Upload one session ---
def upload_session(token, session_obj):
    body = json.dumps(session_obj, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        API_ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": "Bearer " + token,
            "User-Agent": "cursor-sync/1.1"
        }
    )
    # Bypass system proxy to avoid 405 from proxy server
    proxy_handler = urllib.request.ProxyHandler({})
    opener = urllib.request.build_opener(proxy_handler)
    try:
        with opener.open(req, timeout=60) as resp:
            result = json.loads(resp.read())
            if result.get("success"):
                return True, result.get("messages_count", 0), None
            return False, 0, result.get("error", "unknown error")
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            err = json.loads(body).get("error", f"HTTP {e.code}")
        except Exception:
            err = f"HTTP {e.code}"
        return False, 0, err
    except Exception as e:
        return False, 0, str(e)[:120]

# --- Parse CLI args ---
mode = "full"
since = None
args = sys.argv[1:]
if "--check" in args:
    mode = "check"
    args.remove("--check")
elif "--dry-run" in args:
    mode = "dry-run"
    args.remove("--dry-run")
if "--since" in args:
    idx = args.index("--since")
    since = args[idx + 1]
    args.pop(idx); args.pop(idx)

print("")
print("=" * 60)
print("   Cursor -> hj1982.cn Sync  v1.2")
print("=" * 60)
print("")
log(f"mode     : {mode}", "STEP")
log(f"endpoint : {API_ENDPOINT}", "STEP")
log(f"source   : {TRANSCRIPT_DIR}", "STEP")
log(f"parser   : {PARSER_PY}", "STEP")
if since:
    log(f"since    : {since}", "STEP")
log("", "INFO")

# Check files
if not os.path.isdir(TRANSCRIPT_DIR):
    log(f"Transcript dir not found: {TRANSCRIPT_DIR}", "FAIL")
    sys.exit(1)
if not os.path.isfile(PARSER_PY):
    log(f"Parser not found: {PARSER_PY}", "FAIL")
    sys.exit(1)

sessions = get_sessions(since)
log(f"Found {len(sessions)} sessions", "PASS")

if mode == "check":
    print("")
    print(f"  {'Date':<12} {'Turns':>6} {'Msgs':>9}  First Query")
    print("  " + "-" * 65)
    for s in sessions[:25]:
        st = s.get("stats", {})
        ts = (st.get("first_user_ts", "") or "")[:10]
        fq = (st.get("first_user_query", "") or "")[:40].replace("\n", " ")
        print(f"  {ts:<12} {st.get('total_turns',0):>6} {st.get('total_messages',0):>9}  {fq}")
    print("")
    log(f"Check done: {len(sessions)} sessions", "PASS")
    sys.exit(0)

if mode == "dry-run":
    print("")
    log("DRY-RUN mode - no data will be uploaded", "DRY")
    print("")
    print(f"  {'Date':<10} {'UUID':<10} {'Turns':>6} {'Msgs':>9}  First Query")
    print("  " + "-" * 70)
    for s in sessions:
        st = s.get("stats", {})
        ts = (st.get("first_user_ts", "") or "")[:10]
        uuid = (st.get("session_uuid", "") or "")[:8]
        fq = (st.get("first_user_query", "") or "")[:35].replace("\n", " ")
        print(f"  {ts:<10} {uuid:<10} {st.get('total_turns',0):>6} {st.get('total_messages',0):>9}  {fq}")
    print("")
    log(f"Dry-run done: {len(sessions)} sessions queued", "PASS")
    sys.exit(0)

# --- Full sync ---
token = get_bearer_token()
if not token:
    log("Failed to get bearer token", "FAIL")
    sys.exit(1)

log("[Step 2] Uploading to hj1982.cn...", "STEP")
total = len(sessions)
ok, fail = 0, 0
errors = []

for idx, s in enumerate(sessions, 1):
    st = s.get("stats", {})
    uuid = st.get("session_uuid", "unknown")
    short_uuid = uuid[:8]

    # Build upload payload
    upload_body = {
        "session": {
            "session_uuid": uuid,
            "first_user_ts": st.get("first_user_ts"),
            "last_user_ts": st.get("last_user_ts"),
            "total_turns": st.get("total_turns", 0),
            "total_user_turns": st.get("total_user_turns", 0),
            "total_assistant_turns": st.get("total_assistant_turns", 0),
            "total_tool_calls": st.get("total_tool_calls", 0),
            "total_messages": st.get("total_messages", 0),
            "total_size_bytes": st.get("total_size_bytes", 0),
            "first_user_query": st.get("first_user_query", ""),
            "first_user_query_hash": st.get("first_user_query_hash", ""),
            "session_title": st.get("session_title", ""),
            "is_active": st.get("is_active", False),
            "machine_name": st.get("machine_name", ""),
            "username": st.get("username", ""),
            "workspace": st.get("workspace", ""),
            "key_files_changed": [],
            "key_tasks_completed": [],
            "extra": {
                "synced_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "source": "e-HJ-cursor"
            }
        },
        "messages": [
            {
                "turn_index": m.get("turn_index", i),
                "role": m.get("role", "unknown"),
                "content_type": m.get("content_type", "text"),
                "raw_text": m.get("raw_text", ""),
                "tool_name": m.get("tool_name"),
                "has_images": m.get("has_images", False),
                "has_file_refs": m.get("has_file_refs", False),
                "file_refs": m.get("file_refs", []),
                "ts": m.get("ts", "")
            }
            for i, m in enumerate(s.get("messages", []))
        ]
    }

    print(f"  [{idx}/{total}] {short_uuid}...", end="", flush=True)
    success, cnt, err = upload_session(token, upload_body)
    if success:
        print(f" -> [OK] {cnt} msgs")
        ok += 1
    else:
        print(f" -> [FAIL] {err}")
        errors.append(f"{uuid} : {err}")
        fail += 1

    time.sleep(0.15)

print("")
log("=" * 60, "STEP")
if fail == 0:
    log(f"All OK! {ok}/{total} sessions uploaded", "PASS")
else:
    log(f"Partial: {ok} OK, {fail} failed", "WARN")
    for e in errors:
        log(f"  {e}", "FAIL")
log("=" * 60, "STEP")
sys.exit(0 if fail == 0 else 1)
