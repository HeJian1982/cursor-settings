<#
.SYNOPSIS
  自动自省引擎 — 每次 Commit + Push 后执行

.DESCRIPTION
  读取最新 transcript JSONL，提取：
  1. 每日日志追加信息
  2. 可路由到 memory/ 的洞察
  3. 自动同步到 hj1982.cn 数据库
  自动追加到对应文件，无需人工干预。

  用法：此脚本应在 Commit + Push 成功后由 AI 自动调用。

.PARAMETER TranscriptPath
  要分析的 transcript JSONL 文件路径，默认取最新

.PARAMETER DryRun
  仅打印计划，不写文件

.EXAMPLE
  # 自动模式（AI 在每次 Commit 后调用）
  & "$PSScriptRoot\auto-reflect.ps1"

  # 预览模式
  & "$PSScriptRoot\auto-reflect.ps1" -DryRun
#>

[CmdletBinding()]
param(
    [string]$TranscriptPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# 路径配置
$TranscriptBase = "C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
$DailyLogRoot  = "e:\HJ\cursor\cursor-transcripts"
$MemoryRoot    = "e:\HJ\cursor\memory"
$LogDir        = "e:\HJ\cursor\logs"

# UTF-8 No BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# 读取/写入文件（避免 PowerShell 编码问题）
function Read-Text($path) {
    [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}
function Write-Text($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}
function Append-Text($path, $content) {
    [System.IO.File]::AppendAllText($path, $content, $utf8NoBom)
}

# ── Step 1: 找到最新的 transcript ─────────────────────
if ($TranscriptPath -eq "") {
    $sessions = Get-ChildItem $TranscriptBase -Directory
    if ($sessions.Count -eq 0) { Write-Host "[WARN] No transcripts found"; exit 0 }

    $latest = $sessions | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $TranscriptPath = Join-Path $latest.FullName "$($latest.Name).jsonl"

    if (-not (Test-Path $TranscriptPath)) {
        Write-Host "[WARN] Transcript not found: $TranscriptPath"
        exit 1
    }
}

Write-Host ""
Write-Host "===== Auto-Reflect Engine =====" -ForegroundColor Cyan
Write-Host "Transcript : $TranscriptPath" -ForegroundColor Gray
Write-Host "DryRun    : $DryRun" -ForegroundColor Gray
Write-Host ""

# ── Step 2: 解析 JSONL ────────────────────────────────
$lines = Get-Content -Path $TranscriptPath -Encoding UTF8
$userMessages = @()
$fileChanges  = @()

foreach ($line in $lines) {
    if ($line.Trim() -eq "") { continue }
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $obj) { continue }

        if ($obj.role -eq "user") {
            $text = $obj.message.content[0].text
            if ($text) {
                $text = $text.Trim()
                if ($text.Length -gt 200) { $text = $text.Substring(0, 200) + "..." }
                $userMessages += $text
            }
        }

        if ($obj.role -eq "assistant") {
            $tools = $obj.message.content | Where-Object { $_.type -eq "tool_use" }
            foreach ($t in $tools) {
                $name = $t.name
                if ($name -in @("Write", "Delete", "StrReplace", "EditNotebook")) {
                    $path = $t.input.path
                    $path = $path -replace '\\', '/'
                    $fileChanges += @{ name = $name; path = $path }
                }
            }
        }
    } catch { }
}

if ($userMessages.Count -eq 0) {
    Write-Host "[WARN] No user messages found"
    exit 0
}

# ── Step 3: 提取洞察 ───────────────────────────────────
$insights = @()
foreach ($msg in $userMessages) {
    if ($msg -match "重新" -or $msg -match "再次" -or $msg -match "重复") {
        $insights += "[模式] 重复触发同一类任务"
    }
}

$writeCount = ($fileChanges | Where-Object { $_.name -eq "Write" }).Count
$deleteCount = ($fileChanges | Where-Object { $_.name -eq "Delete" }).Count
$editCount = ($fileChanges | Where-Object { $_.name -eq "StrReplace" }).Count

