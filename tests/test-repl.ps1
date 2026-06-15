# Test runner for REPL pipe scenarios (matches task 996048 / 851384 reproduction)
# Usage:
#   pwsh test-repl.ps1 empty      # empty pipe -> expect exit 0
#   pwsh test-repl.ps1 commands   # multi-line commands + /q
#   pwsh test-repl.ps1 crash      # write some lines, close pipe early
param([string]$Mode = 'empty')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Bin = Join-Path $RepoRoot 'subprojects\hj-gateway\bin'
$LogDir = Join-Path $RepoRoot 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "repl-test-$Mode.log"

# Make sure gateway is up
& (Join-Path $Bin 'gateway.ps1') start | Out-Null
Start-Sleep -Seconds 1

$inFile = [System.IO.Path]::GetTempFileName()
try {
    switch ($Mode) {
        'empty' {
            # leave file empty
        }
        'commands' {
            "/skills`n/status`n/hello`n/q`n" | Out-File -FilePath $inFile -Encoding UTF8 -NoNewline
        }
        'crash' {
            "/status`n" | Out-File -FilePath $inFile -Encoding UTF8 -NoNewline
        }
    }

    # Spawn the REPL as a child PowerShell with redirected I/O.
    # Pass the script as -File (most reliable arg passing on Windows PS 5.1).
    # Use a temp .ps1 to avoid quoting hell with the path in Arguments.
    $wrapper = [System.IO.Path]::GetTempFileName() + '.ps1'
    Set-Content -Path $wrapper -Value "& '$Bin\gateway.ps1' repl" -Encoding UTF8
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Command powershell).Source
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $Bin
        $proc = [System.Diagnostics.Process]::Start($psi)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Feed the file then close stdin (so REPL sees EOF)
        Get-Content -Path $inFile -Encoding UTF8 | ForEach-Object {
            $proc.StandardInput.WriteLine($_)
        }
        $proc.StandardInput.Close()

        $exited = $proc.WaitForExit(20000)
        $sw.Stop()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $exit = if ($exited) { $proc.ExitCode } else { -999 }
    } finally {
        Remove-Item $wrapper -Force -ErrorAction SilentlyContinue
    }

    Add-Content -Path $LogFile -Value "---- $Mode ----`nexit=$exit`nelapsed_ms=$($sw.ElapsedMilliseconds)`nstdout=$stdout`nstderr=$stderr" -Encoding UTF8

    Write-Host "[$Mode] exit=$exit elapsed_ms=$($sw.ElapsedMilliseconds)"
    Write-Host "  stdout lines: $($stdout -split "`n" | Where-Object { $_ }).Count"
    if ($stdout) { Write-Host "  first lines:"; ($stdout -split "`n" | Select-Object -First 8) | ForEach-Object { Write-Host "    $_" } }
    if ($stderr) { Write-Host "  stderr:"; ($stderr -split "`n" | Select-Object -First 5) | ForEach-Object { Write-Host "    $_" } }
    if (-not $exited) {
        Write-Host "  (did not exit in 20s; killing)" -ForegroundColor Yellow
        $proc.Kill()
    }
} finally {
    Remove-Item $inFile -Force -ErrorAction SilentlyContinue
}
