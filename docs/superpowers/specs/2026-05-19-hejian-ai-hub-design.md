<!-- 版权所有 © 何健 保留所有权利 -->
<!-- 文件路径：docs/superpowers/specs/2026-05-19-hejian-ai-hub-design.md -->

# HeJian AI Hub — 设计文档

> 版本：v1.0.0
> 日期：2026-05-19
> 作者：HeJian / Cursor AI

## 1. 背景与目标

当前 Cursor AI 定位为单一 IDE 内的辅助编码工具，缺乏跨平台消息汇聚、统一记忆和主动学习能力。本项目旨在将 Cursor 从"IDE 内的 AI 助手"升级为**本地 AI OS**——一个以用户为中心、数据完全本地、跨平台统一调度的个人智能中枢。

### 核心愿景

- **多平台汇聚**：微信、飞书、钉钉、Telegram、Discord 等 50+ 平台消息统一接入
- **多 Agent 协作**：专业 Agent 分工、互相调用、统一编排
- **本地优先**：所有数据存储在本地，不依赖第三方云服务
- **自我进化**：跨会话记忆、自动复盘、技能沉淀
- **主动感知**：自动同步邮件、会议、代码、文档上下文

### 对比参考

| 维度 | OpenClaw Hermes | OpenHuman | 本项目（HeJian AI Hub） |
|------|----------------|-----------|------------------------|
| 平台接入 | 50+ | 多渠道 | 50+（国内优先） |
| Agent 架构 | 多 Agent 联邦 | 单一大脑 | 集中式 Hub + 多 Agent |
| 记忆系统 | 向量数据库 | 云端记忆 | 本地 ChromaDB |
| 部署方式 | 云端 | 云端 | 本地优先 + 可选云端 |
| 与 Cursor 关系 | 解耦 | 解耦 | MCP 深度集成 |

---

## 2. 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户交互层                                 │
│   微信   飞书   钉钉   Telegram   Discord   Slack   Web UI      │
└──────────┬──────────────────────────────────────────────────────┘
           │ NormalizedMessage
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    平台接入层（Adapter Layer）                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐  │
│  │ WeChat  │ │  Lark   │ │ DingTalk│ │Telegram │ │ Discord  │  │
│  │ Adapter │ │ Adapter │ │ Adapter │ │ Adapter │ │ Adapter  │  │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────┘  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    消息路由中枢（Hub）                             │
│  ├─ 消息归一化（NormalizedMessage）                               │
│  ├─ 会话追踪（跨平台同一用户归并）                                   │
│  ├─ 任务队列（Task Queue）                                        │
│  └─ 路由策略（Keyword → LLM Classifier → Rule Engine）            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌──────────┐    ┌────────────┐   ┌──────────────┐
    │ Agent    │    │  上下文    │   │   记忆      │
    │ 编排引擎  │    │  同步器    │   │   系统      │
    └────┬─────┘    └────────────┘   └──────┬───────┘
         │                                   │
    ┌────┴────┐                    ┌─────────┴────────┐
    │ 内置 Agent │                    │  ChromaDB       │
    │          │                    │  (向量检索)      │
    │ Planner  │                    ├─────────────────┤
    │ Coder    │                    │  JSON 记忆文件   │
    │ Researcher│                    │  (结构化)       │
    │ Operator │                    └─────────────────┘
    └──────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      大模型层（可切换）                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  Ollama     │  │  DeepSeek   │  │  其他（Kimi/GLM...） │   │
│  │  (本地)      │  │  (云端合规)  │  │                      │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     MCP Server（向 Cursor 暴露能力）                │
│  ├─ 记忆查询工具                                                  │
│  ├─ 平台消息发送                                                  │
│  ├─ Agent 调用                                                   │
│  └─ 上下文注入                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 子系统详细设计

### 子系统 1：平台接入层（Adapter Layer）

#### 3.1 统一接口

所有 Adapter 实现同一接口：

