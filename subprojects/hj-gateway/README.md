# hj-gateway — 个人 AI 助手本地网关

> 集合 6 个 GitHub 热门开源项目特长，做成可开机自启的本地服务。

## 集合的特长

| 来源 | 特长 | 落地方式 |
|---|---|---|
| **openclaw** | 多渠道接入范本 | HTTP API 入口（`/v1/chat` `/v1/skills` ...） |
| **claude-code-router** | provider 路由抽象 | `ProviderRouter` 支持 echo / openai_compatible / ollama |
| **hermes-agent** | skill 库 + FTS5 检索 | `SkillStore` + 关键词匹配；`Memory` 用 SQLite + LIKE 简化 |
| **openhuman** | JSON-RPC + 进程内 tokio 范式 | 进程内 `Gateway` 单例 + 多 endpoint |
| **ai-api-integration** | OpenAI 兼容协议 | `chat_path` 可配置；输出 JSON 形态对齐 |
| **cursor2api** | 协议转换 | `${VAR}` 环境变量插值在 provider.api_key |

## 架构

```
┌────────────────┐      ┌─────────────────┐      ┌──────────────┐
│  gateway.ps1   │ ───▶ │ server.py       │ ───▶ │  Providers   │
│  (PowerShell)  │      │ (stdlib HTTP)   │      │  ─ echo      │
│                │      │                 │      │  ─ openai    │
│  start/stop/   │      │  Endpoints:     │      │  ─ deepseek  │
│  status/chat/  │      │  /health        │      │  ─ glm       │
│  skill/        │      │  /v1/chat       │      │  ─ ollama    │
│  autostart     │      │  /v1/skills     │      └──────────────┘
└────────────────┘      │  /v1/skills/run │
       │                │  /v1/memory/...  │      ┌──────────────┐
       │                └─────────────────┘ ───▶ │  Skills      │
       ▼                                          │  ─ time      │
┌────────────────┐                                │  ─ weather   │
│  计划任务      │                                │  ─ git_status│
│  (开机自启)    │                                │  ─ ip / echo │
└────────────────┘                                └──────────────┘
       ▼
┌────────────────┐      ┌─────────────────┐
│ state/gateway. │      │  logs/server.log│
│ db (SQLite)    │      │  logs/gateway.log
│ conversations  │      └─────────────────┘
└────────────────┘
```

## 目录结构

```
hj-gateway/
├── bin/
│   ├── gateway.ps1        # PowerShell 入口（start/stop/chat/skill/autostart）
│   └── server.py          # Python stdlib HTTP 服务
├── config/
│   ├── gateway.json       # providers + system_prompt
│   └── .env.example
├── skills/                # 5 个示例 skill
│   ├── time.json
│   ├── ip.json
│   ├── weather.json
│   ├── git_status.json
│   └── echo.json
├── state/                 # 运行时 (PID file, SQLite conversations)
├── logs/                  # server.log + gateway.log
└── README.md
```

## 启动 / 停止 / 状态

```powershell
# 启动（后台，零依赖）
cd E:\HJ\cursor\subprojects\hj-gateway\bin
.\gateway.ps1 start

# 状态
.\gateway.ps1 status
# 预期: running (pid=xxxx), hj-gateway v0.1.0 provider=echo

# 一次性对话
.\gateway.ps1 chat "现在几点了？"
# 预期: 调用 time skill，输出当前时间

.\gateway.ps1 chat "今天北京天气？"
# 预期: 调用 weather skill，输出 wttr.in 数据

.\gateway.ps1 chat "git 状态"
# 预期: 调用 git_status skill，列出 e:\HJ\cursor 改动

# 显式 skill 调用
.\gateway.ps1 skill list
.\gateway.ps1 skill run time

# 停止
.\gateway.ps1 stop
```

## 开机自启

```powershell
# 装：写计划任务（登录时启动）+ 启动文件夹快捷方式（兜底）
.\gateway.ps1 install-autostart

# 卸
.\gateway.ps1 uninstall-autostart
```

自启后：
- 登录 Windows → 计划任务触发 → `gateway.ps1 start` → 端口 7799 监听
- 失败兜底：启动文件夹的 `HJ-Personal-AI-Gateway.lnk` 也会拉起

## HTTP API（外部可调用）

```bash
# 健康
curl http://127.0.0.1:7799/health

# 聊天（默认 provider=echo）
curl -X POST http://127.0.0.1:7799/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"你好"}'

# 用 deepseek
curl -X POST http://127.0.0.1:7799/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"你好","provider":"deepseek"}'

# 列 skill
curl http://127.0.0.1:7799/v1/skills

# 跑 skill
curl -X POST http://127.0.0.1:7799/v1/skills/run \
  -H "Content-Type: application/json" \
  -d '{"name":"time","args":[]}'

# 看最近 20 条对话（sqlite）
curl 'http://127.0.0.1:7799/v1/memory/recent?n=20'
```

## 配置 provider

编辑 `config/gateway.json`：

1. **echo**（默认，零依赖）：永远可用
2. **openai_compatible**：填 `api_key`（支持 `${OPENAI_API_KEY}` 环境变量插值）
3. **ollama_local**：本地 `http://127.0.0.1:11434` 跑 `ollama serve`

改完 `gateway.ps1 restart` 即可。

## 添加 skill

在 `skills/<name>.json` 写一个文件：

```json
{
  "name": "my_skill",
  "description": "我的技能",
  "keywords": ["关键词1", "关键词2"],
  "kind": "literal" | "shell" | "http",
  "response": "...",        // literal 用
  "command": "...",         // shell 用
  "url": "..."              // http 用
}
```

`gateway.ps1 restart` 即可热加载。

## 依赖

- **Python 3.8+**（stdlib 即可，**无需 pip install**）
- **PowerShell 5+**（Windows 自带）
- **git**（git_status skill 用）
- **网络出口**（weather/ip skill 调外部 API）

## 跟 e:\HJ\cursor 主仓的关系

- `hj-gateway/` **不被 .gitignore 排除**（这是本机主仓的自研项目，**必须** git tracked）
- `subprojects/repos-from-external/` 仍被排除（第三方源码，参考用）
- 自研 vs 第三方 分开管理

## 6 仓与本网关的贡献关系

```
openclaw            ─┐
claude-code-router  ─┤
hermes-agent        ─┼──▶  本网关的架构灵感（不复制代码）
openhuman           ─┤
ai-api-integration  ─┤
cursor2api          ─┘
```

**没有引入任何第三方代码到本仓**——纯参考架构 + 用 Python stdlib 重写。
