# cursor2api

> 仓库本地路径：`subprojects/repos-from-external/ai/cursor2api/`
> 来源：<https://github.com/7836246/cursor2api>
> 协议：MIT ｜ 主语言：TypeScript ｜ 1,828★

## 解决什么问题

Cursor IDE 的网页版（cursor.com/cn/docs）有**免费 AI 对话接口**。cursor2api 把它代理成标准 API：

```
Claude Code ──┐
              ├─→ cursor2api (代理+格式转换) ──→ Cursor 免费 API
Cursor IDE  ──┤
ChatBox    ──┘
```

支持的协议：
- `/v1/messages`（Anthropic 兼容，Claude Code 直连）
- `/v1/chat/completions`（OpenAI 兼容，ChatBox/LobeChat）
- `/v1/responses`（Cursor Agent 模式扁平工具格式）

## 核心特性（README 列出 30+，核心 5 个）

1. **全链路日志查看器** — Web UI 实时看请求/响应/工具调用
2. **降级日志诊断** — 标记 `degraded` 状态（工具假成功、截断、自述"写到一半"）
3. **API Token 鉴权** — 公网部署安全
4. **截断无缝续写** — 解决 `max_output_token` 截断（v2.7.8 新增 3 机制）
5. **Chrome TLS 指纹** — 模拟真实浏览器

## 启动方式

```bash
cd subprojects/repos-from-external/ai/cursor2api
npm install
cp config.yaml.example config.yaml
# 编辑 config.yaml，配置 port / auth_tokens / cursor_model
npm start
# 服务跑在 :3010
```

## 与本机 e:\HJ\Web 的结合点

- **本地开发零成本跑 Claude Code** — 接 cursor2api，绕开 Anthropic API 计费
- **风险**：README 自带告警「20260401 Cursor 文档页仅剩 gemini-3-flash 凉」—— Cursor 已收紧免费接口
- 不建议生产用，**仅本地玩具**或紧急时救急

## 风险

- Cursor 公开接口随时变更，仓库可能随时失效
- 多层拒绝拦截（50+ 正则）有 ToS 灰区，**不要对外发布**
- OCR 图片理解是本地 CPU 的，量大时慢
