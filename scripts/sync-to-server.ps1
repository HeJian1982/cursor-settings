# sync-to-server.ps1
# Wrapper: invokes sync-cursor-to-server.py
# Usage: same as before - all args forwarded to Python
#
#   .\sync-to-server.ps1                          # full sync
#   .\sync-to-server.ps1 -DryRun                # --dry-run
#   .\sync-to-server.ps1 -Check                 # --check
#   .\sync-to-server.ps1 -Since "2026-06-01"   # --since

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Check,
    [string]$Since = "",
    [string]$ApiKey = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyScript = Join-Path $ScriptDir "sync-cursor-to-server.py"

$args = @()
if ($Check)    { $args += "--check" }
if ($DryRun)   { $args += "--dry-run" }
if ($Since)    { $args += "--since"; $args += $Since }

& python $PyScript $args
exit $LASTEXITCODE
