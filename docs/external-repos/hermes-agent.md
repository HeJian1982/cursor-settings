# hermes-agent (🐴 养马)

> 仓库本地路径：`subprojects/repos-from-external/agent/hermes-agent/` (**❌ clone 失败，仅占位**)
> 来源：<https://github.com/NousResearch/hermes-agent>
> 协议：MIT ｜ 主语言：Python ｜ **194,071★**
> 体积：335 MB

## 解决什么问题

"The agent that grows with you"（自我进化的 AI Agent）—— 来自 Nous Research（Hermes 系列模型同源）。

Hermes-Agent 仓库内 topics 包含 `clawdbot` / `moltbot` / `openclaw`，与养虾/养人属同一生态（互相引流）。

## clone 失败详情

| 次数 | 错误 | 缺失字节 |
|---|---|---|
| 1 (原始) | `curl 18 transfer closed with outstanding read data remaining` | 7,881 |
| 2 (postBuffer=512M + lowSpeedLimit) | `curl 56 schannel: server closed abruptly (missing close_notify)` | 55,749 |
| 3 (postBuffer=512M) | `curl 56 schannel` | 9,249 |

**根因**：本机到 GitHub HTTPS 长连接不稳，浅克隆 335 MB 仍频繁断链。
**结论**：重试 2 次无效，按计划第 6 节「网速受限，留空目录」处置。

## 启动方式（待 clone 成功）

基于 GitHub API 公开元数据推测：

```bash
cd subprojects/repos-from-external/agent/hermes-agent
pip install -r requirements.txt
# 或：poetry install
python -m hermes_agent
# 具体入口需 clone 完看 README.md
```

## 与本机 e:\HJ\Web 的结合点

- Nous Research 是 Hermes 系列（Hermes-3 / Hermes-4）背后的实验室，hermes-agent 是其 agent 框架
- 适合做自进化 Agent 的**研究参考**
- 与本仓 `local-machine-configs/` 配合：可探索让 Cursor 走 hermes-agent 的本地模型路由

## 风险

- **clone 失败**：本机环境问题，非仓库问题，可重试或换时段
- **极活跃**：每周数千 commit，需要 fetch --unshallow 才能拿到完整 history
- **Python 依赖大**：clone 后若 `pip install` 会装大量 ML 库（torch 等），先评估磁盘

## 后续动作

1. 改 `git clone --depth=1 --filter=blob:none` 减少包体（仅取树结构，不取 blob）
2. 或用 GitHub 官方 zip 下载
3. 修好网络后重试
