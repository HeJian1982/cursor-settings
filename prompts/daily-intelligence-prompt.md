# 每日情报日报自动化提示词 v2.1

## 使用场景

将本文件配置为 Trae/Trae IDE 的自定义任务（Custom Task）或系统级定时任务（Windows Task Scheduler），每日北京时间 06:00 自动执行 `scripts/daily-intelligence.ps1`。

---

## 系统元信息

- **目标用户**：道真仡佬族苗族自治县用户，本地化视角
- **时间窗口**：过去 25 小时（昨日 05:00 ~ 今日 06:00 UTC+8）
- **总耗时上限**：8 分钟，超时立即停止并交付已完成部分
- **总检索上限**：30 次，每领域 ≤ 3 次

---

## 输出路径

```
d:/HJ/Web/daily-news/news-{YYYY-MM-DD}.md
```

首次运行时脚本会自动创建目录。

---

## 关注领域（共 11 + 1 个）

| # | 领域 | 关键词（主） | 关键词（备） |
|---|---|---|---|
| 1 | AI | 大模型、Agent、AIGC、国产AI、DeepSeek、通义、Kimi、智谱、豆包、文心、阶跃、MiniMax、AI政策、AI落地 |  |
| 2 | 医疗 | 医改、医保、新药获批、医疗器械、公立医院、互联网医院、罕见病、AI医疗 |  |
| 3 | 信息 | 5G、6G、芯片、半导体、网络安全、数据合规、个保法、信创 |  |
| 4 | 科技 | 新能源、新材料、航天、机器人、智能制造、量子、低空经济 |  |
| 5 | 编程 | 开源项目、Next.js、React、Vue、Node.js、Python、Rust、Go、技术大会、CVE、AI编程 | GitHub趋势、GitCode榜单 |
| 6 | 民生 | 物价、就业、教育、住房、社保、消费、个税 |  |
| 7 | 中国 | 国务院政策、经济数据、重大事件、外交、央行 |  |
| 8 | 贵州 | 贵州省政府、大数据产业、白酒、煤炭、新能源汽车、乡村振兴 |  |
| 9 | 遵义 | 遵义市政府、红色文旅、白酒、茅台、习酒、董酒、新蒲新区、辣椒 |  |
| 10 | 道真 | 道真仡佬族苗族自治县、仡佬文化、生态农业、铝土矿、中药材、烟草 | 仡佬族、黔北农业 |
| 11 | 中医 | 国家中医药管理局、中医院、中药材、中医药政策、名医名方、中医药出海 | 苗医苗药、民族医药 |
| 12 | **GitHub趋势** | GitHub trending、GitHub Trending、GitHub热榜、GitHub开源项目 |  |
| 13 | **GitCode榜单** | GitCode trending、GitCode热门项目、开源中国、Gitee趋势 |  |

> **注意**：领域 12 和 13 的信息源白名单为 GitHub Trending 页面（github.com/trending）和 GitCode Trending 页面（gitcode.com），不受"禁用境外源"规则限制——这是情报聚合场景，不是新闻报道场景。检索时请使用 `site:github.com/trending` 或直接抓取 GitCode trending 页面。

---

## 信息源白名单

### 官媒（优先）
- 新华社（xinhuanet.com）
- 人民日报（people.com.cn）
- 央视新闻（cctv.com）
- 求是网、光明日报、经济日报
- 中国政府网（gov.cn）

### 行业媒体
- 36氪（36kr.com）、虎嗅（huxiu.com）、少数派（sspai.com）
- 掘金（juejin.cn）、CSDN、InfoQ 中文站
- 机器之心（jiqizhixin.com）、量子位（qbitai.com）
- 钛媒体（tmtpost.com）、雷锋网（leiphone.com）、第一财经

### 地方媒体
- 贵州日报、当代先锋网（ddcpc.cn）、贵阳网、天眼新闻
- 遵义日报、遵义网（zynews.cn）
- 道真县人民政府网（daozhen.gov.cn）

### 专业媒体
- 健康报、中国中医药报、人民邮电报
- 中国科学报、科技日报、中国证券报

### 次优（兜底）
- 澎湃新闻（thepaper.cn）、界面新闻（jiemian.com）
- 财新公开部分、知乎热榜（zhihu.com/billboard）

---

## 硬红线（违反即整篇重写）

1. **禁用境外新闻源**：NYT / BBC / Reuters / Bloomberg / WSJ / Hacker News / Reddit / Twitter / Medium / TechCrunch / The Verge 不得作为主要来源
2. **禁止编造**：标题、URL、发布时间必须真实可访问；查不到写「今日无更新」
3. **超时不收录**：发布时间超 25 小时窗口的一律剔除
4. **不得跳过领域**：13 个领域全部出现，无内容写「今日无更新」

---

## 检索策略与预算

| 项 | 上限 |
|---|---|
| 每领域检索次数 | ≤ 3 |
| 单任务总检索 | ≤ 30 次 |
| 单任务总用时 | ≤ 7 分钟 |
| 每领域候选 | 3-5 条 |
| 全篇最终入选 | ≤ 40 条 |

### 容错规则

- **单领域失败**：标注「⚠️ 本领域检索失败：{原因}」，继续下一个
- **稀缺领域兜底关键词**：
  - 道真 → 仡佬族 → 黔北 → 遵义+山区+农业
  - 中医 → 中药材 → 苗医苗药 → 民族医药
- **网络抖动**：单次检索失败立即重试 1 次，仍失败换关键词
- **时间不够**：剩余 < 90 秒时停止检索，用已有素材完成
- **去重**：标题相似度 > 70% 保留最权威源

---

## 输出格式

### 每日日报结构（Markdown）

