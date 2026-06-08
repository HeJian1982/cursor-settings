# Lessons Index

> 从错误、重复和意外中学到的可执行洞察。
> 每条教训必须：具体 / 可直接执行 / 非显而易见 / 新颖。

## 格式规范

```markdown
## YYYY-MM-DD · <教训标题>

### 来源
会话 ID: `<uuid>`

### 问题
<客观描述发生了什么>

### 教训
<可执行的改进，下次遇到同场景直接应用>

### 验证
<本教训是否被后续工作验证>
```

---

## 教训列表

| 日期 | 标题 | 状态 |
|------|------|------|
| 2026-05-20 | 子 Agent Premature Close 处理 | 待验证 |
| 2026-05-20 | PowerShell BOM 编码陷阱 | 已验证 |
| 2026-05-20 | Git 远端必须先配置 | 待验证 |
| 2026-05-20 | daily-summary 必须 Commit 后立即执行 | 待验证 |
| 2026-06-07 | Git Push 前先诊断网络端口 | 已验证 |
| 2026-06-08 | guard-skills 三层门控纳入 Cursor 规则 | 待验证 |
| 2026-06-08 | Skill 定期优化：每 30 天健康检查 | 待验证 |
| 2026-06-08 | GitHub 页面 SPA 抓取改用 API | 待验证 |

---

## 教训详情

### 2026-05-20 · 子 Agent Premature Close 处理

### 来源
会话 ID: `8cdf47b5`

### 问题
子 Agent 执行复杂任务时多次出现 "Premature close"，被提前终止。涉及 P0 核心实现补漏、飞书适配器等需要多步骤的任务。

### 教训
1. **复杂子任务分块**：超过 10 步的任务应拆成 5 步以内的子 Agent，减小单次执行长度
2. **中间状态写入**：子 Agent 开始时先写 checkpoint，完成关键步骤后写入 memory/lessons/
3. **立即 resume**：收到 Premature close 后立即 resume，不等待

### 验证
待验证

---

### 2026-05-20 · PowerShell BOM 编码陷阱

### 来源
会话 ID: `ef51b429`

### 问题
CI 强制要求 .ps1 脚本有 UTF-8 BOM（`[EF BB BF]`），但 PowerShell 5.1 默认写入无 BOM UTF-8。导致 CI 反复失败。

### 教训
**所有 .ps1 脚本必须带 BOM。** 写入方式：
```powershell
$utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
$content = [System.IO.File]::ReadAllBytes($scriptPath)
$newContent = $utf8Bom + $content
[System.IO.File]::WriteAllBytes($scriptPath, $newContent)
```
不得使用 `>` / `Out-File` 默认编码写 .ps1。

### 验证
已验证：所有脚本添加 BOM 后 CI 通过

---

### 2026-05-20 · Git 远端必须先配置

### 来源
会话 ID: `8cdf47b5`, `ef51b429`

### 问题
连续两次 commit 成功但 push 失败，原因是本地仓库没有配置 git remote。

### 教训
**Commit 前先检查远端配置：**
```powershell
git remote -v
```
如果输出为空，说明没有远端，此时 commit 成功但 push 会失败。在 push 失败处理（`13-workflow.mdc` §三）中补充此检查。

### 验证
待验证：建议在 `13-workflow.mdc` §四检查清单中增加此条

---

### 2026-06-07 · Git Push 前先诊断网络端口

### 来源
会话 ID: `486854` (push task), `479155` (port 22 test), `866604` (port 443 test)

### 问题
Git push via HTTPS 失败，错误：`fatal: unable to access 'https://github.com/...': Recv failure: Connection was reset`。端口检测发现 GitHub 443 端口不通（TCP 连接失败），但 22 端口正常。

### 教训
1. **HTTPS push 失败时，先并行测两个端口**：
   ```powershell
   Test-NetConnection github.com -Port 22 -InformationLevel Quiet
   Test-NetConnection github.com -Port 443 -InformationLevel Quiet
   ```
