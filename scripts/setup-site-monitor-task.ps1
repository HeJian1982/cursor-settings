<#
.SYNOPSIS
  设置网站健康巡检定时任务

.DESCRIPTION
  在 Windows Task Scheduler 注册每 30 分钟执行一次的网站监控任务。
  监控站点：hj1982.cn、1982.cn

  执行时会自动调用 site-monitor.ps1，输出到控制台。

.PARAMETER Action
  Register | Unregister | Show | Test

.PARAMETER Interval
  巡检间隔（分钟），默认 30

.PARAMETER UserContext
  SYSTEM（默认，需要管理员）或 $env:USERNAME（用户级）

.EXAMPLE
  .\setup-site-monitor-task.ps1 -Action Register
  .\setup-site-monitor-task.ps1 -Action Show
  .\setup-site-monitor-task.ps1 -Action Unregister
  .\setup-site-monitor-task.ps1 -Action Test
#>

[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Show', 'Test')]
    [string]$Action = 'Show',
    [int]$Interval = 30,
    [string]$UserContext = "SYSTEM"
)

$ErrorActionPreference = 'Stop'

$TaskName        = "HJ-Cursor-SiteMonitor"
$TaskDescription = "何健网站健康快检 — 每30分钟检测 hj1982.cn / 1982.cn"
$RepoRoot        = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptPath      = Join-Path $RepoRoot "scripts\site-monitor.ps1"
$LogDir          = Join-Path $RepoRoot "logs"

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

function Register-Task {
    param([int]$interval, [string]$user)

    if ($user -eq "SYSTEM" -and -not (Test-AdminPrivileges)) {
        Write-Host "[WARN] SYSTEM 级任务需要管理员权限" -ForegroundColor Yellow
        Write-Host "提示: 使用 -UserContext `$env:USERNAME 以当前用户身份注册（无需管理员）" -ForegroundColor Gray
        Write-Host ""
        throw "需要管理员权限"
    }

    if (-not (Test-Path $ScriptPath)) {
        throw "脚本不存在: $ScriptPath"
    }

    $psExe = Get-PowerShellExe

    # 每 X 分钟触发一次
    $trigger = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval ([TimeSpan]::FromMinutes($interval)) -RepetitionDuration ([TimeSpan]::MaxValue)

    $argStr = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $argStr

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -ExecutionTimeLimit ([TimeSpan]::FromMinutes(2)) `
        -Hidden:$true

    $logonType = if ($user -eq "SYSTEM") { "ServiceAccount" } else { "Password" }
    $principal = New-ScheduledTaskPrincipal `
        -UserId $user `
        -LogonType $logonType `
        -RunLevel Limited

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  [已移除旧任务]" -ForegroundColor Yellow
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description $TaskDescription `
        -Trigger $trigger `
        -Action $action `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null

    Write-Host ""
    Write-Host "[OK] 定时任务已注册" -ForegroundColor Green
    Write-Host ""
    Write-Host "  任务名称  : $TaskName" -ForegroundColor White
    Write-Host "  执行间隔  : 每 $interval 分钟" -ForegroundColor White
    Write-Host "  运行身份  : $user" -ForegroundColor White
    Write-Host "  脚本路径  : $ScriptPath" -ForegroundColor Gray
    Write-Host "  监控站点  : hj1982.cn, 1982.cn" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  日志文件  : $LogDir\site-monitor.log" -ForegroundColor Gray
    Write-Host "  状态文件  : memory\site-monitor\state.json" -ForegroundColor Gray
    Write-Host ""
}

function Show-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ""
        Write-Host "未找到定时任务: $TaskName" -ForegroundColor Yellow
        Write-Host "运行 .\setup-site-monitor-task.ps1 -Action Register 注册" -ForegroundColor Gray
        Write-Host ""
        return
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   🌐 网站健康巡检定时任务" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  任务名称  : $TaskName" -ForegroundColor White
    Write-Host "  状态      : $($task.State)" -ForegroundColor White
    Write-Host "  上次运行  : $($info.LastRunTime)" -ForegroundColor Gray
    Write-Host "  上次结果  : $($info.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  下次运行  : $($info.NextRunTime)" -ForegroundColor Gray
    Write-Host "  脚本路径  : $ScriptPath" -ForegroundColor Gray
    Write-Host ""

    # 显示最近日志
    $logFile = Join-Path $LogDir "site-monitor.log"
    if (Test-Path $logFile) {
        $lastLine = Get-Content $logFile -Tail 3
        Write-Host "  最近日志:" -ForegroundColor Yellow
        $lastLine | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        Write-Host ""
    }

    # 显示状态文件
    $stateFile = Join-Path $RepoRoot "memory\site-monitor\state.json"
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Host "  记忆状态:" -ForegroundColor Yellow
            if ($state.last_check) { Write-Host "    上次巡检: $($state.last_check)" -ForegroundColor Gray }
            if ($state.consecutive_failures -ne $null) { Write-Host "    连续失败: $($state.consecutive_failures) 次" -ForegroundColor $(if ($state.consecutive_failures -ge 3) { 'Red' } else { 'Gray' }) }
            if ($state.baseline_home_ms) { Write-Host "    首页基线: $($state.baseline_home_ms) ms" -ForegroundColor Gray }
            if ($state.baseline_api_ms) { Write-Host "    API基线: $($state.baseline_api_ms) ms" -ForegroundColor Gray }
            if ($state.prev_version) { Write-Host "    上个版本: $($state.prev_version)" -ForegroundColor Gray }
            Write-Host ""
        } catch { }
    }
}

function Unregister-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "已移除任务: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "任务不存在: $TaskName" -ForegroundColor Yellow
    }
}

function Test-Run {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   🧪 立即执行巡检（无定时）" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[FAIL] 脚本不存在: $ScriptPath" -ForegroundColor Red
        exit 1
    }

    $psExe = Get-PowerShellExe
    & $psExe -ExecutionPolicy Bypass -NoProfile -File $ScriptPath
    exit $LASTEXITCODE
}

# ── Main ────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   🌐 网站健康巡检任务管理  v1.0" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  操作      : $Action" -ForegroundColor Gray
Write-Host "  巡检间隔  : $Interval 分钟" -ForegroundColor Gray
Write-Host "  运行身份  : $UserContext" -ForegroundColor Gray
Write-Host "  监控站点  : hj1982.cn, 1982.cn" -ForegroundColor Gray
Write-Host ""

switch ($Action) {
    'Register'   { Register-Task -interval $Interval -user $UserContext }
    'Show'      { Show-Task }
    'Unregister'{ Unregister-Task }
    'Test'      { Test-Run }
}
