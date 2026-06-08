# ============================================================
# HJ-Cursor Skill 健康检查脚本 v1.0
# 每周日 09:00 执行：检查断链、缺失文件、重复、磁盘占用
# ============================================================
[CmdletBinding()]
param(
    [switch]$SkipPush
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ReportFile = Join-Path $RepoRoot "logs\skill-health\health-$(Get-Date -Format 'yyyy-MM-dd').json"
$utf8Bom = New-Object System.Text.UTF8Encoding $true

$now = Get-Date
$startTime = Get-Date

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = @{ PASS = "Green"; FAIL = "Red"; WARN = "Yellow"; STEP = "Cyan"; INFO = "White" }[$Level]
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

$OutputPath = Split-Path $ReportFile
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
}

Write-Log "=== Skill 健康检查 v1.0 ===" -Level "STEP"
Write-Log "报告: $ReportFile" -Level "STEP"

$results = @{}

# ── 1. 基本统计 ───────────────────────────────────
Write-Log "[1/6] 统计 skill 数量..." -Level "STEP"
$globalPath = "$env:USERPROFILE\.agents\skills"
$cursorPath = "$env:USERPROFILE\.cursor\skills-cursor"
$windsurfPath = "$env:USERPROFILE\.codeium\windsurf\skills"

$globalCount = (Get-ChildItem $globalPath -Directory -EA SilentlyContinue).Count
$cursorCount = (Get-ChildItem $cursorPath -Directory -EA SilentlyContinue).Count
$windsurfCount = (Get-ChildItem $windsurfPath -EA SilentlyContinue).Count

$results.globalCount = $globalCount
$results.cursorCount = $cursorCount
$results.windsurfCount = $windsurfCount
Write-Log "Global=$globalCount Cursor=$cursorCount Windsurf=$windsurfCount" -Level "PASS"

# ── 2. 断链检查 ───────────────────────────────────
Write-Log "[2/6] 检查 Windsurf 断链..." -Level "STEP"
$brokenLinks = @()
Get-ChildItem $windsurfPath -EA SilentlyContinue | ForEach-Object {
    if ($_.LinkType) {
        $target = $_.Target -join ''
        if (-not (Test-Path $target)) {
            $brokenLinks += $_.Name
        }
    }
}
$results.brokenLinks = $brokenLinks
if ($brokenLinks.Count -eq 0) {
    Write-Log "断链: 0 (OK)" -Level "PASS"
} else {
    Write-Log "断链: $($brokenLinks.Count)" -ForegroundColor Red
    $brokenLinks | ForEach-Object { Write-Host "  BROKEN: $_" -ForegroundColor Red }
}

# ── 3. 缺失 SKILL.md ───────────────────────────────
Write-Log "[3/6] 检查缺失 SKILL.md..." -Level "STEP"
$missing = @()
foreach ($dir in @($globalPath, $cursorPath)) {
    Get-ChildItem $dir -Directory -EA SilentlyContinue | ForEach-Object {
        $sk = Join-Path $_.FullName "SKILL.md"
        if (-not (Test-Path $sk)) {
            $missing += $_.Name
        }
    }
}
$results.missingSkillMd = $missing
if ($missing.Count -eq 0) {
    Write-Log "缺失 SKILL.md: 0 (OK)" -Level "PASS"
} else {
    Write-Log "缺失 SKILL.md: $($missing.Count)" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  MISSING: $_" -ForegroundColor Red }
}

# ── 4. 空 skill 目录 ────────────────────────────────
Write-Log "[4/6] 检查空/小 skill 目录..." -Level "STEP"
$empty = @()
$tiny = @()  # < 500 bytes
foreach ($dir in @($globalPath, $cursorPath)) {
    Get-ChildItem $dir -Directory -EA SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($size -eq 0) {
            $empty += $_.Name
        } elseif ($size -lt 500) {
            $tiny += @{ name = $_.Name; size = $size }
        }
    }
}
$results.emptySkills = $empty
$results.tinySkills = $tiny
if ($empty.Count -eq 0 -and $tiny.Count -eq 0) {
    Write-Log "空/Tiny skill: 0 (OK)" -Level "PASS"
} else {
    if ($empty.Count -gt 0) { Write-Host "  EMPTY: $($empty -join ', ')" -ForegroundColor Red }
    if ($tiny.Count -gt 0) { Write-Host "  TINY (<500B): $($tiny.ForEach({ $_.name }) -join ', ')" -ForegroundColor Yellow }
}

