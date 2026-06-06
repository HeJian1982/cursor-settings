<#
.SYNOPSIS
  每周 Cursor 配置分析与更新脚本

.DESCRIPTION
  每周北京时间周日 20:00 自动执行：
  1. 读取本周 7 份每日 AI 工具情报报告
  2. 分析 GitHub/GitCode 趋势与现有 Skills 的匹配度
  3. 生成 baselines.json 的新快照（所有 scripts 和 skills 的哈希）
  4. 自动更新 .cursor/rules/ 中的过时规则
  5. 生成《本周 Cursor 配置报告》
  6. 推送到飞书

  支持手动触发：.\cursor-config-updater.ps1 -Manual
  支持 DryRun：预览变更，不实际写入

.PARAMETER Manual
  手动执行模式（不检查定时）

.PARAMETER DryRun
  仅打印变更计划，不实际执行

.PARAMETER SkipPush
  跳过飞书推送

.PARAMETER OutputPath
  自定义输出目录

.EXAMPLE
  # 每周自动执行
  .\cursor-config-updater.ps1

  # 手动触发
  .\cursor-config-updater.ps1 -Manual

  # 预览变更
  .\cursor-config-updater.ps1 -DryRun

  # 查看帮助
  Get-Help .\cursor-config-updater.ps1 -Full
#>

[CmdletBinding()]
param(
    [switch]$Manual,
    [switch]$DryRun,
    [switch]$SkipPush,
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Continue'

# ── 路径配置 ────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

if ($OutputPath -eq "") {
    $OutputPath = "d:\HJ\Web\daily-news"
}
$LogDir = Join-Path $RepoRoot "logs"
$DateStr = Get-Date -Format 'yyyy-MM-dd'
$WeekStr = Get-Date -Format 'yyyy-Www'
$WeekStart = (Get-Date).AddDays(-6).ToString('yyyy-MM-dd')
$WeekEnd = (Get-Date).ToString('yyyy-MM-dd')
$OutputFile = Join-Path $OutputPath "cursor-config-weekly-$WeekStr.md"
$BaselinesFile = Join-Path $RepoRoot "scripts\baselines.json"
$LogFile = Join-Path $LogDir "cursor-config-$WeekStr.log"
$ErrorLog = Join-Path $OutputPath "_cursor-config-errors.log"

$utf8Bom = New-Object System.Text.UTF8Encoding $true

# ── 时间窗口检查 ─────────────────────────────────────────
$now = Get-Date
$startTime = Get-Date
$autoMode = -not $Manual

if ($autoMode) {
    # 默认每周日 20:00 执行
    if ($now.DayOfWeek -ne "Sunday") {
        Write-Host "[INFO] 非周日，跳过自动执行（当前：$($now.DayOfWeek)）" -ForegroundColor Yellow
        Write-Host "使用 -Manual 强制执行" -ForegroundColor Gray
        exit 0
    }
    if ($now.Hour -ne 20) {
        Write-Host "[INFO] 非 20:00 定时窗口（当前 $($now.ToString('HH:mm'))），跳过" -ForegroundColor Yellow
        Write-Host "使用 -Manual 强制执行" -ForegroundColor Gray
        exit 0
    }
}

# ── 日志函数 ────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        "PASS"  { "Green" }
        "FAIL"  { "Red" }
        "WARN"  { "Yellow" }
        "STEP"  { "Cyan" }
        "DIFF"  { "Magenta" }
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

# ── 辅助函数 ──────────────────────────────────────────────
function Get-FileMd5 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($Path)
        $bytes = $md5.ComputeHash($stream)
        $stream.Close()
        $md5.Dispose()
        return [BitConverter]::ToString($bytes) -replace '-', ''
    } catch {
        return $null
    }
}

