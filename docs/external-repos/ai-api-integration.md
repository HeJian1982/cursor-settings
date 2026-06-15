# ai-api-integration

> 仓库本地路径：`subprojects/repos-from-external/ai/ai-api-integration/`
> 来源：<https://github.com/CCCpan/ai-api-integration>
> 协议：MIT ｜ 主语言：Go（教程 + 文档） ｜ 49★

## 解决什么问题

国内开发者接 GPT-5 / Claude Opus 4.7 / Gemini 3.1 时三道关：
1. 账号注册
2. 付费方式
3. 网络访问

每家厂商 SDK / 参数 / 计费都不同。**用一个 OpenAI 兼容网关统一**：

```
所有模型 → xdhdancer.top/v1 (OpenAI 协议) → 路由到各家
```

工具侧（Cursor / Cline / ChatBox / Claude Code）原生支持自定义 OpenAI endpoint，配置一次通吃。

## 核心结构（教程型，非 SDK）

```
ai-api-integration/
├── docs/
│   ├── modalities/      # 视觉/文本/图片/音频/Sora/Suno 各能力教程
│   ├── cases/           # 实战案例
│   └── *.md             # 接入指南
├── examples/            # 客户端配置示例（Cursor/Cline/ChatBox）
├── assets/              # 案例视频/封面
└── README_CN.md / README_EN.md
```

## 实战案例（README 主推）

| 案例 | 成果 |
|---|---|
| 合同核验机器人（微信龙虾） | 8-10 分钟 → 36 秒（-90%），5 工具 → 1 指令 |
| 小红书日更账号 | 14w+ 粉，13w+ 赞，单条最高 160w 播放 |

## 启动方式

```bash
# 本仓库主要是文档，直接读 README_CN.md + docs/ 即可
# 实际接入走 xdhdancer.top 网关，按 README 步骤配置客户端
```

## 与本机 e:\HJ\Web 的结合点

- **接入参考**：hj1982.cn 后台加 AI 能力时，可参照 docs/modalities/ 的视觉/文本接入模板
- **多模型切换**：用 OpenAI 兼容协议一份代码切换底层模型（避免被某家厂商锁死）
- **付费通道**：xdhdancer.top 是该仓库作者自己的网关，与本仓无商业关系，可自行替换为其他网关

## 风险

- 仓库 star 极少（49），社区维护力度低
- 网关 xdhdancer.top 第三方依赖，**长期可用性未承诺**
- 仓库大量内容是"软文"风格（推自家网关），需要甄别
