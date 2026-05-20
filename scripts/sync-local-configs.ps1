<#
.SYNOPSIS
  同步本机 Cursor 配置 <-> 模板库快照

.DESCRIPTION
  双向同步 Cursor settings.json 中的关键配置子集。
  同步范围：cursor.rules、AI模型设置、编辑器基础设置。
  排除项：扩展列表、视图状态等经常变动的临时数据。

  Push: 仓库快照 -> 本机 Cursor settings.json
  Pull: 本机 Cursor settings.json -> 仓库快照

  快照文件保存在 local-machine-configs/hosts/<COMPUTERNAME>/cursor/settings.json

.PARAMETER Direction
  Pull (默认): 本机 -> 仓库
  Push: 仓库 -> 本机

.PARAMETER DryRun
  仅打印计划

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

# 本机 host 目录
$HostDir = Join-Path $RepoRoot "local-machine-configs\hosts\$env:COMPUTERNAME\cursor"
$HostSettingsFile = Join-Path $HostDir "settings.json"
$CursorSettingsPath = "$env:APPDATA\Cursor\User\settings.json"

Write-Host ""
Write-Host "===== Sync Cursor Local Configs =====" -ForegroundColor Cyan
Write-Host "Direction  : $Direction" -ForegroundColor Gray
Write-Host "DryRun     : $DryRun" -ForegroundColor Gray
Write-Host "Host dir   : $HostDir" -ForegroundColor Gray
Write-Host "Cursor cfg : $CursorSettingsPath" -ForegroundColor Gray
Write-Host ""

# 要同步的配置键（按分组）
$SYNC_KEYS = @(
    # AI 规则
    'cursor.rules',
    # 编辑器基础
    'editor.fontFamily', 'editor.fontSize', 'editor.lineHeight', 'editor.fontLigatures',
    'editor.tabSize', 'editor.insertSpaces', 'editor.detectIndentation',
    'editor.minimap.enabled', 'editor.renderLineHighlight', 'editor.lineNumbers',
    'editor.folding', 'editor.foldingStrategy', 'editor.bracketPairColorization.enabled',
    'editor.guides.bracketPairs', 'editor.smoothScrolling', 'editor.mouseWheelZoom',
    'editor.autoClosingBrackets', 'editor.autoClosingQuotes',
    # 格式化 & 保存
    'editor.formatOnSave', 'files.trimTrailingWhitespace', 'files.insertFinalNewline',
    'files.trimFinalNewlines', 'eslint.enable', 'eslint.run', 'eslint.format.enable',
    'eslint.lintTask.enable', 'editor.codeActionsOnSave',
    # 终端
    'terminal.integrated.fontFamily', 'terminal.integrated.fontSize',
    'terminal.integrated.lineHeight', 'terminal.integrated.cursorBlinking',
    'terminal.integrated.cursorStyle', 'terminal.integrated.defaultProfile.windows',
    # AI 行为
    'claudeCode.enhancedCompletions', 'claudeCode.autoContext', 'claudeCode.thinkingBudgetTokens',
    # 文件 & 工作区
    'files.autoSave', 'files.autoSaveDelay', 'git.ignoreLimitWarning',
    'files.exclude', 'search.exclude',
    # UI & 主题
    'window.autoDetectColorScheme', 'workbench.colorTheme', 'workbench.iconTheme',
    'workbench.sideBar.location', 'workbench.statusBar.visible',
    'workbench.panel.defaultHeight', 'workbench.editor.enablePreview',
    'workbench.editor.tabCloseButton', 'workbench.editor.defaultLanguage',
    # 性能
    'typescript.tsserver.maxTsServerMemory', 'typescript.tsserver.experimental.enableProjectDiagnostics',
    'typescript.surveys.enabled', 'javascript.suggest.autoImports'
)

function Get-SettingsSnapshot {
    param($settingsObj, [string[]]$keys, [string]$prefix = '')

    $snapshot = @{}
    foreach ($key in $keys) {
        if ($key -match '\.') {
            $parts = $key -split '\.'
            $val = $settingsObj
            foreach ($p in $parts) {
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
        } else {
            if ($null -ne $settingsObj.$key) {
                $snapshot[$key] = $settingsObj.$key
            }
        }
    }
    return $snapshot
}

function Merge-Settings {
    param(
        [PSCustomObject]$baseSettings,
        [hashtable]$incoming,
        [string[]]$keys
    )

    foreach ($key in $keys) {
        if ($incoming.ContainsKey($key)) {
            if ($key -match '\.') {
                $parts = $key -split '\.'
                $obj = $baseSettings
                for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                    $p = $parts[$i]
                    if ($null -eq $obj.$p) {
                        $obj | Add-Member -NotePropertyName $p -NotePropertyValue ([PSCustomObject]@{}) -Force
                    }
                    $obj = $obj.$p
                }
                $obj.($parts[-1]) = $incoming[$key]
            } else {
                $baseSettings | Add-Member -NotePropertyName $key -NotePropertyValue $incoming[$key] -Force
            }
        }
    }
    return $baseSettings
}

