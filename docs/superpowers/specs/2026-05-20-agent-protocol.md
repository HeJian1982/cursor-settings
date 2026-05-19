<!-- 版权所有 © 何健 保留所有权利 -->
<!-- 文件路径：docs/superpowers/specs/2026-05-20-agent-protocol.md -->

# Agent 编排协议（Agent Protocol）

> 版本：v1.0.0
> 日期：2026-05-20
> 状态：草稿

## 1. 概述

Agent 编排协议定义了 HeJian AI Hub 中多个专业 Agent 之间的协作规范，包括接口契约、内置 Agent 设计、调用协议和编排模式。

## 2. Agent 接口契约

### 2.1 核心接口

```typescript
// 能力描述
interface Capability {
  id: string;
  name: string;
  description: string;
  inputSchema: z.ZodSchema;
  outputSchema: z.ZodSchema;
}

// Agent 请求
interface AgentRequest {
  id: string;                    // 请求唯一 ID
  task: string;                  // 任务描述
  context: ConversationContext;  // 当前对话上下文
  memory?: MemoryQuery;         // 记忆查询条件
  requireCapabilities?: string[]; // 需要的 Agent 能力
  metadata?: Record<string, unknown>;
}

// Agent 响应
interface AgentResponse {
  requestId: string;
  success: boolean;
  result: unknown;
  confidence: number;           // 0-1，置信度
  usedMemory?: MemoryRef[];     // 使用了哪些记忆
  subTasks?: SubTask[];         // 可拆分的子任务
  suggestions?: string[];       // 建议的后续操作
  error?: AgentError;
  duration: number;             // 处理时长（ms）
}

// 子任务定义
interface SubTask {
  id: string;
  description: string;
  assignedAgent?: AgentType;    // 建议的 Agent 类型
  dependsOn?: string[];         // 依赖的其他子任务 ID
  priority?: number;            // 优先级 1-5
  estimatedDuration?: number;   // 预估时长（ms）
}

// Agent 错误
interface AgentError {
  code: AgentErrorCode;
  message: string;
  recoverable: boolean;
  fallback?: string;           // 降级策略描述
}

enum AgentErrorCode {
  TIMEOUT = 'TIMEOUT',
  MODEL_ERROR = 'MODEL_ERROR',
  CONTEXT_OVERFLOW = 'CONTEXT_OVERFLOW',
  CAPABILITY_NOT_FOUND = 'CAPABILITY_NOT_FOUND',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  RATE_LIMITED = 'RATE_LIMITED',
}

// Agent 基类
interface Agent {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly capabilities: Capability[];
  readonly defaultModel: ModelType;
  readonly supportedModels: ModelType[];

  handle(request: AgentRequest): Promise<AgentResponse>;
  validate(request: AgentRequest): ValidationResult;
  health(): Promise<HealthStatus>;
}
```

### 2.2 上下文注入

```typescript
// 对话上下文（短期记忆）
interface ConversationContext {
  sessionId: string;
  userId: string;
  platform: Platform;
  messages: Message[];
  currentTask?: string;
  variables: Record<string, unknown>;
  injectedContext?: InjectedContext;
}

// 注入的上下文（来自上下文同步器）
interface InjectedContext {
  todayAgenda?: AgendaItem[];
  recentCodeChanges?: CodeChange[];
  pendingEmails?: EmailSummary[];
  relevantDocs?: DocSummary[];
}

// 记忆引用
interface MemoryRef {
  type: 'short' | 'mid' | 'long';
  id: string;
  content: string;
  relevance: number;       // 相关度 0-1
  retrievedAt: Date;
}
```

## 3. 内置 Agent 详细设计

### 3.1 Planner Agent

**职责**：任务分解、依赖分析、调度策略制定

```typescript
interface PlannerAgent extends Agent {
  readonly id = 'planner';
  readonly name = '任务规划师';
  readonly description = '分析复杂任务，制定执行计划';
}

// Planner Prompt 模板
const PLANNER_SYSTEM_PROMPT = `你是任务规划专家（Planner）。

## 核心职责
1. 分析用户任务，拆分为可执行的子任务
2. 分析子任务之间的依赖关系
3. 确定最优执行顺序和并行机会
4. 评估任务风险和资源需求

