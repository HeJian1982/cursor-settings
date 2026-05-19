<!-- 版权所有 © 何健 保留所有权利 -->
<!-- 文件路径：docs/superpowers/specs/2026-05-20-memory-rules.md -->

# 记忆系统写入与检索规则

> 版本：v1.0.0
> 日期：2026-05-20
> 状态：草稿

## 1. 概述

记忆系统是 HeJian AI Hub 的核心能力之一，通过三层记忆架构（短期、中期、长期）实现跨会话上下文保持和知识积累。本文档定义记忆的数据模型、写入规则、检索流程和遗忘策略。

## 2. 三层记忆数据模型

### 2.1 短期记忆（内存）

当前会话上下文，存储在内存中，会话结束丢失。

```typescript
// 短期记忆结构
interface ShortTermMemory {
  sessionId: string;
  userId: string;
  startedAt: Date;
  messages: Message[];
  variables: Record<string, unknown>;
  currentTask?: ActiveTask;
  recentResults: Result[];
}

// 单条消息
interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
  platform: Platform;
  agentId?: string;
  metadata?: Record<string, unknown>;
}

// 当前活跃任务
interface ActiveTask {
  id: string;
  description: string;
  status: 'planning' | 'executing' | 'waiting_confirm' | 'completed' | 'failed';
  progress: number;       // 0-100
  assignedAgent?: string;
  subtasks: SubTask[];
}

// 限制：最近 20 条消息
const MAX_SHORT_TERM_MESSAGES = 20;

// 短期记忆管理器
class ShortTermMemoryManager {
  private memory: Map<string, ShortTermMemory> = new Map();

  get(sessionId: string): ShortTermMemory | undefined {
    return this.memory.get(sessionId);
  }

  create(sessionId: string, userId: string): ShortTermMemory {
    const memory: ShortTermMemory = {
      sessionId,
      userId,
      startedAt: new Date(),
      messages: [],
      variables: {},
      recentResults: [],
    };
    this.memory.set(sessionId, memory);
    return memory;
  }

  addMessage(sessionId: string, message: Omit<Message, 'id'>): void {
    const memory = this.memory.get(sessionId);
    if (memory) {
      memory.messages.push({ ...message, id: generateId() });
      // 限制消息数量
      if (memory.messages.length > MAX_SHORT_TERM_MESSAGES) {
        memory.messages = memory.messages.slice(-MAX_SHORT_TERM_MESSAGES);
      }
    }
  }

  clear(sessionId: string): void {
    this.memory.delete(sessionId);
  }
}
```

### 2.2 中期记忆（JSON 文件）

近 7 天的重要事件，存储在 JSON 文件中。

