# hermes-agent (🐴 Hermes Agent — The Self-Improving AI Agent)

> 仓库本地路径：`subprojects/repos-from-external/agent/hermes-agent/`
> 来源：<https://github.com/NousResearch/hermes-agent>
> 协议：MIT（Copyright 2024-2026 Nous Research） ｜ 主语言：Python ｜ **194,071★**
> commit SHA：`ae433634db562e644175d39537ef6b811a381f3f`（2026-06-15 12:07 EDT）
> 本地体积：108 MB（5107 文件，浅克隆）
> 镜像来源：**[gh-proxy.com](https://gh-proxy.com)**（GitHub 直连 7+ 次失败后切换）

## 解决什么问题

**自进化（self-improving）的个人 AI Agent**，由 Nous Research 出品（同源 Hermes-3/4 模型）。

**核心特性**（README 总结）：

1. **真实 TUI**：多行编辑、slash 自动补全、对话历史、中断重定向、流式工具输出
2. **多渠道**：Telegram / Discord / Slack / WhatsApp / Signal / CLI / 桌面（Electron）
3. **闭环学习**：
   - Agent-curated memory
   - 复杂任务后自动创建 skills
   - Skills 在使用中自我进化
   - FTS5 session 搜索 + LLM 摘要
   - **Honcho** dialectic user modeling（用户画像）
   - 兼容 [agentskills.io](https://agentskills.io) 开放标准
4. **调度**：内置 cron scheduler，结果投到任意平台
5. **并行委派**：spawn 独立子 agent，Python script via RPC
6. **6 种 backend**：local / Docker / SSH / Singularity / Modal / **Daytona**（serverless，闲置时近乎零成本）
7. **可训练**：batch trajectory generation + trajectory compression → 训练下一代工具调用模型

**模型可热切**：`hermes model` 切到 Nous Portal / OpenRouter / NovitaAI / NVIDIA NIM / Xiaomi MiMo / z.ai-GLM / Kimi / MiniMax / Hugging Face / OpenAI / 自定义 endpoint

## 顶层目录结构（28 个子目录）

```
hermes-agent/
├── acp_adapter/        # Agent Client Protocol 适配器（外部 agent 接入）
├── acp_registry/       # Agent 注册表
├── agent/              # 核心 agent 引擎（对话循环、工具分发、模型路由）
├── apps/               # 桌面/移动端（Electron + Tauri）
├── cron/               # 内置调度器
├── datagen-config-examples/  # 训练数据生成配置示例
├── docker/             # Docker 镜像
├── docs/               # 文档
├── gateway/            # 消息网关（Telegram/Discord/Slack/WeChat...）
├── hermes_cli/         # CLI 入口
├── infographic/        # 信息图素材
├── locales/            # 多语言（中/英/乌尔都）
├── nix/                # Nix 包
├── optional-mcps/      # 可选 MCP 服务
├── optional-skills/    # 可选 skills
├── packaging/          # 安装包配置（deb/rpm/nsis/AppImage...）
├── plans/              # 路线图
├── plugins/            # 插件系统
├── providers/          # 模型 provider 适配（Anthropic/OpenAI/Moonshot/HF...）
├── scripts/            # 运维脚本
├── skills/             # 内置 skills 库
├── tests/              # 测试
├── tools/              # 核心工具集
├── tui_gateway/        # 终端 UI
├── ui-tui/             # 终端 UI 资源
├── AGENTS.md           # **开发指南（71KB，AI 编码必读）**
├── cli.py              # **CLI 入口（652KB，单文件）**
├── batch_runner.py     # 批量运行器（58KB）
├── CONTRIBUTING.md     # 贡献指南（47KB）
├── README.md / README.zh-CN.md
├── Dockerfile
├── LICENSE (MIT)
└── .hadolint.yaml / .mailmap / .dockerignore / .env.example
```

## 启动方式

```bash
# Linux/macOS/WSL2
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Windows (native PowerShell, no WSL needed)
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

也可手动：

```bash
cd subprojects/repos-from-external/agent/hermes-agent
pip install -r requirements.txt
python cli.py
# 或
python -m hermes_cli
```

## 与本机 e:\HJ\Web 主业务的结合点

| 场景 | 价值 |
|---|---|
| **学习循环机制** | 它的"自创建 skill + 自我进化 + FTS5 检索历史"可借鉴做 e:\HJ\Web 的「AI 客服学习模块」 |
| **多渠道网关** | 22+ 平台统一接入范本（与 openclaw 异曲同工，但 hermes 偏 Python） |
| **Honcho user modeling** | 第三方库的「辩证用户画像」可作个性化推荐后端 |
| **6 种 backend 抽象** | local/Docker/SSH/Modal/Daytona 切换，适合做 hj1982.cn 后台的**多环境部署抽象层** |
| **agentskills.io 开放标准** | Hermes 兼容的 skill 格式是新兴开放标准，可关注 |

## 风险

- **协议修正后无风险**（MIT，可商用、修改、二次发布）
- 体积 108MB（浅克隆），完整克隆可达 GB 级
- 极活跃（每天数百 commit），固定 commit pin 引用
- 桌面 Electron 体积更大；与 openclaw（Tauri）对比，Hermes 偏**研究向**，openclaw 偏**产品向**

## 与同批其他 5 仓的关系

| 仓 | 定位差异 |
|---|---|
| hermes-agent | **Python 自进化 Agent**，支持 ~20 平台，研究向 |
| openclaw | **TypeScript 多渠道**（22+）个人 AI 助手，**含 WeChat/QQ/Feishu** |
| openhuman | **Tauri 桌面**（Rust 核心 + React UI），GPL-3.0 |
| claude-code-router | Claude Code **模型路由代理**（不入应用层） |
| cursor2api | Cursor Web 逆向 → 标准 API（**玩具级**） |
| ai-api-integration | OpenAI 兼容**多模型接入教程**（非 SDK） |
