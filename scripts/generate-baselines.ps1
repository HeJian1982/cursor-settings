<#
.SYNOPSIS
  Generate integrity baselines for security checks

.DESCRIPTION
  Computes SHA256 hashes of PowerShell scripts, SKILL.md files across all
  skills directories, and Cursor settings.json. Outputs baselines.json.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\generate-baselines.ps1
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$OutPath = Join-Path $RepoRoot "scripts\baselines.json"

$utf8Bom = New-Object System.Text.UTF8Encoding $true

Write-Host ""
Write-Host "===== Generate Integrity Baselines =====" -ForegroundColor Cyan

$baselines = @{
    generatedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    machine = $env:COMPUTERNAME
    scripts = @{}
    skills = @{}
    cursorSettings = ""
}

# 1. Scripts hashes
$scriptPaths = @(
    "$RepoRoot\scripts\init-project.ps1",
    "$RepoRoot\scripts\sync-global-rule.ps1",
    "$RepoRoot\scripts\sync-local-configs.ps1",
    "$RepoRoot\scripts\append-daily-log.ps1",
    "$RepoRoot\scripts\generate-baselines.ps1",
    "$RepoRoot\tests\run-tests.ps1"
)

foreach ($p in $scriptPaths) {
    if (Test-Path $p) {
        $name = Split-Path $p -Leaf
        $hash = (Get-FileHash $p -Algorithm SHA256).Hash
        $baselines.scripts[$name] = $hash
        Write-Host ("  [SCRIPT] {0,-35} {1}" -f $name, $hash.Substring(0, 16) + "...") -ForegroundColor Gray
    }
}

# 2. Skills: recursive scan, deduplicate by skill name (first-found wins)
$skillDirs = @(
    "C:\Users\HJ2\.cursor\skills-cursor",
    "C:\Users\HJ2\.claude\skills",
    "C:\Users\HJ2\.agents\skills",
    "C:\Users\HJ2\.claude\plugins\cache\claude-plugins-official\superpowers\5.1.0\skills"
)

$seenSkills = @{}
$skillCount = 0

foreach ($dir in $skillDirs) {
    if (-not (Test-Path $dir)) { continue }
    Write-Host ("  Scanning: {0}" -f $dir) -ForegroundColor DarkGray
    $skillFiles = Get-ChildItem $dir -Recurse -File -Filter "SKILL.md" -ErrorAction SilentlyContinue
    foreach ($sf in $skillFiles) {
        $skillName = $sf.Directory.Name
        if ($seenSkills.ContainsKey($skillName)) { continue }
        $hash = (Get-FileHash $sf.FullName -Algorithm SHA256).Hash
        $baselines.skills[$skillName] = $hash
        $seenSkills[$skillName] = $true
        $skillCount++
    }
}

Write-Host ("  [OK] {0} unique skills registered" -f $skillCount) -ForegroundColor Gray

# 3. Cursor settings.json
$cursorSettingsPath = "$env:APPDATA\Cursor\User\settings.json"
if (Test-Path $cursorSettingsPath) {
    $hash = (Get-FileHash $cursorSettingsPath -Algorithm SHA256).Hash
    $baselines.cursorSettings = $hash
    Write-Host ("  [CURSOR] settings.json                     {0}" -f $hash.Substring(0, 16) + "...") -ForegroundColor Gray
}

# 4. Output
$json = $baselines | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutPath, $json + "`n", $utf8Bom)

Write-Host ""
Write-Host "[OK] Baselines written to: $OutPath" -ForegroundColor Green
Write-Host ("     Scripts: {0}" -f $baselines.scripts.Count) -ForegroundColor Gray
Write-Host ("     Skills : {0}" -f $baselines.skills.Count) -ForegroundColor Gray
Write-Host ""
