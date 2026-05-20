<#
.SYNOPSIS
  Setup Windows Task Scheduler for daily Cursor optimization

.DESCRIPTION
  Registers or removes a scheduled task that runs daily-optimize.ps1.
  Default schedule: 07:30 every day (before work starts)

  Must be run as Administrator for system-wide scheduling.
  Run as current user for user-level scheduling.

  Requires: PowerShell 5.1+, Windows Task Scheduler 2.0+

.PARAMETER Action
  Register (default) | Unregister | Show

.PARAMETER Time
  Daily run time in HH:mm format. Default: 07:30

.PARAMETER UserContext
  User to run under. Default: SYSTEM (highest privileges)
  Use current user for user-level scheduling.

.EXAMPLE
  # Register daily at 07:30 as SYSTEM
  .\setup-daily-task.ps1 -Action Register

  # Register at 09:00 as current user
  .\setup-daily-task.ps1 -Action Register -Time 09:00 -UserContext $env:USERNAME

  # Show current status
  .\setup-daily-task.ps1 -Action Show

  # Remove the scheduled task
  .\setup-daily-task.ps1 -Action Unregister
#>

[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Show')]
    [string]$Action = 'Show',
    [string]$Time = "07:30",
    [string]$UserContext = "SYSTEM"
)

$ErrorActionPreference = 'Stop'

$TaskName = "HJ-Cursor-DailyOptimize"
$TaskDescription = "何健 Cursor 工作区每日优化 — 运行测试、基线检查、配置同步"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ScriptPath = Join-Path $RepoRoot "scripts\daily-optimize.ps1"
$LogDir = Join-Path $RepoRoot "logs"

# Determine PowerShell path
$PsPath = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }

function Get-CdpExe {
    # Get powershell path with full extension for Task Scheduler
    $psCore = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($psCore) { return $psCore.Source }
    $psDesk = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($psDesk) { return $psDesk.Source }
    throw "No PowerShell found"
}

function Register-Task {
    param([string]$runTime, [string]$user)

    $psExe = Get-CdpExe
    $trigger = New-ScheduledTaskTrigger -Daily -At $runTime

    # Action: run the optimize script
    $argStr = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""

    $action = New-ScheduledTaskAction -Execute $psExe -Argument $argStr

    # Settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false `
        -ExecutionTimeLimit ([TimeSpan]::FromHours(1)) `
        -Hidden:$false

    # Principal
    $principal = New-ScheduledTaskPrincipal -UserId $user `
        -LogonType ServiceAccount -RunLevel Limited

    # Register
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[INFO] Removed existing task" -ForegroundColor Yellow
    }

    Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription `
        -Trigger $trigger -Action $action -Settings $settings -Principal $principal `
        -Force | Out-Null

    Write-Host "[OK] Scheduled task registered" -ForegroundColor Green
    Write-Host "  Task name   : $TaskName" -ForegroundColor Gray
    Write-Host "  Run time   : $runTime daily" -ForegroundColor Gray
    Write-Host "  User       : $user" -ForegroundColor Gray
    Write-Host "  Script     : $ScriptPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Logs will be written to: $LogDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Use .\setup-daily-task.ps1 -Action Show to verify" -ForegroundColor Cyan
}

function Show-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "Scheduled Task: $TaskName" -ForegroundColor Cyan
        Write-Host "  State     : $($task.State)" -ForegroundColor White
        Write-Host "  Last Run  : $($info.LastRunTime)" -ForegroundColor Gray
        Write-Host "  Last Result: $($info.LastTaskResult)" -ForegroundColor Gray
        Write-Host "  Next Run  : $($info.NextRunTime)" -ForegroundColor Gray
        Write-Host "  Script    : $ScriptPath" -ForegroundColor Gray
        Write-Host ""
        $actions = $task.Actions | Select-Object -First 1
        Write-Host "  Command   : $($actions.Execute)" -ForegroundColor Gray
        Write-Host "  Arguments : $($actions.Arguments)" -ForegroundColor Gray

        # Show recent logs
        $logFiles = Get-ChildItem $LogDir -Filter "daily-optimize-*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3
        if ($logFiles) {
            Write-Host ""
            Write-Host "Recent logs:" -ForegroundColor Yellow
            foreach ($lf in $logFiles) {
                Write-Host ("  {0} ({1:N0} bytes) {2}" -f $lf.Name, $lf.Length, $lf.LastWriteTime.ToString('MM-dd HH:mm')) -ForegroundColor Gray
            }
        }
    } else {
        Write-Host ""
        Write-Host "No scheduled task found: $TaskName" -ForegroundColor Yellow
        Write-Host "Run with -Action Register to create one" -ForegroundColor Gray
    }
    Write-Host ""
}

function Unregister-Task {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[OK] Scheduled task removed: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Task not found: $TaskName" -ForegroundColor Yellow
    }
}

# ── Main ────────────────────────────────────────────────────
Write-Host ""
Write-Host "===== Setup Daily Cursor Optimization Task =====" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor Gray
Write-Host ""

switch ($Action) {
    'Register' {
        # Validate time format
        if ($Time -notmatch '^\d{2}:\d{2}$') {
            Write-Host "[FAIL] Invalid time format. Use HH:mm (e.g. 07:30)" -ForegroundColor Red
            exit 1
        }
        $hour, $minute = $Time -split ':'
        if ([int]$hour -gt 23 -or [int]$minute -gt 59) {
            Write-Host "[FAIL] Invalid time value: $Time" -ForegroundColor Red
            exit 1
        }

        if (-not (Test-Path $ScriptPath)) {
            Write-Host "[FAIL] Script not found: $ScriptPath" -ForegroundColor Red
            exit 1
        }

        Write-Host "Registering task..." -ForegroundColor Yellow
        Register-Task -runTime $Time -user $UserContext
    }
    'Show' {
        Show-Task
    }
    'Unregister' {
        Write-Host "Removing task..." -ForegroundColor Yellow
        Unregister-Task
    }
}