```markdown
# 📰 {YYYY-MM-DD} 情报日报
🕕 06:00 · 窗口 {昨日 05:00} ~ {今日 06:00}

> **🎯 今日头条**：{最重要 1 条，≤ 40 字}
> **📈 趋势**：{跨领域观察，≤ 30 字}

---

## 🤖 AI
**1. {标题 ≤ 25 字}**
{摘要 ≤ 60 字} · [{媒体}]({URL}) · {HH:mm}

**2. ...**

---

## 🏥 医疗

...

## 📡 信息

...

## 🔬 科技

...

## 💻 编程

...

## 🐙 GitHub 趋势
**今日 {Weekday} GitHub 热榜速览**

**🥇 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

**🥈 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

**🥉 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

**值得关注的国产项目**：
- **{项目}** ⭐ {stars} — {描述} · [{链接}]({URL})
- ...

> 数据来源：[GitHub Trending](https://github.com/trending)

---

## 🐘 GitCode / 开源中国热榜
**今日 {Weekday} GitCode 热门项目**

**🥇 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

**🥈 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

**🥉 {项目名称}** ⭐ {stars} — {一句话描述} · [{链接}]({URL})

> 数据来源：[GitCode Trending](https://gitcode.com/explore/trending)

---

## 👨‍👩‍👧 民生

...

## 🇨🇳 中国

...

## ⛰️ 贵州

...

## 🏛️ 遵义

...

## 🌾 道真

...

## 🌿 中医

...

---

## 🏆 Top 3 必读
1. **{标题}** — {1 句理由}
2. **{标题}** — {1 句理由}
3. **{标题}** — {1 句理由}

---
<sub>📊 检索 {n} 次 · 候选 {n} 条 · 入选 {n} 条 · 用时 {m}m{s}s</sub>
```

---

## 执行流程

```
Step 1 · 准备（30s）
  → 确认北京时间，计算 25h 窗口
  → 加载本提示词文件
  → 检查 d:/HJ/Web/daily-news 目录，不存在则 mkdir

Step 2 · 检索（5min）
  → 并行/串行执行 13 个领域搜索
  → 优先 WebSearch，获取标题+摘要+URL+时间
  → 珍稀领域（道真/遵义）用备选关键词补充
  → GitHub/GitCode：直接抓取 trending 页面

Step 3 · 筛选去重（30s）
  → 剔除超时（>25h）、境外新闻源、重复、低质
  → 每领域保留 1-3 条最权威

Step 4 · 写作（90s）
  → 按上述格式生成 Markdown
  → 置顶今日头条 + 趋势
  → 写 Top 3 必读

Step 5 · 落盘（10s）
  → 保存至 d:/HJ/Web/daily-news/news-{YYYY-MM-DD}.md
  → UTF-8 BOM 编码

Step 6 · 推送（30s）
  → 优先：飞书机器人 Webhook
  → 备选：lark-cli im +send --to-self --file
  → 备选：lark docs +create 归档

Step 7 · 收尾
  → 打印 Top 3 标题 + 文件路径
  → 记录执行统计到控制台
```

---

## 失败兜底

| 故障 | 处置 |
|---|---|
| 推送失败 | 追加错误到 `d:/HJ/Web/daily-news/_errors.log`，文件已落盘不算失败 |
| 全部检索失败 | 发「⚠️ 今日检索失败：{原因}」到飞书 |
| 超时 | 立即停止，用已有素材完成，标注「⏱️ 超时截断」|
| 单领域失败 | 标注「⚠️ 本领域检索失败」，继续下一领域 |

---

## GitHub / GitCode 趋势专题说明

### 为什么收录 GitHub/GitCode？

- 了解全球及中国开源生态最新热点
- 发现新兴开发工具和框架
- 跟踪国产开源项目发展

### 信息来源（白名单）

- **GitHub Trending**：`https://github.com/trending` — 展示今日/本周热门仓库
- **GitCode Trending**：`https://gitcode.com/explore/trending` — 中国开源趋势

### 收录标准

1. 每榜展示前 3 名 + 2-3 个值得关注的国产/特色项目
2. 记录：项目名、星标数、一句话描述、GitHub/GitCode 链接
3. 突出 AI/前端/工具类项目
4. 优先收录有中文 README 的项目

### 特别说明

- GitHub/GitCode 属于**开发者情报聚合**，不是新闻报道
- 不受"禁用境外源"限制——这是开源生态信息获取场景
- 时间窗口：抓取**当日** trending 数据

---

## 输出语言规范

- 全文中文
- Emoji 仅用于章节标题和装饰
- 标题客观中性，不加主观形容词
- 数字和百分比用阿拉伯数字
- 时间统一用北京时间（UTC+8）

---

## 推送指令参考

### 方案 A：飞书机器人 Webhook（推荐）

```powershell
$webhook = "YOUR_WEBHOOK_URL"
$top3 = Get-Content "d:/HJ/Web/daily-news/news-$(Get-Date -Format yyyy-MM-dd).md" -Encoding UTF8 -Raw
$body = @{
    msg_type = "interactive"
    card = @{
        header = @{
            title = @{ tag="plain_text"; content="📰 $(Get-Date -Format yyyy-MM-dd) 每日情报" }
            template = "blue"
        }
        elements = @(
            @{ tag="markdown"; content = $top3 }
        )
    }
} | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType "application/json; charset=utf-8"
```

### 方案 B：lark-cli 私聊

```bash
lark im +send --to-self --file "d:/HJ/Web/daily-news/news-$(date +%Y-%m-%d).md" --as-markdown
```

### 方案 C：飞书云文档归档

```bash
lark docs +create --title "情报日报 $(date +%Y-%m-%d)" --from-markdown "d:/HJ/Web/daily-news/news-$(date +%Y-%m-%d).md" --api-version v2
```
