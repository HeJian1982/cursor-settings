# intake/ — GitHub 热门 AI/Cursor 项目盘点

> 2026-06-28 批次 · 15 个项目 · 全部 `--depth=1` shallow clone
> 来源：用户人工筛选 + GitHub API + WebFetch 补充

## 项目分类总览

### A 类：作为 Skill 安装（5 个）

| 项目 | 源 | 星级 | 状态 |
|---|---|---|---|
| `last30days-skill` | mvanhorn | 47K | ✅ 已装入 `.agents/skills\last30days-skill\` |
| `taste-skill` | Leonxlnx | 52K | ✅ 已装入 `.agents/skills\taste-skill\`（覆盖旧版本） |
| `Understand-Anything` | Egonex-AI | 68K | ✅ 已装入 `.agents/skills\understand-anything\` |
| `Anthropic-Cybersecurity-Skills` | mukul975 | 22K | ✅ 已装入 `.agents/skills\anthropic-cybersecurity-skills\`（817 个子 skill） |
| `no-mistakes` | kunchenguid | 3.8K | ✅ 已装入 `.agents/skills\no-mistakes-tool\` |

### B 类：MCP Server 候选（待评估）

| 项目 | 星级 | 评估状态 |
|---|---|---|
| `codebase-memory-mcp` | 17K | 待集成 npm 包 |
| `Agent-Reach` | 43K | 待集成 mcporter |
| `cognee` | 24K | 可作为 MCP，重量级 |
| `supermemory` | 27K | 可作为 MCP |
| `MoneyPrinterTurbo` | 93K | 视频生成独立产品，非 MCP |
| `worldmonitor` | 60K | Tauri dashboard，独立产品 |

### C 类：参考文档（已抽取到 `references/`）

| 项目 | 抽取内容 |
|---|---|
| `system_prompts_leaks/Cursor/cursor.md` | Cursor 系统提示词泄露（18KB），**仅作内部参考** |
| `OpenMontage/CURSOR.md` + `COPILOT.md` + `CODEX.md` + `CLAUDE.md` | 多 Agent IDE 规则模板（跨 Cursor / Copilot / Codex / Claude Code） |
| `OpenMontage/AGENT_GUIDE.md` (40KB) | Agent 工作流完整指南 |
| `no-mistakes/AGENTS.md` (19KB) | `.no-mistakes.yaml` 工作流规范 |
| `taste-skill/SKILL.md` | AI 防 slop 风格指南 |

### D 类：暂不融入

| 项目 | 理由 |
|---|---|
| `markitdown` (微软) | Python 库，可作为依赖但不是 skill |
| `ai-website-cloner-template` | 仅 1-file 模板 |
| `MoneyPrinterTurbo` | 视频生成独立产品 |
| `worldmonitor` | 实时情报 dashboard，独立部署 |

## 目录结构

```
intake/
├── README.md                       # 本文件
├── references/                     # 抽取的参考文档
└── scripts/                        # intake 相关脚本
    └── intake-clone.ps1            # 批量克隆脚本（在仓库根 scripts/）
```

## 融入路径

| 路径 | 命令 |
|---|---|
| 克隆所有项目 | `pwsh -File scripts/intake-clone.ps1` |
| 复制 A 类 skill 到 `.agents/skills/` | `pwsh -File scripts/intake-install-skills.ps1` |
| 抽取参考文档到 `intake/references/` | `pwsh -File scripts/intake-extract-refs.ps1` |
| 重新生成基线 | `pwsh -File scripts/generate-baselines.ps1` |

## 决策依据

| 维度 | A 类入选 | B 类待评估 | C/D 类排除 |
|---|---|---|---|
| 形态 | plugin.json + skill 可直装 | 需 npm/服务/二进制 | 不匹配 Cursor 集成模型 |
| 语言 | 多为 Python/TS | C/Go/Python | — |
| 依赖 | 轻量 | 中到重 | 重或孤立 |
| License | MIT/Apache | MIT/AGPL | 大多 MIT |

## 下一步建议

1. **B 类实装**：先评估 `codebase-memory-mcp` 和 `cognee` 哪一个做 MCP server
2. **taste-skill 启用**：在 Cursor `cursor.rules` 数组里追加该 skill 的指引
3. **OpenMontage 模板复用**：把它的 6 个 agent 规则格式套用到本仓库的 `.cursor/rules/`
4. **清理**：3 个月后重新评估 `intake/`，未启用的项目可清理或归档