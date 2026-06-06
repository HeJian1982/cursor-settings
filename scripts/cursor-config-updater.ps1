<#
.SYNOPSIS
  Weekly Cursor Config Analysis and Update Script

.DESCRIPTION
  Runs every Sunday at 20:00 Beijing time:
  1. Read 7 daily AI tool intelligence reports
  2. Analyze GitHub/GitCode trends vs existing Skills
  3. Generate baselines.json snapshot
  4. Generate weekly Cursor config report
  5. Push to Feishu

  Manual mode: .\cursor-config-updater.ps1 -Manual
  DryRun mode: .\cursor-config-updater.ps1 -Manual -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Manual,
    [switch]$DryRun,
    [switch]$SkipPush,
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Continue'

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

$utf8Bom = New-Object System.Text.UTF8Encoding $true

$now = Get-Date
$startTime = Get-Date

if (-not $Manual) {
    if ($now.DayOfWeek -ne "Sunday") {
        Write-Host "[INFO] Not Sunday, skip (current: $($now.DayOfWeek))" -ForegroundColor Yellow
        Write-Host "Use -Manual to force run" -ForegroundColor Gray
        exit 0
    }
    if ($now.Hour -ne 20) {
        Write-Host "[INFO] Not 20:00 window" -ForegroundColor Yellow
        Write-Host "Use -Manual to force run" -ForegroundColor Gray
        exit 0
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = "White"
    if ($Level -eq "PASS") { $color = "Green" }
    elseif ($Level -eq "FAIL") { $color = "Red" }
    elseif ($Level -eq "WARN") { $color = "Yellow" }
    elseif ($Level -eq "STEP") { $color = "Cyan" }
    elseif ($Level -eq "DIFF") { $color = "Magenta" }
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $color
    $logLine = "$line`n"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    [System.IO.File]::AppendAllText($LogFile, $logLine, $utf8Bom)
}

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

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Weekly Cursor Config Update  v1.0" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRYRUN] Preview mode - no files written" -ForegroundColor Yellow
    Write-Host ""
}

Write-Log "Period: $WeekStart ~ $WeekEnd" -Level "STEP"
Write-Log "Output: $OutputFile" -Level "STEP"

# Step 1: Read weekly reports
Write-Log "Step 1/6: Reading weekly reports..." -Level "STEP"
$weeklyReports = @()
$weekReports = Get-ChildItem $OutputPath -Filter "skill-intelligence-*.md" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
foreach ($report in $weekReports) {
    if ($report.LastWriteTime -ge (Get-Date).AddDays(-7)) {
        $content = Get-Content $report.FullName -Raw -Encoding UTF8
        $weeklyReports += @{ file = $report.Name; date = $report.LastWriteTime.ToString('yyyy-MM-dd'); content = $content }
    }
}
Write-Log "Weekly reports: $($weeklyReports.Count)" -Level "PASS"

# Step 2: Analyze trends
Write-Log "Step 2/6: Analyzing trends..." -Level "STEP"
$allTools = @{}
$allTopics = @{}
foreach ($report in $weeklyReports) {
    $content = $report.content
    $toolMatches = [regex]::Matches($content, '(?:^###\s+(.+?)$|(?<=\*\*).+?(?=\*\*))', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $toolMatches) {
        $tool = $m.Groups[1].Value.Trim()
        if ($tool.Length -gt 2 -and $tool.Length -lt 100) {
            if (-not $allTools.ContainsKey($tool)) { $allTools[$tool] = 0 }
            $allTools[$tool]++
        }
    }
    $topicMatches = [regex]::Matches($content, '#\w+', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $topicMatches) {
        $topic = $m.Value
        if (-not $allTopics.ContainsKey($topic)) { $allTopics[$topic] = 0 }
        $allTopics[$topic]++
    }
}
$topTools = $allTools.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
$topTopics = $allTopics.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
Write-Log "Top tools: $($topTools.Count)" -Level "PASS"

# Step 3: Read existing baselines.json
Write-Log "Step 3/6: Reading baselines.json..." -Level "STEP"
$oldBaselines = $null
if (Test-Path $BaselinesFile) {
    try {
        $jsonContent = Get-Content $BaselinesFile -Raw -Encoding UTF8
        $oldBaselines = $jsonContent | ConvertFrom-Json
        Write-Log "baselines.json read OK" -Level "PASS"
    } catch {
        Write-Log "baselines.json parse failed: $($_.Exception.Message)" -Level "WARN"
    }
}

