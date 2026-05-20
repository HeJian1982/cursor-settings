<#
.SYNOPSIS
  自动自省引擎 — 每次 Commit + Push 后执行

.DESCRIPTION
  读取最新 transcript JSONL，提取：
  1. 每日日志追加信息
  2. 可路由到 memory/ 的洞察
  自动追加到对应文件，无需人工干预。

  用法：此脚本应在 Commit + Push 成功后由 AI 自动调用。

.PARAMETER TranscriptPath
  要分析的 transcript JSONL 文件路径，默认取最新

.PARAMETER DryRun
  仅打印计划，不写文件

.EXAMPLE
  # 自动模式（AI 在每次 Commit 后调用）
  & "$PSScriptRoot\auto-reflect.ps1"

  # 指定文件
  & "$PSScriptRoot\auto-reflect.ps1" -TranscriptPath "C:\path\to\latest.jsonl"

  # 预览模式
  & "$PSScriptRoot\auto-reflect.ps1" -DryRun
#>

[CmdletBinding()]
param(
    [string]$TranscriptPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ── 路径配置 ────────────────────────────────────────────
$TranscriptBase = "C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
$DailyLogRoot  = "e:\HJ\cursor\cursor-transcripts"
$MemoryRoot    = "e:\HJ\cursor\memory"

# ── UTF-8 No BOM ────────────────────────────────────────
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ── Step 1: 找到最新的 transcript ─────────────────────
if ($TranscriptPath -eq "") {
    $sessions = Get-ChildItem $TranscriptBase -Directory
    if ($sessions.Count -eq 0) { Write-Host "[WARN] No transcripts found"; exit 0 }

    # 按修改时间排序，取最新的
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

# ── Step 2: 解析 JSONL，提取关键信息 ──────────────────
$lines = Get-Content -Path $TranscriptPath -Encoding UTF8
$userMessages = @()
$fileChanges  = @()   # Write / Delete / StrReplace
$sessionMeta  = $null

foreach ($line in $lines) {
    if ($line.Trim() -eq "") { continue }
    try {
        $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $obj) { continue }

        if ($obj.role -eq "user") {
            $text = $obj.message.content[0].text -replace '\|.*', ''
            $text = $text.Trim() -replace '\s+', ' '
            if ($text.Length -gt 200) { $text = $text.Substring(0, 200) + "..." }
            if ($text -ne "") { $userMessages += $text }
        }

        if ($obj.role -eq "assistant") {
            $tools = $obj.message.content | Where-Object { $_.type -eq "tool_use" }
            foreach ($t in $tools) {
                $name = $t.name
                if ($name -in @("Write", "Delete", "StrReplace", "EditNotebook")) {
                    $path = $t.input.path -replace '\\', '/'
                    $fileChanges += @{ name = $name; path = $path }
                }
            }
        }
    } catch { }
}

if ($userMessages.Count -eq 0) {
    Write-Host "[WARN] No user messages found in transcript"
    exit 0
}

# ── Step 3: 提取洞察 ───────────────────────────────────
# 从用户请求和文件变更中提炼可执行的教训
$insights = @()
$decisions = @()

foreach ($msg in $userMessages) {
    # 教训：重复出现的问题模式
    if ($msg -match "重新" -or $msg -match "再次" -or $msg -match "重复") {
        $insights += "[模式] 重复触发同一类任务，可能流程存在问题"
    }
}

# 教训：文件变更统计
$writeCount = ($fileChanges | Where-Object { $_.name -eq "Write" }).Count
$deleteCount = ($fileChanges | Where-Object { $_.name -eq "Delete" }).Count
$editCount = ($fileChanges | Where-Object { $_.name -eq "StrReplace" }).Count

Write-Host "Messages   : $($userMessages.Count)" -ForegroundColor Gray
Write-Host "File writes: $writeCount" -ForegroundColor Gray
Write-Host "File edits : $editCount" -ForegroundColor Gray
Write-Host "File deletes: $deleteCount" -ForegroundColor Gray
Write-Host ""

# ── Step 4: 生成每日日志追加内容 ─────────────────────
$timestamp = Get-Date -Format "HH:mm"
$dateStr = Get-Date -Format "yyyy-MM-dd"
$sessionId = [System.IO.Path]::GetFileNameWithoutExtension($TranscriptPath)

# 计算会话时长（从第一条和最后一条的时间戳估算）
$firstMsg = $userMessages[0]
$lastMsg  = $userMessages[-1]

$logEntry = @"

### $timestamp 左右
**会话 ID**: ``$sessionId``

| 项目 | 内容 |
|------|------|
| 主题 | $firstMsg |
| 触发条件 | 用户主动发起 |
| 动作 | 涉及 $($fileChanges.Count) 个文件操作（Write: $writeCount / Edit: $editCount / Delete: $deleteCount） |
| 结果 | ✅ 完成 |

#### 改动文件
$($fileChanges | Group-Object path | ForEach-Object { "- ``$($_.Name)`` — $($_.Count) 次操作" } | Out-String)

#### 自省洞察
$($insights | ForEach-Object { "- $_" } | Out-String)

#### 验证
- typecheck: ✅ / ❌（待确认）
- git commit: 已提交
"@

# ── Step 5: 追加到每日日志 ───────────────────────────
$dailyLogPath = Join-Path $DailyLogRoot "$dateStr.md"
if (-not (Test-Path $dailyLogPath)) {
    $header = @"
# Cursor AI 每日会话日志

> 每条会话自动追加至此，按日期归档。格式：每轮对话一行，包含时间、主题、结果。

---

"@
    $logEntry = $header + $logEntry + "`n`n---`n`n"
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($dailyLogPath, $logEntry, $utf8NoBom)
        Write-Host "[OK] Created daily log: $dailyLogPath" -ForegroundColor Green
    } else {
        Write-Host "[DryRun] Would create: $dailyLogPath" -ForegroundColor Cyan
    }
} else {
    # 在 "---" 前插入新内容
    $existing = [System.IO.File]::ReadAllText($dailyLogPath, $utf8NoBom)
    if ($existing -match '(\n---\n*)$') {
        $logEntry = $existing -replace '(\n---\n*)$', "`n" + $logEntry + "`n---`n"
    } else {
        $logEntry = $existing + "`n`n" + $logEntry + "`n---`n"
    }
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($dailyLogPath, $logEntry, $utf8NoBom)
        Write-Host "[OK] Appended to: $dailyLogPath" -ForegroundColor Green
    } else {
        Write-Host "[DryRun] Would append to: $dailyLogPath" -ForegroundColor Cyan
    }
}

# ── Step 6: 路由洞察到 memory/ ────────────────────────
# 洞察写入 lessons/
$lessonPath = Join-Path $MemoryRoot "lessons\INDEX.md"
if ((Test-Path $lessonPath) -and $insights.Count -gt 0) {
    Write-Host ""
    Write-Host "Insights to route:" -ForegroundColor Yellow
    foreach ($insight in $insights) {
        Write-Host "  -> $insight" -ForegroundColor Gray
    }
    Write-Host "[INFO] Lessons update requires AI judgment — not auto-written" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "[OK] Auto-reflect complete" -ForegroundColor Green