2. **GitHub 443 不通是常见临时性 GFW 抖动**，不等同于 SSH 也不通——两者路径独立
3. **本项目远端已配置 SSH 地址**（`git@github.com:...`），push 走 SSH 22 端口，443 不通不影响
4. **以后 push 失败不走 HTTPS fallback**：确认远端是 SSH 格式即可，22 通就能 push

### 验证
Port 22 检测通过，SSH push 预期可用

---

### 2026-05-20 · daily-summary 必须 Commit 后立即执行

### 来源
会话 ID: `8cdf47b5`

### 问题
`23-daily-summary.mdc` skill 描述了完整的自省流程，但在实际会话中没有严格执行。导致今日日志不完整、有乱码、缺少洞察。

### 教训
**自省是 Commit + Push 的一部分，不额外执行。**
```
Commit + Push 后 → 立即执行：
1. tail -5 <latest-transcript>.jsonl
2. 提取用户请求 + 关键动作 + 结果
3. 追加到 cursor-transcripts/YYYY-MM-DD.md
4. 路由洞察到 memory/lessons/、memory/decisions/
```
不在会话结束时等待用户提示，Commit 即触发。

### 验证
待验证：以此教训为基准，后续所有会话按此执行

---

### 2026-06-08 · guard-skills 三层门控纳入 Cursor 规则

**来源**
会话 ID: `5790ec6f-aeff-46f8-a98c-b84cc4cfa94d`

**问题**
热榜巡检发现高价值项目 `amElnagdy/guard-skills`（AI 代码质量门控），但未转化为工作区规则。类似有价值的外部知识每次都"知道"但"不用"。

**教训**
1. **发现高价值项目 → 立即评估纳入路径**，不是仅存报告
2. **guard-skills 拆分为 3 条规则**：`25-ai-code-guard`（23条戒律）、`26-test-guard`（测试质量门控）、`27-docs-guard`（文档准确性门控）
3. **与现有规则互补**：02-code-style 是 TypeScript 规范层，25-ai-code-guard 是 AI 生成代码判断层，两层不冲突

**验证**
已生效，commit `b36f001`

---

### 2026-06-08 · Skill 定期优化：每 30 天健康检查

**来源**
会话 ID: `5790ec6f-aeff-46f8-a98c-b84cc4cfa94d`

**问题**
Skill 库存有 93+ skills，存在多种问题：6个重叠设计 skill、功能重复、41MB node_modules 垃圾、babysit/canvas frontmatter 损坏、baselines.json 不同步。

**教训**
1. **定期优化比一次性清理更可持续**——用户决定每周跑 skill-health-check，周日 09:00
2. **skill-health-check.ps1 自动检查 6 项**：断链、缺失 SKILL.md、空/Tiny skill、磁盘占用、大 skill 排名
3. **重叠 skill 处理原则**：保留最具通用性的（taste-skill），删除专项重复（gpt-taste/minimalist-ui 等）
4. **node_modules 必须排除**在 skill 之外，baoyu-url-to-markdown 清理后从 41.5MB 降至 280KB

**验证**
已执行，commit `b22c613`

---

### 2026-06-08 · GitHub 页面 SPA 抓取改用 API

**来源**
会话 ID: `5790ec6f-aeff-46f8-a98c-b84cc4cfa94d`

**问题**
`trending-inspect.ps1` 抓取 GitHub Trending 页面超时（15s）。直接请求 `https://github.com/trending` 返回空内容（JS 渲染）。

**教训**
1. **SPA 页面不适用 WebRequest**，改用 GitHub 搜索 API
2. **API 不超时（8s 响应）**，页面渲染超时
3. **GitCode 无公开 API**（SPA，AtomGit 端点 404），降级跳过
4. **PowerShell 5.1 BOM 问题**：正则 `[` 被 PS 解析器当作数组操作符。解决方案：写入时用 `[System.Text.UTF8Encoding]$true` 创建 BOM 对象

**验证**
已生效，commit `c1905d3`

