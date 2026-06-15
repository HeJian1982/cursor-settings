# claude-code-router

> 仓库本地路径：`subprojects/repos-from-external/ai/claude-code-router/`
> 来源：<https://github.com/musistudio/claude-code-router>
> 协议：MIT ｜ 主语言：TypeScript ｜ 34,997★

## 解决什么问题

Claude Code 默认直连 Anthropic API。Claude Code Router 是个**本地代理**：

```
Claude Code → ccr (本地代理) → 任意 OpenAI 兼容 provider
```

- 简单任务路由到 DeepSeek / GLM / Ollama（便宜）
- 思考任务路由到 Claude Opus（贵但好）
- 长上下文任务路由到 Gemini（1M token）
- **热切换**：在 Claude Code 内用 `/model` 切后端
- **请求/响应变换器**：用 transformer JS 改 provider 行为

## 核心目录结构

```
claude-code-router/
├── packages/                 # 多包工作区
├── custom-router.example.js  # 自定义路由示例
├── config.example.json       # 主配置示例
├── tsconfig.base.json
├── README.md / README_zh.md  # 双语文档（中文完整）
├── CLAUDE.md                 # 给 Claude Code 看的开发备忘
├── blog/                     # 设计博客（Progressive Disclosure 论文等）
└── package.json              # npm 包：@musistudio/claude-code-router
```

## 启动方式

```bash
# 前置：装好 Claude Code
npm install -g @anthropic-ai/claude-code

# 装路由
npm install -g @musistudio/claude-code-router

# 写配置
cp config.example.json ~/.claude-code-router/config.json
# 编辑 config.json，配 Providers + Router 规则

# 跑
ccr start
# 把 Claude Code 的 base URL 指向 127.0.0.1:3456
```

## 与本机 e:\HJ\Web 主业务的结合点

- **低成本 AI 接入**：hj1982.cn 后台需要文本生成时，可改用「Claude Code Router + GLM Coding Plan」替代直接调 Claude API，单月成本可压到 $10
- **多模型兜底**：本地开发可用 Ollama，生产回退到云端 API

## 风险

- 路由规则错了会让 Claude Code 卡住或乱答
- 配置改动需要重启 ccr
- 自定义 transformer 写错可能泄出 API key（注意 `APIKEY` 鉴权设置）
