"""
hj-gateway · server.py
零依赖 stdlib HTTP 服务 (http.server + socketserver + json + sqlite3 + threading)
参考:
  - openclaw       · /v1/chat + /health 端点
  - claude-code-router · provider 路由
  - hermes-agent   · skill 库 + FTS5 (本地化用 LIKE 检索)
  - openhuman      · JSON-RPC 范式
  - ai-api-integration · OpenAI 兼容输出 (chat 端点 v1 形态)
"""
import argparse
import json
import logging
import os
import re
import sqlite3
import sys
import threading
import time
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "0.1.0"
SERVICE = "hj-gateway"

# ---------------- logging ----------------
LOG = logging.getLogger("hj-gateway")


def setup_logging(log_dir: Path):
    log_dir.mkdir(parents=True, exist_ok=True)
    fh = logging.FileHandler(log_dir / "server.log", encoding="utf-8")
    fh.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s"))
    LOG.addHandler(fh)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s"))
    LOG.addHandler(sh)
    LOG.setLevel(logging.INFO)


# ---------------- config ----------------
class Config:
    def __init__(self, root: Path):
        self.root = root
        path = root / "config" / "gateway.json"
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        self.default_provider = data.get("default_provider", "echo")
        self.providers = data.get("providers", {})
        self.skills_dir = root / "skills"
        self.state_db = root / "state" / "gateway.db"
        self.port = data.get("port", 7799)
        self.api_key = data.get("api_key", "")
        self.system_prompt = data.get("system_prompt",
            "你是 hj-gateway 个人 AI 助手。基于本地 skill 库回答，不知道的诚实说不知道。")


# ---------------- skill store (hermes-agent FTS 简化) ----------------
class SkillStore:
    def __init__(self, root: Path):
        self.dir = root / "skills"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.skills = {}
        self._mtimes = {}
        self._load()

    def _load(self):
        for p in self.dir.glob("*.json"):
            try:
                mt = p.stat().st_mtime
                with open(p, encoding="utf-8-sig") as f:
                    s = json.load(f)
                if "name" in s:
                    self.skills[s["name"]] = s
                    self._mtimes[str(p)] = mt
            except Exception as e:
                LOG.warning("skill load failed %s: %s", p.name, e)

    def maybe_reload(self):
        """热加载：扫描 skills/*.json 是否有 mtime 变化"""
        current = {str(p): p.stat().st_mtime for p in self.dir.glob("*.json")}
        if current == self._mtimes:
            return
        # 重新全量加载
        old_names = set(self.skills.keys())
        self.skills = {}
        self._mtimes = {}
        self._load()
        new_names = set(self.skills.keys())
        added = new_names - old_names
        removed = old_names - new_names
        if added or removed:
            LOG.info("skills hot-reload: +%s -%s", added, removed)

    def list(self):
        return [{"name": s["name"], "description": s.get("description", "")}
                for s in self.skills.values()]

    def match(self, text: str):
        """简单的关键词命中: 命中任一 keyword 则返回该 skill"""
        text_l = text.lower()
        scores = []
        for s in self.skills.values():
            kws = [k.lower() for k in s.get("keywords", [])]
            score = sum(1 for k in kws if k in text_l)
            if score > 0:
                scores.append((score, s["name"]))
        scores.sort(reverse=True)
        return [name for _, name in scores]

    def get(self, name: str):
        return self.skills.get(name)


