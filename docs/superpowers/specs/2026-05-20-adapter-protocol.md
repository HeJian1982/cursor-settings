<!-- 版权所有 © 何健 保留所有权利 -->
<!-- 文件路径：docs/superpowers/specs/2026-05-20-adapter-protocol.md -->

# 平台适配器协议（Adapter Protocol）

> 版本：v1.0.0
> 日期：2026-05-20
> 状态：草稿

## 1. 概述

适配器协议是 HeJian AI Hub 与各消息平台（飞书、钉钉、Telegram、微信等）之间的标准化通信契约。所有平台适配器必须实现统一的接口规范，确保消息归一化、错误处理和生命周期管理的一致性。

## 2. 接口契约

### 2.1 核心接口

```typescript
// 平台能力描述
interface PlatformCapabilities {
  supportsMedia: boolean;           // 是否支持媒体消息
  supportsThreads: boolean;         // 是否支持会话线程
  supportsReactions: boolean;       // 是否支持表情回应
  supportsEdit: boolean;            // 是否支持消息编辑
  supportsDelete: boolean;          // 是否支持消息撤回
  supportsReply: boolean;           // 是否支持回复
  maxMessageLength: number;         // 最大消息长度
  supportedMediaTypes: MediaType[]; // 支持的媒体类型
}

type MediaType = 'image' | 'video' | 'audio' | 'file' | 'location';

interface PlatformAdapter {
  readonly platform: Platform;       // 平台标识
  readonly capabilities: PlatformCapabilities;
  readonly version: string;         // Adapter 版本

  // 生命周期
  init(config: AdapterConfig): Promise<void>;
  destroy(): Promise<void>;

  // 消息处理
  receive(raw: unknown): NormalizedMessage;
  send(target: UserRef, content: MessageContent): Promise<SendResult>;
  sendTyping(userId: string): Promise<void>;

  // Webhook 验证（部分平台需要）
  validateWebhook?(payload: unknown, headers: Record<string, string>): boolean;
}

// 用户引用（跨平台统一标识）
interface UserRef {
  platform: Platform;
  platformUserId: string;
  displayName: string;
  avatar?: string;
}

// 消息内容（结构化）
type MessageContent =
  | TextContent
  | MediaContent
  | TemplateContent
  | CompositeContent;

interface TextContent {
  type: 'text';
  text: string;
}

interface MediaContent {
  type: 'media';
  mediaType: MediaType;
  url: string;
  thumbnailUrl?: string;
  caption?: string;
}

interface TemplateContent {
  type: 'template';
  templateId: string;
  templateData: Record<string, unknown>;
}

interface CompositeContent {
  type: 'composite';
  parts: MessageContent[];
}

// 附件
interface Attachment {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
  url: string;
  thumbnailUrl?: string;
}

// 归一化消息
interface NormalizedMessage {
  id: string;               // 全局唯一 ID（platform + platformMsgId）
  platform: Platform;
  platformMsgId: string;    // 平台侧原始消息 ID
  user: UserRef;
  content: MessageContent;
  timestamp: Date;
  threadId?: string;        // 会话线程 ID
  replyTo?: string;         // 回复的消息 ID
  attachments: Attachment[];
  raw: unknown;             // 原始消息（保留用于调试）
}

// 发送结果
interface SendResult {
  success: boolean;
  platformMsgId?: string;
  error?: AdapterError;
}
```

### 2.2 平台枚举

```typescript
type Platform =
  | 'wechat' | 'lark' | 'dingtalk'
  | 'telegram' | 'discord' | 'slack'
  | 'email' | 'whatsapp' | 'line';

const PLATFORM_DISPLAY_NAMES: Record<Platform, string> = {
  wechat: '微信',
  lark: '飞书',
  dingtalk: '钉钉',
  telegram: 'Telegram',
  discord: 'Discord',
  slack: 'Slack',
  email: '邮件',
  whatsapp: 'WhatsApp',
  line: 'LINE',
};
```

## 3. 生命周期

### 3.1 状态机

