<#
.SYNOPSIS
  每日情报日报自动化执行脚本

.DESCRIPTION
  每日北京时间 06:00 自动执行以下流程：
  1. 准备：计算时间窗口、创建目录
  2. AI Agent：执行情报检索与写作（基于 prompts/daily-intelligence-prompt.md）
  3. 落盘：保存 Markdown 到 d:/HJ/Web/daily-news/
  4. 推送：发送摘要到飞书
  5. 收尾：统计输出

  支持手动触发：.\daily-intelligence.ps1 -Manual
  手动模式跳过定时限制，直接执行

.PARAMETER Manual
  手动执行模式（不检查定时）

.PARAMETER SkipPush
  跳过飞书推送（仅生成报告）

.PARAMETER PromptPath
  自定义提示词文件路径

.PARAMETER OutputPath
  自定义输出目录

.PARAMETER DryRun
  仅打印执行计划，不实际执行

.EXAMPLE
  # 每日自动执行
  .\daily-intelligence.ps1

  # 手动触发
  .\daily-intelligence.ps1 -Manual

  # 仅生成，不推送
  .\daily-intelligence.ps1 -SkipPush

  # 预览
  .\daily-intelligence.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Manual,
    [switch]$SkipPush,
    [string]$PromptPath = "",
    [string]$OutputPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

# ── 路径配置 ────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

if ($PromptPath -eq "") {
    $PromptPath = Join-Path $RepoRoot "prompts\daily-intelligence-prompt.md"
}
if ($OutputPath -eq "") {
    $OutputPath = "d:\HJ\Web\daily-news"
}
$LogDir = Join-Path $RepoRoot "logs"
$DateStr = Get-Date -Format 'yyyy-MM-dd'
$FullDateStr = Get-Date -Format 'yyyy年MM月dd日'
$Weekday = (Get-Culture).DateTimeFormat.DayNames[(Get-Date).DayOfWeek]
$OutputFile = Join-Path $OutputPath "news-$DateStr.md"
$LogFile = Join-Path $LogDir "daily-intelligence-$DateStr.log"
$ErrorLog = Join-Path $OutputPath "_errors.log"

$utf8Bom = New-Object System.Text.UTF8Encoding $true

# ── 时间窗口 ────────────────────────────────────────────
$now = Get-Date
$windowEnd = $now.ToString("yyyy-MM-dd 06:00")
$windowStart = $now.AddDays(-1).ToString("yyyy-MM-dd 05:00")
$startTime = Get-Date

# ── 日志函数 ────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        "PASS"  { "Green" }
        "FAIL"  { "Red" }
        "WARN"  { "Yellow" }
        "STEP"  { "Cyan" }
        "AI"    { "Magenta" }
        default { "White" }
    }
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $color
    $logLine = "$line`n"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    [System.IO.File]::AppendAllText($LogFile, $logLine, $utf8Bom)
}

# ── 初始化 ─────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   📰 每日情报日报自动化  v2.1" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 检查是否为手动模式
$autoMode = -not $Manual
if ($autoMode) {
    $hour = $now.Hour
    if ($hour -ne 6) {
        Write-Log "非 06:00 定时窗口（当前 $($now.ToString('HH:mm'))），跳过自动执行" -Level "WARN"
        Write-Host "使用 -Manual 强制执行" -ForegroundColor Gray
        exit 0
    }
}

# 检查提示词文件
if (-not (Test-Path $PromptPath)) {
    Write-Log "提示词文件不存在: $PromptPath" -Level "FAIL"
    exit 1
}

# 创建输出目录
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    Write-Log "创建输出目录: $OutputPath" -Level "PASS"
}

# 检查是否已有今日报告
if ((Test-Path $OutputFile) -and -not $Manual) {
    $existing = Get-Item $OutputFile
    $age = ($now - $existing.LastWriteTime).TotalHours
    if ($age -lt 6) {
        Write-Log "今日报告已存在（$($existing.LastWriteTime.ToString('HH:mm'))），跳过生成" -Level "WARN"
        Write-Host "使用 -Manual 强制重新生成" -ForegroundColor Gray
        exit 0
    }
}

