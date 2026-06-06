# 每日 AI 工具情报专项提示词 v1.0

## 使用场景

将本文件配置为 AI 对话框的自定义提示词，每日自动执行：
- 检索 GitHub / GitCode 的 AI / 编程工具趋势
- 分析 Cursor / Claude / GPT 相关的热门 Skills 和工具
- 结合项目实践生成洞察报告
- 落盘至 `d:/HJ/Web/daily-news/skill-intelligence-{YYYY-MM-DD}.md`
- 推送飞书

---

## 系统元信息

- **目标用户**：何健（Cursor IDE 重度用户）
- **时间窗口**：过去 24 小时
- **总耗时上限**：5 分钟
- **总检索上限**：20 次

---

## 输出路径

```
d:/HJ/Web/daily-news/skill-intelligence-{YYYY-MM-DD}.md
```

---

## 核心检索任务

### 一、AI / LLM 相关工具（GitHub Trending）

**检索关键词**：
```
site:github.com/trending AI OR "cursor" OR "claude" OR "openai" OR "llm" OR "agent"
```

**筛选条件**：
- ⭐ ≥ 500 的项目优先
- 聚焦：Cursor 插件、Claude 工具、GPT 应用、AI Agent 框架、编程助手
- 语言不限，优先英文（有中文 README 标注）
- 排除：纯研究论文、数据集、无可运行代码的仓库

**记录字段**：
| 字段 | 说明 |
|---|---|
| 项目名 | full_name |
| 描述 | 一句话描述 |
| 星标数 | stars_today |
| 语言 | primary language |
| GitHub 链接 | github.com/xxx |
| 特色 | 中文 README / 支持中文 / Cursor 集成 等 |

---

### 二、Cursor IDE 相关（GitHub + Google）

**检索关键词**：
```
site:github.com cursor IDE plugin OR extension OR "cursor rules"
site:github.com "cursor" "agent" "AI coding"
```

**重点关注**：
- `.cursor/rules/` 项目
- Cursor MCP 服务器
- Cursor 与其他工具的集成方案
- Cursor Rules 最佳实践仓库

---

### 三、Claude / GPT 编程工具

**检索关键词**：
```
site:github.com claude "cursor" OR "IDE" OR "agent"
site:github.com openai GPT "coding" OR "assistant" OR "agent"
```

**重点关注**：
- Claude Code 相关工具
- GPT 模型编程辅助工具
- AI Agent 框架的新发布

---

### 四、GitCode 中国开源 AI 工具

**检索源**：
```
https://gitcode.com/explore/trending
```

**筛选条件**：
- 聚焦国产 AI 工具、大模型应用、开源 AI 项目
- 标注是否为国产项目

---

### 五、项目实践知识整合（结合你的知识库）

**整合维度**：
1. 当前使用的 Skills 与规则体系（来自 `e:/HJ/cursor/.cursor/rules/`）
2. 已安装的 Cursor Skills（来自 `e:/HJ/cursor/skills/`）
3. 近期使用效果最好的工作流（来自 `e:/HJ/cursor/logs/`）

**判断标准**：
- 哪些现有 Skills 与今日趋势重叠 → 建议优先使用
- 哪些新工具值得测试 → 标记为「值得测试」
- 哪些旧 Skills 已过时 → 标记为「可归档」

---

## 信息源白名单

- GitHub Trending：`https://github.com/trending`
- GitHub Search：`https://github.com/search`
- GitCode Trending：`https://gitcode.com/explore/trending`
- Google（补充）：Cursor 官方博客、Anthropic 博客、OpenAI 博客

---

## 硬红线

1. 不得收录无星标或星标 < 100 的 GitHub 项目（除非有重大创新）
2. 不得收录纯商业 SaaS（必须是开源或可本地部署的工具）
3. 不得收录已超过 30 天未更新的项目（除非是里程碑级项目）
4. 所有链接必须真实可访问

---

## 输出格式（Markdown）