```typescript
interface PlatformAdapter {
  readonly platform: string;
  readonly capabilities: PlatformCapabilities;

  // 接收消息（被动）
  receive(raw: unknown): NormalizedMessage;

  // 发送消息（主动）
  send(target: UserRef, content: MessageContent): Promise<void>;

  // 生命周期
  init(): Promise<void>;
  destroy(): Promise<void>;
}

interface NormalizedMessage {
  id: string;           // 全局唯一
  platform: Platform;
  platformMsgId: string; // 平台侧消息ID
  userId: string;
  userName: string;
  content: MessageContent;
  timestamp: Date;
  threadId?: string;   // 会话线程
  attachments?: Attachment[];
  replyTo?: string;    // 回复某条消息
}

type Platform =
  | 'wechat' | 'lark' | 'dingtalk'
  | 'telegram' | 'discord' | 'slack'
  | 'email' | 'whatsapp' | 'line';
```

#### 3.2 平台优先级

**第一期（国内优先）**

| 平台 | 接入方式 | 难度 | 优先级 |
|------|---------|------|--------|
| 飞书 | Webhook + Bot API | 中 | P0 |
| 钉钉 | 自定义 Robot | 中 | P0 |
| Telegram | Bot API + Webhook | 低 | P0 |
| 微信 | Windows Hook（网页版协议） | 高 | P1 |

**第二期（海外扩展）**

| 平台 | 接入方式 | 难度 |
|------|---------|------|
| Discord | Bot API | 低 |
| Slack | Bolt SDK | 低 |
| WhatsApp | WhatsApp Business API | 高 |
| Line | Messaging API | 中 |

#### 3.3 Adapter 实现规范

- 每个 Adapter 独立 npm 包：`@hejianhub/adapter-<platform>`
- 共享基础库：`@hejianhub/adapter-core`（统一错误处理、重试、日志）
- 消息去重：基于 `platformMsgId` 缓存 1 小时
- 限流保护：每分钟最大消息数可配置

---

### 子系统 2：消息路由中枢（Hub）

#### 3.4 核心职责

1. **消息归一化**：将所有 Adapter 的消息转换为 `NormalizedMessage`
2. **会话追踪**：同一用户在多平台的消息归并为统一会话
3. **任务队列**：将消息路由到对应 Agent，支持优先级
4. **路由策略**：Keyword → LLM Classifier → Rule Engine 三级路由

#### 3.5 路由策略

```
用户消息
  │
  ├─ [Keyword 匹配] ── 精确关键词 → 直接路由
  │
  ├─ [LLM Classifier] ── 小模型（llama3/qwen）判断意图 → 路由
  │
  └─ [Rule Engine] ── 兜底规则（时间/用户/上下文）
```

#### 3.6 会话追踪

```typescript
interface UnifiedSession {
  id: string;              // 全局会话ID
  userId: string;          // 用户全局ID
  primaryPlatform: Platform;
  threads: {               // 各平台会话线程
    wechat?: string;
    lark?: string;
    telegram?: string;
  };
  context: ConversationContext;
  lastActive: Date;
  tags: string[];          // 用户标签
}
```

---

### 子系统 3：多 Agent 编排引擎

#### 3.7 内置 Agent

| Agent | 职责 | 调用模型 |
|-------|------|---------|
| `planner` | 任务分解、规划、调度 | DeepSeek / Ollama |
| `coder` | 代码生成、调试、review | DeepSeek / Ollama |
| `researcher` | 信息检索、总结、知识挖掘 | DeepSeek |
| `operator` | 执行操作（发消息、查日历、发邮件） | DeepSeek / 小模型 |

#### 3.8 Agent 间调用协议

```typescript
interface AgentRequest {
  task: string;
  context: ConversationContext;
  memory?: MemoryQuery;
  requireCapabilities?: Capability[];
}

interface AgentResponse {
  result: unknown;
  confidence: number;      // 0-1
  usedMemory?: MemoryRef[];
  subTasks?: AgentRequest[]; // 可拆分任务
}
```

#### 3.9 编排模式

- **串行**：Planner 分解 → Coder 执行 → Operator 反馈
- **并行**：多个独立子任务并行分发给专业 Agent
- **循环**：结果不达标时重新规划（最多 3 轮）

---

### 子系统 4：本地记忆系统

#### 3.10 三层记忆架构