## 输出格式
必须返回结构化的执行计划，包含：
- 子任务列表（每个有明确的输入输出）
- 依赖关系图
- 建议的 Agent 类型
- 预估完成时间

## 约束
- 子任务粒度适中（单个任务 5-15 分钟可完成）
- 考虑记忆系统中的历史经验
- 对不确定的内容明确标注"需确认"

## 当前用户信息
{m userInfo}
{m userPreferences}

## 当前上下文
{m todayAgenda}
{m recentWork}

## 相关记忆
{m relevantMemories}`;

// 任务分解示例
interface TaskPlan {
  goal: string;
  tasks: PlannedTask[];
  estimatedTotalTime: number;
  riskFactors: string[];
}

interface PlannedTask {
  id: string;
  description: string;
  agentType: AgentType;
  input: Record<string, unknown>;
  expectedOutput: string;
  dependsOn: string[];
  estimatedTime: number;
  canParallelWith?: string[];
}
```

### 3.2 Coder Agent

**职责**：代码生成、调试、Code Review

```typescript
interface CoderAgent extends Agent {
  readonly id = 'coder';
  readonly name = '代码助手';
  readonly description = '生成、审查、调试代码';
}

// Coder Prompt 模板
const CODER_SYSTEM_PROMPT = `你是资深全栈工程师（Coder），专精 TypeScript、React、Node.js。

## 核心职责
1. 根据需求生成高质量代码
2. Code Review 和优化建议
3. 调试和 Bug 定位
4. 解释代码逻辑

## 代码质量标准
- 遵循 TypeScript strict 模式
- 完整的类型定义
- 必要的注释（解释"为什么"而非"是什么"）
- 考虑边界情况和错误处理
- 符合项目现有代码风格

## 当前项目上下文
- 项目路径：{projectPath}
- 使用的框架：{frameworks}
- 代码风格规范：{codingStandards}
- 相关测试要求：{testRequirements}

## 可用的工具
- 文件读取/写入
- 代码搜索
- 运行命令（lint/typecheck/test）

## 约束
- 不生成可能有安全漏洞的代码
- SQL 查询必须参数化
- 不在代码中硬编码密钥
- 生成测试代码时覆盖主要分支`;

// Code Review 模板
interface CodeReviewRequest {
  code: string;
  filePath: string;
  language: string;
  reviewFocus?: ('security' | 'performance' | 'style' | 'correctness')[];
}

interface CodeReviewResult {
  issues: CodeIssue[];
  suggestions: CodeSuggestion[];
  score: number;  // 0-100
  summary: string;
}

interface CodeIssue {
  severity: 'critical' | 'major' | 'minor';
  line?: number;
  message: string;
  rule?: string;
  suggestion?: string;
}
```

### 3.3 Researcher Agent

**职责**：信息检索、来源优先级、总结格式

```typescript
interface ResearcherAgent extends Agent {
  readonly id = 'researcher';
  readonly name = '研究助手';
  readonly description = '检索信息、总结知识';
}

// 信息来源优先级
const SOURCE_PRIORITIES: Record<string, number> = {
  'official-docs': 10,      // 官方文档
  'github-issue': 8,        // GitHub Issue
  'stackoverflow': 7,       // Stack Overflow
  'blog': 5,                // 博客文章
  'forum': 4,                // 论坛
  'unknown': 1,             // 未知来源
};

// Researcher Prompt 模板
const RESEARCHER_SYSTEM_PROMPT = `你是信息检索专家（Researcher）。

## 核心职责
1. 理解用户的信息需求
2. 从多个来源检索相关信息
3. 评估来源的可信度和时效性
4. 整合信息，生成结构化总结

## 来源优先级
- 官方文档 > GitHub Issue > Stack Overflow > 博客 > 论坛
- 优先选择最近 2 年内的资料
- 技术问题优先英文资料

## 总结格式
\`\`\`
## 信息摘要
[1-3 句话概括核心发现]

## 详细发现
### 要点 1
- 来源：[来源名称]
- 内容：[具体信息]
- 可信度：高/中/低

### 要点 2
...

## 参考资料
1. [标题](URL) - [来源] - [时间]
2. ...

## 行动建议
基于研究发现，建议：
1. ...
\`\`\`

## 约束
- 标注每个要点的来源
- 区分事实和观点
- 对不确定的内容说明"需要进一步验证"
- 避免偏见和夸大`;