```typescript
// 中期记忆条目
interface MidTermEntry {
  id: string;
  type: 'event' | 'preference' | 'project' | 'decision';
  content: string;
  summary: string;         // 简短摘要（用于快速检索）
  tags: string[];
  source: {
    sessionId: string;
    platform: Platform;
    timestamp: Date;
  };
  confidence: number;      // 0-1
  importance: 'high' | 'medium' | 'low';
  expiresAt: Date;         // 7 天后过期
  archived: boolean;       // 是否已归档
}

// 事件条目（项目里程碑、重要活动）
interface EventEntry extends MidTermEntry {
  type: 'event';
  data: {
    title: string;
    description: string;
    date: Date;
    category: 'milestone' | 'meeting' | 'deadline' | 'achievement';
    relatedProject?: string;
    relatedPeople?: string[];
  };
}

// 偏好条目（用户喜欢/不喜欢）
interface PreferenceEntry extends MidTermEntry {
  type: 'preference';
  data: {
    category: 'code_style' | 'communication' | 'tool' | 'schedule' | 'other';
    preference: 'like' | 'dislike' | 'neutral';
    description: string;
    examples?: string[];
  };
}

// 项目快照（当前项目状态）
interface ProjectSnapshot extends MidTermEntry {
  type: 'project';
  data: {
    projectPath: string;
    projectName: string;
    currentTask?: string;
    recentChanges: string[];
    issues?: string[];
    technologies: string[];
  };
}

// 决策条目（架构选型、重要决定）
interface DecisionEntry extends MidTermEntry {
  type: 'decision';
  data: {
    title: string;
    options: string[];
    chosen: string;
    reason: string;
    alternatives: string[];
    reviewDate?: Date;
  };
}

// 中期记忆存储位置
const MID_TERM_DIR = 'data/memory/mid/';
const MID_TERM_FILES = {
  events: `${MID_TERM_DIR}events.json`,
  preferences: `${MID_TERM_DIR}preferences.json`,
  projects: `${MID_TERM_DIR}projects.json`,
  decisions: `${MID_TERM_DIR}decisions.json`,
};

// 中期记忆管理器
class MidTermMemoryManager {
  private cache: Map<string, MidTermEntry[]> = new Map();
  private filePaths: Record<string, string>;

  constructor(basePath: string) {
    this.filePaths = {
      events: `${basePath}/events.json`,
      preferences: `${basePath}/preferences.json`,
      projects: `${basePath}/projects.json`,
      decisions: `${basePath}/decisions.json`,
    };
  }

  async write(entry: MidTermEntry): Promise<void> {
    const type = entry.type === 'event' ? 'events' :
                 entry.type === 'preference' ? 'preferences' :
                 entry.type === 'project' ? 'projects' : 'decisions';

    const entries = await this.load(type);
    entries.push(entry);

    // 设置 7 天过期
    entry.expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await this.save(type, entries);
    this.cache.set(type, entries);
  }

  async query(filter: {
    type?: MidTermEntry['type'];
    tags?: string[];
    since?: Date;
    importance?: 'high' | 'medium' | 'low';
  }): Promise<MidTermEntry[]> {
    const entries = await this.loadAll();

    return entries.filter(entry => {
      if (filter.type && entry.type !== filter.type) return false;
      if (filter.tags?.length && !filter.tags.some(t => entry.tags.includes(t))) return false;
      if (filter.since && entry.source.timestamp < filter.since) return false;
      if (filter.importance && entry.importance !== filter.importance) return false;
      return true;
    });
  }

  async archive(): Promise<void> {
    // 归档过期条目为结构化摘要
    const now = new Date();
    const entries = await this.loadAll();

    const expired = entries.filter(e => e.expiresAt < now && !e.archived);

    for (const entry of expired) {
      entry.archived = true;
      // 写入长期记忆（ChromaDB）
      await longTermMemory.write({
        content: `${entry.summary}\n\n${entry.content}`,
        metadata: {
          type: entry.type,
          tags: entry.tags,
          originalId: entry.id,
          archivedAt: now,
        },
      });
    }

    // 删除已归档条目
    await this.saveAll(entries.filter(e => !e.archived));
  }
}
```

### 2.3 长期记忆（ChromaDB）

持久化语义记忆，支持向量检索。

