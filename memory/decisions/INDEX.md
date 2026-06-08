# Decisions Index

> 记录每个重要架构/方案决策及其理由，供未来参考。
> 格式：问题 → 选项 → 决策 → 理由。

---

## 决策记录

| 日期 | 决策 | 状态 |
|------|------|------|
| 2026-05-20 | 规则文件从 20 个合并为 18 个 | 已执行 |
| 2026-05-20 | 同步脚本全部重写而非删除 | 已执行 |
| 2026-05-20 | 同步工具目标：Cursor settings.json 子集（而非全局规则） | 已执行 |
| 2026-05-20 | 记忆系统分层：preferences/projects/lessons/decisions 四类 | 已执行 |
| 2026-05-19 | HeJian AI Hub 项目启动，TypeScript Node.js | 已执行 |
| 2026-05-19 | HeJianHub 适配器协议：统一 PlatformAdapter 接口 | 已执行 |
| 2026-05-19 | HeJianHub 多 Agent 协议：主 Agent 编排子 Agent | 已执行 |
| 2026-06-08 | 热榜巡检纳入定时任务，每日 08:00 | 已执行 |
| 2026-06-08 | Skill 健康检查纳入每周任务，周日 09:00 | 已执行 |
| 2026-06-08 | Skill 优化：保留 taste-skill，删除 6 个重叠 design skill | 已执行 |
| 2026-06-08 | 热榜高价值项目转化为 Cursor 规则（25/26/27 三层门控） | 已执行 |

---

## 决策详情

### 2026-05-20 · 规则文件合并策略

**问题**：20 个规则文件存在大量重复内容（跨文件引用不一致、版权头重复、commit 格式重复）。

**选项**：
- A. 删除重复引用，保留现状
- B. 系统性合并：从删除重复文件开始，逐步整合

**决策**：B（系统性合并）

**理由**：方案 A 治标不治本，合并后文件减少 2 个（20→18），消除了 5 处悬空引用，后续维护成本更低。

---

### 2026-05-20 · 同步工具保留而非删除

**问题**：`sync-global-rule.ps1` 等 3 个脚本核心逻辑为空。

**选项**：
- A. 删除脚本，降低 INSTALL.md 描述
- B. 实现真正的同步逻辑

**决策**：B（实现同步逻辑）

**理由**：用户工作流需要跨机器同步 Cursor 配置，实现价值大于维护成本。

---

### 2026-05-20 · 同步工具目标：Cursor settings.json 子集

**问题**：Cursor 全局规则存储在 `settings.json` 的 `cursor.rules` 字段，路径指向文件系统目录。

**决策**：sync-global-rule.ps1 同步 `cursor.rules` 条目；sync-local-configs.ps1 同步 settings 快照（排除扩展列表等临时数据）。

**理由**：不能直接覆盖整个 settings.json（会丢失未同步的字段），但可以精细化同步关键子集。

---

### 2026-05-20 · 记忆系统分层设计

**问题**：单一日志文件无法区分偏好/项目/教训/决策。

**决策**：四层分类
- `preferences/` — 用户偏好和通信风格
- `projects/` — 项目上下文
- `lessons/` — 从错误中学到的可执行洞察
- `decisions/` — 架构/方案决策及理由

**理由**：分层后每次洞察有唯一归属，不污染同一文件。分类明确也便于后续检索。

---

### 2026-05-19 · HeJianHub 技术栈选型

**问题**：AI Hub 需要跨平台消息网关 + 多 Agent 编排。

**决策**：TypeScript + Node.js + Zod（运行时验证）+ BullMQ（任务队列）+ pg（PostgreSQL 持久化）

**理由**：
- 与 Cursor（TypeScript）技能复用，降低认知负担
- Zod 比 class-validator 更适合运行时 schema 验证
- BullMQ 提供可靠的任务队列 + 重试机制
- pg 支持向量扩展（未来 AI 向量检索）

---

### 2026-05-19 · 适配器协议统一接口

**问题**：多平台接入（Telegram/Discord/飞书/微信）各有不同的 API 和认证方式。

**决策**：`PlatformAdapter` 统一接口
```typescript
interface PlatformAdapter {
  sendMessage(chatId: string, text: string): Promise<void>;
  getUpdates(): Promise<Message[]>;
  // ...
}
```

**理由**：上层 Agent 逻辑不感知具体平台，换平台只需实现新适配器。

---

### 2026-05-19 · 多 Agent 编排协议

**问题**：主 Agent 需要调度多个专业化子 Agent（如记忆 Agent、工具 Agent）。

**决策**：`AgentProtocol` 统一通信格式
```typescript
interface AgentMessage {
  from: AgentId;
  to: AgentId;
  task: Task;
  priority: 'high' | 'normal' | 'low';
}
```

**理由**：统一协议使 Agent 间通信有据可依，支持任务依赖、优先级、并行执行。

---

### 2026-06-08 · 热榜巡检纳入定时任务 + 转化为规则

**问题**：热榜巡检靠手动，分析结果没有转化为行动。

**决策**：
1. 创建 `trending-inspect.ps1`，每日 08:00 自动抓 GitHub API，对比基线，高价值推飞书
2. 发现的高价值项目立即评估纳入规则：guard-skills 转化为 25/26/27 三条 Cursor 规则

**理由**：热榜价值在于"今天发现，明天就用"。定时任务保证持续输入，三层规则保证每次 AI 生成都经过质量门控。

---

### 2026-06-08 · Skill 定期优化：每周健康检查

**问题**：93+ skills 积累后出现重叠、垃圾、不一致，没有机制清理。

**决策**：
1. `skill-health-check.ps1`：自动检查断链、缺失 SKILL.md、空 skill、磁盘占用
2. 每周日 09:00 定时执行，有问题推飞书
3. 重叠 skill 原则：保留通用性最强的，删除专项重复

**理由**：定期小修优于一次性大清理。健康检查 + 飞书告警使问题在积累成灾前被捕获。
