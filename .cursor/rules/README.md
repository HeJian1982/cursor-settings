# Cursor AI 协作规则索引

## 核心规则（alwaysApply，每次会话必加载）

|| 文件 | 内容 |
||------|------|
|| 00-core.mdc | 项目身份卡片、绝对禁止、每次必做 |
|| 13-workflow.mdc | AI执行协议 — 4-Loop（含黑名单/Push失败处理） |
|| 14-decision-trees.mdc | AI决策树 — 工具/编辑/命令/commit类型 |

## 按需触发规则

|| 文件 | 触发条件 | 内容 |
||------|----------|------|
|| 01-project-layout.mdc | 目录相关 | 目录结构白名单、归档规则 |
|| 02-code-style.mdc | 编辑代码 | TS/React代码风格、导入排序、版权声明 |
|| 03-git-workflow.mdc | commit/push | 版本升级矩阵、SemVer发版 |
|| 04-runtime-safety.mdc | 编辑代码 | SSR守卫、ENV陷阱、API降级 |
|| 06-dependency-management.mdc | package.json | 安装原则、安全审计 |
|| 07-testing-discipline.mdc | 测试文件 | 测试金字塔、覆盖率、回归测试 |
|| 08-security.mdc | 代码/API | 密钥管理、XSS/SQL注入 |
|| 09-performance.mdc | AI判断需要 | Core Web Vitals、Bundle、DB |
|| 10-documentation.mdc | 文档 | README/CHANGELOG/API文档、版权头模板 |
|| 11-debugging.mdc | AI判断需要 | 根因分析、日志策略 |
|| 12-incident-response.mdc | AI判断需要 | 事故分级、回滚、复盘 |
|| 15-pre-flight.mdc | 高风险动作前 | Migration/.env/强推检查 |
|| 16-chinese-resources-only.mdc | 提及资源 | 中国资源优先 |
|| 18-environment.mdc | 部署/运维 | 环境对齐、服务器档案、回滚流程 |
|| 19-text-encoding.mdc | .env*/PS脚本/乱码 | 文本编码规范 |
|| 21-room-features.mdc | 家居设计游戏 | 房间类型规范 + V1.5功能模块 |
|| 22-animations.mdc | 动画相关 | Framer Motion规范 |
|| 23-daily-summary.mdc | 每条指令完成后 | 自动自省引擎 — transcript解析/每日日志/教训沉淀 |

> 注：编号 05/17/20 已被历史迭代删除（05已删除、17和20已合并）。当前共 21 个规则文件。
