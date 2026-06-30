# Cursor 当前模型诊断报告

**日期**：2026-07-01 02:30 BJT
**诊断人**：HJ Agent（多轮排查）

---

## 🎯 结论（确凿）

**Cursor 当前正在使用的模型：`gpt-5.5-extra-high`**

证据强度：⭐⭐⭐⭐⭐（直接读取 Cursor 本地 SQLite 数据库 `ai_code_hashes.model` 列）

---

## 一、证据来源

| 路径 | 类型 | 大小 | 最后修改 |
|---|---|---|---|
| `C:\Users\HJ2\.cursor\ai-tracking\ai-code-tracking.db` | SQLite 3 | 80 MB | 2026-07-01 02:29:33 |

**关键表 schema**：

```sql
ai_code_hashes(
  hash TEXT, source TEXT, fileExtension TEXT, fileName TEXT,
  requestId TEXT, conversationId TEXT, timestamp INTEGER,
  createdAt INTEGER, model TEXT          -- ← 关键字段
)
```

---

## 二、最新 20 条记录（按 `createdAt` 倒序）

```
[2026-07-01 02:29:33] [ai_code_hashes] model=gpt-5.5-extra-high
    fileName = /C:/Users/HJ2/read_cursor_ai_db_v2.py
    requestId = 0e37cb45-d5ad-45f5-8db7-dcc87c2b00fa
    conversationId = 399f5be3-8e6d-47a6-9ddb-08bbfef8818f

[2026-07-01 02:29:33] [ai_code_hashes] model=gpt-5.5-extra-high
    fileName = /C:/Users/HJ2/read_cursor_ai_db.py
    conversationId = 399f5be3-8e6d-47a6-9ddb-08bbfef8818f
    （同 requestId、同 conversationId，全 gpt-5.5-extra-high）

[2026-06-28 21:17:52] [ai_deleted_files] model=claude-fable-5-thinking-max
[2026-06-28 21:17:51] [ai_deleted_files] model=claude-fable-5-thinking-max
[2026-06-28 21:05:02] [ai_deleted_files] model=claude-fable-5-thinking-max
```

---

## 三、模型使用频率（历史）

| 模型 | 总写入次数 | 最近一次 |
|---|---|---|
| `claude-opus-4-8-thinking-max` | **171 458** | 2026-06-28 08:22:40 |
| `claude-opus-4-8-thinking-xhigh` | 37 184 | 2026-06-10 12:57:13 |
| `claude-fable-5-thinking-max` | 13 512 | 2026-06-30 13:33:30 |
| `gpt-5.5-extra-high` | **11 345** | 2026-07-01 02:29:33 ← 当前 |
| `claude-opus-4-7-thinking-max` | 1 | 2026-06-11 06:24:46 |

---

## 四、为什么之前几次方案都失败

### 方案 1：直接调用 580ai `/v1/models` 端点 → ❌ 失败

| 检查 | 结果 |
|---|---|
| `nslookup cc.580ai.net 8.8.8.8` | **Non-existent domain** |
| `https://dns.google/resolve?name=cc.580ai.net` | 公网 DNS 不存在 |
| `https://api.580ai.com/v1/models` | 是 new-api 首页 HTML，非模型端点 |

**根因**：`cc.580ai.net` 在公网 DNS 不存在（new-api 私有部署）。但你的 Cursor 能调通 → 它在你所在网络能解析（私有 hosts / 内网 DNS / 公司网关）。

→ **我执行 PowerShell / curl / mitmproxy 调不到，是因为网络可达性不一致，不是我方法错。**

### 方案 2：mitmproxy 抓包 → ❌ 失败

| 检查 | 结果 |
|---|---|
| mitmdump 进程 | ✅ 运行中（PID 35068，监听 0.0.0.0:8080）|
| `C:\Windows\System32\drivers\etc\hosts` | 无 `cc.580ai.net` 覆盖 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` | `ProxyEnable=0`、`ProxyServer=127.0.0.1:7897` |
| `HTTPS_PROXY` 环境变量 | `http://127.0.0.1:8080` 已设，但 ProxyEnable=0 不生效 |
| Cursor.exe 启动参数 | 无 `--proxy-server` 参数 |
| 抓包脚本 (`cursor_model_capture_v2.py`) | ✅ 已加 `cc.580ai.net` 白名单，但从未收到请求 |

**根因**：Cursor 通过 **`ANTHROPIC_BASE_URL=https://cc.580ai.net` + `ANTHROPIC_AUTH_TOKEN=sk-...`** 这两个**用户级环境变量**直连 cc.580ai.net，**完全绕开系统代理和 mitmproxy**。

→ **要让 mitmproxy 抓到 Cursor 流量，必须让 Cursor 重启时带 `--proxy-server=...` 参数**（会断当前会话）。

---

## 五、最终方案（成功）

**不抓包，直接读 Cursor 本地数据**。

Cursor 把每次 AI 写入文件的 model 字段持久化到 SQLite 数据库（`ai_code_hashes.model`），
**这个值就是请求时实际使用的模型 ID**，可信度 100%。

**脚本**：`C:\Users\HJ2\read_cursor_ai_db_v2.py`

---

## 六、对比"settings.json 注释"的误导

`%APPDATA%\Cursor\User\settings.json` 第 3 行：

```js
// 适配：Max Mode + Claude Opus 4 7 Thinking Max + 第三方代理 (claudecode.top)
```

**这是 2026-05-19 的过时注释**，与实际不符：
- ✅ 第三方代理 (claudecode.top / cc.580ai.net) 仍生效
- ❌ Claude Opus 4.7 Thinking Max **不是当前模型**（最后一次使用 2026-06-11）
- ✅ Max Mode 仍生效

**建议**：更新该注释为 "Max Mode + gpt-5.5-extra-high + 第三方代理 (cc.580ai.net)"。

---

## 七、附加收获

1. mitmproxy 脚本 `cursor_model_capture_v2.py` 已加上 `cc.580ai.net, 580ai.net, api.580ai.com, 580ai.com` 白名单 —— **未来若重启 Cursor 并启用代理就能立即抓包**。
2. 数据库读取脚本 `read_cursor_ai_db_v2.py` 可重复使用 —— **快速查询当前模型的标准方法**。
3. 真正能识别 Cursor 当前模型的最权威数据源是 `ai-tracking.db`，不是 settings.json，不是网络抓包。