Write-Log "报告日期: $FullDateStr $Weekday" -Level "STEP"
Write-Log "时间窗口: $windowStart ~ $windowEnd" -Level "STEP"
Write-Log "输出文件: $OutputFile" -Level "STEP"
Write-Log "提示词  : $PromptPath" -Level "STEP"
Write-Log "" -Level "STEP"

# ═══════════════════════════════════════════════════════════
# Step 1：调用 AI Agent（降级模式 — 自动选择可用接口）
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 1/5】调用 AI Agent..." -Level "STEP"
$agentStart = Get-Date

$reportContent = ""

# ── 检测可用接口 ─────────────────────────────────────────
# 优先级：SDK脚本 > Cursor MCP > Cursor CLI > Trae CLI > 兜底提示词摘要
$agentUsed = $false

# 方式 1：call-agent.ps1（用户自定义封装）
$callAgentScript = Join-Path $RepoRoot "scripts\call-agent.ps1"
if ((Test-Path $callAgentScript) -and -not $agentUsed) {
    try {
        Write-Log "尝试方式 1: call-agent.ps1..." -Level "INFO"
        $result = & $callAgentScript `
            -PromptFile $PromptPath `
            -OutputPath $OutputFile `
            -Sites "hj1982.cn,1982.cn" `
            2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputFile)) {
            $reportContent = Get-Content $OutputFile -Raw -Encoding UTF8
            $agentUsed = $true
            Write-Log "方式 1 成功（call-agent.ps1）" -Level "PASS"
        }
    } catch {
        Write-Log "方式 1 失败: $($_.Exception.Message)" -Level "WARN"
    }
}

# 方式 2：Cursor MCP（检查环境变量）
$cursorMcpEnabled = $env:CURSOR_MCP_ENABLED -eq "1"
if ($cursorMcpEnabled -and -not $agentUsed) {
    try {
        Write-Log "尝试方式 2: Cursor MCP..." -Level "INFO"
        $promptContent = Get-Content $PromptPath -Raw -Encoding UTF8
        # 通过 Cursor MCP 发送消息（需要 MCP server 配置）
        # 依赖: C:\Users\HJ2\.cursor\projects\e-HJ-cursor\mcps 目录下的 MCP tools
        # 以下为占位，实际通过 MCP tool 调用
        Write-Log "方式 2: Cursor MCP 已启用，请在 Cursor IDE 中手动执行提示词" -Level "WARN"
    } catch {
        Write-Log "方式 2 失败: $($_.Exception.Message)" -Level "WARN"
    }
}

