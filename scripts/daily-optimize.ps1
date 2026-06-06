<#
.SYNOPSIS
  Daily Cursor workspace optimization orchestrator

.DESCRIPTION
  Runs all optimization and health checks in one pass:

  1. Pull latest local configs  -> sync-local-configs.ps1
  2. Site health check         -> site-monitor.ps1 (hj1982.cn / 1982.cn)
  3. Run full test suite       -> run-tests.ps1
  4. Re-generate baselines      -> generate-baselines.ps1
  5. Run test suite again      -> run-tests.ps1 (post-baseline)
  6. Git commit (if dirty)     -> only if files changed
  7. Git push (if remote)      -> only if remote exists

  Designed for both interactive use and Task Scheduler automation.
  Logs everything to a local run record.

.PARAMETER DryRun
  Preview all steps without writing or committing

.PARAMETER SkipCommit
  Skip git commit/push step (useful for review)

.PARAMETER LogPath
  Path to the run log file. Default: logs/daily-optimize-<date>.log

.EXAMPLE
  .\daily-optimize.ps1
  .\daily-optimize.ps1 -DryRun
  .\daily-optimize.ps1 -SkipCommit
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipCommit,
    [string]$LogPath = ""
)

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$LogDir = Join-Path $RepoRoot "logs"

if ($LogPath -eq "") {
    $dateStr = Get-Date -Format 'yyyy-MM-dd'
    $LogPath = Join-Path $LogDir "daily-optimize-$dateStr.log"
}

$utf8Bom = New-Object System.Text.UTF8Encoding $true

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        "PASS"  { "Green" }
        "FAIL"  { "Red" }
        "WARN"  { "Yellow" }
        "STEP"  { "Cyan" }
        default { "White" }
    }
    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $color
    $logLine = "$line`n"
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    [System.IO.File]::AppendAllText($LogPath, $logLine, $utf8Bom)
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    Write-Log $Name -Level "STEP"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $ScriptBlock
        $sw.Stop()
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Log "$Name failed (exit $LASTEXITCODE) in $($sw.Elapsed.TotalSeconds)s" -Level "FAIL"
            return $false
        }
        Write-Log "$Name OK in $($sw.Elapsed.TotalSeconds)s" -Level "PASS"
        return $true
    } catch {
        $sw.Stop()
        Write-Log "$Name ERROR: $($_.Exception.Message) in $($sw.Elapsed.TotalSeconds)s" -Level "FAIL"
        return $false
    }
}

# ── Header ───────────────────────────────────────────────────
$dateFull = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Log "=== Daily Cursor Optimization ===" -Level "STEP"
Write-Log "Date    : $dateFull" -Level "STEP"
Write-Log "DryRun  : $DryRun" -Level "STEP"
Write-Log "RepoRoot: $RepoRoot" -Level "STEP"
Write-Log "Log     : $LogPath" -Level "STEP"
Write-Log "" -Level "STEP"

$steps = @()
$results = @{}

# ── Step 1: Pull local configs ──────────────────────────────
$steps += @{
    Name = "Pull local configs"
    ScriptBlock = {
        if ($DryRun) {
            powershell -ExecutionPolicy Bypass -File "$RepoRoot\scripts\sync-local-configs.ps1" -DryRun 2>&1 | Out-Null
        } else {
            powershell -ExecutionPolicy Bypass -File "$RepoRoot\scripts\sync-local-configs.ps1" -Direction Pull 2>&1 | Out-Null
        }
        return $true
    }
}

# ── Step 2: Site health check ───────────────────────────
$steps += @{
    Name = "Site health check (hj1982.cn / 1982.cn)"
    ScriptBlock = {
        powershell -ExecutionPolicy Bypass -File "$RepoRoot\scripts\site-monitor.ps1" 2>&1 | Out-String
        # site-monitor.ps1 输出到控制台和日志，不影响主流程
        # exit code 0 始终成功（正常/劣化/失败都算执行完成）
        return $true
    }
}