```
┌─────────────────────────────────────────────┐
│           长期记忆（ChromaDB）                │
│   - 语义检索                                  │
│   - 项目上下文、历史决策、偏好模式              │
│   - 全部对话的嵌入向量                         │
└─────────────────────────────────────────────┘
                    ▲ 每日复盘沉淀
                    │
┌─────────────────────────────────────────────┐
│           中期记忆（JSON 文件）                │
│   - 近 7 天重要事件                           │
│   - 项目里程碑、用户偏好快照                   │
│   - 结构化：projects.json / preferences.json  │
└─────────────────────────────────────────────┘
                    ▲ 每轮对话后评估
                    │
┌─────────────────────────────────────────────┐
│           短期记忆（内存）                      │
│   - 当前会话上下文                            │
│   - Cursor 当前打开的文件/项目                 │
│   - 最近 20 条消息                            │
└─────────────────────────────────────────────┘
```

#### 3.11 记忆自动写入规则

每轮对话结束后，调用 LLM 判断是否写入记忆：

```
IF 对话产生了新知识（API用法、项目事实）
   OR 用户表达了偏好（喜欢/不喜欢）
   OR 有未完成的后续任务
   OR 有重要决策（架构选型、放弃方案）
THEN 写入记忆
```

写入时同时写入：
- **ChromaDB**：嵌入向量（长期，可语义检索）
- **JSON 文件**：结构化摘要（中期，快速读取）

#### 3.12 每日复盘

每天固定时间（可配置）运行复盘 Agent：

1. 读取当天所有对话记录
2. 提炼：完成了什么、学到了什么、有什么未完成
3. 生成复盘摘要，写入 `memory/daily/YYYY-MM-DD-reflection.md`
4. 将复盘精华沉淀到长期记忆（ChromaDB）

---

### 子系统 5：上下文同步器

#### 3.13 同步范围

| 类别 | 数据源 | 同步频率 |
|------|--------|---------|
| 邮件 | Gmail / QQ邮箱 / 网易邮箱 | 每 5 分钟 |
| 日历 | 飞书日历 / Google Calendar | 每 5 分钟 |
| 代码 | Cursor 当前打开的 git 仓库 | 实时 |
| 文档 | 飞书文档 / 本地 Markdown | 每 10 分钟 |

#### 3.14 上下文注入

将同步到的内容经 LLM 压缩后，作为系统提示注入到 Agent 上下文：

```
[今日日程]
- 10:00 团队周会
- 15:00 代码评审

[最近代码变更]
- src/app/page.tsx: 新增 XXX 功能
- ...

[今日未处理邮件]
- 来自 XX 的邮件：...
```

---

## 4. 技术栈

| 组件 | 选型 | 版本 | 备注 |
|------|------|------|------|
| 运行时 | Node.js | >= 20 | 与 Cursor 生态一致 |
| 语言 | TypeScript | 5.x | strict 模式 |
| 本地大模型 | Ollama | latest | 纯本地，数据不外流 |
| 云端大模型 | DeepSeek | v3 | 国内合规优先 |
| 向量数据库 | ChromaDB | latest | 本地优先 |
| 消息队列 | BullMQ | 2.x | Redis 后端 |
| 平台 SDK | 各平台官方 | — | 稳定性优先 |
| ORM | Drizzle | latest | 轻量、结构化存储 |
| 配置管理 | Zod + dotenv | — | 类型安全的环境变量 |
| 日志 | Pino | latest | 结构化 JSON 日志 |

---

## 5. 项目结构

```
e:\HJ\HeJianHub\                    # 项目根目录
├── src/
│   ├── core/
│   │   ├── hub.ts                 # 消息路由中枢
│   │   ├── orchestrator.ts        # Agent 编排引擎
│   │   └── memory/
│   │       ├── short-term.ts      # 短期记忆
│   │       ├── mid-term.ts        # 中期记忆（JSON）
│   │       └── long-term.ts       # 长期记忆（ChromaDB）
│   ├── agents/
│   │   ├── planner/
│   │   ├── coder/
│   │   ├── researcher/
│   │   └── operator/
│   ├── adapters/
│   │   ├── core/                  # 共享基础库
│   │   ├── wechat/
│   │   ├── lark/
│   │   ├── dingtalk/
│   │   ├── telegram/
│   │   └── discord/
│   ├── context-sync/
│   │   ├── email.ts
│   │   ├── calendar.ts
│   │   └── code.ts
│   └── mcp-server/
│       └── index.ts               # MCP Server 向 Cursor 暴露能力
├── data/                          # 本地数据（完全用户掌控）
│   ├── memory/
│   │   ├── short/                 # 短期（内存快照）
│   │   ├── mid/                   # 中期（JSON）
│   │   └── long/                  # ChromaDB
│   ├── sessions/                  # 会话历史
│   └── config/                    # 用户配置
├── scripts/
│   └── daily-reflection.ts        # 每日复盘脚本
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── package.json
├── tsconfig.json
├── .env.local.template
└── README.md
```