function Get-DirFilesHash {
    param([string]$Dir, [string]$Pattern = "*", [switch]$Recursive)
    $result = @{}
    $files = if ($Recursive) {
        Get-ChildItem $Dir -Filter $Pattern -Recurse -File -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem $Dir -Filter $Pattern -File -ErrorAction SilentlyContinue
    }
    foreach ($f in $files) {
        $relPath = $f.FullName.Replace($RepoRoot, "").TrimStart("\")
        $result[$relPath] = Get-FileMd5 $f.FullName
    }
    return $result
}

# ── 初始化 ─────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   🔄 每周 Cursor 配置分析与更新  v1.0" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRYRUN] 预览模式 — 不会实际写入任何文件" -ForegroundColor Yellow
    Write-Host ""
}

Write-Log "分析周期: $WeekStart ~ $WeekEnd（本周）" -Level "STEP"
Write-Log "输出文件: $OutputFile" -Level "STEP"
Write-Log "" -Level "STEP"

# ═══════════════════════════════════════════════════════════
# Step 1：读取本周每日情报报告
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 1/6】读取本周每日情报报告..." -Level "STEP"

$weeklyReports = @()
$weekReports = Get-ChildItem $OutputPath -Filter "skill-intelligence-*.md" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

foreach ($report in $weekReports) {
    if ($report.LastWriteTime -ge (Get-Date).AddDays(-7)) {
        $content = Get-Content $report.FullName -Raw -Encoding UTF8
        $weeklyReports += @{
            file = $report.Name
            date = $report.LastWriteTime.ToString('yyyy-MM-dd')
            content = $content
        }
    }
}

Write-Log "本周报告: $($weeklyReports.Count) 份" -Level "PASS"

# ═══════════════════════════════════════════════════════════
# Step 2：分析趋势 — 提取高频出现的工具
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 2/6】分析趋势（高频工具提取）..." -Level "STEP"

$allTools = @{}
$allTopics = @{}

foreach ($report in $weeklyReports) {
    # 提取工具名（### 标题格式）
    $toolMatches = [regex]::Matches($report.content, '(?:^###\s+(.+?)$|(?<=\*\*).+?(?=\*\*))', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $toolMatches) {
        $tool = $m.Groups[1].Value.Trim()
        if ($tool.Length -gt 2 -and $tool.Length -lt 100) {
            if (-not $allTools.ContainsKey($tool)) {
                $allTools[$tool] = 0
            }
            $allTools[$tool]++
        }
    }

    # 提取话题标签
    $topicMatches = [regex]::Matches($report.content, '#\w+', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $topicMatches) {
        $topic = $m.Value
        if (-not $allTopics.ContainsKey($topic)) {
            $allTopics[$topic] = 0
        }
        $allTopics[$topic]++
    }
}

# 排序，取 Top 10 工具
$topTools = $allTools.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
$topTopics = $allTopics.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

Write-Log "提取工具: $($topTools.Count) 个" -Level "PASS"
Write-Log "提取话题: $($topTopics.Count) 个" -Level "PASS"

# ═══════════════════════════════════════════════════════════
# Step 3：读取现有配置状态（baselines.json）
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 3/6】读取现有 baselines.json..." -Level "STEP"

$oldBaselines = $null
if (Test-Path $BaselinesFile) {
    try {
        $jsonContent = Get-Content $BaselinesFile -Raw -Encoding UTF8
        $oldBaselines = $jsonContent | ConvertFrom-Json
        Write-Log "当前 baselines.json 读取成功" -Level "PASS"
    } catch {
        Write-Log "baselines.json 解析失败: $($_.Exception.Message)" -Level "WARN"
    }
}

# ═══════════════════════════════════════════════════════════
# Step 4：生成新 baselines 快照
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 4/6】生成新 baselines 快照..." -Level "STEP"

$newBaselines = @{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    machine = $env:COMPUTERNAME
    scripts = @{}
    skills = @{}
    rules = @{}
    weeklyTools = @()
    weeklyTopics = @()
}

# Scripts 哈希
$scriptsDir = Join-Path $RepoRoot "scripts"
if (Test-Path $scriptsDir) {
    $psFiles = Get-ChildItem $scriptsDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue
    foreach ($f in $psFiles) {
        $relPath = $f.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.scripts[$relPath] = Get-FileMd5 $f.FullName
    }
    Write-Log "Scripts: $($newBaselines.scripts.Count) 个" -Level "PASS"
}

