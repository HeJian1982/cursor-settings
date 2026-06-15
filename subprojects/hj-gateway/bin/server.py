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
        self._load()

    def _load(self):
        for p in self.dir.glob("*.json"):
            try:
                with open(p, encoding="utf-8") as f:
                    s = json.load(f)
                if "name" in s:
                    self.skills[s["name"]] = s
            except Exception as e:
                LOG.warning("skill load failed %s: %s", p.name, e)

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
def run_skill(skill: dict, args: list) -> str:
    kind = skill.get("kind", "literal")
    if kind == "literal":
        return skill.get("response", "").format(*args, **{
            f"arg{i}": a for i, a in enumerate(args)
        })
    if kind == "shell":
        cmd = skill.get("command", "").format(*args, **{
            f"arg{i}": a for i, a in enumerate(args)
        })
        try:
            import subprocess
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
            out = r.stdout.strip() if r.returncode == 0 else r.stderr.strip()
            return out or "(no output)"
        except subprocess.TimeoutExpired:
            return "[timeout after 15s]"
        except Exception as e:
            return f"[shell error] {e}"
    if kind == "http":
        url = skill.get("url", "").format(*args, **{
            f"arg{i}": a for i, a in enumerate(args)
        })
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
        # 找匹配的 skill
        matched = self.skills.match(message)
        if matched:
            top = self.skills.get(matched[0])
            if top and top.get("kind") in ("literal", "shell", "http"):
                # 自动跑 skill（仅当 message 跟 skill 关键词强相关）
                args = re.findall(r"\S+", message)
                out = run_skill(top, args[1:])  # 去掉首词
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

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path == "/health":
                self._json(200, gw.health())
            elif path == "/v1/skills":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                self._json(200, gw.skills_list())
            elif path == "/v1/memory/recent":
                if not self._check_auth():
                    return self._json(401, {"error": "unauthorized"})
                n = int(urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("n", ["20"])[0])
                self._json(200, {"history": gw.memory.recent(n)})
            elif path == "/":
                self._json(200, {
                    "service": SERVICE,
                    "version": VERSION,
                    "endpoints": ["/health", "/v1/chat", "/v1/skills", "/v1/skills/run", "/v1/memory/recent"]
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
