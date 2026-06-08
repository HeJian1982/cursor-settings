<#
.SYNOPSIS
  统一管理所有定时任务

.DESCRIPTION
  在 Windows Task Scheduler 中一次性注册/查看/移除三个任务：

  1. HJ-Cursor-DailyOptimize     — 每日 07:30，工作区优化
  2. HJ-Cursor-SiteMonitor       — 每 30 分钟，网站健康巡检
  3. HJ-Cursor-DailyIntelligence  — 每日 06:00，情报日报
  4. HJ-Cursor-TrendingInspect — 每日 08:00，GitHub+GitCode 热榜巡检
  5. HJ-Cursor-SkillHealth    — 每周日 09:00，Skill 健康检查

  使用 schtasks.exe + chcp 65001 避免编码问题。

.PARAMETER Action
  Register | Unregister | Show | Test | TestAll

.PARAMETER Task
  Optimize | Monitor | Intelligence | All（默认 All）

.PARAMETER UserContext
  SYSTEM 或 $env:USERNAME（默认当前用户）

.EXAMPLE
  .\setup-all-tasks.ps1 -Action Register
  .\setup-all-tasks.ps1 -Action Show
  .\setup-all-tasks.ps1 -Action Test -Task Monitor
#>

[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Show', 'Test', 'TestAll')]
    [string]$Action = 'Show',

    [ValidateSet('Optimize', 'Monitor', 'Intelligence', 'Trending', 'SkillHealth', 'All')]
    [string]$Task = 'All',

    [string]$UserContext = ""
)

$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ── 任务定义 ───────────────────────────────────────────
$tasks = [ordered]@{
    Optimize = @{
        Name        = "HJ-Cursor-DailyOptimize"
        Desc        = "Cursor workspace daily optimization"
        Script      = Join-Path $RepoRoot "scripts\daily-optimize.ps1"
        Schedule    = "daily"
        Time        = "07:30"
        Interval    = 0
    }
    Monitor = @{
        Name        = "HJ-Cursor-SiteMonitor"
        Desc        = "Site health check: hj1982.cn / 1982.cn every 30min"
        Script      = Join-Path $RepoRoot "scripts\site-monitor.ps1"
        Schedule    = "minute"
        Time        = $null
        Interval    = 30
    }
    Intelligence = @{
        Name        = "HJ-Cursor-DailyIntelligence"
        Desc        = "Daily intelligence report: AI retrieval + Feishu push"
        Script      = Join-Path $RepoRoot "scripts\daily-intelligence.ps1"
        Schedule    = "daily"
        Time        = "06:00"
        Interval    = 0
    }
    Trending = @{
        Name        = "HJ-Cursor-TrendingInspect"
        Desc        = "Daily GitHub + GitCode Trending inspection, Feishu push"
        Script      = Join-Path $RepoRoot "scripts\trending-inspect.ps1"
        Schedule    = "daily"
        Time        = "08:00"
        Interval    = 0
    }
    SkillHealth = @{
        Name        = "HJ-Cursor-SkillHealth"
        Desc        = "Weekly skill health check: broken links, missing files, disk usage"
        Script      = Join-Path $RepoRoot "scripts\skill-health-check.ps1"
        Schedule    = "weekly"
        Time        = "09:00"
        Interval    = 0
    }
}

$targetKeys = if ($Task -eq 'All') { $tasks.Keys } else { @($Task) }

# ── schtasks 注册（chcp 65001 防乱码）──────────────────
function Register-SchtasksTask {
    param($t, $runAs)
    $currentUser = [Environment]::UserName
    $targetUser = if ([string]::IsNullOrWhiteSpace($runAs)) { $currentUser } else { $runAs }

    # Remove old task
    $delBat = @"
schtasks /Delete /TN "$($t.Name)" /F
"@
    $delBatPath = Join-Path $env:TEMP "sched_del_$([guid]::NewGuid().ToString('N')).bat"
    [System.IO.File]::WriteAllText($delBatPath, $delBat, [System.Text.Encoding]::UTF8)
    $p = Start-Process cmd -ArgumentList "/c",$delBatPath -NoNewWindow -Wait -PassThru
    Remove-Item $delBatPath -Force -EA SilentlyContinue

    # Build task command
    $psExe = "powershell.exe"
    $argStr = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$($t.Script)`""
    $taskCmd = "$psExe $argStr"

    # Trigger
    if ($t.Schedule -eq "daily") {
        $triggerArg = "/SC DAILY /ST $($t.Time)"
    } elseif ($t.Schedule -eq "weekly") {
        $triggerArg = "/SC WEEKLY /D SUN /ST $($t.Time)"
    } else {
        $triggerArg = "/SC MINUTE /MO $($t.Interval)"
    }

    # User context
    if ($targetUser -eq "SYSTEM") {
        $runAsArg = "/RU SYSTEM"
    } elseif ($targetUser -ne $currentUser) {
        Write-Output "SKIP|$($t.Name)|user_mismatch|$targetUser vs $currentUser"
        return
    } else {
        # Current user: schtasks defaults to current user without /RU
        $runAsArg = ""
    }

    $regBat = "schtasks /Create /TN `"$($t.Name)`" /TR `"$taskCmd`" $triggerArg $runAsArg /F`n"
    $regBatPath = Join-Path $env:TEMP "sched_reg_$([guid]::NewGuid().ToString('N')).bat"
    # Write WITHOUT BOM (cmd.exe cannot parse UTF-8 BOM)
    $noBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($regBatPath, $regBat, $noBom)

    $p = Start-Process cmd -ArgumentList "/c",$regBatPath -NoNewWindow -Wait -PassThru
    $exit = $p.ExitCode
    Remove-Item $regBatPath -Force -EA SilentlyContinue

    if ($exit -eq 0) {
        $runStr = if ($targetUser -eq "SYSTEM") { "SYSTEM" } else { "current_user" }
        Write-Output "OK|$($t.Name)|$($t.Schedule)|$runStr"
    } else {
        Write-Output "FAIL|$($t.Name)|exit=$exit"
    }
}

