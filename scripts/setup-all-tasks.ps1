<#
.SYNOPSIS
  统一管理所有定时任务

.DESCRIPTION
  在 Windows Task Scheduler 中一次性注册/查看/移除三个任务：

  1. HJ-Cursor-DailyOptimize  — 每日 07:30，工作区优化
  2. HJ-Cursor-SiteMonitor    — 每 30 分钟，网站健康巡检<br>  3. HJ-Cursor-DailyIntelligence — 每日 06:00，情报日报<br>  4. HJ-Cursor-SkillIntelligence — 每日 17:00，AI工具情报<br>  5. HJ-Cursor-ConfigUpdater — 每周五 17:10，Cursor配置周报<br>  6. HJ-Cursor-SessionLogger — 每 30 分钟，Cursor对话入库

  也支持单独操作各任务（通过 -Task 指定）

.PARAMETER Action
  Register（默认）| Unregister | Show | Test | TestAll

.PARAMETER Task
  指定单个任务：Optimize | Monitor | Intelligence | SkillIntelligence | ConfigUpdater | All（默认 All）

.PARAMETER UserContext
  SYSTEM（默认，需管理员）或 $env:USERNAME（用户级，无需管理员）

.EXAMPLE
  # 一次性注册全部三个任务
  .\setup-all-tasks.ps1 -Action Register

  # 查看全部任务状态
  .\setup-all-tasks.ps1 -Action Show

  # 仅注册网站监控
  .\setup-all-tasks.ps1 -Action Register -Task Monitor

  # 测试网站监控
  .\setup-all-tasks.ps1 -Action Test -Task Monitor

  # 一次性移除全部
  .\setup-all-tasks.ps1 -Action Unregister
#>