```typescript
// 长期记忆条目
interface LongTermEntry {
  id: string;
  content: string;              // 原始内容
  embedding: number[];          // 向量
  metadata: {
    type: 'knowledge' | 'pattern' | 'skill' | 'context';
    tags: string[];
    timestamp: Date;
    source: 'user' | 'reflection' | 'archive' | 'import';
    confidence: number;
    lastAccessed?: Date;
    accessCount: number;
    userId?: string;
  };
}

// 长期记忆配置
interface LongTermConfig {
  embeddingModel: 'deepseek-embed' | 'ollama-embed';
  embeddingDimension: number;
  collectionName: string;
  persistPath: string;
}

// 默认配置（DeepSeek embed）
const DEFAULT_LONG_TERM_CONFIG: LongTermConfig = {
  embeddingModel: 'deepseek-embed',
  embeddingDimension: 1536,
  collectionName: 'hejian-hub-memory',
  persistPath: 'data/memory/long/',
};

// 长期记忆管理器
class LongTermMemoryManager {
  private client: ChromaClient;
  private collection: Collection;

  constructor(config: LongTermConfig) {
    this.client = new ChromaClient({ path: config.persistPath });
  }

  async init(): Promise<void> {
    this.collection = await this.client.getOrCreateCollection({
      name: this.config.collectionName,
      metadata: { 'hnsw:space': 'cosine' },
    });
  }

  async write(entry: Omit<LongTermEntry, 'id' | 'embedding'>): Promise<string> {
    // 生成 embedding
    const embedding = await this.generateEmbedding(entry.content);

    const id = generateId();

    await this.collection.add({
      ids: [id],
      embeddings: [embedding],
      documents: [entry.content],
      metadatas: [{
        ...entry.metadata,
        timestamp: entry.metadata.timestamp.toISOString(),
      }],
    });

    return id;
  }

  async query(
    query: string,
    options: {
      nResults?: number;       // 返回数量，默认 5
      where?: Record<string, unknown>;  // 元数据过滤
      threshold?: number;      // 相似度阈值
    } = {}
  ): Promise<LongTermEntry[]> {
    const { nResults = 5, where, threshold = 0.7 } = options;

    const queryEmbedding = await this.generateEmbedding(query);

    const results = await this.collection.query({
      queryEmbeddings: [queryEmbedding],
      nResults,
      where,
    });

    if (!results.documents?.[0]) return [];

    return results.documents[0].map((doc, i) => ({
      id: results.ids[0][i],
      content: doc,
      embedding: results.embeddings?.[0][i] || [],
      metadata: {
        ...results.metadatas[0][i],
        timestamp: new Date(results.metadatas[0][i].timestamp),
      },
    })).filter(entry => entry.metadata.confidence >= threshold);
  }

  private async generateEmbedding(text: string): Promise<number[]> {
    if (this.config.embeddingModel === 'deepseek-embed') {
      // 调用 DeepSeek embed API
      const response = await fetch('https://api.deepseek.com/embeddings', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`,
        },
        body: JSON.stringify({
          model: 'deepseek-embed',
          input: text,
        }),
      });
      const data = await response.json();
      return data.data[0].embedding;
    } else {
      // Ollama embed
      const response = await fetch('http://localhost:11434/api/embeddings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'nomic-embed-text',
          prompt: text,
        }),
      });
      const data = await response.json();
      return data.embedding;
    }
  }

  // 更新访问统计
  async updateAccess(id: string): Promise<void> {
    const result = await this.collection.get({ ids: [id] });
    if (result.metadatas?.[0]) {
      await this.collection.update({
        ids: [id],
        metadatas: [{
          ...result.metadatas[0],
          lastAccessed: new Date().toISOString(),
          accessCount: (result.metadatas[0].accessCount || 0) + 1,
        }],
      });
    }
  }
}
```

## 3. 自动写入触发条件

每轮对话结束后，调用 LLM 评估是否写入记忆：

```typescript
interface MemoryWriteDecision {
  shouldWrite: boolean;
  targetLayer: 'short' | 'mid' | 'long' | 'both';
  entries: {
    content: string;
    type: 'event' | 'preference' | 'project' | 'decision' | 'knowledge';
    importance: 'high' | 'medium' | 'low';
    tags: string[];
  }[];
  reason: string;
}

// 评估 Prompt
const MEMORY_EVAL_PROMPT = `你是记忆评估专家。每轮对话结束后，判断是否需要写入记忆。

## 评估标准

必须写入的情况：
1. 新知识：API 用法、项目事实、技术方案
2. 用户偏好：表达喜欢/不喜欢（代码风格、沟通方式、工具选择）
3. 未完成任务：需要后续跟进的事项
4. 重要决策：架构选型、放弃的方案、最终决定
5. 项目里程碑：功能完成、版本发布、重大进展

不写入的情况：
- 普通闲聊
- 简单问答（不涉及项目上下文）
- 重复确认

## 输出格式
\`\`\`json
{
  "shouldWrite": true/false,
  "targetLayer": "short/mid/long/both",
  "entries": [{
    "content": "具体内容",
    "type": "event/preference/project/decision/knowledge",
    "importance": "high/medium/low",
    "tags": ["tag1", "tag2"]
  }],
  "reason": "判断理由"
}
\`\`\`

## 当前对话
{conversationHistory}

## 分析：`;