---

## 6. 实现阶段

### 第一阶段（P0 — 核心跑通）

**目标**：Hub + Telegram + 飞书 + 记忆系统 + MCP Server

- [ ] 项目脚手架 + TypeScript 配置
- [ ] Adapter 基础框架（`@hejianhub/adapter-core`）
- [ ] Hub 消息路由核心逻辑
- [ ] Telegram Adapter（最简单，先跑通）
- [ ] 飞书 Adapter
- [ ] 三层记忆系统实现
- [ ] MCP Server 向 Cursor 暴露记忆查询工具
- [ ] DeepSeek 集成

**验收**：从 Telegram/飞书发消息，Hub 收到并回复，记忆正确存储。

### 第二阶段（P1 — 国内平台全接入）

- [ ] 钉钉 Adapter
- [ ] 微信 Adapter（Windows Hook）
- [ ] Agent 编排引擎（Planner / Coder / Researcher / Operator）
- [ ] BullMQ 任务队列
- [ ] 上下文同步器（邮件 + 日历）

**验收**：四个 Agent 协作完成复杂任务。

### 第三阶段（P2 — 自我进化）

- [ ] 每日自动复盘
- [ ] 技能沉淀系统（从复盘中提取可复用模式）
- [ ] 用户偏好学习（显式 + 隐式）

**验收**：连续使用一周后，Agent 展现出"记住用户习惯"的能力。

### 第四阶段（P3 — 海外扩展）

- [ ] Discord / Slack / WhatsApp Adapter
- [ ] Ollama 本地模型集成
- [ ] 数据加密（AES-256）
- [ ] Web UI 管理后台

**验收**：50+ 平台全部接入，统一管理。

---

## 7. 安全与隐私

- 所有用户数据存储在 `e:\HJ\HeJianHub\data\`，不上传任何第三方
- API 密钥存储在 `.env.local`，不 commit 到 git
- ChromaDB 数据可选 AES-256 加密
- 平台 Webhook 全部验证签名
- 敏感操作（删除记忆、清空会话）需要用户二次确认
- 日志脱敏：密钥、token、手机号自动打码

---

## 8. 与 Cursor 的集成

HeJian AI Hub 通过 MCP Server 向 Cursor 暴露以下能力：

| MCP 工具 | 功能 |
|----------|------|
| `hub.query_memory` | 查询用户的长期记忆 |
| `hub.send_to_platform` | 通过指定平台给用户发消息 |
| `hub.get_agenda` | 获取用户今日日程 |
| `hub.get_recent_code` | 获取 Cursor 最近修改的代码 |
| `hub.invoke_agent` | 调用指定 Agent 执行任务 |

Cursor 的 Agent 可以调用这些工具，将 Hub 的记忆和平台能力注入当前会话上下文。

---

## 9. 依赖与约束

### 依赖

- Node.js >= 20
- Redis（BullMQ 后端）
- ChromaDB（长期记忆）
- Ollama（可选，本地模型）
- DeepSeek API（云端模型）

### 约束

- 不得将任何用户数据发送到非用户授权的服务器
- 不得在用户不知情的情况下主动发送消息
- 不得使用未经用户同意的第三方服务
- 记忆系统对用户完全透明，可随时查看、修改、删除

---

## 10. 验收标准

| 维度 | 指标 |
|------|------|
| 功能完整性 | P0 阶段 6 项验收条件全部通过 |
| 记忆准确性 | Agent 能正确回忆 7 天前的对话要点 |
| 响应延迟 | Hub 路由消息 < 500ms（不含模型推理） |
| 平台稳定性 | 各平台 Adapter 月均掉线 < 1 次 |
| 用户可控性 | 所有数据可导出、可删除、可迁移 |
