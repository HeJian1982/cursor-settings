# Copyright (c) 2026 何健 (He Jian)
# Cursor Conversation Logger — Parse Cursor agent transcript JSONL files,
#   write structured session data to SQLite (Python sqlite3) or JSON fallback.
param(
    [switch]$Sync,
    [int]$RecentHours = 0,
    [string]$SessionId = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

$script:LOG_DIR  = "e:\HJ\cursor\logs"
$script:PYTHON   = "python"
$script:ENGINE   = "e:\HJ\cursor\scripts\_cursor_log_engine.py"
$script:LOG_FILE = Join-Path $script:LOG_DIR ("conversation-log-" + (Get-Date -Format "yyyy-MM-dd") + ".log")

# --- Init log dir ---
if (-not (Test-Path $script:LOG_DIR)) {
    New-Item -ItemType Directory -Path $script:LOG_DIR -Force | Out-Null
}

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Msg"
    Write-Host $line
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::AppendAllText($script:LOG_FILE, $line + [Environment]::NewLine, $utf8NoBom)
}

# --- Pre-flight: Python engine exists ---
if (-not (Test-Path $script:ENGINE)) {
    Write-Log "Python engine not found: $script:ENGINE" "ERROR"
    return $null
}

Write-Log "Starting conversation logger..."
Write-Log "  Engine     : $script:ENGINE"
Write-Log "  Mode       : $(if($Sync){'Sync'}elseif($SessionId){'SessionId='+$SessionId}elseif($RecentHours -gt 0){'RecentHours='+$RecentHours}else{'Full'})"
if ($DryRun) { Write-Log "  DryRun     : ENABLED" }

# --- Build argument list ---
$argList = @($script:ENGINE)
if ($Sync)            { $argList += "--sync" }
if ($RecentHours -gt 0) {
    $argList += "--recent-hours"
    $argList += $RecentHours.ToString()
}
if ($SessionId -ne "") {
    $argList += "--session-id"
    $argList += $SessionId
}
if ($DryRun)          { $argList += "--dry-run" }

# --- Run Python engine ---
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $script:PYTHON
$psi.Arguments              = $argList -join " "
$psi.UseShellExecute        = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow         = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

$proc   = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
$exitCode = $proc.ExitCode

# --- Parse structured output ---
$useJson  = $false
$stats    = $null
$pyErrors = @()
foreach ($line in ($stdout -split [Environment]::NewLine)) {
    if ($line.StartsWith("JSON_STORE=")) {
        $useJson = ($line.Substring(11) -eq "True")
    } elseif ($line.StartsWith("STATS=")) {
        try {
            $stats = $line.Substring(6) | ConvertFrom-Json
        } catch {
            try {
                $stats = [System.Web.Script.Serialization.JavaScriptSerializer]::new() | % { $_.Deserialize($line.Substring(6), [type][object]) }
            } catch {}
        }
    } elseif ($line.StartsWith("ERRORS=")) {
        try {
            $pyErrors = ($line.Substring(6) | ConvertFrom-Json)
        } catch {}
    } elseif ($line.StartsWith("  DRYRUN:")) {
        Write-Log $line "DRYRUN"
    }
}

if ($stderr -and $stderr.Trim()) {
    Write-Log ("Python stderr: " + $stderr.Trim()) "WARN"
}

if ($exitCode -ne 0 -and -not $DryRun) {
    Write-Log ("Python exited with code: " + $exitCode) "ERROR"
}

# --- Summary ---
if ($DryRun) {
    Write-Log "DRYRUN complete — run without -DryRun to write data." "INFO"
} else {
    if ($stats) {
        $s = $stats
        $ses = if ($s.sessions) { $s.sessions } else { 0 }
        $msg = if ($s.messages) { $s.messages } else { 0 }
        $fq  = if ($s.first_queries) { $s.first_queries } else { 0 }
        $sk  = if ($s.skipped) { $s.skipped } else { 0 }
        Write-Log ("Summary: $ses sessions | $msg messages | $fq first queries | $sk skipped (sync)") "INFO"
    }
    $storage = if ($useJson) { "JSON (SQLite unavailable on this system)" } else { "SQLite" }
    Write-Log ("Storage engine: $storage") "INFO"
}

if ($pyErrors -and $pyErrors.Count -gt 0) {
    foreach ($e in $pyErrors) {
        Write-Log ("Parse error: $e") "WARN"
    }
}

# --- Structured return object ---
$script:result = @{
    Storage      = if ($useJson) { "JSON" } else { "SQLite" }
    Sessions     = if ($stats -and $stats.sessions) { $stats.sessions } else { 0 }
    Messages     = if ($stats -and $stats.messages) { $stats.messages } else { 0 }
    FirstQueries = if ($stats -and $stats.first_queries) { $stats.first_queries } else { 0 }
    Skipped      = if ($stats -and $stats.skipped) { $stats.skipped } else { 0 }
    DryRun       = $DryRun.IsPresent
    LogFile      = $script:LOG_FILE
    ExitCode     = $exitCode
}

return $script:result
