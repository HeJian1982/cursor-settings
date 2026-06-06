<#
.SYNOPSIS
  为每日情报日报设置 Windows 定时任务

.DESCRIPTION
  在 Windows Task Scheduler 中注册每日 06:00 (北京时间) 自动执行
  daily-intelligence.ps1 的定时任务。

  每日北京时间 06:00 = UTC 前一天 22:00
  使用 Windows Task Scheduler 的 Daily 触发器，时间设为 06:00 即可（系统时区已为 CST）

  依赖：PowerShell 5.1+, Windows Task Scheduler

.PARAMETER Action
  Register | Unregister | Show | Test

.PARAMETER Time
  每日执行时间，HH:mm 格式，默认 06:00

.PARAMETER UserContext
  SYSTEM（默认，system 级最高权限）
  或 $env:USERNAME（当前用户，用户级）

.PARAMETER RunNow
  注册后立即执行一次（测试用）

.EXAMPLE
  # 注册每日 06:00 定时任务（系统级）
  .\setup-daily-intelligence-task.ps1 -Action Register

  # 用户级注册
  .\setup-daily-intelligence-task.ps1 -Action Register -UserContext $env:USERNAME

  # 自定义时间
  .\setup-daily-intelligence-task.ps1 -Action Register -Time 06:30

  # 注册并立即测试
  .\setup-daily-intelligence-task.ps1 -Action Register -RunNow

  # 查看状态
  .\setup-daily-intelligence-task.ps1 -Action Show

  # 移除任务
  .\setup-daily-intelligence-task.ps1 -Action Unregister

  # 仅测试执行（不注册）
  .\setup-daily-intelligence-task.ps1 -Action Test
#>

[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Show', 'Test')]
    [string]$Action = 'Show',
    [string]$Time = "06:00",
    [string]$UserContext = "SYSTEM",
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$TaskName        = "HJ-Cursor-DailyIntelligence"
$TaskDescription = "何健 每日情报日报 — AI 检索 + Markdown 落盘 + 飞书推送"
$RepoRoot        = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptPath      = Join-Path $RepoRoot "scripts\daily-intelligence.ps1"
$LogDir          = Join-Path $RepoRoot "logs"

# ── 辅助函数 ──────────────────────────────────────────────
function Get-PowerShellExe {
    $psCore = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($psCore) { return $psCore.Source }
    $psDesk = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($psDesk) { return $psDesk.Source }
    throw "No PowerShell found on this system"
}

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ScriptMd5 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    $bytes = $md5.ComputeHash($stream)
    $stream.Close()
    $md5.Dispose()
    return [BitConverter]::ToString($bytes) -replace '-', ''
}

# ── 任务注册 ──────────────────────────────────────────────
function Register-Task {
    param([string]$runTime, [string]$user, [bool]$runNow)

    # 权限检查
    if ($user -eq "SYSTEM") {
        if (-not (Test-AdminPrivileges)) {
            Write-Host ""
            Write-Host "[WARN] SYSTEM 级任务需要管理员权限" -ForegroundColor Yellow
            Write-Host "提示: 使用 -UserContext `$env:USERNAME 以当前用户身份注册（无需管理员）" -ForegroundColor Gray
            Write-Host ""
            Write-Host "以管理员身份重新运行，或改用用户级注册：" -ForegroundColor Yellow
            Write-Host "  .\setup-daily-intelligence-task.ps1 -Action Register -UserContext `$env:USERNAME" -ForegroundColor Gray
            Write-Host ""
            throw "需要管理员权限"
        }
    }

    # 验证脚本
    if (-not (Test-Path $ScriptPath)) {
        throw "脚本不存在: $ScriptPath"
    }
    $scriptHash = Get-ScriptMd5 $ScriptPath
    Write-Host "  脚本哈希: $scriptHash" -ForegroundColor Gray

    # 验证输出目录
    $outDir = "d:\HJ\Web\daily-news"
    if (-not (Test-Path $outDir)) {
        Write-Host "  创建输出目录: $outDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }

    # PowerShell 路径
    $psExe = Get-PowerShellExe
    Write-Host "  PowerShell: $psExe" -ForegroundColor Gray

    # 触发器：每日一次
    $trigger = New-ScheduledTaskTrigger -Daily -At $runTime

    # 操作：执行脚本
    $argStr = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $argStr

    # 设置
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -ExecutionTimeLimit ([TimeSpan]::FromHours(1)) `
        -Hidden:$false

    # 主体
    $logonType = if ($user -eq "SYSTEM") { "ServiceAccount" } else { "Password" }
    $principal = New-ScheduledTaskPrincipal `
        -UserId $user `
        -LogonType $logonType `
        -RunLevel Limited

    # 注册前先移除同名任务
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
    Write-Host "  执行时间  : 每日 $runTime" -ForegroundColor White
    Write-Host "  运行身份  : $user" -ForegroundColor White
    Write-Host "  脚本路径  : $ScriptPath" -ForegroundColor Gray
    Write-Host "  输出目录  : $outDir" -ForegroundColor Gray
    Write-Host "  日志目录  : $LogDir" -ForegroundColor Gray
    Write-Host ""

    # 立即执行测试
    if ($runNow) {
        Write-Host "  [立即执行测试...]" -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 3
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($info.LastTaskResult -eq 0) {
            Write-Host "  [PASS] 测试执行已启动" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] 测试执行状态: $($info.LastTaskResult)" -ForegroundColor Yellow
        }
    }
}

