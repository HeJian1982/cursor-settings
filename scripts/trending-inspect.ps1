# ============================================================
# HJ-Cursor 热榜巡检脚本 v1.1
# 每日 08:00 执行：抓 GitHub 趋势，评估价值，有高价值项目推飞书
# GitCode 无公开 API，降级为手动查看
# ============================================================
[CmdletBinding()]
param(
    [switch]$Manual,
    [switch]$SkipPush
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$OutputPath = Join-Path $RepoRoot "logs\trending"
$StateFile = Join-Path $OutputPath "_seen_projects.json"
$ReportFile = Join-Path $OutputPath "trending-$(Get-Date -Format 'yyyy-MM-dd').json"
$utf8Bom = New-Object System.Text.UTF8Encoding $true

$now = Get-Date
$startTime = Get-Date

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = @{ PASS = "Green"; FAIL = "Red"; WARN = "Yellow"; STEP = "Cyan"; INFO = "White" }[$Level]
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
}
Write-Log "=== 热榜巡检 v1.1 ===" -Level "STEP"

$seen = @{}
if (Test-Path $StateFile) {
    try {
        $seen = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        Write-Log "已加载基线: $($seen.Count) 个项目" -Level "PASS"
    } catch {
        Write-Log "基线加载失败: $($_.Exception.Message)" -Level "WARN"
    }
}

# GitHub: 用搜索 API（最近一周内创建的热门项目）
Write-Log "[1/2] GitHub Trending (API)..." -Level "STEP"
$ghProjects = @()
try {
    $daysAgo = 7
    $apiUrl = "https://api.github.com/search/repositories?q=created:>$($now.AddDays(-$daysAgo).ToString('yyyy-MM-dd'))+stars:>50&sort=stars&order=desc&per_page=15&type=Repositories"
    $ghResp = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 12 -Headers @{ UserAgent = "DailyTrendingBot/1.0" }
    if ($ghResp.items) {
        foreach ($item in $ghResp.items) {
            $ghProjects += @{
                owner = $item.owner.login
                repo = $item.name
                fullName = $item.full_name
                description = $item.description
                stars = $item.stargazers_count
                language = $item.language
                source = "github"
                url = $item.html_url
                created = $item.created_at
            }
        }
    }
    Write-Log "GitHub: $($ghProjects.Count) 个项目" -Level "PASS"
} catch {
    Write-Log "GitHub API 失败: $($_.Exception.Message)" -Level "FAIL"
}

# GitCode: 无公开 API，尝试 JS 渲染后页面（AtomGit API）
Write-Log "[2/2] GitCode Trending..." -Level "STEP"
$gcProjects = @()
try {
    $gcUrl = "https://api.atomgit.com/trending/repos?limit=10&period=day"
    $gcResp = Invoke-RestMethod -Uri $gcUrl -TimeoutSec 10 -Headers @{ UserAgent = "DailyTrendingBot/1.0" }
    if ($gcResp.data) {
        foreach ($item in $gcResp.data) {
            $gcProjects += @{
                owner = $item.namespace
                repo = $item.name
                fullName = "$($item.namespace)/$($item.name)"
                description = $item.description
                stars = $item.star_count
                language = ""
                source = "gitcode"
                url = $item.url
            }
        }
        Write-Log "GitCode: $($gcProjects.Count) 个项目" -Level "PASS"
    }
} catch {
    Write-Log "GitCode 无公开 API (AtomGit: 404)，跳过" -Level "WARN"
}

# 对比基线
Write-Log "对比基线..." -Level "STEP"
$allNew = @()
$allSeenKeys = @{}
foreach ($p in $ghProjects) {
    $key = "gh:$($p.fullName)"
    $allSeenKeys[$key] = $true
    if (-not $seen.ContainsKey($key)) { $p.isNew = $true; $allNew += $p }
}
foreach ($p in $gcProjects) {
    $key = "gc:$($p.fullName)"
    $allSeenKeys[$key] = $true
    if (-not $seen.ContainsKey($key)) { $p.isNew = $true; $allNew += $p }
}