function Remove-SchtasksTask {
    param($t)
    $noBom = New-Object System.Text.UTF8Encoding $false
    $delBat = "schtasks /Delete /TN `"$($t.Name)`" /F`n"
    $delBatPath = Join-Path $env:TEMP "sched_del_$([guid]::NewGuid().ToString('N')).bat"
    [System.IO.File]::WriteAllText($delBatPath, $delBat, $noBom)
    $p = Start-Process cmd -ArgumentList "/c",$delBatPath -NoNewWindow -Wait -PassThru
    Remove-Item $delBatPath -Force -EA SilentlyContinue
    Write-Output "REMOVED|$($t.Name)"
}

# ── Main ────────────────────────────────────────────────
switch ($Action) {
    'Register' {
        foreach ($key in $targetKeys) {
            $t = $tasks[$key]
            $result = Register-SchtasksTask -t $t -runAs $UserContext
            $parts = $result -split '\|'
            $status = $parts[0]
            $name = $parts[1]
            $detail = if ($parts[2]) { $parts[2] } else { "" }

            if ($status -eq "OK") {
                $emoji = @{ Optimize = "OPTI"; Monitor = "MON"; Intelligence = "INTL"; Trending = "TREND"; SkillHealth = "HLTH" }[$key]
                Write-Host "$emoji OK | $name | $detail" -ForegroundColor Green
            } elseif ($status -eq "SKIP_USER") {
                Write-Host "SKIP | $name | requires password: $detail" -ForegroundColor Yellow
            } else {
                Write-Host "FAIL | $name | $detail" -ForegroundColor Red
            }
        }
    }
    'Unregister' {
        foreach ($key in $targetKeys) {
            $t = $tasks[$key]
            Remove-SchtasksTask -t $t
            Write-Host "OK | Removed: $($t.Name)" -ForegroundColor Green
        }
    }
    'Show' {
        Write-Host ""
        Write-Host "=== Task Status ===" -ForegroundColor Cyan
        Write-Host ""
        foreach ($key in $tasks.Keys) {
            $t = $tasks[$key]
            $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($existing) {
                $info = Get-ScheduledTaskInfo -TaskName $t.Name -ErrorAction SilentlyContinue
                $stateColor = switch ($existing.State) {
                    "Ready"   { "Green" }
                    "Running" { "Yellow" }
                    default   { "Red" }
                }
                Write-Host "[$($existing.State)] $($t.Name)" -ForegroundColor $stateColor
                Write-Host "  LastRun : $($info.LastRunTime)" -ForegroundColor Gray
                Write-Host "  NextRun : $($info.NextRunTime)" -ForegroundColor Gray
            } else {
                Write-Host "[NOT_REGISTERED] $($t.Name)" -ForegroundColor Red
            }
            Write-Host ""
        }
        # Recent log
        $logFile = Join-Path $RepoRoot "logs\scheduled-tasks.log"
        if (Test-Path $logFile) {
            Write-Host "Recent registrations:" -ForegroundColor Cyan
            Get-Content $logFile -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
        Write-Host ""
    }
    'Test' {
        foreach ($key in $targetKeys) {
            $t = $tasks[$key]
            Write-Host "Testing: $($t.Name)" -ForegroundColor Cyan
            if (Test-Path $t.Script) {
                powershell -ExecutionPolicy Bypass -NoProfile -File $t.Script
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host "  PASS" -ForegroundColor Green
                } else {
                    Write-Host "  FAIL (exit $LASTEXITCODE)" -ForegroundColor Red
                }
            } else {
                Write-Host "  SKIP (script not found)" -ForegroundColor Yellow
            }
            Write-Host ""
        }
    }
    'TestAll' {
        foreach ($key in $tasks.Keys) {
            $t = $tasks[$key]
            Write-Host "Testing: $($t.Name)" -ForegroundColor Cyan
            if (Test-Path $t.Script) {
                powershell -ExecutionPolicy Bypass -NoProfile -File $t.Script
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Host "  PASS" -ForegroundColor Green
                } else {
                    Write-Host "  FAIL (exit $LASTEXITCODE)" -ForegroundColor Red
                }
            } else {
                Write-Host "  SKIP (script not found)" -ForegroundColor Yellow
            }
            Write-Host ""
        }
    }
}