# ── 任务状态 ─────────────────────────────────────────────
function Show-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ""
        Write-Host "未找到定时任务: $TaskName" -ForegroundColor Yellow
        Write-Host "运行 .\setup-daily-intelligence-task.ps1 -Action Register 注册" -ForegroundColor Gray
        Write-Host ""
        return
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   📰 每日情报日报定时任务" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  任务名称  : $TaskName" -ForegroundColor White
    Write-Host "  状态      : $($task.State)" -ForegroundColor White
    Write-Host "  上次运行  : $($info.LastRunTime)" -ForegroundColor Gray
    Write-Host "  上次结果  : $($info.LastTaskResult)" -ForegroundColor Gray
    Write-Host "  下次运行  : $($info.NextRunTime)" -ForegroundColor Gray
    Write-Host "  脚本路径  : $ScriptPath" -ForegroundColor Gray
    Write-Host ""

    $actions = $task.Actions | Select-Object -First 1
    Write-Host "  执行命令  : $($actions.Execute)" -ForegroundColor Gray
    Write-Host "  参数      : $($actions.Arguments)" -ForegroundColor Gray
    Write-Host ""

    # 显示近期日志
    $logFiles = Get-ChildItem $LogDir -Filter "daily-intelligence-*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($logFiles) {
        Write-Host "  近期日志:" -ForegroundColor Yellow
        foreach ($lf in $logFiles) {
            $sizeKB = [math]::Round($lf.Length / 1KB, 1)
            $age = ($now - $lf.LastWriteTime).TotalHours
            $ageStr = if ($age -lt 1) { "<1h前" } else { "$([int]$age)h前" }
            Write-Host ("    {0} ({1}KB, {2})" -f $lf.Name, $sizeKB, $ageStr) -ForegroundColor Gray
        }
        Write-Host ""
    }

    # 显示今日报告
    $todayReport = Join-Path "d:\HJ\Web\daily-news" "news-$(Get-Date -Format 'yyyy-MM-dd').md"
    if (Test-Path $todayReport) {
        $repAge = ($now - (Get-Item $todayReport).LastWriteTime).TotalHours
        $repAgeStr = if ($repAge -lt 1) { "<1h前" } else { "$([int]$repAge)h前" }
        Write-Host "  今日报告: ✅ 已生成（$repAgeStr）" -ForegroundColor Green
        Write-Host "    $todayReport" -ForegroundColor Gray
    } else {
        Write-Host "  今日报告: ⏳ 尚未生成（$($info.NextRunTime) 定时）" -ForegroundColor Yellow
    }
    Write-Host ""

    # 显示错误日志
    $errLog = "d:\HJ\Web\daily-news\_errors.log"
    if (Test-Path $errLog) {
        $recentErrs = Get-Content $errLog -Tail 3 -ErrorAction SilentlyContinue
        if ($recentErrs) {
            Write-Host "  近期错误:" -ForegroundColor Yellow
            $recentErrs | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            Write-Host ""
        }
    }
}

# ── 任务移除 ─────────────────────────────────────────────
function Unregister-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "任务不存在: $TaskName" -ForegroundColor Yellow
        return
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "已移除任务: $TaskName" -ForegroundColor Green
}

# ── 测试执行 ─────────────────────────────────────────────
function Test-Run {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   🧪 测试执行（无定时检查）" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[FAIL] 脚本不存在: $ScriptPath" -ForegroundColor Red
        exit 1
    }

    $psExe = Get-PowerShellExe
    Write-Host "执行: $psExe" -ForegroundColor Gray
    Write-Host "脚本: $ScriptPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[开始执行，输出如下...]" -ForegroundColor Yellow
    Write-Host ""

    & $psExe -ExecutionPolicy Bypass -NoProfile -File $ScriptPath -Manual
    exit $LASTEXITCODE
}

# ── 主流程 ───────────────────────────────────────────────
$now = Get-Date

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   📰 每日情报日报定时任务管理  v2.1" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  操作      : $Action" -ForegroundColor Gray
Write-Host "  执行时间  : $Time" -ForegroundColor Gray
Write-Host "  运行身份  : $UserContext" -ForegroundColor Gray
Write-Host "  脚本路径  : $ScriptPath" -ForegroundColor Gray
Write-Host ""

switch ($Action) {
    'Register' {
        # 时间格式验证
        if ($Time -notmatch '^\d{2}:\d{2}$') {
            Write-Host "[FAIL] 时间格式错误，请使用 HH:mm 格式（如 06:00）" -ForegroundColor Red
            exit 1
        }
        $hour, $minute = $Time -split ':'
        if ([int]$hour -gt 23 -or [int]$minute -gt 59) {
            Write-Host "[FAIL] 无效的时间值: $Time" -ForegroundColor Red
            exit 1
        }
        Register-Task -runTime $Time -user $UserContext -runNow $RunNow
    }
    'Show' {
        Show-Task
    }
    'Unregister' {
        Unregister-Task
    }
    'Test' {
        Test-Run
    }
}