// 检索结果
interface ResearchResult {
  query: string;
  findings: Finding[];
  summary: string;
  references: Reference[];
  confidence: number;
  nextSteps?: string[];
}

interface Finding {
  content: string;
  source: string;
  sourceType: string;
  relevance: number;
  timestamp?: Date;
  verified: boolean;
}
```

### 3.4 Operator Agent

**职责**：执行操作（发消息、查日历、发邮件），权限管理

```typescript
interface OperatorAgent extends Agent {
  readonly id = 'operator';
  readonly name = '操作执行器';
  readonly description = '执行平台操作：发消息、查日历、发邮件等';
}

// 操作能力定义
const OPERATOR_CAPABILITIES: Capability[] = [
  {
    id: 'send-message',
    name: '发送消息',
    description: '通过指定平台发送消息',
    inputSchema: z.object({
      platform: PlatformSchema,
      target: UserRefSchema,
      content: MessageContentSchema,
    }),
    outputSchema: z.object({ success: z.boolean(), messageId: z.string() }),
  },
  {
    id: 'query-calendar',
    name: '查询日历',
    description: '查询用户的日历事件',
    inputSchema: z.object({
      startDate: z.date(),
      endDate: z.date(),
      calendarIds: z.array(z.string()).optional(),
    }),
    outputSchema: z.array(CalendarEventSchema),
  },
  {
    id: 'send-email',
    name: '发送邮件',
    description: '通过用户邮箱发送邮件',
    inputSchema: z.object({
      to: z.array(z.string().email()),
      cc: z.array(z.string().email()).optional(),
      subject: z.string(),
      body: z.string(),
      attachments: z.array(AttachmentSchema).optional(),
    }),
    outputSchema: z.object({ success: z.boolean(), messageId: z.string() }),
  },
  {
    id: 'create-reminder',
    name: '创建提醒',
    description: '创建定时提醒',
    inputSchema: z.object({
      title: z.string(),
      remindAt: z.date(),
      description: z.string().optional(),
    }),
    outputSchema: z.object({ reminderId: z.string() }),
  },
];

// Operator Prompt 模板
const OPERATOR_SYSTEM_PROMPT = `你是操作执行专家（Operator）。

## 核心职责
1. 执行需要权限的操作（发消息、查日历、发邮件等）
2. 严格遵循权限边界
3. 操作前确认，执行后报告
4. 处理操作失败的情况

## 权限要求
| 操作 | 需要的权限 |
|------|-----------|
| 发消息 | 平台已登录 |
| 查日历 | 日历同步已授权 |
| 发邮件 | 邮箱已配置 |
| 创建提醒 | 系统提醒已授权 |

## 操作确认流程
对于高风险操作（发送外部消息、删除数据等），必须：
1. 先向用户确认操作内容
2. 用户明确同意后执行
3. 执行后汇报结果

## 约束
- 不执行未授权的操作
- 不在用户不知情的情况下发送消息
- 所有操作记录到日志
- 操作超时时间：30 秒

## 当前可用的操作能力
{availableCapabilities}

## 用户权限状态
{userPermissions}`;

// 操作结果
interface OperationResult {
  operation: string;
  success: boolean;
  result?: unknown;
  error?: string;
  duration: number;
  timestamp: Date;
}
```

## 4. Agent 间调用协议

### 4.1 任务依赖表达

```typescript
// 依赖关系定义
interface TaskDependency {
  taskId: string;
  dependsOn: string[];
  mergeStrategy: 'replace' | 'merge' | 'latest';
}

// 结果合并策略
type MergeStrategy =
  | 'replace'    // 直接替换
  | 'merge'      // 合并内容
  | 'latest'     // 使用最新结果
  | 'best'       // 选择置信度最高的
  | 'vote';      // 投票决定