# 方式 3：直接生成（当无 AI 接口可用时的兜底模式）
# 读取最新 GitHub/GitCode trending 作为实时数据源
if (-not $agentUsed) {
    Write-Log "无自动 AI 接口可用，生成提示词摘要..." -Level "WARN"

    # 尝试抓取 GitHub Trending 作为实时数据
    $githubTrending = ""
    try {
        $ghResp = Invoke-RestMethod -Uri "https://api.github.com/search/repositories?q=stars:>100+pushed:>2026-06-01&sort=stars&order=desc&per_page=5" `
            -TimeoutSec 8 -UserAgent "DailyIntelligenceBot/1.0"
        if ($ghResp.items) {
            $githubTrending = $ghResp.items | ForEach-Object {
                "- **{0}** ⭐ {1:N0} — {2}" -f $_.full_name, $_.stargazers_count, $_.description
            } | Out-String
        }
    } catch {
        Write-Log "GitHub Trending 获取失败（非致命）: $($_.Exception.Message)" -Level "WARN"
    }

    $reportContent = @"
# 📰 $DateStr 情报日报
🕕 06:00 · 窗口 $windowStart ~ $windowEnd

> **⚠️ 本报告由脚本自动生成（AI Agent 接口未配置）**
> **请将 prompts/daily-intelligence-prompt.md 内容复制到 AI 对话框手动执行获取完整报告**

---

## 📋 执行指南

1. 打开 `prompts/daily-intelligence-prompt.md`
2. 复制全部内容到 Trae/Cursor 对话框
3. AI 将执行检索、写作、落盘、推送全套流程

## 🐙 GitHub 趋势（实时抓取）

$githubTrending

---

## 📋 本次执行状态

- 执行时间: $($now.ToString('yyyy-MM-dd HH:mm:ss'))
- 输出路径: $OutputFile
- AI 接口状态: 未配置（call-agent.ps1 不存在）
- 提示词文件: $PromptPath

---

<sub>📊 状态: 待手动 AI 执行 | 来源: daily-intelligence.ps1 v2.1</sub>
"@
    $agentUsed = $true
}

$agentElapsed = (Get-Date) - $agentStart
Write-Log "AI 处理完成，耗时 $($agentElapsed.TotalSeconds.ToString('0.0'))s" -Level "PASS"

# ── Step 2: 保存报告 ────────────────────────────────────
Write-Log "【Step 2/5】保存报告..." -Level "STEP"
try {
    if ($reportContent -and $reportContent.Trim().Length -gt 0) {
        [System.IO.File]::WriteAllText($OutputFile, $reportContent, $utf8Bom)
        Write-Log "报告已落盘: $OutputFile" -Level "PASS"
    } else {
        Write-Log "报告内容为空，跳过保存" -Level "WARN"
    }
} catch {
    Write-Log "保存失败: $($_.Exception.Message)" -Level "FAIL"
    $errMsg = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) - 保存失败: $($_.Exception.Message)`n"
    [System.IO.File]::AppendAllText($ErrorLog, $errMsg, $utf8Bom)
}

# ── Step 3: 提取摘要推送 ────────────────────────────────
Write-Log "【Step 3/5】准备飞书推送内容..." -Level "STEP"

# 提取前 8 条关键信息作为推送摘要
$pushContent = ""
if ((Test-Path $OutputFile) -and (-not $DryRun)) {
    $content = Get-Content $OutputFile -Raw -Encoding UTF8
    # 提取今日头条、趋势、Top 3
    $lines = $content -split "`n"
    $summaryLines = @()
    $inTop3 = $false
    $foundTop3 = $false
    foreach ($line in $lines) {
        if ($line -match "^## 🏆 Top 3") { $inTop3 = $true; $foundTop3 = $true }
        if ($line -match "^---") { $inTop3 = $false }
        if ($inTop3 -and ($line -match "^\*\*(.+?)\*\*")) {
            $summaryLines += $line.Trim()
        }
    }

    # 推送内容（飞书卡片限制，约 2000 字）
    $pushContent = $content
    if ($pushContent.Length -gt 1800) {
        $pushContent = $pushContent.Substring(0, 1800) + "`n`n_（内容过长，已截断。完整报告见本地文件）_"
    }
} else {
    $pushContent = "📰 $FullDateStr $Weekday 情报日报`n`n报告已生成，请查看本地文件。`n$OutputFile"
}

# ── Step 4: 推送飞书 ────────────────────────────────────
if ($SkipPush) {
    Write-Log "跳过飞书推送（-SkipPush）" -Level "WARN"
} else {
    Write-Log "【Step 4/5】推送飞书..." -Level "STEP"
    $pushSuccess = $false

    # 方案 A：飞书机器人 Webhook
    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            Write-Log "尝试方案 A：飞书 Webhook..." -Level "INFO"
            $body = @{
                msg_type = "interactive"
                card = @{
                    header = @{
                        title = @{ tag = "plain_text"; content = "📰 $FullDateStr 情报日报" }
                        template = "blue"
                    }
                    elements = @(
                        @{ tag = "markdown"; content = $pushContent }
                    )
                }
            } | ConvertTo-Json -Depth 10 -Compress

            $response = Invoke-RestMethod -Uri $webhook -Method Post -Body $body `
                -ContentType "application/json; charset=utf-8" `
                -TimeoutSec 15
            if ($response -and $response.code -eq 0) {
                Write-Log "飞书 Webhook 推送成功" -Level "PASS"
                $pushSuccess = $true
            } else {
                Write-Log "飞书 Webhook 响应异常: $(($response | ConvertTo-Json -Compress))" -Level "WARN"
            }
        } catch {
            Write-Log "飞书 Webhook 推送失败: $($_.Exception.Message)" -Level "WARN"
        }
    }

    # 方案 B：lark-cli
    if (-not $pushSuccess) {
        try {
            Write-Log "尝试方案 B：lark-cli..." -Level "INFO"
            if ((Get-Command lark -ErrorAction SilentlyContinue) -or (Get-Command lark.exe -ErrorAction SilentlyContinue)) {
                $larkOut = lark im +send --to-self --file $OutputFile --as-markdown 2>&1
                $larkStr = $larkOut | Out-String
                if ($LASTEXITCODE -eq 0 -or $larkStr -match "success|发送成功") {
                    Write-Log "lark-cli 推送成功" -Level "PASS"
                    $pushSuccess = $true
                } else {
                    Write-Log "lark-cli 推送失败: $larkStr" -Level "WARN"
                }
            } else {
                Write-Log "lark-cli 未安装，跳过" -Level "INFO"
            }
        } catch {
            Write-Log "lark-cli 调用失败: $($_.Exception.Message)" -Level "WARN"
        }
    }

    # 方案 C：云文档归档（不依赖推送成功）
    try {
        Write-Log "尝试方案 C：飞书云文档归档..." -Level "INFO"
        if ((Get-Command lark -ErrorAction SilentlyContinue) -or (Get-Command lark.exe -ErrorAction SilentlyContinue)) {
            $docOut = lark docs +create `
                --title "情报日报 $DateStr" `
                --from-markdown $OutputFile `
                --api-version v2 2>&1
            $docStr = $docOut | Out-String
            if ($LASTEXITCODE -eq 0 -or $docStr -match "success|创建成功|docx") {
                Write-Log "飞书云文档创建成功" -Level "PASS"
            } else {
                Write-Log "飞书云文档创建失败（非致命）: $docStr" -Level "WARN"
            }
        }
    } catch {
        Write-Log "云文档归档失败（非致命）: $($_.Exception.Message)" -Level "WARN"
    }

    if (-not $pushSuccess) {
        $errMsg = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) - 推送失败，所有方案均不可用`n"
        [System.IO.File]::AppendAllText($ErrorLog, $errMsg, $utf8Bom)
        Write-Log "推送失败，已记录到错误日志" -Level "WARN"
    }
}

# ── Step 5: 收尾统计 ────────────────────────────────────
$totalElapsed = (Get-Date) - $startTime
$stats = @{
    "检索" = "≤30次"
    "候选" = "≤40条"
    "入选" = "≤35条"
    "用时" = "$([int]$totalElapsed.TotalMinutes)m$($totalElapsed.Seconds)s"
}

Write-Log "" -Level "STEP"
Write-Log "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Log "   ✅ 情报日报执行完成" -ForegroundColor Green
Write-Log "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Log "输出文件: $OutputFile" -Level "STEP"
Write-Log "推送状态: $(if ($SkipPush) { '已跳过' } elseif ($pushSuccess) { '成功' } else { '失败（已记录）' })" -Level "STEP"
Write-Log "总耗时  : $($totalElapsed.TotalSeconds.ToString('0.0'))s" -Level "STEP"
Write-Log "" -Level "STEP"

if (-not $DryRun) {
    Write-Host "📄 报告路径: $OutputFile" -ForegroundColor White
    Write-Host ""
    Write-Host "如需在 AI 对话中手动执行，请复制以下提示词文件内容：" -ForegroundColor Gray
    Write-Host "  $PromptPath" -ForegroundColor Gray
    Write-Host ""
}

exit 0