# ---------------- memory (sqlite 简化版 FTS5-less) ----------------
class Memory:
    def __init__(self, db_path: Path):
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(db_path), check_same_thread=False)
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS conversations(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL
            )""")
        self.db.execute("""
            CREATE TABLE IF NOT EXISTS feedback(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts TEXT NOT NULL,
                skill TEXT,
                score INTEGER,
                note TEXT
            )""")
        self.db.commit()
        self.lock = threading.Lock()

    def append(self, role: str, content: str):
        with self.lock:
            self.db.execute("INSERT INTO conversations(ts,role,content) VALUES(?,?,?)",
                            (datetime.now().isoformat(timespec='seconds'), role, content))
            self.db.commit()

    def recent(self, n: int = 20):
        with self.lock:
            cur = self.db.execute("SELECT ts,role,content FROM conversations ORDER BY id DESC LIMIT ?", (n,))
            return [{"ts": r[0], "role": r[1], "content": r[2]} for r in cur.fetchall()][::-1]

    def search(self, q: str, n: int = 5):
        with self.lock:
            cur = self.db.execute(
                "SELECT ts,role,content FROM conversations WHERE content LIKE ? ORDER BY id DESC LIMIT ?",
                (f"%{q}%", n))
            return [{"ts": r[0], "role": r[1], "content": r[2]} for r in cur.fetchall()]

    def clear(self):
        with self.lock:
            self.db.execute("DELETE FROM conversations")
            self.db.commit()


# ---------------- provider router (claude-code-router 简化) ----------------
class ProviderRouter:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    def call(self, provider: str, system: str, user: str, history: list) -> str:
        if provider not in self.cfg.providers:
            return f"[error] unknown provider: {provider}"
        p = self.cfg.providers[provider]
        kind = p.get("kind", "echo")

        if kind == "echo":
            # 永远可用：纯本地回显
            return self._echo(system, user, history)

        if kind == "openai_compatible":
            return self._openai_compatible(p, system, user, history)

        if kind == "ollama":
            return self._ollama(p, system, user, history)

        return f"[error] provider kind not implemented: {kind}"

    def _echo(self, system, user, history):
        # 命中 skill 的话先调用
        # 走外部 — 由 call() 调用方已选过 skill；这里仅回显
        recent = "\n".join([f"{m['role']}: {m['content'][:80]}" for m in history[-3:]])
        return (
            f"[echo provider · 本地占位]\n"
            f"系统提示: {system[:60]}...\n"
            f"用户: {user}\n"
            f"上下文 ({len(history)} 条):\n{recent or '(空)'}\n"
            f"\n> 提示: 配置 OpenAI 兼容 provider 后才能获得真实回复。"
        )

    def _openai_compatible(self, p, system, user, history):
        base = p["base_url"].rstrip("/")
        url = base + (p.get("chat_path", "/v1/chat/completions"))
        msgs = [{"role": "system", "content": system}]
        for m in history:
            msgs.append({"role": m["role"], "content": m["content"]})
        msgs.append({"role": "user", "content": user})
        body = {
            "model": p.get("model", "gpt-4o-mini"),
            "messages": msgs,
            "max_tokens": p.get("max_tokens", 512),
            "temperature": p.get("temperature", 0.7),
            "stream": False,
        }
        headers = {"Content-Type": "application/json"}
        if p.get("api_key"):
            headers["Authorization"] = f"Bearer {p['api_key']}"
        try:
            data = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=p.get("timeout", 60)) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            return payload["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")[:500]
            return f"[openai_compatible http {e.code}] {body}"
        except Exception as e:
            return f"[openai_compatible error] {type(e).__name__}: {e}"

    def _ollama(self, p, system, user, history):
        base = p["base_url"].rstrip("/")
        url = base + "/api/chat"
        msgs = [{"role": "system", "content": system}]
        for m in history:
            msgs.append({"role": m["role"], "content": m["content"]})
        msgs.append({"role": "user", "content": user})
        body = {"model": p.get("model", "llama3.1:8b"), "messages": msgs, "stream": False}
        try:
            data = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=p.get("timeout", 60)) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            return payload["message"]["content"]
        except Exception as e:
            return f"[ollama error] {type(e).__name__}: {e}"


# ---------------- skill runner ----------------
def _render(template: str, args: list) -> str:
    """安全渲染: 支持 {{arg0}} {{arg1}} {{argN}} 或 {{arg0..argN}} 区间
    用双花括号避开 PowerShell 单花括号语法
    """
    import re as _re
    out = template
    out = out.replace("{{args}}", " ".join(args))
    out = out.replace("{{args_csv}}", ",".join(args))
    for i, a in enumerate(args):
        out = out.replace(f"{{{{arg{i}}}}}", a)
    return out


def run_skill(skill: dict, args: list) -> str:
    kind = skill.get("kind", "literal")
    if kind == "literal":
        return _render(skill.get("response", ""), args)
    if kind == "shell":
        cmd = _render(skill.get("command", ""), args)
        try:
            import subprocess
            r = subprocess.run(
                cmd, shell=True, capture_output=True,
                text=True, encoding="utf-8", errors="replace",
                timeout=skill.get("timeout", 15)
            )
            out = r.stdout.strip() if r.returncode == 0 else (r.stderr.strip() or f"[exit {r.returncode}]")
            return out or "(no output)"
        except subprocess.TimeoutExpired:
            return f"[timeout after {skill.get('timeout', 15)}s]"
        except Exception as e:
            return f"[shell error] {e}"
    if kind == "http":
        url = _render(skill.get("url", ""), args)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "hj-gateway/0.1"})
            with urllib.request.urlopen(req, timeout=8) as r:
                return r.read().decode("utf-8", errors="replace")[:2000]
        except Exception as e:
            return f"[http error] {e}"
    return f"[unknown skill kind: {kind}]"


# ---------------- HTTP server ----------------
class Gateway:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.skills = SkillStore(cfg.root)
        self.memory = Memory(cfg.state_db)
        self.router = ProviderRouter(cfg)

    def chat(self, message: str, provider: str = None) -> dict:
        provider = provider or self.cfg.default_provider
        self.memory.append("user", message)
        # 每次 chat 检查 skill 是否有变动（热加载）
        self.skills.maybe_reload()
        # 找匹配的 skill
        matched = self.skills.match(message)
        if matched:
            top = self.skills.get(matched[0])
            if top and top.get("kind") in ("literal", "shell", "http"):
                # 仅当命令模板需要参数（{{argN}} 或 {{args}}）才剥首词
                tmpl = top.get("command") or top.get("response") or top.get("url") or ""
                needs_args = ("{{arg" in tmpl) or ("{{args}}" in tmpl) or ("{{args_csv}}" in tmpl)
                tokens = re.findall(r"\S+", message)
                args = tokens[1:] if (needs_args and len(tokens) > 1) else tokens
                out = run_skill(top, args)
                if out:
                    self.memory.append("assistant", out)
                    return {"reply": out, "skill": top["name"], "provider": provider}

        history = self.memory.recent(20)[:-1]  # 去刚 append 的 user
        reply = self.router.call(provider, self.cfg.system_prompt, message, history)
        self.memory.append("assistant", reply)
        return {"reply": reply, "skill": None, "provider": provider}

    def skills_list(self) -> dict:
        return {"skills": self.skills.list()}

    def skills_run(self, name: str, args: list) -> dict:
        s = self.skills.get(name)
        if not s:
            return {"error": f"skill not found: {name}"}
        out = run_skill(s, args)
        return {"output": out}

    def memory_recent(self, n: int = 20) -> list:
        rows = self.memory.recent(n)
        return [{"role": r["role"], "content": r["content"], "ts": r["ts"]} for r in rows]

    def providers(self) -> dict:
        out = {}
        for name, p in self.cfg.providers.items():
            out[name] = {
                "kind": p.get("kind", "?"),
                "description": p.get("description", ""),
                "model": p.get("model", ""),
            }
        return {"providers": out}

    def health(self) -> dict:
        return {
            "service": SERVICE,
            "version": VERSION,
            "provider": self.cfg.default_provider,
            "skills": len(self.skills.skills),
            "memory_rows": self.memory.db.execute("SELECT COUNT(*) FROM conversations").fetchone()[0],
            "uptime_s": int(time.time() - self.t0),
        }


def make_handler(gw: Gateway, api_key: str):
    class H(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # 静音默认
            LOG.info("%s - %s", self.address_string(), fmt % args)

        def _check_auth(self):
            if not api_key:
                return True
            k = self.headers.get("Authorization", "")
            return k == f"Bearer {api_key}" or self.headers.get("x-api-key") == api_key

        def _json(self, code: int, payload: dict):
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _sse_event(self, event: str, data: dict):
            try:
                payload = f"event: {event}\n" + "data: " + json.dumps(data, ensure_ascii=False) + "\n\n"
                self.wfile.write(payload.encode("utf-8"))
                self.wfile.flush()
            except Exception:
                pass

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            if path == "/health":
                self._json(200, gw.health())
            elif path == "/v1/skills":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                self._json(200, gw.skills_list())
            elif path == "/v1/memory" or path == "/v1/memory/recent":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                n = int(q.get("n", q.get("limit", ["20"]))[0])
                self._json(200, {"items": gw.memory_recent(n)})
            elif path == "/v1/providers":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                self._json(200, gw.providers())
            elif path == "/v1/memory/clear":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                gw.memory.clear()
                self._json(200, {"ok": True})
            elif path == "/":
                self._json(200, {
                    "service": SERVICE,
                    "version": VERSION,
                    "endpoints": [
                        "/health",
                        "/v1/chat", "/v1/chat/stream",
                        "/v1/skills", "/v1/skills/run",
                        "/v1/providers",
                        "/v1/memory", "/v1/memory/clear"
                    ]
                })
            else:
                self._json(404, {"error": "not found", "path": path})

        def do_POST(self):
            path = urllib.parse.urlsplit(self.path).path
            if not self._check_auth():
                return self._json(401, {"error": "unauthorized"})
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode("utf-8"))
            except Exception:
                return self._json(400, {"error": "invalid json"})

            if path == "/v1/chat":
                LOG.info("chat body=%s", raw[:300])
                msg = (body.get("message") or body.get("messages", [{}])[-1].get("content") or "").strip()
                if not msg:
                    return self._json(400, {"error": "message required"})
                provider = body.get("provider")
                try:
                    return self._json(200, gw.chat(msg, provider))
                except Exception as e:
                    LOG.exception("chat error")
                    return self._json(500, {"error": f"{type(e).__name__}: {e}"})
            elif path == "/v1/chat/stream":
                LOG.info("chat-stream body=%s", raw[:300])
                msg = (body.get("message") or body.get("messages", [{}])[-1].get("content") or "").strip()
                if not msg:
                    return self._json(400, {"error": "message required"})
                provider = body.get("provider")
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()
                # 先发一个 start 事件
                self._sse_event("start", {"ts": time.time()})
                try:
                    # 如果命中 skill，则发单条 done 事件
                    matched = gw.skills.match(msg)
                    if matched:
                        top = gw.skills.get(matched[0])
                        if top and top.get("kind") in ("literal", "shell", "http"):
                            tmpl = top.get("command") or top.get("response") or top.get("url") or ""
                            needs_args = ("{{arg" in tmpl) or ("{{args}}" in tmpl) or ("{{args_csv}}" in tmpl)
                            tokens = re.findall(r"\S+", msg)
                            args = tokens[1:] if (needs_args and len(tokens) > 1) else tokens
                            # 流式分段
                            out = run_skill(top, args)
                            chunks = [out[i:i+8] for i in range(0, len(out), 8)] or [""]
                            for ch in chunks:
                                self._sse_event("token", {"delta": ch})
                                time.sleep(0.02)
                            self._sse_event("done", {"skill": top["name"], "full": out})
                            return
                    # 否则流式调 provider（按 8 字符分段伪流式）
                    history = gw.memory.recent(20)[:-1]
                    reply = gw.router.call(provider or gw.cfg.default_provider, gw.cfg.system_prompt, msg, history)
                    gw.memory.append("assistant", reply)
                    chunks = [reply[i:i+8] for i in range(0, len(reply), 8)] or [""]
                    for ch in chunks:
                        self._sse_event("token", {"delta": ch})
                        time.sleep(0.02)
                    self._sse_event("done", {"full": reply, "provider": provider or gw.cfg.default_provider})
                except Exception as e:
                    LOG.exception("stream chat error")
                    self._sse_event("error", {"message": f"{type(e).__name__}: {e}"})
            elif path == "/v1/skills/run":
                name = body.get("name", "")
                args = body.get("args", [])
                if isinstance(args, str):
                    args = [args]
                return self._json(200, gw.skills_run(name, args))
            else:
                self._json(404, {"error": "not found", "path": path})

    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7799)
    ap.add_argument("--root", required=True)
    args = ap.parse_args()
    root = Path(args.root)
    setup_logging(root / "logs")
    cfg = Config(root)
    cfg.port = args.port
    gw = Gateway(cfg)
    gw.t0 = time.time()

    handler = make_handler(gw, cfg.api_key)
    srv = ThreadingHTTPServer(("127.0.0.1", cfg.port), handler)
    LOG.info("hj-gateway v%s listening on http://127.0.0.1:%d (provider=%s, skills=%d)",
             VERSION, cfg.port, cfg.default_provider, len(gw.skills.skills))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        LOG.info("shutting down")
        srv.server_close()


if __name__ == "__main__":
    main()
