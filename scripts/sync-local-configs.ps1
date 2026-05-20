<#
.SYNOPSIS
  Bidirectional sync for Cursor local settings <-> template library snapshot

.DESCRIPTION
  Syncs a curated subset of Cursor settings.json keys between the local machine
  and a host-specific snapshot in local-machine-configs/hosts/<COMPUTERNAME>/cursor/settings.json

  Push: host snapshot -> local Cursor settings.json
  Pull: local Cursor settings.json -> host snapshot

  Excludes transient keys like extension lists and view state.

.PARAMETER Direction
  Pull (default): local -> repo
  Push: repo -> local

.PARAMETER DryRun
  Preview changes without writing

.EXAMPLE
  .\sync-local-configs.ps1 -DryRun
  .\sync-local-configs.ps1
  .\sync-local-configs.ps1 -Direction Push -DryRun
#>

[CmdletBinding()]
param(
    [ValidateSet('Pull', 'Push')]
    [string]$Direction = 'Pull',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

$HostDir = Join-Path $RepoRoot "local-machine-configs\hosts\$env:COMPUTERNAME\cursor"
$HostSettingsFile = Join-Path $HostDir "settings.json"
$CursorSettingsPath = "$env:APPDATA\Cursor\User\settings.json"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

Write-Host ""
Write-Host "===== Sync Cursor Local Configs =====" -ForegroundColor Cyan
Write-Host "Direction  : $Direction" -ForegroundColor Gray
Write-Host "DryRun     : $DryRun" -ForegroundColor Gray
Write-Host "Host dir   : $HostDir" -ForegroundColor Gray
Write-Host "Cursor cfg : $CursorSettingsPath" -ForegroundColor Gray
Write-Host ""

$SYNC_KEYS = @(
    # AI rules
    'cursor.rules',
    # Editor basics
    'editor.fontFamily', 'editor.fontSize', 'editor.lineHeight', 'editor.fontLigatures',
    'editor.tabSize', 'editor.insertSpaces', 'editor.detectIndentation',
    'editor.minimap.enabled', 'editor.renderLineHighlight', 'editor.lineNumbers',
    'editor.folding', 'editor.foldingStrategy', 'editor.bracketPairColorization.enabled',
    'editor.guides.bracketPairs', 'editor.smoothScrolling', 'editor.mouseWheelZoom',
    'editor.autoClosingBrackets', 'editor.autoClosingQuotes',
    # Format & save
    'editor.formatOnSave', 'files.trimTrailingWhitespace', 'files.insertFinalNewline',
    'files.trimFinalNewlines', 'eslint.enable', 'eslint.run', 'eslint.format.enable',
    'eslint.lintTask.enable', 'editor.codeActionsOnSave',
    # Terminal
    'terminal.integrated.fontFamily', 'terminal.integrated.fontSize',
    'terminal.integrated.lineHeight', 'terminal.integrated.cursorBlinking',
    'terminal.integrated.cursorStyle', 'terminal.integrated.defaultProfile.windows',
    # AI behavior
    'claudeCode.enhancedCompletions', 'claudeCode.autoContext', 'claudeCode.thinkingBudgetTokens',
    # File & workspace
    'files.autoSave', 'files.autoSaveDelay', 'git.ignoreLimitWarning',
    'files.exclude', 'search.exclude',
    # UI & theme
    'window.autoDetectColorScheme', 'workbench.colorTheme', 'workbench.iconTheme',
    'workbench.sideBar.location', 'workbench.statusBar.visible',
    'workbench.panel.defaultHeight', 'workbench.editor.enablePreview',
    'workbench.editor.tabCloseButton', 'workbench.editor.defaultLanguage',
    # Performance
    'typescript.tsserver.maxTsServerMemory', 'typescript.tsserver.experimental.enableProjectDiagnostics',
    'typescript.surveys.enabled', 'javascript.suggest.autoImports'
)

function Get-SettingsSnapshot {
    param($settingsObj, [string[]]$keys)

    $snapshot = @{}
    foreach ($key in $keys) {
        $val = $settingsObj
        foreach ($p in ($key -split '\.')) {
            if ($null -ne $val -and $null -ne $val.$p) {
                $val = $val.$p
            } else {
                $val = $null
                break
            }
        }
        if ($null -ne $val) {
            $snapshot[$key] = $val
        }
    }
    return $snapshot
}

function Merge-Settings {
    param($baseSettings, [hashtable]$incoming, [string[]]$keys)

    foreach ($key in $keys) {
        if (-not $incoming.ContainsKey($key)) { continue }
        $val = $incoming[$key]
        $parts = $key -split '\.'
        $obj = $baseSettings
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            $p = $parts[$i]
            if ($null -eq $obj.$p) {
                $obj | Add-Member -NotePropertyName $p -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            $obj = $obj.$p
        }
        $obj.($parts[-1]) = $val
    }
    return $baseSettings
}

if (-not (Test-Path $CursorSettingsPath)) {
    throw "Cursor settings not found: $CursorSettingsPath"
}

$cursorText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
$cleanText = $cursorText -replace '(?m)^\s*//.*$', ''
$cursorSettings = $cleanText | ConvertFrom-Json -ErrorAction Stop

if ($null -eq $cursorSettings) {
    throw "Failed to parse Cursor settings.json"
}

if ($Direction -eq 'Pull') {
    # Pull: local -> repo
    if (-not (Test-Path $HostDir)) {
        New-Item -ItemType Directory -Force -Path $HostDir | Out-Null
        Write-Host "[INFO] Created host directory: $HostDir" -ForegroundColor Cyan
    }

    $snapshot = Get-SettingsSnapshot -settingsObj $cursorSettings -keys $SYNC_KEYS

    $output = @{
        _meta = @{
            computerName = $env:COMPUTERNAME
            pulledAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
            ruleSourcePath = $RepoRoot -replace '\\', '/'
        }
        settings = $snapshot
    }

    $newJson = $output | ConvertTo-Json -Depth 10
    $newJson = "$newJson`n"

    if ($DryRun) {
        Write-Host "[DryRun] Would write snapshot to: $HostSettingsFile" -ForegroundColor Cyan
        Write-Host "  Sync keys count: $($SYNC_KEYS.Count)" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($HostSettingsFile, $newJson, $utf8NoBom)
        Write-Host "[OK] Pulled cursor settings to: $HostSettingsFile" -ForegroundColor Green
        Write-Host "     Synced $($snapshot.Count) keys" -ForegroundColor Gray
    }

} else {
    # Push: repo -> local
    if (-not (Test-Path $HostSettingsFile)) {
        throw "Host snapshot not found: $HostSettingsFile`nRun with -Direction Pull first."
    }

    $hostText = [System.IO.File]::ReadAllText($HostSettingsFile, $utf8NoBom)
    $hostSnapshot = $hostText | ConvertFrom-Json -ErrorAction Stop

    if ($null -eq $hostSnapshot -or $null -eq $hostSnapshot.settings) {
        throw "Invalid snapshot format: $HostSettingsFile"
    }

    $incoming = @{}
    $hostSnapshot.settings.PSObject.Properties | ForEach-Object { $incoming[$_.Name] = $_.Value }

    $merged = Merge-Settings -baseSettings $cursorSettings -incoming $incoming -keys $SYNC_KEYS

    $newJson = $merged | ConvertTo-Json -Depth 10
    $newJson = "$newJson`n"

    if ($DryRun) {
        Write-Host "[DryRun] Would overwrite: $CursorSettingsPath" -ForegroundColor Cyan
        Write-Host "  Merged $($incoming.Count) keys from snapshot" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($CursorSettingsPath, $newJson, $utf8NoBom)
        Write-Host "[OK] Pushed cursor settings from snapshot" -ForegroundColor Green
        Write-Host "     Merged $($incoming.Count) keys" -ForegroundColor Gray
        Write-Host "     Restart Cursor to apply changes" -ForegroundColor Yellow
    }
}

Write-Host ""