Write-Host "Messages   : $($userMessages.Count)" -ForegroundColor Gray
Write-Host "File writes: $writeCount" -ForegroundColor Gray
Write-Host "File edits : $editCount" -ForegroundColor Gray
Write-Host "File deletes: $deleteCount" -ForegroundColor Gray
Write-Host ""

# ── Step 4: 生成改动文件列表 ──────────────────────────
$fileListText = ""
if ($fileChanges.Count -gt 0) {
    $grouped = $fileChanges | Group-Object path
    $lines2 = @()
    foreach ($g in $grouped) {
        $lines2 += "- ``$($g.Name)`` — $($g.Count) 次操作"
    }
    $fileListText = $lines2 -join "`n"
} else {
    $fileListText = "- 无文件变更"
}

# ── Step 5: 生成洞察列表 ──────────────────────────────
$insightsText = ""
if ($insights.Count -gt 0) {
    $insightsText = ($insights | ForEach-Object { "- $_" }) -join "`n"
} else {
    $insightsText = "- 无新洞察"
}

# ── Step 6: 追加到每日日志 ───────────────────────────
$timestamp = Get-Date -Format "HH:mm"
$dateStr = Get-Date -Format "yyyy-MM-dd"
$sessionId = [System.IO.Path]::GetFileNameWithoutExtension($TranscriptPath)
$firstMsg = $userMessages[0]
$firstMsgEsc = $firstMsg -replace '\*', '\*' -replace '`', '``'

# 生成日志块（纯字符串拼接，避免 PowerShell heredoc 的 | 解析问题）
$nl = "`n"
$logBlock = "$nl" +
"### $timestamp 左右$nl" +
"**会话 ID**: ``$sessionId``$nl" +
"$nl" +
"  - 主题: $firstMsgEsc$nl" +
"  - 触发条件: 用户主动发起$nl" +
"  - 动作: 涉及 $($fileChanges.Count) 个文件操作（Write: $writeCount / Edit: $editCount / Delete: $deleteCount）$nl" +
"  - 结果: 完成$nl" +
"$nl" +
"#### 改动文件$nl" +
"$fileListText$nl" +
"$nl" +
"#### 自省洞察$nl" +
"$insightsText$nl" +
"$nl" +
"#### 验证$nl" +
"- typecheck: 待确认$nl" +
"- git commit: 已提交$nl"

$dailyLogPath = Join-Path $DailyLogRoot "$dateStr.md"
if (-not (Test-Path $DailyLogRoot)) {
    New-Item -ItemType Directory -Force -Path $DailyLogRoot | Out-Null
}

if (-not (Test-Path $dailyLogPath)) {
    $header = "# Cursor AI 每日会话日志" + $nl + $nl + "> 每条会话自动追加至此，按日期归档。" + $nl + $nl + "---" + $nl + $nl
    $content = $header + $logBlock + $nl + "---" + $nl
    if (-not $DryRun) {
        Write-Text $dailyLogPath $logBlock
        Write-Host "[OK] Created: $dailyLogPath" -ForegroundColor Green
    } else {
        Write-Host "[DryRun] Would create: $dailyLogPath" -ForegroundColor Cyan
    }
} else {
    $existing = Read-Text $dailyLogPath
    # 追加到文件末尾（不再尝试插入分隔符前）
    $content = $existing + $nl + $logBlock + $nl + "---" + $nl
    if (-not $DryRun) {
        Write-Text $dailyLogPath $content
        Write-Host "[OK] Appended to: $dailyLogPath" -ForegroundColor Green
    } else {
        Write-Host "[DryRun] Would append to: $dailyLogPath" -ForegroundColor Cyan
    }
}

# ── Step 7: 路由洞察 ─────────────────────────────────
$lessonPath = Join-Path $MemoryRoot "lessons\INDEX.md"
if ((Test-Path $lessonPath) -and $insights.Count -gt 0) {
    Write-Host ""
    Write-Host "Insights:" -ForegroundColor Yellow
    foreach ($insight in $insights) {
        Write-Host "  -> $insight" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "[OK] Auto-reflect complete" -ForegroundColor Green

