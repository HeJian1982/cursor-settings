# Cursor AI 协作规则模板库 v1.0

> 何健个人网站（e:\HJ\Web）专属优化版，基于 WindSurf v2.7 配置体系迁移。
> 适用于 Cursor IDE 的 AI 协作规则模板，支持多机共享、脚本自动化、配置版本化。

---

## 模板包含

- **23 个项目规则文件**（`.cursor/rules/`）
- **8 个 PowerShell 工具脚本**（`scripts/`）
- **2 个 GitHub Actions CI**（`.github/workflows/`）
- **自测试套件**（`tests/run-tests.ps1`）
- **本机配置快照**（`local-machine-configs/`）
- **项目专属定制**（适配 e:\HJ\Web 项目）

---

## 快速开始（新项目初始化）

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor-templates\scripts\init-project.ps1"
```

---

## 与 WindSurf 版本的区别

| 方面 | WindSurf 版 | Cursor 版 |
|------|------------|----------|
| 规则文件 | `.windsurf/rules/` | `.cursor/rules/` |
| 模板根目录 | `~\.windsurf-templates\` | `~\.cursor-templates\` |
| 规则前缀 | `00-` ~ `19-` | `00-` ~ `22-` |
| 核心差异 | 多 AI 协作协议 | 适配 Cursor 交互模式 |
| 保留特色 | 全部保留 | 中国资源优先、版权声明 |
