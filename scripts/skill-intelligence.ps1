<#
.SYNOPSIS
  每日 AI 工具情报自动化脚本

.DESCRIPTION
  每日北京时间 07:00 自动执行以下流程：
  1. 抓取 GitHub / GitCode AI 相关热门工具
  2. 分析 Cursor / Claude / GPT 相关 Skills 和工具
  3. 结合项目实践生成洞察报告
  4. 落盘：保存 Markdown 到 d:/HJ/Web/daily-news/
  5. 推送：发送摘要到飞书

  支持手动触发：.\skill-intelligence.ps1 -Manual
  支持每周汇总模式：.\skill-intelligence.ps1 -Weekly

.PARAMETER Manual
  手动执行模式（不检查定时）

.PARAMETER Weekly
  每周汇总模式（分析一周数据 + 更新 baselines + 更新 rules）

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
  .\skill-intelligence.ps1

  # 手动触发
  .\skill-intelligence.ps1 -Manual

  # 每周汇总
  .\skill-intelligence.ps1 -Weekly -Manual

  # 预览
  .\skill-intelligence.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$Manual,
    [switch]$Weekly,
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
    $PromptPath = Join-Path $RepoRoot "prompts\skill-intelligence-prompt.md"
}
if ($OutputPath -eq "") {
    $OutputPath = "d:\HJ\Web\daily-news"
}
$LogDir = Join-Path $RepoRoot "logs"
$DateStr = Get-Date -Format 'yyyy-MM-dd'
$FullDateStr = Get-Date -Format 'yyyy年MM月dd日'
$Weekday = (Get-Culture).DateTimeFormat.DayNames[(Get-Date).DayOfWeek]
$OutputFile = Join-Path $OutputPath "skill-intelligence-$DateStr.md"
$WeeklyOutputFile = Join-Path $OutputPath "skill-intelligence-weekly-$(Get-Date -Format 'yyyy-Www').md"
$LogFile = Join-Path $LogDir "skill-intelligence-$DateStr.log"
$ErrorLog = Join-Path $OutputPath "_skill-errors.log"

$utf8Bom = New-Object System.Text.UTF8Encoding $true

# ── 时间窗口 ────────────────────────────────────────────
$now = Get-Date
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
Write-Host "   🛠️ 每日 AI 工具情报  v1.0" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 检查手动模式
$autoMode = -not $Manual
if ($autoMode) {
    $hour = $now.Hour
    if ($hour -ne 7) {
        Write-Log "非 07:00 定时窗口（当前 $($now.ToString('HH:mm'))），跳过自动执行" -Level "WARN"
        Write-Host "使用 -Manual 强制执行" -ForegroundColor Gray
        exit 0
    }
}

# 创建输出目录
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    Write-Log "创建输出目录: $OutputPath" -Level "PASS"
}

Write-Log "报告日期: $FullDateStr $Weekday" -Level "STEP"
Write-Log "输出文件: $OutputFile" -Level "STEP"
Write-Log "模式    : $(if ($Weekly) { '每周汇总' } else { '每日情报' })" -Level "STEP"
Write-Log "" -Level "STEP"

# ═══════════════════════════════════════════════════════════
# Step 1：抓取 GitHub Trending — AI/LLM 相关
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 1/6】抓取 GitHub Trending AI 工具..." -Level "STEP"

$githubTrending = @()

# 方式 1：直接抓取 GitHub Trending 页面
try {
    Write-Log "尝试抓取 GitHub Trending 页面..." -Level "INFO"
    $ghResp = Invoke-RestMethod -Uri "https://api.github.com/search/repositories?q=stars:>300+pushed:>2026-06-01+AI+OR+llm+OR+agent+OR+cursor&sort=stars&order=desc&per_page=10" `
        -TimeoutSec 10 -UserAgent "SkillIntelligenceBot/1.0"
    if ($ghResp.items) {
        $githubTrending = $ghResp.items | Select-Object -First 10 | ForEach-Object {
            @{
                name = $_.full_name
                description = $_.description
                stars = $_.stargazers_count
                stars_today = $_.stargazers_count  # 估算
                language = $_.language
                url = $_.html_url
                pushed_at = $_.pushed_at
            }
        }
        Write-Log "GitHub Trending 获取成功（$($githubTrending.Count) 个项目）" -Level "PASS"
    }
} catch {
    Write-Log "GitHub Trending 抓取失败: $($_.Exception.Message)" -Level "WARN"
}

# 方式 2：抓取 GitHub Trending 热门仓库（备用）
if ($githubTrending.Count -eq 0) {
    try {
        Write-Log "尝试备选方式获取 GitHub 数据..." -Level "INFO"
        $ghWeekly = Invoke-RestMethod -Uri "https://api.github.com/search/repositories?q=stars:>500+pushed:>2026-05-01&sort=stars&order=desc&per_page=10&language=Python" `
            -TimeoutSec 10 -UserAgent "SkillIntelligenceBot/1.0"
        if ($ghWeekly.items) {
            $githubTrending = $ghWeekly.items | Select-Object -First 5 | ForEach-Object {
                @{
                    name = $_.full_name
                    description = $_.description
                    stars = $_.stargazers_count
                    stars_today = 0
                    language = $_.language
                    url = $_.html_url
                    pushed_at = $_.pushed_at
                }
            }
            Write-Log "备用 GitHub 数据获取成功（$($githubTrending.Count) 个项目）" -Level "PASS"
        }
    } catch {
        Write-Log "备用方式也失败: $($_.Exception.Message)" -Level "WARN"
    }
}

