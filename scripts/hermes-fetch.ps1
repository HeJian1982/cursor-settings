<#
hj-cursor / hermes-agent one-shot fetcher

Goal:
  Fill the ~0.5% promisor-remote blobs missing in
  subprojects\repos-from-external\agent\hermes-agent
  (5,073 files already on disk; only a few Tauri installer submodules left).

Design notes:
  - No infinite retry. Last job burned 10min on 5 short retries and never
    hit the threshold because the partial check counted BEFORE checkout.
  - git gc is the actual cause of the noisy "unable to unlink .idx"
    warnings (AV/OneDrive holds the .idx). Fetch uses --no-tags to avoid
    triggering gc as often.
  - Designed to run in the background; exit code is always 0 unless the
    repo path doesn't exist.

Usage:
  .\hermes-fetch.ps1              # 1 attempt, 60s per fetch
  .\hermes-fetch.ps1 -Attempts 3  # 3 attempts
#>
[CmdletBinding()]
param(
    [int]$Attempts = 1,
    [int]$PerAttemptSec = 60,
    [string]$Remote = 'origin',
    [string]$Branch = 'main',
    [switch]$Reset  # if set, run `git reset --hard origin/$Branch` after fetch
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$RepoDir = Join-Path $Root 'subprojects\repos-from-external\agent\hermes-agent'
$LogDir = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'hermes-fetch.log'

# Force UTF-8 across the board so the rest of the file stays ASCII-clean
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $RepoDir)) {
    Write-Host "[hermes-fetch] repo not found: $RepoDir" -ForegroundColor Red
    exit 1
}

function Write-Log {
    param([string]$Level, [string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'
    $line = "[$ts] [$Level] $Msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

Write-Log 'INFO' "start; repo=$RepoDir attempts=$Attempts perAttemptSec=$PerAttemptSec"

# Slow-connection tolerance for fetches that hang on TLS renegotiation
$env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
$env:GIT_HTTP_LOW_SPEED_TIME  = '30'

Push-Location $RepoDir
try {
    $head = git rev-parse HEAD 2>$null
    Write-Log 'INFO' "current HEAD: $head"

    for ($i = 1; $i -le $Attempts; $i++) {
        Write-Log 'INFO' "=== attempt $i / $Attempts ==="

        # Run the fetch in a background job with an explicit working directory
        # (PS 5.1 does NOT inherit cwd from Push-Location across jobs).
        $fetchJob = Start-Job -ScriptBlock {
            param($r, $b, $repoDir)
            $env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
            $env:GIT_HTTP_LOW_SPEED_TIME  = '30'
            Set-Location $repoDir
            # protocol v2 + no tags (tags cost half the time last fetch)
            git -c protocol.version=2 -c http.postBuffer=524288000 `
                fetch --no-tags --filter=blob:none $r $b 2>&1
        } -ArgumentList $Remote, $Branch, $RepoDir

        $fetchOk = $false
        if (Wait-Job $fetchJob -Timeout $PerAttemptSec) {
            $out = Receive-Job $fetchJob
            Write-Log 'INFO' ("fetch output: " + ($out -join "`n"))
            $fetchOk = $true
        } else {
            Stop-Job $fetchJob
            Write-Log 'WARN' ("fetch timeout after " + $PerAttemptSec + "s; killed")
        }
        Remove-Job $fetchJob -Force

        if (-not $fetchOk) { continue }

        # Checkout in another background job (its own timeout)
        $coJob = Start-Job -ScriptBlock {
            param($repoDir, $branch, $doReset)
            Set-Location $repoDir
            # Default: just materialize the working tree from the current HEAD.
            # With -Reset: also move HEAD to origin/$branch.
            if ($doReset) {
                git reset --hard "origin/$branch" 2>&1
            } else {
                git checkout -f HEAD -- . 2>&1
            }
        } -ArgumentList $RepoDir, $Branch, [bool]$Reset
        if (Wait-Job $coJob -Timeout 30) {
            $coOut = Receive-Job $coJob
            $badLines = @($coOut | Where-Object { $_ -match '^(error|fatal|warning):' })
            if ($badLines.Count -gt 0) {
                $tag = if ($Reset) { 'reset' } else { 'checkout' }
                Write-Log 'WARN' ("$tag issues: " + ($badLines -join ' | '))
            } else {
                $tag = if ($Reset) { 'reset' } else { 'checkout' }
                Write-Log 'INFO' ("$tag clean")
            }
        } else {
            Stop-Job $coJob
            Write-Log 'WARN' 'checkout/reset timeout 30s; killed'
        }
        Remove-Job $coJob -Force
    }

    $fileCount = (Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object { $_.FullName -notmatch '\.git' }).Count
    $headAfter = git rev-parse HEAD 2>$null
    Write-Log 'INFO' ("final: HEAD=" + $headAfter + " files=" + $fileCount)
} finally {
    Pop-Location
}

Write-Log 'INFO' 'done'
exit 0