# Step 4: Generate new baselines snapshot
Write-Log "Step 4/6: Generating baselines snapshot..." -Level "STEP"
$newBaselines = @{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    machine = $env:COMPUTERNAME
    scripts = @{}
    skills = @{}
    rules = @{}
    weeklyTools = @()
    weeklyTopics = @()
}

$scriptsDir = Join-Path $RepoRoot "scripts"
if (Test-Path $scriptsDir) {
    Get-ChildItem $scriptsDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $relPath = $_.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.scripts[$relPath] = Get-FileMd5 $_.FullName
    }
}
$skillsDir = Join-Path $RepoRoot "skills"
if (Test-Path $skillsDir) {
    Get-ChildItem $skillsDir -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $relPath = $_.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.skills[$relPath] = Get-FileMd5 $_.FullName
    }
}
$rulesDir = Join-Path $RepoRoot ".cursor\rules"
if (Test-Path $rulesDir) {
    Get-ChildItem $rulesDir -Filter "*.mdc" -ErrorAction SilentlyContinue | ForEach-Object {
        $relPath = $_.FullName.Replace($RepoRoot, "").TrimStart("\")
        $newBaselines.rules[$relPath] = Get-FileMd5 $_.FullName
    }
}
foreach ($t in $topTools) {
    $newBaselines.weeklyTools += @{ name = $t.Key; appearances = $t.Value }
}
foreach ($t in $topTopics) {
    $newBaselines.weeklyTopics += @{ tag = $t.Key; appearances = $t.Value }
}
Write-Log "Scripts:$($newBaselines.scripts.Count) Skills:$($newBaselines.skills.Count) Rules:$($newBaselines.rules.Count)" -Level "PASS"

# Step 5: Change detection
Write-Log "Step 5/6: Detecting changes..." -Level "STEP"
$changes = @{
    newScripts=@(); modifiedScripts=@()
    newSkills=@(); modifiedSkills=@()
    newRules=@(); modifiedRules=@()
    deletedScripts=@(); deletedSkills=@(); deletedRules=@()
}

if ($oldBaselines -and $oldBaselines.scripts) {
    $oldMap = @{}
    $oldBaselines.scripts.PSObject.Properties | ForEach-Object { $oldMap[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.scripts.Keys) {
        if (-not $oldMap.ContainsKey($key)) { $changes.newScripts += $key }
        elseif ($oldMap[$key] -ne $newBaselines.scripts[$key]) { $changes.modifiedScripts += $key }
    }
    foreach ($key in $oldMap.Keys) {
        if (-not $newBaselines.scripts.ContainsKey($key)) { $changes.deletedScripts += $key }
    }
}
if ($oldBaselines -and $oldBaselines.skills) {
    $oldMap = @{}
    $oldBaselines.skills.PSObject.Properties | ForEach-Object { $oldMap[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.skills.Keys) {
        if (-not $oldMap.ContainsKey($key)) { $changes.newSkills += $key }
        elseif ($oldMap[$key] -ne $newBaselines.skills[$key]) { $changes.modifiedSkills += $key }
    }
    foreach ($key in $oldMap.Keys) {
        if (-not $newBaselines.skills.ContainsKey($key)) { $changes.deletedSkills += $key }
    }
}
if ($oldBaselines -and $oldBaselines.rules) {
    $oldMap = @{}
    $oldBaselines.rules.PSObject.Properties | ForEach-Object { $oldMap[$_.Name] = $_.Value }
    foreach ($key in $newBaselines.rules.Keys) {
        if (-not $oldMap.ContainsKey($key)) { $changes.newRules += $key }
        elseif ($oldMap[$key] -ne $newBaselines.rules[$key]) { $changes.modifiedRules += $key }
    }
    foreach ($key in $oldMap.Keys) {
        if (-not $newBaselines.rules.ContainsKey($key)) { $changes.deletedRules += $key }
    }
}

$totalChanges = $changes.newScripts.Count + $changes.modifiedScripts.Count +
                 $changes.newSkills.Count + $changes.modifiedSkills.Count +
                 $changes.newRules.Count + $changes.modifiedRules.Count +
                 $changes.deletedScripts.Count + $changes.deletedSkills.Count + $changes.deletedRules.Count

$changeSummary = "Changes: new=$($changes.newScripts.Count+$changes.newSkills.Count+$changes.newRules.Count) mod=$($changes.modifiedScripts.Count+$changes.modifiedSkills.Count+$changes.modifiedRules.Count) del=$($changes.deletedScripts.Count+$changes.deletedSkills.Count+$changes.deletedRules.Count)"
Write-Log $changeSummary -Level "STEP"

if ($totalChanges -gt 0) {
    Write-Log "=== Diff Details ===" -Level "DIFF"
    foreach ($c in $changes.newScripts) { Write-Log "  + Script: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedScripts) { Write-Log "  ~ Script: $c" -Level "DIFF" }
    foreach ($c in $changes.newSkills) { Write-Log "  + Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedSkills) { Write-Log "  ~ Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.newRules) { Write-Log "  + Rule: $c" -Level "DIFF" }
    foreach ($c in $changes.modifiedRules) { Write-Log "  ~ Rule: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedScripts) { Write-Log "  - Script: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedSkills) { Write-Log "  - Skill: $c" -Level "DIFF" }
    foreach ($c in $changes.deletedRules) { Write-Log "  - Rule: $c" -Level "DIFF" }
}

# Step 6: Write baselines.json
if ($DryRun) {
    Write-Log "[DryRun] Skip baselines.json write" -Level "WARN"
} else {
    Write-Log "Step 6/6: Writing baselines.json..." -Level "STEP"
    try {
        $newJson = $newBaselines | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($BaselinesFile, $newJson, $utf8Bom)
        Write-Log "baselines.json updated" -Level "PASS"
    } catch {
        Write-Log "baselines.json write failed: $($_.Exception.Message)" -Level "FAIL"
    }
}

# Step 7: Generate weekly report
Write-Log "Generating weekly report..." -Level "STEP"

$nl = "`n"

# Tools table
$toolsTableLines = ""
foreach ($t in $topTools) {
    $barLen = [Math]::Min($t.Value, 7)
    $bar = [string]::Join("", (@("#") * $barLen))
    $toolsTableLines += [string]::Format("| {0} | {1} | {2} |{3}", $bar, $t.Key, $t.Value, $nl)
}

# Topics table
$topicsTableLines = ""
foreach ($t in $topTopics) {
    $topicsTableLines += [string]::Format("| {0} | {1} |{2}", $t.Key, $t.Value, $nl)
}

# Stats
$statsLines = "| Type | Count |" + $nl + "|---|---:|" + $nl
$statsLines += [string]::Format("| Scripts | {0} |{1}", $newBaselines.scripts.Count, $nl)
$statsLines += [string]::Format("| Skills | {0} |{1}", $newBaselines.skills.Count, $nl)
$statsLines += [string]::Format("| Rules | {0} |{1}", $newBaselines.rules.Count, $nl)
$statsLines += [string]::Format("| Weekly Reports | {0} |{1}", $weeklyReports.Count, $nl)

# Changes log
$changesLogLines = ""
if ($totalChanges -eq 0) {
    $changesLogLines = "**No config changes this week** - all Scripts/Skills/Rules up to date"
} else {
    if ($changes.newScripts.Count -gt 0) { $changesLogLines += "$nl- New Scripts: " + ($changes.newScripts -join ', ') }
    if ($changes.modifiedScripts.Count -gt 0) { $changesLogLines += "$nl- Modified Scripts: " + ($changes.modifiedScripts -join ', ') }
    if ($changes.newSkills.Count -gt 0) { $changesLogLines += "$nl- New Skills: " + ($changes.newSkills -join ', ') }
    if ($changes.modifiedSkills.Count -gt 0) { $changesLogLines += "$nl- Modified Skills: " + ($changes.modifiedSkills -join ', ') }
    if ($changes.newRules.Count -gt 0) { $changesLogLines += "$nl- New Rules: " + ($changes.newRules -join ', ') }
    if ($changes.modifiedRules.Count -gt 0) { $changesLogLines += "$nl- Modified Rules: " + ($changes.modifiedRules -join ', ') }
    if ($changes.deletedScripts.Count -gt 0) { $changesLogLines += "$nl- Deleted Scripts: " + ($changes.deletedScripts -join ', ') }
    if ($changes.deletedSkills.Count -gt 0) { $changesLogLines += "$nl- Deleted Skills: " + ($changes.deletedSkills -join ', ') }
    if ($changes.deletedRules.Count -gt 0) { $changesLogLines += "$nl- Deleted Rules: " + ($changes.deletedRules -join ', ') }
}

# Active skills
$skillsList = ($newBaselines.skills.Keys | Select-Object -First 5 | ForEach-Object { "- $_" }) -join $nl

# Suggestions
$suggestions = ""
foreach ($t in ($topTools | Select-Object -First 3)) {
    $suggestions += "- **$($t.Key)** - appeared $($t.Value) times this week, worth testing" + $nl
}

$top0Key = if ($topTools.Count -gt 0) { $topTools[0].Key } else { "No data" }
$top0Val = if ($topTools.Count -gt 0) { $topTools[0].Value } else { 0 }
$generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# Build report
$reportContent = "# Weekly Cursor Config Report $WeekStr" + $nl
$reportContent += "Period $WeekStart ~ $WeekEnd - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')" + $nl + $nl
$reportContent += "> **Overview**: $($topTools.Count) trending tools - $totalChanges config changes" + $nl
$reportContent += "> **Top trend**: $top0Key (appeared $top0Val times)" + $nl + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Config Snapshot" + $nl + $nl
$reportContent += $statsLines + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Top 10 Trending Tools" + $nl + $nl
$reportContent += "| Trend | Tool | Appearances |" + $nl + "|---|---|---:|" + $nl
$reportContent += $toolsTableLines + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Top 10 Topic Tags" + $nl + $nl
$reportContent += "| Tag | Appearances |" + $nl + "|---|---:|" + $nl
$reportContent += $topicsTableLines + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Config Change Log" + $nl + $nl
$reportContent += $changesLogLines + $nl + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Skills Assessment" + $nl + $nl
$reportContent += "### Active Skills" + $nl + $nl
$reportContent += $skillsList + $nl + $nl
$reportContent += "### Suggested Tools to Test" + $nl + $nl
$reportContent += $suggestions + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## Next Week Recommendations" + $nl + $nl
$reportContent += "1. **Track $top0Key** - hottest tool this week, schedule testing" + $nl
$reportContent += "2. **Update $($changes.modifiedRules.Count) changed Rules** - match latest project needs" + $nl
$reportContent += "3. **Add $($changes.newSkills.Count) new Skills** - discovered via weekly intelligence" + $nl + $nl
$reportContent += "---" + $nl + $nl
$reportContent += "## baselines.json Status" + $nl + $nl
$reportContent += "- Updated: $generatedAt" + $nl
$reportContent += "- Machine: $($newBaselines.machine)" + $nl
$reportContent += "- Scripts hashes: $($newBaselines.scripts.Count)" + $nl
$reportContent += "- Skills hashes: $($newBaselines.skills.Count)" + $nl
$reportContent += "- Rules hashes: $($newBaselines.rules.Count)" + $nl + $nl
$reportContent += "---" + $nl
$reportContent += "<sub>Cursor Config Weekly Report - $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')</sub>" + $nl

if (-not $DryRun) {
    try {
        [System.IO.File]::WriteAllText($OutputFile, $reportContent, $utf8Bom)
        Write-Log "Report saved: $OutputFile" -Level "PASS"
    } catch {
        Write-Log "Report save failed: $($_.Exception.Message)" -Level "FAIL"
    }
}

# Step 8: Push to Feishu
if (-not $SkipPush) {
    Write-Log "Pushing to Feishu..." -Level "STEP"
    $pushSuccess = $false
    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            $pushContent = $reportContent
            if ($pushContent.Length -gt 1800) {
                $pushContent = $reportContent.Substring(0, 1800) + "$nl$nl_(truncated, full report in local file)_"
            }
            $body = @{
                msg_type = "interactive"
                card = @{
                    header = @{
                        title = @{ tag = "plain_text"; content = "Cursor Config Weekly $WeekStr" }
                        template = "orange"
                    }
                    elements = @(@{ tag = "markdown"; content = $pushContent })
                }
            } | ConvertTo-Json -Depth 10 -Compress
            $response = Invoke-RestMethod -Uri $webhook -Method Post -Body $body `
                -ContentType "application/json; charset=utf-8" -TimeoutSec 15
            if ($response -and $response.code -eq 0) {
                Write-Log "Feishu push OK" -Level "PASS"
                $pushSuccess = $true
            }
        } catch {
            Write-Log "Feishu push failed: $($_.Exception.Message)" -Level "WARN"
        }
    }
    if (-not $pushSuccess) {
        Write-Log "Feishu push failed (non-fatal, report saved)" -Level "WARN"
    }
}

$totalElapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Done" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Report: $OutputFile" -ForegroundColor White
if (-not $DryRun) {
    Write-Host "  baselines: $BaselinesFile" -ForegroundColor White
}
Write-Host "  Changes: $totalChanges" -ForegroundColor $(if ($totalChanges -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Time: $($totalElapsed.TotalSeconds.ToString('0.0'))s" -ForegroundColor Gray
Write-Host ""
exit 0