```
                    ┌──────────┐
                    │   IDLE   │
                    └────┬─────┘
                         │ init()
                         ▼
         ┌──────────────────────────────────┐
         │           INITIALIZING            │
         │  (建立连接、认证、事件订阅)         │
         └───────────────┬──────────────────┘
                         │ 成功
                         ▼
              ┌─────────────────────┐
              │       READY          │◄─────────┐
              │ (可收发消息)          │          │
              └──────────┬───────────┘          │
                         │                     │
           ┌─────────────┼─────────────┐       │
           ▼             ▼             ▼       │
    ┌──────────┐  ┌────────────┐  ┌────────┐   │
    │RECEIVING │  │  SENDING   │  │ERROR   │───┘
    └──────────┘  └────────────┘  └────────┘   destroy()
                         │                     ▼
                         │              ┌──────────┐
                         └─────────────►│DESTROYING│
                                        └────┬─────┘
                                             │ 成功
                                             ▼
                                        ┌──────────┐
                                        │DESTROYED │
                                        └──────────┘
```

### 3.2 状态转换规则

| 当前状态 | 允许操作 | 转换条件 |
|---------|---------|---------|
| IDLE | init() | 调用 init() 后进入 INITIALIZING |
| INITIALIZING | 等待完成 | 成功进入 READY，失败进入 ERROR |
| READY | receive/send/destroy | 失败进入 ERROR，主动 destroy 进入 DESTROYING |
| ERROR | retry()/destroy() | retry() 重新进入 INITIALIZING，destroy() 进入 DESTROYING |
| DESTROYING | 等待完成 | 完成进入 DESTROYED |
| DESTROYED | — | 终态 |

## 4. 错误处理规范

### 4.1 错误分类

```typescript
interface AdapterError extends Error {
  code: AdapterErrorCode;
  platform: Platform;
  retryable: boolean;          // 是否可重试
  originalError?: Error;
  context?: Record<string, unknown>;
}

enum AdapterErrorCode {
  // 网络类（通常可重试）
  NETWORK_ERROR = 'NETWORK_ERROR',
  TIMEOUT = 'TIMEOUT',
  CONNECTION_LOST = 'CONNECTION_LOST',

  // 认证类（需要用户介入）
  AUTH_EXPIRED = 'AUTH_EXPIRED',
  AUTH_INVALID = 'AUTH_INVALID',
  PERMISSION_DENIED = 'PERMISSION_DENIED',

  // 限流类（可延迟重试）
  RATE_LIMITED = 'RATE_LIMITED',
  QUOTA_EXCEEDED = 'QUOTA_EXCEEDED',

  // 消息类（通常不可重试）
  MESSAGE_TOO_LONG = 'MESSAGE_TOO_LONG',
  INVALID_FORMAT = 'INVALID_FORMAT',
  UNSUPPORTED_MEDIA = 'UNSUPPORTED_MEDIA',

  // 平台类
  PLATFORM_ERROR = 'PLATFORM_ERROR',   // 平台返回的错误
  PLATFORM_UNAVAILABLE = 'PLATFORM_UNAVAILABLE',
}
```

### 4.2 重试策略（指数退避）

```typescript
interface RetryConfig {
  maxRetries: number;          // 最大重试次数，默认 3
  baseDelay: number;           // 基础延迟（ms），默认 1000
  maxDelay: number;            // 最大延迟（ms），默认 30000
  backoffMultiplier: number;   // 退避倍数，默认 2
  retryableErrors: AdapterErrorCode[]; // 可重试的错误码
}

const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 3,
  baseDelay: 1000,
  maxDelay: 30000,
  backoffMultiplier: 2,
  retryableErrors: [
    AdapterErrorCode.NETWORK_ERROR,
    AdapterErrorCode.TIMEOUT,
    AdapterErrorCode.CONNECTION_LOST,
    AdapterErrorCode.RATE_LIMITED,
    AdapterErrorCode.PLATFORM_UNAVAILABLE,
  ],
};

// 计算重试延迟
function calculateBackoff(attempt: number, config: RetryConfig): number {
  const delay = Math.min(
    config.baseDelay * Math.pow(config.backoffMultiplier, attempt),
    config.maxDelay
  );
  // 添加随机抖动（±20%）
  const jitter = delay * 0.2 * (Math.random() * 2 - 1);
  return Math.floor(delay + jitter);
}
```

### 4.3 死信处理

当消息处理失败且达到最大重试次数后，进入死信队列：

```typescript
interface DeadLetterEntry {
  message: NormalizedMessage;
  error: AdapterError;
  attempts: number;
  firstAttempt: Date;
  lastAttempt: Date;
  status: 'pending' | 'reviewed' | 'requeued' | 'discarded';
}

// 死信队列管理
interface DeadLetterQueue {
  enqueue(entry: DeadLetterEntry): Promise<void>;
  dequeue(): Promise<DeadLetterEntry | null>;
  requeue(id: string): Promise<void>;
  discard(id: string): Promise<void>;
}

// 死信处理策略
interface DeadLetterStrategy {
  onExhausted: 'queue' | 'notify' | 'discard';
  notifyUser?: boolean;
  maxAge?: number;  // 最长保留天数
}
```