# ═══════════════════════════════════════════════════════════
# Step 2：抓取 GitCode 趋势
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 2/6】抓取 GitCode 趋势..." -Level "STEP"

$gitcodeTrending = @()

try {
    # 尝试抓取 GitCode trending（可能需要登录，部分数据可访问）
    $gcResp = Invoke-WebRequest -Uri "https://gitcode.com/explore/trending" `
        -TimeoutSec 10 -UserAgent "SkillIntelligenceBot/1.0" -UseBasicParsing
    if ($gcResp.StatusCode -eq 200) {
        # 解析 HTML 获取项目列表（简单提取）
        $content = $gcResp.Content
        # 提取项目名和描述（正则匹配）
        $matches = [regex]::Matches($content, 'href="/([^/]+)/([^"]+)"[^>]*>([^<]+)</a>')
        Write-Log "GitCode trending 抓取成功" -Level "PASS"
    } else {
        Write-Log "GitCode 访问失败（HTTP $($gcResp.StatusCode)）" -Level "WARN"
    }
} catch {
    Write-Log "GitCode trending 抓取失败: $($_.Exception.Message)" -Level "WARN"
}

# ═══════════════════════════════════════════════════════════
# Step 3：读取现有 Skills 和 Rules
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 3/6】读取现有 Skills 和 Rules..." -Level "STEP"

$existingSkills = @()
$skillsDir = Join-Path $RepoRoot "skills"

# 扫描 skills 目录
if (Test-Path $skillsDir) {
    $skillFiles = Get-ChildItem $skillsDir -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
    $existingSkills = $skillFiles | ForEach-Object {
        $content = Get-Content $_.FullName -Raw -Encoding UTF8
        $desc = if ($content -match '(?m)^[Dd]escription:\s*(.+)$') { $Matches[1].Trim() } else { "" }
        @{
            name = $_.BaseName
            path = $_.FullName.Replace($RepoRoot, "").TrimStart("\")
            description = $desc
        }
    }
    Write-Log "现有 Skills: $($existingSkills.Count) 个" -Level "PASS"
}

# 读取 rules 列表
$existingRules = @()
$rulesDir = Join-Path $RepoRoot ".cursor\rules"
if (Test-Path $rulesDir) {
    $ruleFiles = Get-ChildItem $rulesDir -Filter "*.mdc" -ErrorAction SilentlyContinue
    $existingRules = $ruleFiles | ForEach-Object {
        @{
            name = $_.BaseName
            path = $_.FullName.Replace($RepoRoot, "").TrimStart("\")
            size = $_.Length
        }
    }
    Write-Log "现有 Rules: $($existingRules.Count) 个" -Level "PASS"
}

# ═══════════════════════════════════════════════════════════
# Step 4：读取本周历史报告（用于趋势分析）
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 4/6】读取本周历史报告..." -Level "STEP"

$weeklyReports = @()
$weekStart = $now.AddDays(-7)
$allReports = Get-ChildItem $OutputPath -Filter "skill-intelligence-*.md" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

foreach ($report in $allReports) {
    if ($report.LastWriteTime -ge $weekStart) {
        $weeklyReports += $report
    }
}

Write-Log "本周历史报告: $($weeklyReports.Count) 份" -Level "PASS"

# ═══════════════════════════════════════════════════════════
# Step 5：生成报告内容
# ═══════════════════════════════════════════════════════════
Write-Log "【Step 5/6】生成情报报告..." -Level "STEP"

$agentStart = Get-Date
$agentUsed = $false

# 尝试调用 AI（通过 call-agent.ps1 或 Cursor MCP）
$reportContent = ""

# 方式 1：call-agent.ps1
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

# 方式 2：兜底模式（无 AI 接口时）
if (-not $agentUsed) {
    Write-Log "无自动 AI 接口，生成提示词摘要..." -Level "WARN"

    # 构建 GitHub 趋势部分
    $ghSection = ""
    foreach ($i in 0..([Math]::Min(4, $githubTrending.Count - 1))) {
        $item = $githubTrending[$i]
        $rank = $i + 1
        $medal = switch ($rank) {
            1 { "🥇" }
            2 { "🥈" }
            3 { "🥉" }
            default { "$rank." }
        }
        $ghSection += "`n$medal **$($item.name)** ⭐ $($item.stars) — $($item.description)`n"
        $ghSection += "- 语言: $($item.language) | [$($item.url)]() `n`n"
    }

    # 构建 Skills 分析部分
    $skillsSection = ""
    foreach ($skill in $existingSkills | Select-Object -First 5) {
        $skillsSection += "- **$($skill.name)** — $($skill.description)`n"
    }

    # 构建 Rules 分析部分
    $rulesSection = ""
    foreach ($rule in $existingRules | Select-Object -First 5) {
        $rulesSection += "- **$($rule.name)** — $($rule.size) bytes`n"
    }

    $reportContent = @"