```markdown
# 🛠️ AI 工具情报 {YYYY-MM-DD}
🕕 {HH:00} · 过去 24h 检索

> **今日头条工具**：{最重要 1 个新工具，≤ 30 字}
> **趋势洞察**：{跨领域观察，≤ 30 字}

---

## 🤖 AI / LLM 工具趋势（GitHub）

### 🥇 {项目名} ⭐ {stars}
{description}
- 语言: {lang} | 今日 +{stars_today} ⭐
- [{链接}]({url})
- {特色标签}

### 🥈 ...（共 3-5 个）

---

## 🎯 Cursor IDE 生态

### {项目名} ⭐ {stars}
{description}
- [{链接}]({url})
- {对我的价值评估}

---

## 🧠 Claude / GPT 编程工具

### {项目名} ⭐ {stars}
{description}
- [{链接}]({url})

---

## 🐘 GitCode 国产 AI 工具

### 🥇 {项目名} ⭐ {stars}
{description}
- [{链接}]({url})
- 国产: 是/否

---

## 📊 现有 Skills 匹配分析

### 🔥 已有 Skills 今日可用
- {skill 名} — {理由}（来自今日趋势）

### 💡 值得测试的新工具
1. **{工具}** — {测试理由}
2. ...

### ⚠️ 可归档的旧 Skills
- {skill 名} — {原因}

---

## 💡 本周 Cursor 配置建议

{基于今日情报，给出 1-3 条可操作的配置建议}

---

## 🏆 Top 3 推荐

1. **{工具名}** — {推荐理由}
2. **{工具名}** — {推荐理由}
3. **{工具名}** — {推荐理由}

---
<sub>🛠️ 检索 {n} 次 · 入选 {n} 个项目 · 用时 {m}m{s}s</sub>
```

---

## 执行流程

```
Step 1 · 准备（10s）
  → 确认日期，计算 24h 窗口
  → 加载本提示词
  → 检查 d:/HJ/Web/daily-news 目录

Step 2 · GitHub Trending AI 工具（60s）
  → 检索 site:github.com/trending AI/llm/agent
  → 筛选 ⭐ ≥ 500，获取前 5 名

Step 3 · Cursor 生态（40s）
  → 检索 cursor IDE 相关项目
  → 检索 cursor rules 最佳实践

Step 4 · Claude/GPT 工具（40s）
  → 检索 claude coding 相关
  → 检索 GPT agent 相关

Step 5 · GitCode 国产（30s）
  → 抓取 gitcode.com/explore/trending
  → 筛选 AI 相关

Step 6 · 项目知识整合（30s）
  → 读取现有 skills 列表
  → 匹配今日趋势
  → 生成洞察

Step 7 · 写作（60s）
  → 按格式生成报告
  → 写出配置建议

Step 8 · 落盘（10s）
  → 保存至 d:/HJ/Web/daily-news/skill-intelligence-{YYYY-MM-DD}.md
  → UTF-8 BOM 编码

Step 9 · 推送飞书（20s）
  → 飞书机器人 Webhook 推送摘要
  → 飞书云文档归档
```

---

## 推送参考

### 飞书卡片推送

```json
{
  "msg_type": "interactive",
  "card": {
    "header": {
      "title": { "tag": "plain_text", "content": "🛠️ AI工具情报 {YYYY-MM-DD}" },
      "template": "purple"
    },
    "elements": [
      { "tag": "markdown", "content": "{报告摘要}" }
    ]
  }
}
```

---

## 与每日情报日报的协同

- **每日情报日报**（daily-intelligence.ps1）：覆盖 13 个领域，含 GitHub 趋势（编程领域）
- **每日 AI 工具情报**（skill-intelligence.ps1）：专注 AI/编程工具深度分析，含 Skills 匹配
- 两者互补：情报日报提供广度，工具情报提供深度

- **每周 Cursor 配置分析**（cursor-config-updater.ps1）：每周汇总一周工具情报，更新 baselines.json 和 rules