[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Show', 'Test', 'TestAll')]
    [string]$Action = 'Show',

    [ValidateSet('Optimize', 'Monitor', 'Intelligence', 'SkillIntelligence', 'ConfigUpdater', 'SessionLogger', 'All')]
    [string]$Task = 'All',

    [string]$UserContext = ""
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ── 任务定义 ───────────────────────────────────────────
$tasks = @{
    Optimize = @{
        Name        = "HJ-Cursor-DailyOptimize"
        Description = "何健 Cursor 工作区每日优化 — 测试+基线+配置同步"
        Script      = Join-Path $RepoRoot "scripts\daily-optimize.ps1"
        Schedule    = "daily"
        Time        = "07:30"
        Interval    = $null
        Enabled     = $true
    }
    Monitor = @{
        Name        = "HJ-Cursor-SiteMonitor"
        Description = "何健网站健康巡检 — hj1982.cn/1982.cn 每30分钟"
        Script      = Join-Path $RepoRoot "scripts\site-monitor.ps1"
        Schedule    = "interval"
        Time        = $null
        Interval    = 30
        Enabled     = $true
    }
    Intelligence = @{
        Name        = "HJ-Cursor-DailyIntelligence"
        Description = "何健每日情报日报 — AI检索+落盘+飞书推送"
        Script      = Join-Path $RepoRoot "scripts\daily-intelligence.ps1"
        Schedule    = "daily"
        Time        = "06:00"
        Interval    = $null
        Enabled     = $true
    }
    SkillIntelligence = @{
        Name        = "HJ-Cursor-SkillIntelligence"
        Description = "何健每日AI工具情报 — 每日17:00，GitHub/GitCode+Skills分析+飞书推送"
        Script      = Join-Path $RepoRoot "scripts\skill-intelligence.ps1"
        Schedule    = "daily"
        Time        = "17:00"
        Interval    = $null
        Enabled     = $true
    }
    ConfigUpdater = @{
        Name        = "HJ-Cursor-ConfigUpdater"
        Description = "何健每周Cursor配置分析 — 每周五17:10，baselines更新+Rules优化+飞书报告"
        Script      = Join-Path $RepoRoot "scripts\cursor-config-updater.ps1"
        Schedule    = "weekly"
        Time        = "17:10"
        DayOfWeek   = "Friday"
        Interval    = $null
        Enabled     = $true
    }
    SessionLogger = @{
        Name        = "HJ-Cursor-SessionLogger"
        Description = "何健 Cursor 对话记录器 — 每30分钟扫描transcript并入库SQLite"
        Script      = Join-Path $RepoRoot "scripts\log-conversation.ps1"
        Schedule    = "interval"
        Time        = $null
        Interval    = 30
        Enabled     = $true
    }
}

# 筛选要操作的任务
$targetTasks = @{}
if ($Task -eq 'All') {
    $targetTasks = $tasks
} else {
    $targetTasks[$Task] = $tasks[$Task]
}

function Get-PowerShellExe {
    $psCore = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($psCore) { return $psCore.Source }
    $psDesk = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($psDesk) { return $psDesk.Source }
    throw "No PowerShell found"
}

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── 注册 ────────────────────────────────────────────────
function Register-Tasks {
    $runAs = if ([string]::IsNullOrWhiteSpace($UserContext)) { "SYSTEM" } else { $UserContext }
    $currentUser = [Environment]::UserName

    $registered = 0
    $skipped = 0

    foreach ($key in $targetTasks.Keys) {
        $t = $targetTasks[$key]
        Write-Host ""
        Write-Host "── $key ──" -ForegroundColor Cyan

        if (-not (Test-Path $t.Script)) {
            Write-Host "  [SKIP] 脚本不存在: $($t.Script)" -ForegroundColor Red
            $skipped++
            continue
        }

        # 移除旧任务
        $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
            Write-Host "  [移除旧任务] $($t.Name)" -ForegroundColor Yellow
        }

        # 构建 schtasks 命令（绕过 PowerShell 5.x Register-ScheduledTask -File 嵌套 bug）
        $psExe = "powershell.exe"
        $argStr = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$($t.Script)`""
        $taskCmd = "$psExe $argStr"

        # 触发器参数
        $scheduleType = $t.Schedule
        $extraArgs = ""

        if ($scheduleType -eq "daily") {
            $extraArgs = "/SC DAILY /ST $($t.Time)"
        } elseif ($scheduleType -eq "weekly") {
            $dayAbbr = switch ($t.DayOfWeek) {
                "Sunday"    { "SUN" }
                "Monday"    { "MON" }
                "Tuesday"   { "TUE" }
                "Wednesday" { "WED" }
                "Thursday"  { "THU" }
                "Friday"   { "FRI" }
                "Saturday"  { "SAT" }
                default     { "SUN" }
            }
            $extraArgs = "/SC WEEKLY /D $dayAbbr /ST $($t.Time)"
        } else {
            # interval: 每 N 分钟
            $extraArgs = "/SC MINUTE /MO $($t.Interval)"
        }

        # 运行身份
        if ($runAs -eq "SYSTEM") {
            $ruArg = "/RU SYSTEM"
        } else {
            $ruArg = "/RU $runAs"
        }

        # 执行 schtasks /Create
        $fullCmd = "schtasks /Create /TN `"$($t.Name)`" /TR `"$taskCmd`" $extraArgs $ruArg /F"
        Write-Host "  CMD: $fullCmd" -ForegroundColor Gray

        $output = cmd /c $fullCmd 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] 已注册: $($t.Name)" -ForegroundColor Green
            Write-Host "      计划: $(if ($scheduleType -eq 'daily') { "每日 $($t.Time)" } elseif ($scheduleType -eq 'weekly') { "每周 $($t.DayOfWeek) $($t.Time)" } else { "每$($t.Interval)分钟" })" -ForegroundColor White
            Write-Host "      身份: $runAs" -ForegroundColor Gray
            $registered++
        } else {
            Write-Host "  [FAIL] 注册失败: $($output.Substring(0, [Math]::Min(200, $output.Length)))" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "注册完成: $registered 成功, $skipped 跳过" -ForegroundColor $(if ($skipped -eq 0) { "Green" } else { "Yellow" })
}