// 写入决策执行
async function evaluateAndWriteMemory(
  conversation: Message[],
  context: ConversationContext
): Promise<void> {
  const decision = await llm.evaluate(MEMORY_EVAL_PROMPT, {
    conversationHistory: formatConversation(conversation),
  });

  if (!decision.shouldWrite) return;

  for (const entry of decision.entries) {
    // 写入中期记忆
    if (decision.targetLayer === 'mid' || decision.targetLayer === 'both') {
      await midTermMemory.write({
        id: generateId(),
        type: entry.type,
        content: entry.content,
        summary: summarize(entry.content, 100),
        tags: entry.tags,
        source: {
          sessionId: context.sessionId,
          platform: context.platform,
          timestamp: new Date(),
        },
        confidence: entry.importance === 'high' ? 0.9 :
                     entry.importance === 'medium' ? 0.7 : 0.5,
        importance: entry.importance,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        archived: false,
      });
    }

    // 写入长期记忆
    if (decision.targetLayer === 'long' || decision.targetLayer === 'both') {
      await longTermMemory.write({
        content: entry.content,
        metadata: {
          type: entry.type === 'knowledge' ? 'knowledge' :
                entry.type === 'preference' ? 'pattern' : 'context',
          tags: entry.tags,
          timestamp: new Date(),
          source: 'user',
          confidence: entry.importance === 'high' ? 0.9 :
                      entry.importance === 'medium' ? 0.7 : 0.5,
          accessCount: 0,
          userId: context.userId,
        },
      });
    }
  }
}
```

## 4. 检索流程

### 4.1 三层融合检索

```typescript
interface MemoryQuery {
  query: string;
  sessionId?: string;
  userId?: string;
  types?: LongTermEntry['metadata']['type'][];
  tags?: string[];
  since?: Date;
  limit?: number;         // 最大返回条数，默认 10
  layers?: ('short' | 'mid' | 'long')[];
}

interface MemoryResult {
  items: MemoryRef[];
  totalCount: number;
  layerDistribution: {
    short: number;
    mid: number;
    long: number;
  };
}

// 三层融合检索
async function queryMemory(query: MemoryQuery): Promise<MemoryResult> {
  const {
    limit = 10,
    layers = ['short', 'mid', 'long'],
  } = query;

  const items: MemoryRef[] = [];
  const layerDistribution = { short: 0, mid: 0, long: 0 };

  // 1. 短期记忆（如果有 sessionId）
  if (layers.includes('short') && query.sessionId) {
    const shortMemory = shortTermMemory.get(query.sessionId);
    if (shortMemory) {
      const relevant = findRelevant(shortMemory.messages, query.query, 3);
      items.push(...relevant.map(m => ({
        type: 'short' as const,
        id: m.id,
        content: m.content,
        relevance: 1.0,  // 短期记忆相关性 = 1
        retrievedAt: new Date(),
      })));
      layerDistribution.short = relevant.length;
    }
  }

  // 2. 中期记忆
  if (layers.includes('mid')) {
    const midResults = await midTermMemory.query({
      type: query.types as any,
      tags: query.tags,
      since: query.since,
    });

    const topMid = midResults
      .sort((a, b) => b.confidence - a.confidence)
      .slice(0, Math.ceil(limit * 0.3));

    items.push(...topMid.map(e => ({
      type: 'mid' as const,
      id: e.id,
      content: e.content,
      relevance: e.confidence,
      retrievedAt: new Date(),
    })));
    layerDistribution.mid = topMid.length;
  }

  // 3. 长期记忆（语义检索）
  if (layers.includes('long')) {
    const longResults = await longTermMemory.query(query.query, {
      nResults: Math.ceil(limit * 0.5),
      where: {
        ...(query.userId && { userId: query.userId }),
        ...(query.types && { type: { $in: query.types } }),
      },
    });

    items.push(...longResults.map(e => ({
      type: 'long' as const,
      id: e.id,
      content: e.content,
      relevance: e.metadata.confidence,
      retrievedAt: new Date(),
    })));

    // 更新访问统计
    for (const entry of longResults) {
      await longTermMemory.updateAccess(entry.id);
    }
    layerDistribution.long = longResults.length;
  }

  // 4. 按相关性和优先级排序
  items.sort((a, b) => {
    // 短期记忆优先级最高
    const priority = { short: 3, mid: 2, long: 1 };
    const priorityDiff = priority[b.type] - priority[a.type];
    if (priorityDiff !== 0) return priorityDiff;
    // 同优先级按相关性排序
    return b.relevance - a.relevance;
  });

  return {
    items: items.slice(0, limit),
    totalCount: items.length,
    layerDistribution,
  };
}

