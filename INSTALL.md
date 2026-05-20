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

### 自动化脚本

|| 脚本 | 说明 |
||------|------|
| `scripts/init-project.ps1` | 交互式初始化新项目的 Cursor AI 协作规则 |
| `scripts/sync-global-rule.ps1` | 双向同步 `global-rule-paste.md` <-> Cursor `cursor.rules` |
| `scripts/sync-local-configs.ps1` | 双向同步本机 Cursor 设置 <-> `local-machine-configs/` |
| `scripts/append-daily-log.ps1` | 追加当日会话记录到 `cursor-transcripts/YYYY-MM-DD.md` |
| `scripts/generate-baselines.ps1` | 生成 SHA256 基线：`baselines.json`（6脚本 + 96 Skills + Cursor settings） |
| `scripts/daily-optimize.ps1` | 每日优化编排器：测试+基线+同步+提交 |
| `scripts/setup-daily-task.ps1` | 注册/查看/删除 Windows 定时任务 |

### 每日定时优化

```powershell
# 注册每日 07:30 自动优化（推荐 SYSTEM 权限）
.\scripts\setup-daily-task.ps1 -Action Register

# 查看当前定时任务状态
.\scripts\setup-daily-task.ps1 -Action Show

# 移除定时任务
.\scripts\setup-daily-task.ps1 -Action Unregister

# 手动运行（测试用）
.\scripts\daily-optimize.ps1
.\scripts\daily-optimize.ps1 -DryRun   # 预览，不写文件不提交
.\scripts\daily-optimize.ps1 -SkipCommit  # 跳过 git commit
```

**定时任务内容**：`daily-optimize.ps1` 每次运行：
1. Pull 最新本机配置到仓库快照
2. 运行完整测试套件（84 项安全检查）
3. 重新生成 SHA256 基线
4. 再次运行测试套件验证基线
5. Git commit（如有变更）→ 自动 push（如配置了 remote）

**运行日志**：`logs/daily-optimize-YYYY-MM-DD.log`

### 安全基线体系

- **T9**: PowerShell 脚本 SHA256 基线验证
- **T13**: Skills `SKILL.md` SHA256 基线验证（96 个 Skills）
- **T14**: 可疑脚本注入扫描（检测 `scripts/` 外的新增 `.ps1`/`.sh`/`.bat`）
- **T15**: Transcript 文件完整性快照（大小合理性 100B-50MB）
- **P5**: 每日日志追加时记录 transcript SHA256 签名