# ── 5. 磁盘占用 ───────────────────────────────────
Write-Log "[5/6] 检查磁盘占用..." -Level "STEP"
$diskUsage = @{}
foreach ($dir in @($globalPath, $cursorPath)) {
    $size = (Get-ChildItem $dir -Recurse -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $name = Split-Path $dir -Leaf
    $diskUsage[$name] = @{ sizeBytes = $size; sizeMB = [math]::Round($size / 1MB, 2) }
    Write-Log "$name : $([math]::Round($size / 1MB, 1)) MB" -Level "INFO"
}
$results.diskUsage = $diskUsage

# ── 6. 大 skill 排名 ────────────────────────────────
Write-Log "[6/6] 大 skill 排名 (Top 5)..." -Level "STEP"
$bigSkills = @()
foreach ($dir in @($globalPath, $cursorPath)) {
    Get-ChildItem $dir -Directory -EA SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $bigSkills += @{ name = $_.Name; sizeMB = [math]::Round($size / 1MB, 2); location = Split-Path $dir -Leaf }
    }
}
$topBig = ($bigSkills | Sort-Object -Property sizeMB -Descending | Select-Object -First 5)
$results.topBigSkills = $topBig
$topBig | ForEach-Object { Write-Log "  $($_.sizeMB) MB | $($_.location) | $($_.name)" -Level "INFO" }

# ── 总结 ─────────────────────────────────────────
$totalElapsed = (Get-Date) - $startTime
$status = if ($brokenLinks.Count -eq 0 -and $missing.Count -eq 0) { "HEALTHY" } else { "ISSUES_FOUND" }

$report = @{
    generatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
    status = $status
    globalCount = $globalCount
    cursorCount = $cursorCount
    windsurfCount = $windsurfCount
    brokenLinksCount = $brokenLinks.Count
    brokenLinks = $brokenLinks
    missingSkillMdCount = $missing.Count
    missingSkillMd = $missing
    emptySkillsCount = $empty.Count
    tinySkillsCount = $tiny.Count
    topBigSkills = $topBig
    elapsedSeconds = [math]::Round($totalElapsed.TotalSeconds, 1)
} | ConvertTo-Json -Depth 5

[System.IO.File]::WriteAllText($ReportFile, $report, $utf8Bom)
Write-Log "报告落盘: $ReportFile" -Level "PASS"

# ── 飞书推送 ─────────────────────────────────────
if (-not $SkipPush) {
    $summary = "Skill 健康检查`n$($now.ToString('MM月dd日 HH:mm'))`n"
    $summary += "Global=$globalCount Cursor=$cursorCount Windsurf=$windsurfCount`n"
    if ($status -eq "HEALTHY") {
        $summary += "状态: 全部正常"
    } else {
        $summary += "状态: 发现问题`n"
        if ($brokenLinks.Count -gt 0) { $summary += "断链: $($brokenLinks.Count) 个`n" }
        if ($missing.Count -gt 0) { $summary += "缺失 SKILL.md: $($missing.Count) 个`n" }
        if ($empty.Count -gt 0) { $summary += "空 skill: $($empty.Count) 个`n" }
    }
    $summary += "`n耗时: $($totalElapsed.TotalSeconds.ToString('0.0'))s"

    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            $body = @{ msg_type = "text"; content = @{ text = $summary } } | ConvertTo-Json -Depth 5 -Compress
            Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 10 | Out-Null
            Write-Log "飞书推送成功" -Level "PASS"
        } catch {
            Write-Log "飞书推送失败: $($_.Exception.Message)" -Level "WARN"
        }
    }
}

Write-Log ""
Write-Log "=== 完成 ===" -ForegroundColor Green
Write-Log "状态: $status | 断链:$($brokenLinks.Count) | 缺失:$($missing.Count)"
Write-Log "耗时: $($totalElapsed.TotalSeconds.ToString('0.0'))s"