// 上下文注入格式
function formatMemoryForContext(results: MemoryResult): string {
  if (results.items.length === 0) return '';

  const sections: string[] = ['## 相关记忆\n'];

  const byLayer = groupBy(results.items, 'type');

  if (byLayer.short?.length) {
    sections.push('### 当前会话\n');
    byLayer.short.forEach(item => {
      sections.push(`- ${item.content}\n`);
    });
  }

  if (byLayer.mid?.length) {
    sections.push('\n### 近期记忆（7天内）\n');
    byLayer.mid.forEach(item => {
      sections.push(`- ${item.content}\n`);
    });
  }

  if (byLayer.long?.length) {
    sections.push('\n### 历史知识\n');
    byLayer.long.forEach(item => {
      sections.push(`- ${item.content}\n`);
    });
  }

  return sections.join('');
}
```

### 4.2 上下文爆炸防护

限制返回条数和 token 消耗：

```typescript
const MEMORY_CONTEXT_LIMITS = {
  maxItems: 10,
  maxTokens: 2000,
  maxPerLayer: {
    short: 5,
    mid: 3,
    long: 5,
  },
};

function enforceMemoryLimits(result: MemoryResult): MemoryResult {
  let totalTokens = 0;
  const enforcedItems: MemoryRef[] = [];

  for (const item of result.items) {
    const itemTokens = estimateTokens(item.content);
    if (
      enforcedItems.length >= MEMORY_CONTEXT_LIMITS.maxItems ||
      totalTokens + itemTokens > MEMORY_CONTEXT_LIMITS.maxTokens ||
      enforcedItems.filter(i => i.type === item.type).length >=
        MEMORY_CONTEXT_LIMITS.maxPerLayer[item.type]
    ) {
      continue;
    }

    enforcedItems.push(item);
    totalTokens += itemTokens;
  }

  return {
    items: enforcedItems,
    totalCount: result.totalCount,
    layerDistribution: {
      short: enforcedItems.filter(i => i.type === 'short').length,
      mid: enforcedItems.filter(i => i.type === 'mid').length,
      long: enforcedItems.filter(i => i.type === 'long').length,
    },
  };
}
```

## 5. 遗忘策略

### 5.1 中期记忆遗忘

```typescript
// 归档任务（每天执行）
async function archiveMidTermMemory(): Promise<ArchiveResult> {
  const entries = await midTermMemory.loadAll();
  const now = new Date();

  const toArchive = entries.filter(e =>
    e.expiresAt < now && !e.archived
  );

  const result: ArchiveResult = {
    archived: 0,
    discarded: 0,
    errors: [],
  };

  for (const entry of toArchive) {
    try {
      // 生成结构化摘要
      const summary = await generateArchiveSummary(entry);

      // 写入长期记忆
      await longTermMemory.write({
        content: summary,
        metadata: {
          type: 'knowledge',
          tags: [...entry.tags, 'archived'],
          timestamp: now,
          source: 'archive',
          confidence: entry.confidence * 0.8,  // 归档时降低置信度
          accessCount: 0,
        },
      });

      entry.archived = true;
      result.archived++;
    } catch (error) {
      result.errors.push({ entryId: entry.id, error });
    }
  }

  // 删除已归档条目
  await midTermMemory.saveAll(entries.filter(e => !e.archived));

  return result;
}

async function generateArchiveSummary(entry: MidTermEntry): Promise<string> {
  const prompt = `将以下记忆条目压缩为结构化摘要（50-100字）：

类型：${entry.type}
内容：${entry.content}
标签：${entry.tags.join(', ')}

摘要：`;

  return await llm.complete(prompt);
}
```

### 5.2 长期记忆遗忘

```typescript
// 置信度降级策略
const CONFIDENCE_DECAY = {
  // 30 天内未访问，置信度降低
  decayAfterDays: 30,
  decayRate: 0.1,  // 每次降低 0.1
  minimumConfidence: 0.3,  // 低于此值标记为可删除
};

