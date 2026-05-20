# Cursor AI 协作规则 — 安装指南

## v1.0.0

### 快速安装

1. 将 `e:\HJ\cursor` 目录复制到合适位置（推荐 `e:\HJ\cursor`）

2. 如果需要多机共享，建立 Junction：
   ```cmd
   cmd /c mklink /J "%USERPROFILE%\.cursor-templates" "e:\HJ\cursor"
   ```

3. 在桌面创建快捷方式（可选）：
   复制 `local-machine-configs\base\desktop\init-cursor-rules.bat` 到桌面

4. 初始化新项目：
   ```powershell
   powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.cursor-templates\scripts\init-project.ps1"
   ```

### 规则文件列表

| 文件 | 说明 |
|------|------|
| 00-core.mdc | 项目身份卡片、绝对禁止、每次必做 |
| 01-project-layout.mdc | 项目目录结构与归档规则 |
| 02-code-style.mdc | 代码风格（TypeScript + React 规范） |
| 03-git-workflow.mdc | 版本升级与发版规则 |
| 04-runtime-safety.mdc | 运行时稳定性（SSR守卫、ENV陷阱、API降级） |
| 06-dependency-management.mdc | 依赖管理（安装、锁文件、安全审计） |
| 07-testing-discipline.mdc | 测试纪律（测试金字塔、覆盖率、回归测试） |
| 08-security.mdc | 安全规则（密钥管理、输入校验、XSS/CSRF防护） |
| 09-performance.mdc | 性能规则（加载性能、Bundle、数据库、缓存） |
| 10-documentation.mdc | 文档规范（README/CHANGELOG/API文档） |
| 11-debugging.mdc | 调试方法论（根因分析、最小修复、回归测试） |
| 12-incident-response.mdc | 事故响应与回滚（P0-P3分级、PM2回滚方案） |
| 13-workflow.mdc | AI执行协议（4-Loop P/A/V/S） |
| 14-decision-trees.mdc | AI决策树（工具选择、Commit类型、IDE反馈信任度） |
| 15-pre-flight.mdc | 高风险动作Pre-Flight Check（Migration/.env/强推） |
| 16-chinese-resources-only.mdc | 中国资源优先规则（境内CDN、国内AI） |
| 18-environment.mdc | 服务器档案与环境对齐（阿里云ECS、部署验证） |
| 19-text-encoding.mdc | 文本编码规范（UTF-8+LF、PowerShell BOM陷阱） |
| 21-room-features.mdc | 房间类型规范（6种房间类型、V1.5功能模块） |
| 22-animations.mdc | 动画规范（Framer Motion三类动效模式） |
| 23-daily-summary.mdc | 每日会话摘要Skill（transcript解析、自动追加） |