// 调用上下文
interface AgentCallContext {
  request: AgentRequest;
  parent?: {
    agentId: string;
    requestId: string;
  };
  dependencies: Map<string, AgentResponse>;
  sharedState: Record<string, unknown>;
}
```

### 4.2 合并结果示例

```typescript
// 合并多个 Research Agent 的结果
function mergeResearchResults(
  results: AgentResponse[],
  strategy: MergeStrategy
): ResearchResult {
  switch (strategy) {
    case 'merge':
      // 合并所有来源，去重后排序
      const allFindings = results.flatMap(r => r.result.findings);
      const deduplicated = deduplicateBySource(allFindings);
      return {
        findings: deduplicated.sort((a, b) => b.relevance - a.relevance),
        summary: consensusSummary(results.map(r => r.result.summary)),
        confidence: averageConfidence(results),
      };

    case 'best':
      // 选择置信度最高的
      const best = results.reduce((a, b) =>
        a.confidence > b.confidence ? a : b
      );
      return best.result;

    default:
      return results[0].result;
  }
}
```

## 5. 编排模式

### 5.1 串行编排（Serial）

```
用户: "帮我写一个用户注册 API"

┌──────────┐    ┌──────────┐    ┌──────────┐
│ Planner  │───▶│  Coder   │───▶│ Operator │
│ 分解任务  │    │ 生成代码  │    │ 保存文件  │
└──────────┘    └──────────┘    └──────────┘
     │               │                │
  任务列表      生成的代码      保存结果
```

```typescript
async function serialOrchestration(
  request: AgentRequest,
  agents: Agent[]
): Promise<AgentResponse> {
  const context = new AgentCallContext({ request });

  for (const agent of agents) {
    const response = await agent.handle({
      ...context.request,
      context: {
        ...context.request.context,
        variables: {
          ...context.request.context.variables,
          previousResult: context.dependencies.get(agent.id),
        },
      },
    });

    if (!response.success) {
      return handleFailure(response, agents);
    }

    context.dependencies.set(agent.id, response);
  }

  return context.dependencies.get(agents[agents.length - 1].id)!;
}
```

### 5.2 并行编排（Parallel）

```
用户: "帮我调研 React 和 Vue 的最新状态管理方案"

┌──────────────────────────────────────────┐
│                  Planner                  │
│              分解为两个子任务              │
└───────────┬──────────────────┬───────────┘
            ▼                  ▼
   ┌────────────────┐  ┌────────────────┐
   │ Researcher-A   │  │ Researcher-B   │
   │ 调研 React      │  │ 调研 Vue       │
   │ 状态管理        │  │ 状态管理        │
   └───────┬────────┘  └───────┬────────┘
           │                    │
           ▼                    ▼
   ┌──────────────────────────────────────┐
   │              Merge                    │
   │         合并结果，生成对比报告          │
   └──────────────────────────────────────┘
```

```typescript
async function parallelOrchestration(
  request: AgentRequest,
  tasks: SubTask[]
): Promise<AgentResponse> {
  // 1. 按依赖分组，无依赖的任务并行执行
  const groups = groupByDependencies(tasks);

  const allResults: AgentResponse[] = [];

  for (const group of groups) {
    const parallelTasks = group.filter(t => !t.dependsOn?.length);

    const results = await Promise.all(
      parallelTasks.map(task => executeTask(task))
    );

    allResults.push(...results);
  }

  // 2. 合并结果
  return mergeResults(allResults, request);
}
```

### 5.3 循环编排（Loop）

最多 3 轮，用于结果不达标时的重新规划：

```
┌──────────────────────────────────────┐
│         初始规划（Planner）            │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│           执行（Agent(s)）             │
└──────────────┬───────────────────────┘
               │
               ▼
       ┌───────────────┐
       │ 结果评估       │
       │ (confidence?) │
       └───────┬───────┘
               │
    ┌──────────┴──────────┐
    ▼                      ▼
  达标                   未达标
    │                   ┌──┴───────────────┐
    ▼                   │ loop < 3?       │
  结束                  └──┬───────────────┘
                          ▼
                   ┌───────────────┐
                   │ 重新规划       │
                   │ (调整策略)     │
                   └───────┬───────┘
                           │
                           ▼
                   ┌───────────────┐
                   │ 继续执行       │
                   └───────────────┘
```

```typescript
const MAX_LOOP_ITERATIONS = 3;
const CONFIDENCE_THRESHOLD = 0.7;