// 定期降级任务（每周执行）
async function degradeLowConfidenceMemory(): Promise<void> {
  const cutoff = new Date(
    Date.now() - CONFIDENCE_DECAY.decayAfterDays * 24 * 60 * 60 * 1000
  );

  const results = await longTermMemory.collection.get({
    where: {
      lastAccessed: { $lt: cutoff.toISOString() },
    },
  });

  for (const metadata of results.metadatas) {
    const newConfidence = metadata.confidence - CONFIDENCE_DECAY.decayRate;

    if (newConfidence < CONFIDENCE_DECAY.minimumConfidence) {
      // 标记为可删除（不立即删除，保留用户确认机会）
      await markForDeletion(metadata.id);
    } else {
      await longTermMemory.collection.update({
        ids: [metadata.id],
        metadatas: [{
          ...metadata,
          confidence: newConfidence,
        }],
      });
    }
  }
}

// 用户可手动删除
async function deleteMemory(id: string, userId: string): Promise<boolean> {
  const entry = await longTermMemory.collection.get({ ids: [id] });

  if (!entry.metadatas?.[0]) return false;
  if (entry.metadatas[0].userId !== userId) {
    throw new Error('Permission denied');
  }

  await longTermMemory.collection.delete({ ids: [id] });
  return true;
}
```

## 6. 每日复盘流程

### 6.1 触发配置

```typescript
interface DailyReflectionConfig {
  enabled: boolean;
  time: string;           // HH:mm 格式，默认 "22:00"
  timezone: string;      // 时区，默认 "Asia/Shanghai"
  excludeSessions?: string[];  // 排除的 session
}

// 默认配置
const DEFAULT_REFLECTION_CONFIG: DailyReflectionConfig = {
  enabled: true,
  time: '22:00',
  timezone: 'Asia/Shanghai',
};

// 复盘 Prompt 模板
const REFLECTION_PROMPT = `你是每日复盘专家。请分析今天的对话记录，生成复盘报告。

## 复盘目标
1. 总结今天完成了什么
2. 提炼学到的关键知识
3. 识别未完成的事项
4. 提取可复用的模式

## 输出格式
\`\`\`markdown
# 每日复盘 - {date}

## 今日完成
-

## 关键收获
-

## 待办事项
-

## 沉淀知识
-

## 改进建议
-
\`\`\`

## 今天的所有对话
{allConversations}

## 开始复盘`;
```

### 6.2 复盘执行

```typescript
class DailyReflectionExecutor {
  constructor(
    private shortTerm: ShortTermMemoryManager,
    private midTerm: MidTermMemoryManager,
    private longTerm: LongTermMemoryManager,
    private config: DailyReflectionConfig
  ) {}

  async execute(date: Date): Promise<ReflectionResult> {
    // 1. 收集当天的所有对话
    const sessions = await this.collectDaySessions(date);
    const conversations = sessions.flatMap(s => s.messages);

    if (conversations.length < 5) {
      return { executed: false, reason: '对话太少，跳过复盘' };
    }

    // 2. 生成复盘
    const reflection = await this.generateReflection(conversations, date);

    // 3. 保存复盘文件
    await this.saveReflectionFile(reflection, date);

    // 4. 提取精华写入长期记忆
    await this.promoteToLongTerm(reflection);

    // 5. 清理短期记忆（保留关键变量）
    await this.cleanupShortTerm(sessions);

    return {
      executed: true,
      reflection,
      stats: {
        sessionsCount: sessions.length,
        messagesCount: conversations.length,
      },
    };
  }

  private async generateReflection(
    conversations: Message[],
    date: Date
  ): Promise<string> {
    const formatted = this.formatConversations(conversations);

    const prompt = REFLECTION_PROMPT
      .replace('{date}', formatDate(date))
      .replace('{allConversations}', formatted);

    return await llm.complete(prompt);
  }

  private async promoteToLongTerm(reflection: string): Promise<void> {
    // 提取"沉淀知识"部分
    const knowledgeSection = extractSection(reflection, '沉淀知识');

    if (knowledgeSection) {
      await this.longTerm.write({
        content: knowledgeSection,
        metadata: {
          type: 'knowledge',
          tags: ['daily-reflection', '沉淀'],
          timestamp: new Date(),
          source: 'reflection',
          confidence: 0.8,
          accessCount: 0,
        },
      });
    }
  }

