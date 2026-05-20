<#
.SYNOPSIS
  Sync Cursor global rules <-> template library

.DESCRIPTION
  Push: global-rule-paste.md -> Cursor settings.json (cursor.rules array)
  Pull: Cursor settings.json -> global-rule-paste.md
  Global rules stored in %APPDATA%\Cursor\User\settings.json cursor.rules field.

.PARAMETER Direction
  Push (default) | Pull

.PARAMETER DryRun
  Preview changes without writing

.EXAMPLE
  .\sync-global-rule.ps1 -DryRun
  .\sync-global-rule.ps1 -Direction Push
  .\sync-global-rule.ps1 -Direction Pull
#>

[CmdletBinding()]
param(
    [ValidateSet('Push', 'Pull')]
    [string]$Direction = 'Push',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$RepoFile = Join-Path $RepoRoot 'global-rule-paste.md'
$CursorSettingsPath = "$env:APPDATA\Cursor\User\settings.json"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

Write-Host ""
Write-Host "===== Sync Cursor Global Rule =====" -ForegroundColor Cyan
Write-Host "Direction : $Direction" -ForegroundColor Gray
Write-Host "DryRun   : $DryRun" -ForegroundColor Gray
Write-Host ""

if ($Direction -eq 'Push') {
    # Push: repo -> Cursor settings.json
    if (-not (Test-Path $RepoFile)) {
        throw "Repo file not found: $RepoFile"
    }

    $repoContent = Get-Content -Raw -Path $RepoFile -Encoding UTF8

    if (-not (Test-Path $CursorSettingsPath)) {
        throw "Cursor settings not found: $CursorSettingsPath"
    }

    $cursorText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
    # Remove JS comments for parsing
    $cleanText = $cursorText -replace '(?m)^\s*//.*$', ''
    $settings = $cleanText | ConvertFrom-Json -ErrorAction Stop

    $newRule = [PSCustomObject]@{
        name = "HJ Agent Global Rules"
        filePath = $RepoRoot -replace '\\', '\\'
    }

    if ($null -ne $settings.'cursor.rules') {
        $existingRules = @($settings.'cursor.rules')
        $idx = 0
        $found = $false
        while ($idx -lt $existingRules.Count) {
            if ($existingRules[$idx].name -eq "HJ Agent Global Rules") {
                $existingRules[$idx] = $newRule
                $found = $true
                break
            }
            $idx++
        }
        if (-not $found) {
            $existingRules += @($newRule)
        }
        $settings.'cursor.rules' = $existingRules
    } else {
        $settings | Add-Member -NotePropertyName 'cursor.rules' -NotePropertyValue @($newRule) -Force
    }

    $newJson = $settings | ConvertTo-Json -Depth 10
    $newJson = "$newJson`n"

    if ($DryRun) {
        Write-Host "[DryRun] Would write cursor.rules entry:" -ForegroundColor Cyan
        Write-Host "  name    : $($newRule.name)" -ForegroundColor Gray
        Write-Host "  filePath: $($newRule.filePath)" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($CursorSettingsPath, $newJson, $utf8NoBom)
        Write-Host "[OK] Pushed global rule to Cursor settings.json" -ForegroundColor Green
        Write-Host "     Rule name: $($newRule.name)" -ForegroundColor Gray
        Write-Host "     FilePath : $($newRule.filePath)" -ForegroundColor Gray
        Write-Host "     Restart Cursor to apply changes" -ForegroundColor Yellow
    }

} else {
    # Pull: Cursor settings.json -> repo
    if (-not (Test-Path $CursorSettingsPath)) {
        throw "Cursor settings not found: $CursorSettingsPath"
    }

    $cursorText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
    $cleanText = $cursorText -replace '(?m)^\s*//.*$', ''
    $settings = $cleanText | ConvertFrom-Json -ErrorAction Stop

    $hjRule = $null
    if ($null -ne $settings.'cursor.rules') {
        foreach ($r in $settings.'cursor.rules') {
            if ($r.name -eq "HJ Agent Global Rules") {
                $hjRule = $r
                break
            }
        }
    }

    if ($null -eq $hjRule) {
        Write-Host "[WARN] No 'HJ Agent Global Rules' entry found in Cursor settings" -ForegroundColor Yellow
        if ($DryRun) {
            Write-Host "[DryRun] Would NOT write repo file" -ForegroundColor Cyan
        }
        exit 0
    }

    $rulePath = $hjRule.filePath -replace '\\\\', '\'
    if (-not (Test-Path $rulePath)) {
        Write-Host "[WARN] Rule path not found: $rulePath" -ForegroundColor Yellow
        exit 1
    }

    $ruleContent = Get-Content -Raw -Path $rulePath -Encoding UTF8

    if ($DryRun) {
        Write-Host "[DryRun] Would write rule content to: $RepoFile" -ForegroundColor Cyan
        Write-Host "  Source: $rulePath" -ForegroundColor Gray
        Write-Host "  Size  : $($ruleContent.Length) chars" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($RepoFile, $ruleContent, $utf8NoBom)
        Write-Host "[OK] Pulled global rule from Cursor" -ForegroundColor Green
        Write-Host "     Source: $rulePath" -ForegroundColor Gray
        Write-Host "     Written to: $RepoFile" -ForegroundColor Gray
    }
}

Write-Host ""