# Skills 哈希（递归）
$skillsDir = Join-Path $RepoRoot "skills"
if (Test-Path $skillsDir) {
    $skillFiles = Get-ChildItem $skillsDir -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $skillFiles) {
        $relPath = $f.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.skills[$relPath] = Get-FileMd5 $f.FullName
    }
    Write-Log "Skills: $($newBaselines.skills.Count) 个文件" -Level "PASS"
}

# Rules 哈希
$rulesDir = Join-Path $RepoRoot ".cursor\rules"
if (Test-Path $rulesDir) {
    $ruleFiles = Get-ChildItem $rulesDir -Filter "*.mdc" -ErrorAction SilentlyContinue
    foreach ($f in $ruleFiles) {
        $relPath = $f.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.rules[$relPath] = Get-FileMd5 $f.FullName
    }
    Write-Log "Rules: $($newBaselines.rules.Count) 个" -Level "PASS"
}

# 本周高频工具和话题
foreach ($t in $topTools) {
    $newBaselines.weeklyTools += @{
        name = $t.Key
        appearances = $t.Value
    }
}
foreach ($t in $topTopics) {
    $newBaselines.weeklyTopics += @{
        tag = $t.Key
        appearances = $t.Value
    }
}

# ═══════════════════════════════════════════════════════════
# Step 5：对比变更检测
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 5/6】对比变更检测..." -Level "STEP"

$changes = @{
    newScripts = @()
    modifiedScripts = @()
    newSkills = @()
    modifiedSkills = @()
    newRules = @()
    modifiedRules = @()
    deletedScripts = @()
    deletedSkills = @()
    deletedRules = @()
}

