# openclaw (🦞 OpenClaw — Personal AI Assistant)

> 仓库本地路径：`subprojects/repos-from-external/agent/openclaw/`
> 来源：<https://github.com/openclaw/openclaw>
> 协议：**MIT**（Copyright 2026 OpenClaw Foundation） ｜ 主语言：TypeScript ｜ **378,814★**
> commit SHA：`c1219d161d3e8a6a78c21915c97d6e87858104d6`（2026-06-15）
> 本地体积：180 MB（20037 文件，浅克隆）

> ⚠️ **协议修正**：之前 GitHub API 返回 `NOASSERTION` / `Other` 误判为协议未明；实查 LICENSE 文件是 **MIT**（README badge `License-MIT-blue.svg` 也有声明）。可自由使用、商用、修改。

## 解决什么问题

**个人 AI 助手**跑在你自己的设备上，**多渠道接入**：

- 跨设备：macOS / iOS / Android / Windows（含原生 Windows Hub）
- 跨渠道：**22+ 平台**
  - 国际：WhatsApp / Telegram / Slack / Discord / Google Chat / Signal / iMessage / IRC / Microsoft Teams / Matrix / Mattermost / Nextcloud Talk / Nostr / Synology Chat / Tlon / Twitch / Zalo
  - **国内**：**Feishu（飞书）/ WeChat（微信）/ QQ** / Zalo Personal / LINE
  - 调试：WebChat
- Gateway 只是**控制面**，产品是助手本身
- 支持 Live Canvas（实时渲染）、语音/听写
- 推荐安装：`openclaw onboard`（交互式引导，macOS/Linux/Windows 通吃）

## 顶层目录结构

```
openclaw/
├── apps/                    # 多端应用（macos, ios, windows, swabble...）
├── packages/                # monorepo 核心包
├── extensions/              # 插件（含 open-prose 等）
├── skills/                  # 技能库（含 skill-creator）
├── ui/                      # 独立 UI 模块
├── config/                  # 配置文件
├── deploy/                  # 部署相关
├── docs/                    # 文档源
├── src/                     # 主代码（gateway）
├── scripts/                 # 运维脚本
├── test/                    # 测试
├── qa/                      # QA 工具
├── security/                # 安全相关
├── patches/                 # 补丁
├── git-hooks/               # git 钩子
├── .agents/                 # Agent 配置
├── LICENSE                  # MIT
├── README.md
└── VISION.md
```

## 启动方式

```bash
# 1. 装好 node/npm/pnpm/bun 任一
# 2. 交互式引导（推荐）
cd subprojects/repos-from-external/agent/openclaw
openclaw onboard

# 或用 npm 全局
npm install -g openclaw
openclaw start
```

Windows 用户有**原生 Hub 桌面 app**（tray + chat + node mode + local MCP）。

## 与本机 e:\HJ\Web 主业务的结合点

| 场景 | 价值 |
|---|---|
| **个人 AI 助手 + 国内渠道** | OpenClaw 是少数**直接支持微信/QQ/飞书**的开源个人 AI 助手，可作 hj1982.cn 后台个人版接入参考 |
| **多渠道整合** | 一个后端、22+ 渠道前端的架构范本（解决「小红书 / 抖音 / 公众号 各自 API 各自接」的痛点） |
| **Live Canvas** | 实时渲染能力可借鉴做交互式组件展示 |
| **Tauri 桌面 + MCP** | 与 openhuman（养人）类似，OpenClaw 也有 Windows Hub，参考其本地 MCP 模式 |

## 风险

- **协议修正后无协议风险**（MIT，可商用、修改、二次发布，保留版权声明即可）
- 极活跃（每天数千 commit），固定 commit pin 引用
- 22 渠道里部分（iMessage / WeChat）涉及**逆向或非公开 API**，商用时注意 ToS
- 体积 180MB（浅克隆），全克隆可达 GB 级

## 与同批其他 5 仓的关系

| 仓 | 定位差异 |
|---|---|
| openclaw | 个人 AI 助手，**多渠道**（22+），桌面 + 移动 |
| hermes-agent | Nous Research 自进化 agent，**Python + ML** 向 |
| openhuman | Tauri 桌面 AI，**Rust 核心 + React UI** |
| claude-code-router | Claude Code 的**模型路由代理**（不入应用层） |
| cursor2api | Cursor Web 逆向 → 标准 API（**玩具级**，接口易变） |
| ai-api-integration | OpenAI 兼容**多模型接入教程**（非 SDK） |
