"""hj-gateway 基本测试 - 不依赖外部 LLM
覆盖: Config / SkillStore hot-reload / _render / run_sill literal|shell / Gateway.chat
用法: python tests/test_basic.py
"""
import json
import os
import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch

# 把 bin/ 加入 path
ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin"
sys.path.insert(0, str(BIN))

# 强制 server 不读 CLI args
import server  # noqa: E402


class TestRender(unittest.TestCase):
    def test_no_args(self):
        self.assertEqual(server._render("hello", []), "hello")
    def test_argN(self):
        self.assertEqual(server._render("hi {{arg0}}", ["alice"]), "hi alice")
        self.assertEqual(server._render("{{arg0}} -> {{arg1}}", ["a", "b"]), "a -> b")
    def test_args_joined(self):
        self.assertEqual(server._render("[{{args}}]", ["x", "y"]), "[x y]")
    def test_args_csv(self):
        self.assertEqual(server._render("{{args_csv}}", ["a", "b", "c"]), "a,b,c")
    def test_powershell_braces_preserved(self):
        # 关键: 模板里含 $_.Size 等 PS 语法不应被破坏
        tmpl = "Get-Item | Where-Object {$_.Length -gt 0}"
        self.assertEqual(server._render(tmpl, []), tmpl)


class TestRunSkill(unittest.TestCase):
    def test_literal(self):
        s = {"kind": "literal", "response": "echo: {{args}}"}
        self.assertEqual(server.run_skill(s, ["hello"]), "echo: hello")
    def test_unknown_kind(self):
        self.assertIn("unknown skill kind", server.run_skill({"kind": "x"}, []))
    def test_shell_no_template_args(self):
        # 不含 {{argN}} 模板的命令: 即使 args 不空也直接跑整段命令
        s = {"kind": "shell", "command": "echo hello"}
        out = server.run_skill(s, ["ignored"])
        self.assertIn("hello", out)


class TestSkillStore(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(server.__file__).parent / "_test_skills"
        if self.tmp.exists():
            for f in self.tmp.glob("*.json"):
                f.unlink()
        self.tmp.mkdir(exist_ok=True)
        (self.tmp / "hello.json").write_text(json.dumps({
            "name": "hello", "description": "say hi", "keywords": ["hi", "你好"],
            "kind": "literal", "response": "hi!"
        }), encoding="utf-8")
    def tearDown(self):
        for f in self.tmp.glob("*.json"):
            f.unlink()
        try:
            self.tmp.rmdir()
        except OSError:
            pass
    def test_load_and_match(self):
        # 用 monkey-patch 替换 skills dir
        store = server.SkillStore.__new__(server.SkillStore)
        store.dir = self.tmp
        store.skills = {}
        store._mtimes = {}
        store._load()
        self.assertIn("hello", store.skills)
        self.assertEqual(store.match("hi"), ["hello"])
        self.assertEqual(store.match("你好"), ["hello"])
    def test_hot_reload(self):
        store = server.SkillStore.__new__(server.SkillStore)
        store.dir = self.tmp
        store.skills = {}
        store._mtimes = {}
        store._load()
        # 添加新文件
        (self.tmp / "world.json").write_text(json.dumps({
            "name": "world", "keywords": ["world"], "kind": "literal", "response": "world!"
        }), encoding="utf-8")
        store.maybe_reload()
        self.assertIn("world", store.skills)


class TestProviderRouterEcho(unittest.TestCase):
    def test_echo_works(self):
        cfg = server.Config.__new__(server.Config)
        cfg.providers = {"echo": {"kind": "echo"}}
        cfg.default_provider = "echo"
        cfg.system_prompt = "test"
        r = server.ProviderRouter(cfg)
        out = r.call("echo", "sys", "user msg", [])
        self.assertIn("echo", out.lower())


class TestConfigLoad(unittest.TestCase):
    def test_loads_gateway_json(self):
        cfg = server.Config(ROOT)
        self.assertGreater(len(cfg.providers), 0)
        self.assertIn("echo", cfg.providers)
        # system prompt 应当非空
        self.assertGreater(len(cfg.system_prompt), 0)


class TestGatewayChatEcho(unittest.TestCase):
    """端到端: 用 echo provider 跑 chat"""
    def test_chat_returns_reply(self):
        cfg = server.Config(ROOT)
        cfg.default_provider = "echo"
        cfg.api_key = ""
        gw = server.Gateway(cfg)
        # 问 "现在几点了" — echo provider 应回显
        r = gw.chat("hello world", "echo")
        self.assertIn("reply", r)
        self.assertIn("provider", r)
        self.assertEqual(r["provider"], "echo")
    def test_skill_match_preempts_provider(self):
        """如果 message 命中 skill，则应走 skill（不调 provider）"""
        cfg = server.Config(ROOT)
        cfg.default_provider = "echo"
        gw = server.Gateway(cfg)
        # time skill 的 keyword: "现在几点"
        r = gw.chat("现在几点", "echo")
        self.assertIn("skill", r)
        self.assertEqual(r["skill"], "time")
        # 实际时间应包含 "20" (2026-06-16)
        self.assertRegex(r["reply"], r"\d{2}:\d{2}:\d{2}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