# ── Step 3: Run test suite ────────────────────────────────
$steps += @{
    Name = "Run test suite (baseline check)"
    ScriptBlock = {
        if ($DryRun) {
            powershell -ExecutionPolicy Bypass -File "$RepoRoot\tests\run-tests.ps1" 2>&1 | Out-String
            return $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null
        } else {
            powershell -ExecutionPolicy Bypass -File "$RepoRoot\tests\run-tests.ps1" 2>&1 | Out-String
            return $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null
        }
    }
}

# ── Step 4: Re-generate baselines ──────────────────────────
$steps += @{
    Name = "Re-generate baselines"
    ScriptBlock = {
        powershell -ExecutionPolicy Bypass -File "$RepoRoot\scripts\generate-baselines.ps1" 2>&1 | Out-Null
        return $true
    }
}

# ── Step 5: Run test suite again (post-baseline) ──────────
$steps += @{
    Name = "Run test suite (post-baseline)"
    ScriptBlock = {
        powershell -ExecutionPolicy Bypass -File "$RepoRoot\tests\run-tests.ps1" 2>&1 | Out-String
        return $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null
    }
}

# ── Execute steps ────────────────────────────────────────────
$passed = 0
$failed = 0
foreach ($step in $steps) {
    $ok = Invoke-Step -Name $step.Name -ScriptBlock $step.ScriptBlock
    $results[$step.Name] = $ok
    if ($ok) { $passed++ } else { $failed++ }
}

# ── Step 5: Git commit ──────────────────────────────────────
$gitDirty = $false
if (-not $SkipCommit) {
    Write-Log "Checking git status..." -Level "STEP"
    $status = powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git status --porcelain" 2>&1
    $statusText = $status | Out-String
    if ($statusText.Trim().Length -gt 0) {
        $gitDirty = $true
        Write-Log "Git dirty: changes detected" -Level "WARN"

        if ($DryRun) {
            Write-Log "Git commit [SKIPPED - DryRun]" -Level "WARN"
        } else {
            $addedFiles = $status | Where-Object { $_ -match '^\?\?|^\AM|^M ' } | ForEach-Object { $_.Substring(3).Trim() }
            $changedFiles = $status | Where-Object { $_ -match '^[ M]' -and $_ -notmatch '^\?\?' } | ForEach-Object { $_.Substring(3).Trim() }
            $allFiles = @($addedFiles) + @($changedFiles) | Select-Object -Unique

            $commitMsg = @"
chore: daily optimization $(Get-Date -Format 'yyyy-MM-dd')

Automated changes:
$(($allFiles | ForEach-Object { "- $_" }) -join "`n")

Ran by: daily-optimize.ps1
"@

            try {
                powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git add -A" 2>&1 | Out-Null
                powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git commit -m `$commitMsg" 2>&1 | Out-Null
                $commitOutput = powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git log -1 --format='%H %s'" 2>&1
                $commitText = $commitOutput | Out-String
                Write-Log "Git committed: $($commitText.Trim())" -Level "PASS"

                # Try push
                $remoteCheck = powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git remote get-url origin 2>`$null" 2>&1
                if ($remoteCheck) {
                    powershell -ExecutionPolicy Bypass -Command "cd '$RepoRoot'; git push 2>&1" | Out-Null
                    Write-Log "Git pushed to origin" -Level "PASS"
                }
            } catch {
                Write-Log "Git commit/push failed: $($_.Exception.Message)" -Level "FAIL"
            }
        }
    } else {
        Write-Log "Git clean, nothing to commit" -Level "PASS"
    }
}

# ── Summary ─────────────────────────────────────────────────
Write-Log "" -Level "STEP"
Write-Log "=== Summary ===" -Level "STEP"
Write-Log "Steps passed: $passed / $($steps.Count)" -Level $(if ($passed -eq $steps.Count) { "PASS" } else { "WARN" })
Write-Log "Git dirty  : $gitDirty" -Level "STEP"
Write-Log "Log file  : $LogPath" -Level "STEP"
Write-Log "" -Level "STEP"

$overall = ($failed -eq 0)
if ($overall) {
    Write-Log "ALL STEPS PASSED" -Level "PASS"
    exit 0
} else {
    Write-Log "SOME STEPS FAILED" -Level "FAIL"
    exit 1
}
