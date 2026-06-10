# bg-sync.ps1
# 定时同步 Cursor transcripts 到 hj1982.cn（由 Windows 计划任务每 5 分钟调用）
# 幂等：服务器端根据 session_uuid UPSERT，可安全重复运行

$ErrorActionPreference = "SilentlyContinue"
$SyncScript = Join-Path $PSScriptRoot "sync-cursor-to-server.py"
$MarkerFile = Join-Path $PSScriptRoot ".bg-sync-marker.txt"
$LogDir = "e:\HJ\cursor\logs"
$LogFile = Join-Path $LogDir "bg-sync.log"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

function Get-SinceDate {
    if (Test-Path $MarkerFile) {
        $ts = Get-Content $MarkerFile -Raw
        $d = [DateTime]::ParseExact($ts.Trim(), "yyyy-MM-ddTHH:mm:ss", $null)
        return $d.ToString("yyyy-MM-ddTHH:mm:ss")
    }
    return $null
}

function Set-Marker($ts) {
    [System.IO.File]::WriteAllText($MarkerFile, $ts, [System.Text.Encoding]::UTF8)
}

$ts = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

# Build command
$runBat = "@echo off`nchcp 65001 >nul`n"
$tmpOut = [IO.Path]::GetTempFileName()
$tmpErr = [IO.Path]::GetTempFileName()
$since = Get-SinceDate
$sinceArg = if ($since) { "--since `"$since`"" } else { "" }
$runBat += "python `"$SyncScript`" $sinceArg > `"$tmpOut`" 2> `"$tmpErr`"`n"
$batPath = [IO.Path]::GetTempFileName() + ".bat"
[System.IO.File]::WriteAllText($batPath, $runBat, [System.Text.Encoding]::UTF8)

$proc = Start-Process cmd -ArgumentList "/c", $batPath -Wait -WindowStyle Hidden -PassThru
$exitCode = $proc.ExitCode
$stdout = if (Test-Path $tmpOut) { [System.IO.File]::ReadAllText($tmpOut, [System.Text.Encoding]::UTF8) } else { "" }
$stderr = if (Test-Path $tmpErr) { [System.IO.File]::ReadAllText($tmpErr, [System.Text.Encoding]::UTF8) } else { "" }
Remove-Item $batPath, $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

$exitCode = if ($null -ne $proc.ExitCode) { $proc.ExitCode } else { 0 }
$lines = $stdout -split "`n" | Where-Object { $_ -match "sessions uploaded|All OK|uploaded|PASS" }
$okLine = ($lines | Select-Object -First 1).Trim()
$countLine = if ($stdout -match "(\d+)\s+sessions") { $Matches[0] } else { "" }

$logLine = "$ts | exit=$exitCode | $countLine"
if ($okLine) { $logLine += " | $okLine" }
if ($stderr) { $logLine += " | ERR: $($stderr.Substring(0, [Math]::Min(80, $stderr.Length)))" }
Add-Content -Path $LogFile -Value $logLine

# 只有真正有 sessions 上传成功才更新 marker（避免 dry-run 也更新）
if ($exitCode -eq 0 -and $stdout -match "sessions uploaded|All OK" -and $stdout -notmatch "DRY-RUN") {
    Set-Marker $ts
    exit 0
} else {
    exit 1
}