async function loopOrchestration(
  request: AgentRequest
): Promise<AgentResponse> {
  let iteration = 0;
  let context = new AgentCallContext({ request });

  while (iteration < MAX_LOOP_ITERATIONS) {
    // 1. 规划
    if (iteration > 0) {
      context.request.task = adjustTaskBasedOnFeedback(
        context.request.task,
        context.dependencies
      );
    }

    const plannerResponse = await planner.handle(context.request);

    // 2. 执行
    const executionResult = await executePlan(plannerResponse.subTasks);

    // 3. 评估
    if (executionResult.confidence >= CONFIDENCE_THRESHOLD) {
      return executionResult;
    }

    iteration++;

    if (iteration >= MAX_LOOP_ITERATIONS) {
      return {
        ...executionResult,
        warning: 'Max iterations reached, returning best effort result',
      };
    }
  }
}
```

## 6. 超时与熔断

### 6.1 Agent 超时配置

| Agent | 默认超时 | 最大超时 | 降级策略 |
|-------|---------|---------|---------|
| planner | 30s | 60s | 返回草稿计划 |
| coder | 60s | 120s | 返回代码框架 |
| researcher | 45s | 90s | 返回已知信息 |
| operator | 30s | 30s | 报告操作失败 |

### 6.2 熔断器

```typescript
interface CircuitBreakerConfig {
  failureThreshold: number;      // 失败次数阈值
  resetTimeout: number;          // 重置超时（ms）
  halfOpenRequests: number;      // 半开状态请求数
}

class AgentCircuitBreaker {
  private failures = 0;
  private lastFailure: Date;
  private state: 'closed' | 'open' | 'half-open' = 'closed';

  async execute<T>(agent: Agent, request: AgentRequest): Promise<T> {
    if (this.state === 'open') {
      if (Date.now() - this.lastFailure > this.config.resetTimeout) {
        this.state = 'half-open';
      } else {
        throw new AgentError({
          code: AgentErrorCode.RATE_LIMITED,
          message: `Circuit breaker open for ${agent.id}`,
          recoverable: true,
          fallback: 'fallbackStrategy',
        });
      }
    }

    try {
      const result = await withTimeout(
        agent.handle(request),
        agent.defaultTimeout
      );

      if (this.state === 'half-open') {
        this.reset();
      }

      return result;
    } catch (error) {
      this.recordFailure();
      throw error;
    }
  }

  private recordFailure(): void {
    this.failures++;
    this.lastFailure = new Date();

    if (this.failures >= this.config.failureThreshold) {
      this.state = 'open';
    }
  }

  private reset(): void {
    this.failures = 0;
    this.state = 'closed';
  }
}
```

## 7. 结果置信度

### 7.1 置信度计算

```typescript
function calculateConfidence(
  result: unknown,
  context: {
    memoryHitRate: number;       // 记忆命中率
    sourceReliability: number;   // 来源可靠性
    modelConfidence: number;     // 模型自评置信度
    errorCount: number;          // 处理过程中的错误数
  }
): number {
  // 加权平均
  const weights = {
    memory: 0.2,
    source: 0.3,
    model: 0.4,
    errors: 0.1,
  };

  // 错误惩罚
  const errorPenalty = Math.max(0, 1 - context.errorCount * 0.1);

  return (
    context.memoryHitRate * weights.memory +
    context.sourceReliability * weights.source +
    context.modelConfidence * weights.model +
    errorPenalty * weights.errors
  );
}
```

### 7.2 置信度影响决策

| 置信度范围 | 行为 |
|-----------|------|
| 0.9-1.0 | 直接返回，可附带建议 |
| 0.7-0.9 | 返回结果，标注不确定性 |
| 0.5-0.7 | 返回结果，提示需要确认 |
| 0.3-0.5 | 触发循环编排，重新处理 |
| < 0.3 | 返回错误，请求用户澄清 |

## 8. 依赖

- 依赖文档：
  - [2026-05-19-hejian-ai-hub-design.md](./2026-05-19-hejian-ai-hub-design.md)
  - [2026-05-20-adapter-protocol.md](./2026-05-20-adapter-protocol.md)
- 被依赖文档：
  - [2026-05-20-memory-rules.md](./2026-05-20-memory-rules.md)（Agent 调用记忆系统）

---

*文档版本：v1.0.0 | 最后更新：2026-05-20*