## 5. 消息去重

基于 `platformMsgId` + 1 小时滑动窗口的幂等性保证：

```typescript
interface DeduplicationConfig {
  windowMs: number;     // 去重窗口（ms），默认 3600000（1小时）
  maxEntries: number;  // 缓存最大条目数，默认 10000
}

class MessageDeduplicator {
  private cache: LRUCache<string, Date>;

  constructor(private config: DeduplicationConfig) {
    this.cache = new LRUCache(config.maxEntries);
  }

  // 生成去重 key
  private makeKey(platform: Platform, platformMsgId: string): string {
    return `${platform}:${platformMsgId}`;
  }

  // 检查是否重复
  isDuplicate(platform: Platform, platformMsgId: string): boolean {
    const key = this.makeKey(platform, platformMsgId);
    return this.cache.has(key);
  }

  // 标记已处理
  markProcessed(platform: Platform, platformMsgId: string): void {
    const key = this.makeKey(platform, platformMsgId);
    this.cache.set(key, new Date());
  }

  // 清理过期条目
  cleanup(): void {
    const cutoff = Date.now() - this.config.windowMs;
    // LRUCache 自动处理...
  }
}
```

## 6. 限流保护

每个 Adapter 可独立配置每分钟最大消息数：

```typescript
interface RateLimitConfig {
  maxPerMinute: number;        // 每分钟最大消息数
  maxPerSecond: number;        // 每秒最大消息数（平滑发送用）
  burstAllowance: number;      // 突发容许量
  strategy: 'reject' | 'queue' | 'delay';
}

class RateLimiter {
  private tokens: number;
  private lastRefill: number;

  constructor(private config: RateLimitConfig) {
    this.tokens = config.maxPerMinute;
    this.lastRefill = Date.now();
  }

  // 尝试获取发送令牌
  async acquire(): Promise<boolean> {
    this.refill();

    if (this.tokens > 0) {
      this.tokens--;
      return true;
    }

    switch (this.config.strategy) {
      case 'reject':
        return false;
      case 'queue':
        // 加入等待队列
        await this.queueForRetry();
        return false;
      case 'delay':
        // 等待令牌恢复
        await this.waitForToken();
        return true;
    }
  }

  // 平滑补充令牌
  private refill(): void {
    const now = Date.now();
    const elapsed = now - this.lastRefill;
    const refillAmount = (elapsed / 60000) * this.config.maxPerMinute;

    this.tokens = Math.min(
      this.config.maxPerMinute,
      this.tokens + refillAmount
    );
    this.lastRefill = now;
  }
}
```

## 7. 飞书 Adapter 示例

