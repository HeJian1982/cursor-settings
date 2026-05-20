# Cursor AI 协作全局规则 — 何健个人网站

> 基于 WindSurf v2.7 配置体系迁移，适配 Cursor IDE
> 适用于所有 Cursor 会话

---

## 每次会话开始

1. 检查当前工作区根目录是否存在 `.cursor/rules/` 目录
2. 如果不存在，在回复用户之前先提醒："检测到此项目还没有 Cursor AI 协作规则"
3. 如果已存在，正常加载规则

---

## 通用铁律

### 绝对禁止
1. 不硬编码密钥/密码/token → 一律环境变量
2. 不擅自修改 `.env.local` → 改动前必须与用户确认
3. 不杜撰 API/函数/字段 → 必须基于代码或官方文档查证
4. 不修改与任务无关的代码 → 保持变更最小化
5. 不删减或弱化已有测试 → 除非用户显式授权
6. 不 `git push --force` → 永远不（用户显式授权+二次确认才可）
7. 不 `git reset --hard` → 同上
8. 不 commit `.env*` / `node_modules` / `_archive/**` / 大于 10MB 的二进制

### 每条指令完成后必做
1. `npm run typecheck` → 0 错
2. `npm run lint` → 0 警告
3. `git add -A; git commit`（本地永远安全）
4. `git push origin main`（尽力而为，失败不回滚 commit）
5. push 失败 → 告知用户"已本地提交，push 失败原因"

### 版本管理
- patch：bug/文案/配置 → 直接跑 `npm run release:patch`
- minor：新功能 → 告知用户建议，不反对即执行
- major：破坏性变更 → **必须用户显式确认**
- 发版前必须 typecheck + lint + build 全过
- CHANGELOG [Unreleased] 为空时不得发版

### Commit message 格式
- `<type>(<scope>): <subject>`
- type: feat / fix / docs / style / refactor / perf / test / build / ci / chore / revert

### 遇到不确定
- 先用搜索找证据，不凭记忆
- 用户提供的路径/常量原样使用，不要"纠正"

### AI 自己发现的问题
- 不要静默修掉 → 先告知用户并询问

### 项目身份
- 项目名：何健个人网站
- 当前版本：v2.20
- 工作区：e:\HJ\Web
- 框架：Next.js 14 + React 18 + TypeScript 5 + Tailwind 3
- 运行时：Node >= 20
- 主分支：main

### 开发语言
所有交流、注释、文档均使用**中文**
