# openhuman (🧑 养人)

> 仓库本地路径：`subprojects/repos-from-external/agent/openhuman/`
> 来源：<https://github.com/tinyhumansai/openhuman>
> 协议：**⚠️ GPL-3.0**（传染） ｜ 主语言：Rust + TypeScript ｜ 32,204★

## 解决什么问题

"养人" = 个人 AI 超智能，**桌面端应用**：

- 平台：Windows / macOS / Linux（Tauri 桌面）
- 内核：Rust（tokio async runtime）
- 前端：React + Vite
- 通信：JSON-RPC 嵌入进程
- 数据：本地优先 + 云端协同
- 多端：桌面 + iOS（实验性，通过 LAN / Tunnel / Cloud 传输）

## 核心架构（来自 AGENTS.md）

```
openhuman/
├── app/                          # pnpm workspace: openhuman-app
│   ├── src/                      # Vite + React 前端
│   ├── src-tauri/                # Tauri 桌面宿主
│   │   └── src/core_process.rs   # 核心进程句柄（CoreProcessHandle）
│   └── ...
├── src/                          # Rust 库
│   ├── core/                     # transport (JSON-RPC)
│   ├── openhuman/                # 业务域（devices, domains...）
│   ├── bin/                      # openhuman-core CLI + backfill 工具
│   └── main.rs
├── docs/                         # 深度内部文档
├── gitbooks/developing/          # 公共贡献者文档（含架构图）
├── packages/                     # monorepo 子包
└── Cargo.toml                    # 13,715 字节，核心 crate
```

## 关键设计

1. **Core in-process**：核心跑在 tokio 任务里（不再用 sidecar 进程，PR #1061）
2. **RPC Token**：每次启动随机 hex bearer，内存传递（不落盘）
3. **端口 + Bearer**：前端通过 `http://127.0.0.1:<port>/rpc` + `Authorization: Bearer <hex>`
4. **多 transport**：LAN HTTP / Tunnel（XChaCha20-Poly1305 E2E 加密）/ Cloud HTTP
5. **iOS 实验**：不直接跑 core，通过 `ConnectionProfile` transport 接到桌面 core

## 启动方式

```bash
# 前端开发
pnpm dev              # Vite dev
pnpm dev:app          # Tauri 桌面（含 CEF）

# Rust 检查
cargo check --manifest-path Cargo.toml
cargo build --manifest-path Cargo.toml --bin openhuman-core

# 编译
pnpm build
```

## 与本机 e:\HJ\Web 的结合点

- **架构范本**：「Rust core + React UI + JSON-RPC 嵌入」模式适合 hj1982.cn 后台改造
- **桌面 AI 形态**：可作「个人 AI 助手」桌面版的实现参考
- **iOS+Desktop 通信**：XChaCha20-Poly1305 tunnel 模式可借鉴
- **⚠️ 严禁**：不要把它的 Rust 业务代码片段合入本仓业务代码（GPL 传染）

## 风险

- **协议是 GPL-3.0**：派生作品必须开源 + 同样 GPL + 注明改动
- 任何「学习完改写」的 Rust 业务代码都需重写（不能直接 copy + rename）
- 仅学习架构思想 + Tauri + tokio 范式，安全
- iOS 端非 shipping，需自己评估