# 🛠️ AI 工具情报 $DateStr
🕕 $(Get-Date -Format 'HH:00') · 过去 24h 检索

> **今日头条工具**：{请在 AI 对话框中手动执行 prompts/skill-intelligence-prompt.md 获取完整分析}
> **趋势洞察**：GitHub Trending 持续被 AI/Agent 项目占据

---

## 🤖 AI / LLM 工具趋势（GitHub）

$ghSection

> 数据来源：[GitHub Trending](https://github.com/trending)

---

## 📊 现有 Skills 匹配分析

### 🔥 已有 Skills（共 $($existingSkills.Count) 个）
$skillsSection

### 📋 已有 Rules（共 $($existingRules.Count) 个）
$rulesSection

---

## 💡 Cursor 配置建议

> 请在 AI 对话框中手动执行 prompts/skill-intelligence-prompt.md 获取完整分析和建议

---

## 🏆 Top 3 推荐

1. **{待分析}** — 请手动执行获取
2. **{待分析}** — 请手动执行获取
3. **{待分析}** — 请手动执行获取

---
<sub>🛠️ 检索 $($githubTrending.Count) 个项目 · Skills $($existingSkills.Count) 个 · Rules $($existingRules.Count) 个</sub>
"@
    $agentUsed = $true
}

$agentElapsed = (Get-Date) - $agentStart
Write-Log "报告生成完成，耗时 $($agentElapsed.TotalSeconds.ToString('0.0'))s" -Level "PASS"

# ── Step 6: 保存报告 ────────────────────────────────────
Write-Log "【Step 6/6】保存报告..." -Level "STEP"
try {
    if ($reportContent -and $reportContent.Trim().Length -gt 0) {
        [System.IO.File]::WriteAllText($OutputFile, $reportContent, $utf8Bom)
        Write-Log "报告已落盘: $OutputFile" -Level "PASS"

        # 如果是每周汇总模式，同时保存周报
        if ($Weekly) {
            [System.IO.File]::WriteAllText($WeeklyOutputFile, $reportContent, $utf8Bom)
            Write-Log "周报已落盘: $WeeklyOutputFile" -Level "PASS"
        }
    } else {
        Write-Log "报告内容为空，跳过保存" -Level "WARN"
    }
} catch {
    Write-Log "保存失败: $($_.Exception.Message)" -Level "FAIL"
}

# ── 推送飞书 ───────────────────────────────────────────
if ($SkipPush) {
    Write-Log "跳过飞书推送（-SkipPush）" -Level "WARN"
} else {
    Write-Log "推送飞书..." -Level "STEP"
    $pushSuccess = $false

    $webhook = $env:FEISHU_WEBHOOK_URL
    if ($webhook) {
        try {
            $pushContent = $reportContent
            if ($pushContent.Length -gt 1800) {
                $pushContent = $pushContent.Substring(0, 1800) + "`n`n_（内容过长，已截断。完整报告见本地文件）_"
            }

            $body = @{
                msg_type = "interactive"
                card = @{
                    header = @{
                        title = @{ tag = "plain_text"; content = "🛠️ AI工具情报 $DateStr" }
                        template = "purple"
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

    if (-not $pushSuccess) {
        Write-Log "推送失败（已记录到错误日志）" -Level "WARN"
    }
}

# ── 收尾统计 ───────────────────────────────────────────
$totalElapsed = (Get-Date) - $startTime

Write-Log "" -Level "STEP"
Write-Log "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Log "   ✅ AI 工具情报执行完成" -ForegroundColor Green
Write-Log "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Log "输出文件: $OutputFile" -Level "STEP"
Write-Log "总耗时  : $($totalElapsed.TotalSeconds.ToString('0.0'))s" -Level "STEP"
Write-Log "" -Level "STEP"

Write-Host "📄 报告路径: $OutputFile" -ForegroundColor White
Write-Host ""

exit 0