# 更新基线
$newSeen = @{}
foreach ($k in $allSeenKeys.Keys) { $newSeen[$k] = $true }
$kept = 0
foreach ($k in $seen.Keys) { if ($kept -lt 200) { $newSeen[$k] = $true; $kept++ } }
[System.IO.File]::WriteAllText($StateFile, ($newSeen | ConvertTo-Json -Depth 3), $utf8Bom)

# 价值评估
Write-Log "评估 $($allNew.Count) 个新增项目..." -Level "STEP"
$highKws = @("skill","agent","ai-agent","cursor","mcp","llm","rag","vector","knowledge-base","design-system","frontend","ui-component","motion","animation","hook","cli-tool","automation","open-source","productivity","workflow","knowledge-graph","rag","agentic","cursor-rules","cursor-skill")
$mediumKws = @("rust","golang","python","vscode","extension","typescript","react","next","svelte","vue","node")
$highValue = @(); $mediumValue = @(); $lowValue = @()
foreach ($p in $allNew) {
    $combined = "$($p.description) $($p.fullName) $($p.language)".ToLower()
    $score = 0
    foreach ($kw in $highKws) { if ($combined.Contains($kw)) { $score += 3 } }
    foreach ($kw in $mediumKws) { if ($combined.Contains($kw)) { $score += 1 } }
    $p | Add-Member -NotePropertyName "score" -NotePropertyValue $score -Force
    if ($score -ge 4) { $p | Add-Member -NotePropertyName "valueTier" -NotePropertyValue "high" -Force; $highValue += $p }
    elseif ($score -ge 2) { $p | Add-Member -NotePropertyName "valueTier" -NotePropertyValue "medium" -Force; $mediumValue += $p }
    else { $p | Add-Member -NotePropertyName "valueTier" -NotePropertyValue "low" -Force; $lowValue += $p }
}

# 报告落盘
$totalElapsed = (Get-Date) - $startTime
$report = @{
    generatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
    githubCount = $ghProjects.Count
    gitcodeCount = $gcProjects.Count
    newCount = $allNew.Count
    highValueCount = $highValue.Count
    newProjects = $allNew
    elapsedSeconds = [math]::Round($totalElapsed.TotalSeconds, 1)
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($ReportFile, $report, $utf8Bom)
Write-Log "报告落盘: $ReportFile" -Level "PASS"

# 飞书推送（有新增项目才推送）
if (-not $SkipPush -and $allNew.Count -gt 0) {
    Write-Log "飞书推送..." -Level "STEP"
    $summary = "GitHub + GitCode 热榜巡检`n$($now.ToString('MM月dd日 HH:mm'))`n抓取 $($ghProjects.Count) 个 | 新增 $($allNew.Count) 个 | 高价值 $($highValue.Count) 个`n`n"
    foreach ($p in $highValue) {
        $desc = $p.description
        if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 60) + "..." }
        if (-not $desc) { $desc = "无描述" }
        $stars = if ($p.stars) { " $($p.stars) stars" } else { "" }
        $summary += "★ $($p.fullName)$stars`n  $desc`n  $($p.url)`n`n"
    }
    if ($mediumValue.Count -gt 0 -and $highValue.Count -lt 3) {
        $summary += "中价值:`n"
        foreach ($p in ($mediumValue | Select-Object -First 3)) {
            $summary += "- $($p.fullName)`n"
        }
    }
    $summary += "`n⏱ $($totalElapsed.TotalSeconds.ToString('0.0'))s | 基线 $($seen.Count) -> $($newSeen.Count)"

    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            $body = @{ msg_type = "text"; content = @{ text = $summary } } | ConvertTo-Json -Depth 5 -Compress
            $resp = Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 10
            if ($resp.code -eq 0) { Write-Log "飞书推送成功" -Level "PASS" }
        } catch {
            Write-Log "飞书推送失败: $($_.Exception.Message)" -Level "WARN"
        }
    }
}

Write-Log ""
Write-Log "=== 完成 ===" -ForegroundColor Green
Write-Log "抓取: GitHub=$($ghProjects.Count) GitCode=$($gcProjects.Count)"
Write-Log "新增: $($allNew.Count) | 高:$($highValue.Count) 中:$($mediumValue.Count) 普通:$($lowValue.Count)"
Write-Log "耗时: $($totalElapsed.TotalSeconds.ToString('0.0'))s"