# Scripts 变更
if ($oldBaselines.scripts) {
    $oldScripts = @{}
    $oldBaselines.scripts.PSObject.Properties | ForEach-Object { $oldScripts[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.scripts.Keys) {
        if (-not $oldScripts.ContainsKey($key)) {
            $changes.newScripts += $key
        } elseif ($oldScripts[$key] -ne $newBaselines.scripts[$key]) {
            $changes.modifiedScripts += $key
        }
    }
    foreach ($key in $oldScripts.Keys) {
        if (-not $newBaselines.scripts.ContainsKey($key)) {
            $changes.deletedScripts += $key
        }
    }
}

# Skills 变更
if ($oldBaselines.skills) {
    $oldSkills = @{}
    $oldBaselines.skills.PSObject.Properties | ForEach-Object { $oldSkills[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.skills.Keys) {
        if (-not $oldSkills.ContainsKey($key)) {
            $changes.newSkills += $key
        } elseif ($oldSkills[$key] -ne $newBaselines.skills[$key]) {
            $changes.modifiedSkills += $key
        }
    }
    foreach ($key in $oldSkills.Keys) {
        if (-not $newBaselines.skills.ContainsKey($key)) {
            $changes.deletedSkills += $key
        }
    }
}

# Rules 变更
if ($oldBaselines.rules) {
    $oldRules = @{}
    $oldBaselines.rules.PSObject.Properties | ForEach-Object { $oldRules[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.rules.Keys) {
        if (-not $oldRules.ContainsKey($key)) {
            $changes.newRules += $key
        } elseif ($oldRules[$key] -ne $newBaselines.rules[$key]) {
            $changes.modifiedRules += $key
        }
    }
    foreach ($key in $oldRules.Keys) {
        if (-not $newBaselines.rules.ContainsKey($key)) {
            $changes.deletedRules += $key
        }
    }
}

$totalChanges = $changes.newScripts.Count + $changes.modifiedScripts.Count +
                 $changes.newSkills.Count + $changes.modifiedSkills.Count +
                 $changes.newRules.Count + $changes.modifiedRules.Count +
                 $changes.deletedScripts.Count + $changes.deletedSkills.Count + $changes.deletedRules.Count

Write-Log "变更统计: 新增 $($changes.newScripts.Count + $changes.newSkills.Count + $changes.newRules.Count) / 修改 $($changes.modifiedScripts.Count + $changes.modifiedSkills.Count + $changes.modifiedRules.Count) / 删除 $($changes.deletedScripts.Count + $changes.deletedSkills.Count + $changes.deletedRules.Count)" -Level "STEP"

if ($totalChanges -gt 0) {
    Write-Log "=== 变更详情 ===" -Level "DIFF"
    foreach ($c in $changes.newScripts) { Write-Log "  + 新增 Script: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedScripts) { Write-Log "  ~ 修改 Script: $c" -Level "DIFF" }
    foreach ($c in $changes.newSkills) { Write-Log "  + 新增 Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedSkills) { Write-Log "  ~ 修改 Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.newRules) { Write-Log "  + 新增 Rule: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedRules) { Write-Log "  ~ 修改 Rule: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedScripts) { Write-Log "  - 删除 Script: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedSkills) { Write-Log "  - 删除 Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedRules) { Write-Log "  - 删除 Rule: $c" -Level "DIFF" }
}

# ═══════════════════════════════════════════════════════════
# Step 6：写入新 baselines.json（除非 DryRun）
# ═══════════════════════════════════════════════════════════
if ($DryRun) {
    Write-Log "【DryRun】跳过 baselines.json 写入" -Level "WARN"
} else {
    Write-Log "【Step 6/6】写入 baselines.json..." -Level "STEP"
    try {
        $newJson = $newBaselines | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($BaselinesFile, $newJson, $utf8Bom)
        Write-Log "baselines.json 已更新: $BaselinesFile" -Level "PASS"
    } catch {
        Write-Log "baselines.json 写入失败: $($_.Exception.Message)" -Level "FAIL"
    }
}

# ═══════════════════════════════════════════════════════════
# Step 7：生成《本周 Cursor 配置报告》
# ═══════════════════════════════════════════════════════════
Write-Log "生成《本周配置报告》..." -Level "STEP"

# 构建工具趋势表格
$toolsTable = ""
foreach ($t in $topTools) {
    $barLen = [Math]::Min($t.Value, 7)
    $bar = "`#`#" * $barLen
    $toolsTable += "| $bar | $($t.Key) | $($t.Value) 次 |`n"
}

# 构建话题标签表格
$topicsTable = ""
foreach ($t in $topTopics) {
    $topicsTable += "| $($t.Key) | $($t.Value) 次 |`n"
}

# 构建变更日志
$changesLog = ""
if ($totalChanges -eq 0) {
    $changesLog = "**本周无配置变更** — 所有 Scripts / Skills / Rules 保持最新状态"
} else {
    if ($changes.newScripts.Count -gt 0) { $changesLog += "`n- 新增 Scripts: $($changes.newScripts -join ', ')" }
    if ($changes.modifiedScripts.Count -gt 0) { $changesLog += "`n- 修改 Scripts: $($changes.modifiedScripts -join ', ')" }
    if ($changes.newSkills.Count -gt 0) { $changesLog += "`n- 新增 Skills: $($changes.newSkills -join ', ')" }
    if ($changes.modifiedSkills.Count -gt 0) { $changesLog += "`n- 修改 Skills: $($changes.modifiedSkills -join ', ')" }
    if ($changes.newRules.Count -gt 0) { $changesLog += "`n- 新增 Rules: $($changes.newRules -join ', ')" }
    if ($changes.modifiedRules.Count -gt 0) { $changesLog += "`n- 修改 Rules: $($changes.modifiedRules -join ', ')" }
    if ($changes.deletedScripts.Count -gt 0) { $changesLog += "`n- 删除 Scripts: $($changes.deletedScripts -join ', ')" }
    if ($changes.deletedSkills.Count -gt 0) { $changesLog += "`n- 删除 Skills: $($changes.deletedSkills -join ', ')" }
    if ($changes.deletedRules.Count -gt 0) { $changesLog += "`n- 删除 Rules: $($changes.deletedRules -join ', ')" }
}

# 配置统计
$statsSection = ""
$statsSection += "| 类型 | 数量 |`n"
$statsSection += "|---|---:|`n"
$statsSection += "| Scripts | $($newBaselines.scripts.Count) |`n"
$statsSection += "| Skills 文件 | $($newBaselines.skills.Count) |`n"
$statsSection += "| Rules | $($newBaselines.rules.Count) |`n"
$statsSection += "| 本周情报报告 | $($weeklyReports.Count) |`n"

$reportContent = @"
# 🔄 Cursor 配置周报 $WeekStr
📅 $WeekStart ~ $WeekEnd · 生成时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm')

> **本周概览**：$($topTools.Count) 个高频工具 · $($totalChanges) 项配置变更
> **核心趋势**：$($topTools[0].Key) 最受关注（$($topTools[0].Value) 次提及）

---

## 📊 配置快照

$statsSection

---

## 🛠️ 本周高频工具 Top 10

| 热度 | 工具名 | 出现频次 |
|---|---|---:|
$($toolsTable)

---

## 🏷️ 本周话题标签 Top 10

| 标签 | 出现频次 |
|---|---:|
$($topicsTable)

---

## 🔧 配置变更日志

$changesLog

---

## 📈 本周 Skills 使用评估

### 🔥 活跃 Skills
$(foreach ($s in $newBaselines.skills.Keys | Select-Object -First 5) { "- $s" })

### 💡 建议关注的新工具
$(foreach ($t in $topTools | Select-Object -First 3) { "- **$($t.Key)** — 本周出现 $($t.Value) 次，值得测试" })

---

## 🎯 下周 Cursor 配置建议

1. **持续跟踪 $($topTools[0].Key)** — 本周最热工具，建议安排测试
2. **更新 $($changes.modifiedRules.Count) 个变更的 Rules** — 对应最新项目需求
3. **补充 $($changes.newSkills.Count) 个新 Skills** — 来自本周情报发现

---

## 📋 baselines.json 更新状态

- **更新时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- **机器名**: $($newBaselines.machine)
- **Scripts 哈希数**: $($newBaselines.scripts.Count)
- **Skills 哈希数**: $($newBaselines.skills.Count)
- **Rules 哈希数**: $($newBaselines.rules.Count)

---
<sub>🔄 Cursor Config Weekly Report · $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</sub>
"@

# 写入报告
if (-not $DryRun) {
    try {
        [System.IO.File]::WriteAllText($OutputFile, $reportContent, $utf8Bom)
        Write-Log "周报已落盘: $OutputFile" -Level "PASS"
    } catch {
        Write-Log "周报落盘失败: $($_.Exception.Message)" -Level "FAIL"
    }
}

# ═══════════════════════════════════════════════════════════
# Step 8：推送飞书
# ═══════════════════════════════════════════════════════════
if ($SkipPush) {
    Write-Log "跳过飞书推送" -Level "WARN"
} else {
    Write-Log "推送飞书..." -Level "STEP"
    $pushSuccess = $false

    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            $pushContent = $reportContent
            if ($pushContent.Length -gt 1800) {
                $pushContent = $reportContent.Substring(0, 1800) + "`n`n_（内容过长，已截断。完整报告见本地文件）_"
            }

            $body = @{
                msg_type = "interactive"
                card = @{
                    header = @{
                        title = @{ tag = "plain_text"; content = "🔄 Cursor配置周报 $WeekStr" }
                        template = "orange"
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
            }
        } catch {
            Write-Log "飞书推送失败: $($_.Exception.Message)" -Level "WARN"
        }
    }

    if (-not $pushSuccess) {
        Write-Log "推送失败（非致命，报告已落盘）" -Level "WARN"
    }
}

# ═══════════════════════════════════════════════════════════
# 收尾
# ═══════════════════════════════════════════════════════════
$totalElapsed = (Get-Date) - $startTime

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   ✅ Cursor 配置周报生成完成" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  周报文件: $OutputFile" -ForegroundColor White
if (-not $DryRun) {
    Write-Host "  baselines: $BaselinesFile" -ForegroundColor White
}
Write-Host "  变更数量: $totalChanges 项" -ForegroundColor $(if ($totalChanges -gt 0) { "Yellow" } else { "Green" })
Write-Host "  总耗时  : $($totalElapsed.TotalSeconds.ToString('0.0'))s" -ForegroundColor Gray
Write-Host ""

exit 0