# ── 状态 ───────────────────────────────────────────────
function Show-Tasks {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   全局定时任务管理器  v2.0" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  当前操作: $Action | 任务: $Task | 身份: $(if ([string]::IsNullOrWhiteSpace($UserContext)) { [Environment]::UserName } else { $UserContext })" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  ┌────────┬────────────────────────────────────────────────────┬────────────┐" -ForegroundColor Cyan
    Write-Host "  │ 任务    │ 名称                                               │ 计划       │" -ForegroundColor Cyan
    Write-Host "  ├────────┼────────────────────────────────────────────────────┼────────────┤" -ForegroundColor Cyan
    foreach ($key in $targetTasks.Keys) {
        $t = $targetTasks[$key]
        $emoji = switch ($key) {
            "Optimize"          { "🔧" }
            "Monitor"           { "🌐" }
            "Intelligence"      { "📰" }
            "SkillIntelligence" { "🛠️" }
            "ConfigUpdater"     { "🔄" }
            "SessionLogger"     { "💬" }
        }
        $schedule = switch ($t.Schedule) {
            "daily"   { "每日 $($t.Time)" }
            "weekly"  { "每周 $($t.DayOfWeek) $($t.Time)" }
            "interval" { "每$($t.Interval)min" }
        }
        $stateStr = ""
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) {
            $stateStr = $task.State
        }
        Write-Host "  │ $($emoji) $key │ $($t.Name) │ $($schedule) │" -ForegroundColor White
    }
    Write-Host "  └────────┴────────────────────────────────────────────────────┴────────────┘" -ForegroundColor Cyan
    Write-Host ""

    foreach ($key in $targetTasks.Keys) {
        $t = $targetTasks[$key]
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        $info = if ($task) { Get-ScheduledTaskInfo -TaskName $t.Name -ErrorAction SilentlyContinue } else { $null }

        $emoji = switch ($key) {
            "Optimize"          { "🔧" }
            "Monitor"           { "🌐" }
            "Intelligence"      { "📰" }
            "SkillIntelligence" { "🛠️" }
            "ConfigUpdater"     { "🔄" }
            "SessionLogger"     { "💬" }
        }

        Write-Host "$emoji $key — $($t.Name)" -ForegroundColor White
        if ($task) {
            $color = switch ($task.State) {
                "Ready"    { "Green" }
                "Running"  { "Yellow" }
                "Disabled" { "Red" }
                default    { "Gray" }
            }
            Write-Host "   状态    : $($task.State)" -ForegroundColor $color
            Write-Host "   上次运行: $($info.LastRunTime)" -ForegroundColor Gray
            Write-Host "   上次结果: $($info.LastTaskResult)" -ForegroundColor Gray
            Write-Host "   下次运行: $($info.NextRunTime)" -ForegroundColor Gray
            $actions = $task.Actions | Select-Object -First 1
            Write-Host "   脚本    : $($actions.Arguments -replace '.*-File "(.+?)".*', '$1')" -ForegroundColor Gray
        } else {
            Write-Host "   状态    : 未注册" -ForegroundColor Red
            Write-Host "   运行 .\setup-all-tasks.ps1 -Action Register 注册" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # 近期日志汇总
    $LogDir = Join-Path $RepoRoot "logs"
    $monitorLog = Join-Path $LogDir "site-monitor.log"
    $optimizeLog = Get-ChildItem $LogDir -Filter "daily-optimize-*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    Write-Host "最近日志:" -ForegroundColor Yellow
    if (Test-Path $monitorLog) {
        $mLast = Get-Content $monitorLog -Tail 1
        Write-Host "  🌐 Monitor: $($mLast.Substring(0, [Math]::Min(100, $mLast.Length)))" -ForegroundColor Gray
    }
    if ($optimizeLog) {
        Write-Host "  🔧 Optimize: $($optimizeLog.Name) — $($optimizeLog.LastWriteTime.ToString('MM-dd HH:mm'))" -ForegroundColor Gray
    }
    Write-Host ""
}

# ── 移除 ────────────────────────────────────────────────
function Unregister-Tasks {
    $removed = 0
    foreach ($key in $targetTasks.Keys) {
        $t = $targetTasks[$key]
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
            Write-Host "[移除] $($t.Name)" -ForegroundColor Green
            $removed++
        } else {
            Write-Host "[跳过] $($t.Name) 未注册" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "移除完成: $removed 个任务已移除" -ForegroundColor Green
}

# ── 测试 ───────────────────────────────────────────────
function Test-Tasks {
    foreach ($key in $targetTasks.Keys) {
        $t = $targetTasks[$key]
        Write-Host ""
        Write-Host "═══ 测试: $key ═══" -ForegroundColor Cyan

        if (-not (Test-Path $t.Script)) {
            Write-Host "[FAIL] 脚本不存在: $($t.Script)" -ForegroundColor Red
            continue
        }

        $psExe = Get-PowerShellExe
        & $psExe -ExecutionPolicy Bypass -NoProfile -File $t.Script
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Host "[PASS] $key 测试通过" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $key 测试失败 (exit $($LASTEXITCODE))" -ForegroundColor Red
        }
    }
}

function Test-All {
    foreach ($key in $tasks.Keys) {
        $t = $tasks[$key]
        Write-Host ""
        Write-Host "═══ 测试: $key ═══" -ForegroundColor Cyan
        if (-not (Test-Path $t.Script)) {
            Write-Host "[SKIP] 脚本不存在: $($t.Script)" -ForegroundColor Yellow
            continue
        }
        $psExe = Get-PowerShellExe
        & $psExe -ExecutionPolicy Bypass -NoProfile -File $t.Script
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Host "[PASS] $key" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] $key (exit $($LASTEXITCODE))" -ForegroundColor Red
        }
    }
}

# ── Main ────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   全局定时任务管理器  v2.0" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

switch ($Action) {
    'Register'  { Register-Tasks }
    'Show'      { Show-Tasks }
    'Unregister'{ Unregister-Tasks }
    'Test'      { Test-Tasks }
    'TestAll'   { Test-All }
}