```typescript
// @hejianhub/adapter-lark
import {
  PlatformAdapter,
  NormalizedMessage,
  MessageContent,
  UserRef,
  PlatformCapabilities,
  AdapterError,
  AdapterErrorCode,
} from '@hejianhub/adapter-core';

export class LarkAdapter implements PlatformAdapter {
  readonly platform = 'lark' as const;
  readonly capabilities: PlatformCapabilities = {
    supportsMedia: true,
    supportsThreads: true,
    supportsReactions: true,
    supportsEdit: true,
    supportsDelete: true,
    supportsReply: true,
    maxMessageLength: 4000,
    supportedMediaTypes: ['image', 'video', 'audio', 'file'],
  };

  private client: LarkClient;
  private deduplicator: MessageDeduplicator;
  private rateLimiter: RateLimiter;

  async init(config: AdapterConfig): Promise<void> {
    // 1. 验证配置
    this.validateConfig(config);

    // 2. 初始化飞书客户端
    this.client = new LarkClient({
      appId: config.appId,
      appSecret: config.appSecret,
      botName: config.botName,
    });

    // 3. 初始化去重和限流
    this.deduplicator = new MessageDeduplicator({ windowMs: 3600000 });
    this.rateLimiter = new RateLimiter({ maxPerMinute: 60 });

    // 4. 注册 Webhook 端点
    await this.registerWebhook(config.webhookUrl);

    console.log(`[LarkAdapter] Initialized for bot: ${config.botName}`);
  }

  async destroy(): Promise<void> {
    await this.unregisterWebhook();
    this.client = null as any;
    console.log('[LarkAdapter] Destroyed');
  }

  receive(raw: unknown): NormalizedMessage {
    const event = raw as LarkEvent;

    // 去重检查
    if (this.deduplicator.isDuplicate(this.platform, event.message.message_id)) {
      throw new AdapterError({
        code: AdapterErrorCode.DUPLICATE_MESSAGE,
        message: `Duplicate message: ${event.message.message_id}`,
        platform: this.platform,
        retryable: false,
      });
    }

    this.deduplicator.markProcessed(this.platform, event.message.message_id);

    // 归一化转换
    return {
      id: `${this.platform}:${event.message.message_id}`,
      platform: this.platform,
      platformMsgId: event.message.message_id,
      user: {
        platform: this.platform,
        platformUserId: event.sender.sender_id.open_id,
        displayName: event.sender.sender_id.open_id,
      },
      content: this.normalizeContent(event.message),
      timestamp: new Date(event.message.create_time * 1000),
      threadId: event.message.thread_id,
      replyTo: event.message.root_id,
      attachments: this.extractAttachments(event.message),
      raw: event,
    };
  }

  async send(target: UserRef, content: MessageContent): Promise<SendResult> {
    // 限流检查
    if (!(await this.rateLimiter.acquire())) {
      return {
        success: false,
        error: new AdapterError({
          code: AdapterErrorCode.RATE_LIMITED,
          message: 'Rate limit exceeded',
          platform: this.platform,
          retryable: true,
        }),
      };
    }

    try {
      const response = await this.client.message.create({
        receive_id_type: 'open_id',
        receive_id: target.platformUserId,
        msg_type: this.getMsgType(content),
        content: JSON.stringify(this.getContent(content)),
      });

      return {
        success: true,
        platformMsgId: response.data.message_id,
      };
    } catch (error) {
      return {
        success: false,
        error: AdapterError.from(error, this.platform),
      };
    }
  }

  // 内容归一化
  private normalizeContent(msg: LarkMessage): MessageContent {
    switch (msg.msg_type) {
      case 'text':
        return { type: 'text', text: msg.content };
      case 'post':
        return { type: 'text', text: this.extractTextFromPost(msg.content) };
      case 'image':
        return { type: 'media', mediaType: 'image', url: msg.content };
      default:
        return { type: 'text', text: JSON.stringify(msg.content) };
    }
  }

  private getMsgType(content: MessageContent): string {
    const mapping = {
      text: 'text',
      media: 'image',
      template: 'interactive',
      composite: 'post',
    };
    return mapping[content.type];
  }
}
```

## 8. 钉钉/微信 Adapter 注意事项

### 8.1 钉钉（DingTalk）差异

| 特性 | Telegram | 钉钉 |
|------|---------|------|
| 消息长度 | 4096 | 2048（文本）/ 5000（卡片） |
| 媒体上传 | Bot API | 需要先上传到媒体服务器 |
| 群消息 | 支持 | 需指定群 ID，非@也收到 |
| 消息撤回 | 不支持 | 24 小时内支持 |
| 加密 | TLS | 钉钉签名验证（CRAM-MD5） |

钉钉特殊处理：
- 媒体消息必须先调用 `/media/upload` 上传
- 群消息需要使用 `conversationId` 而非 `openId`
- 回调签名验证使用 `sign` 字段

### 8.2 微信（WeChat）差异

| 特性 | Telegram | 微信 |
|------|---------|------|
| 接入方式 | 官方 Bot API | Windows Hook / 网页协议 |
| 消息接收 | Webhook 推送 | 轮询或 Hook 回调 |
| 消息发送 | 直接调用 API | 受限于协议 |
| 群管理 | 完整 | 有限 |
| 商业账号 | 支持 | 仅企业微信 API |

微信特殊风险：
- 网页协议随时可能被微信封禁
- Windows Hook 需要管理员权限
- 建议优先使用企业微信 API

## 9. 依赖

- 依赖文档：[2026-05-19-hejian-ai-hub-design.md](./2026-05-19-hejian-ai-hub-design.md)
- 被依赖文档：
  - [2026-05-20-agent-protocol.md](./2026-05-20-agent-protocol.md)（Hub 层依赖 Adapter）
  - [2026-05-20-memory-rules.md](./2026-05-20-memory-rules.md)

---

*文档版本：v1.0.0 | 最后更新：2026-05-20*