  private async saveReflectionFile(
    reflection: string,
    date: Date
  ): Promise<void> {
    const fileName = `memory/daily/${formatDate(date, 'yyyy-MM-dd')}-reflection.md`;
    const fullPath = join(process.cwd(), 'data', fileName);

    await fs.mkdir(dirname(fullPath), { recursive: true });
    await fs.writeFile(fullPath, `# 每日复盘\n\n${reflection}\n`, 'utf-8');
  }
}
```

## 7. 隐私保护

### 7.1 敏感信息识别与脱敏

```typescript
// 敏感信息模式
const SENSITIVE_PATTERNS: [RegExp, string][] = [
  // 密钥
  [/(?:api[_-]?key|secret[_-]?key|token)[\s:=]+["']?([a-zA-Z0-9_\-]{20,})["']?/gi, '[REDACTED_KEY]'],
  // 密码
  [/(?:password|pwd|passwd)[\s:=]+["']?([^\s'"]{8,})["']?/gi, '[REDACTED_PWD]'],
  // 身份证号
  [/\b\d{17}[\dXx]\b/g, '[REDACTED_ID]'],
  // 手机号
  [/\b1[3-9]\d{9}\b/g, '[REDACTED_PHONE]'],
  // 邮箱（部分脱敏）
  [/([a-zA-Z0-9])[a-zA-Z0-9]{2,10}(@[a-zA-Z0-9.]+)/g, '$1***$2'],
];

// 脱敏函数
function sanitizeForMemory(text: string): { text: string; redactedCount: number } {
  let redactedCount = 0;
  let sanitized = text;

  for (const [pattern, replacement] of SENSITIVE_PATTERNS) {
    const matches = text.match(pattern);
    if (matches) {
      redactedCount += matches.length;
      sanitized = sanitized.replace(pattern, replacement);
    }
  }

  return { text: sanitized, redactedCount };
}

// 写入前自动脱敏
async function writeMemoryWithSanitization(
  content: string,
  targetLayer: 'mid' | 'long'
): Promise<{ success: boolean; redactedCount: number }> {
  const { text, redactedCount } = sanitizeForMemory(content);

  if (redactedCount > 0) {
    console.log(`[Memory] Sanitized ${redactedCount} sensitive items before writing`);
  }

  if (targetLayer === 'mid') {
    await midTermMemory.write({ /* ... */ });
  } else {
    await longTermMemory.write({ /* ... */ });
  }

  return { success: true, redactedCount };
}
```

### 7.2 用户数据导出与删除

```typescript
// 导出用户所有数据
async function exportUserData(userId: string): Promise<ExportData> {
  return {
    shortTerm: Array.from(shortTermMemory.memory.values())
      .filter(m => m.userId === userId),
    midTerm: await midTermMemory.query({ userId }),
    longTerm: await longTermMemory.query('', { userId }),
    reflections: await loadReflectionFiles(userId),
    exportedAt: new Date(),
  };
}

// 删除用户所有数据
async function deleteUserData(userId: string): Promise<DeleteResult> {
  // 短期记忆
  const shortTermToDelete = Array.from(shortTermMemory.memory.entries())
    .filter(([, m]) => m.userId === userId)
    .map(([id]) => id);
  shortTermToDelete.forEach(id => shortTermMemory.clear(id));

  // 中期记忆（标记为删除）
  const midTermEntries = await midTermMemory.query({});
  const midTermToDelete = midTermEntries.filter(e =>
    e.source.sessionId.includes(userId)
  );
  // 物理删除...

  // 长期记忆
  await longTermMemory.collection.delete({
    where: { userId },
  });

  return {
    shortTermDeleted: shortTermToDelete.length,
    midTermDeleted: midTermToDelete.length,
    longTermDeleted: 0, // ChromaDB delete 返回值
  };
}
```

## 8. 依赖

- 依赖文档：
  - [2026-05-19-hejian-ai-hub-design.md](./2026-05-19-hejian-ai-hub-design.md)
  - [2026-05-20-agent-protocol.md](./2026-05-20-agent-protocol.md)（Agent 编排依赖记忆系统）

---

*文档版本：v1.0.0 | 最后更新：2026-05-20*
