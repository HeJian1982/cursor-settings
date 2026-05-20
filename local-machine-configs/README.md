# Local Machine Configs · 本机配置快照

本目录管理 Cursor IDE 相关配置的版本化快照。

## 目录结构

```
local-machine-configs/
├── README.md                    ← 本文件
├── base/                        ← 所有机器共享
│   ├── cursor/                  ← Cursor 通用配置
│   └── global-workflows/        ← 全局工作流
└── hosts/                       ← 每台机一个子目录
    ├── <COMPUTERNAME>/         ← 如 HJ2/
    │   └── cursor/
    │       └── settings.json
    └── _template/               ← 新机参考骨架
```

## 使用方法

### 新机器初始化

1. 复制模板库到新电脑
2. 创建 Junction（如果需要多机共享）
3. 运行 `scripts/sync-local-configs.ps1 -InitHost`

### 配置同步

```powershell
# 拉取配置到仓库
.\scripts\sync-local-configs.ps1 -Direction Pull

# 推送配置到本机
.\scripts\sync-local-configs.ps1 -Direction Push
```