# 读取 Cursor settings.json
if (-not (Test-Path $CursorSettingsPath)) {
    throw "Cursor settings not found: $CursorSettingsPath"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$cursorText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
# 移除注释以解析 JSON
$cleanText = $cursorText -replace '(?m)^\s*//.*$', ''
$cursorSettings = [System.Text.Json.JsonSerializer]::Deserialize($cleanText, [PSCustomObject])

if ($null -eq $cursorSettings) {
    throw "Failed to parse Cursor settings.json"
}

if ($Direction -eq 'Pull') {
    # --- Pull: 本机 -> 仓库 ---

    # 确保 host 目录存在
    if (-not (Test-Path $HostDir)) {
        New-Item -ItemType Directory -Force -Path $HostDir | Out-Null
        Write-Host "[INFO] Created host directory: $HostDir" -ForegroundColor Cyan
    }

    $snapshot = Get-SettingsSnapshot -settingsObj $cursorSettings -keys $SYNC_KEYS

    # 保留现有 snapshot 中的 cursor.rules 路径信息
    $meta = @{
        computerName = $env:COMPUTERNAME
        pulledAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        ruleSourcePath = $RepoRoot -replace '\\', '/'
    }

    $output = @{
        _meta = $meta
        settings = $snapshot
    }

    $jsonOptions = [System.Text.Json.JsonSerializerOptions]::new()
    $jsonOptions.WriteIndented = $true
    $newJson = [System.Text.Json.JsonSerializer]::Serialize($output, $jsonOptions)

    if ($DryRun) {
        Write-Host "[DryRun] Would write snapshot to: $HostSettingsFile" -ForegroundColor Cyan
        Write-Host "         Sync keys count: $($SYNC_KEYS.Count)" -ForegroundColor Gray
        Write-Host "         Snapshot preview (first 500 chars):" -ForegroundColor Gray
        Write-Host ($newJson.Substring(0, [Math]::Min(500, $newJson.Length))) -ForegroundColor DarkGray
    } else {
        [System.IO.File]::WriteAllText($HostSettingsFile, $newJson + "`n", $utf8NoBom)
        Write-Host "[OK] Pulled cursor settings to: $HostSettingsFile" -ForegroundColor Green
        Write-Host "     Synced $($snapshot.Count) keys" -ForegroundColor Gray
    }

} else {
    # --- Push: 仓库 -> 本机 ---

    if (-not (Test-Path $HostSettingsFile)) {
        throw "Host snapshot not found: $HostSettingsFile`nRun with -Direction Pull first."
    }

    $hostText = [System.IO.File]::ReadAllText($HostSettingsFile, $utf8NoBom)
    $hostSnapshot = [System.Text.Json.JsonSerializer]::Deserialize($hostText, [PSCustomObject])

    if ($null -eq $hostSnapshot -or $null -eq $hostSnapshot.settings) {
        throw "Invalid snapshot format: $HostSettingsFile"
    }

    $hostSettings = $hostSnapshot.settings
    $incoming = @{}
    $hostSettings.PSObject.Properties | ForEach-Object { $incoming[$_.Name] = $_.Value }

    $merged = Merge-Settings -baseSettings $cursorSettings -incoming $incoming -keys $SYNC_KEYS

    $jsonOptions = [System.Text.Json.JsonSerializerOptions]::new()
    $jsonOptions.WriteIndented = $true
    $newJson = [System.Text.Json.JsonSerializer]::Serialize($merged, $jsonOptions)
    $newJson = "$newJson`n"

    if ($DryRun) {
        Write-Host "[DryRun] Would overwrite: $CursorSettingsPath" -ForegroundColor Cyan
        Write-Host "         Merged $($incoming.Count) keys from snapshot" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($CursorSettingsPath, $newJson, $utf8NoBom)
        Write-Host "[OK] Pushed cursor settings from snapshot" -ForegroundColor Green
        Write-Host "     Merged $($incoming.Count) keys" -ForegroundColor Gray
        Write-Host "     Restart Cursor to apply changes" -ForegroundColor Yellow
    }
}

Write-Host ""
