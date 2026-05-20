<#
.SYNOPSIS
  同步 Cursor 全局规则 <-> 模板库

.DESCRIPTION
  Push: global-rule-paste.md -> Cursor settings.json (cursor.rules 数组)
  Pull: Cursor settings.json -> global-rule-paste.md
  Cursor 的全局规则存储在 %APPDATA%\Cursor\User\settings.json 的 cursor.rules 字段中。

.PARAMETER Direction
  Push (默认) | Pull

.PARAMETER DryRun
  仅打印计划不写文件

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

Write-Host ""
Write-Host "===== Sync Cursor Global Rule =====" -ForegroundColor Cyan
Write-Host "Direction : $Direction" -ForegroundColor Gray
Write-Host "DryRun   : $DryRun" -ForegroundColor Gray
Write-Host ""

if ($Direction -eq 'Push') {
    # --- Push: repo -> Cursor settings.json ---
    if (-not (Test-Path $RepoFile)) {
        throw "Repo file not found: $RepoFile"
    }

    $repoContent = Get-Content -Raw -Path $RepoFile -Encoding UTF8

    # 读取 Cursor settings.json
    if (-not (Test-Path $CursorSettingsPath)) {
        throw "Cursor settings not found: $CursorSettingsPath"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $settingsText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
    $settings = [System.Text.Json.JsonSerializer]::Deserialize($settingsText, [PSCustomObject])

    if ($null -eq $settings) {
        throw "Failed to parse Cursor settings.json"
    }

    # 构建规则条目
    $newRule = [PSCustomObject]@{
        name = "HJ Agent Global Rules"
        filePath = $RepoRoot -replace '\\', '\\'
    }

    # 更新或新增 cursor.rules
    if ($null -ne $settings.'cursor.rules') {
        $existingRules = $settings.'cursor.rules'
        $idx = 0
        while ($idx -lt $existingRules.Count) {
            if ($existingRules[$idx].name -eq "HJ Agent Global Rules") {
                $existingRules[$idx] = $newRule
                break
            }
            $idx++
        }
        if ($idx -eq $existingRules.Count) {
            $existingRules.Add($newRule) | Out-Null
        }
    } else {
        # 添加 cursor.rules 字段（如果不存在）
        Add-Member -InputObject $settings -NotePropertyName 'cursor.rules' -NotePropertyValue ([System.Collections.ArrayList]@($newRule))
    }

    $newJson = [System.Text.Json.JsonSerializer]::Serialize($settings, [System.Text.Json.JsonSerializerOptions]::new())
    $newJson = "$newJson`n"

    if ($DryRun) {
        Write-Host "[DryRun] Would write $newJson" -ForegroundColor Cyan
    } else {
        [System.IO.File]::WriteAllText($CursorSettingsPath, $newJson, $utf8NoBom)
        Write-Host "[OK] Pushed global rule to Cursor settings.json" -ForegroundColor Green
        Write-Host "     Rule name: $($newRule.name)" -ForegroundColor Gray
        Write-Host "     FilePath : $($newRule.filePath)" -ForegroundColor Gray
        Write-Host "     Restart Cursor to apply changes" -ForegroundColor Yellow
    }

} else {
    # --- Pull: Cursor settings.json -> repo ---
    if (-not (Test-Path $CursorSettingsPath)) {
        throw "Cursor settings not found: $CursorSettingsPath"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $settingsText = [System.IO.File]::ReadAllText($CursorSettingsPath, $utf8NoBom)
    $settings = [System.Text.Json.JsonSerializer]::Deserialize($settingsText, [PSCustomObject])

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
        Write-Host "       cursor.rules: $($settings.'cursor.rules' | ConvertTo-Json -Compress)" -ForegroundColor Gray
        if ($DryRun) {
            Write-Host "[DryRun] Would NOT write repo file" -ForegroundColor Cyan
        }
        exit 0
    }

    # 读取规则文件内容
    $rulePath = $hjRule.filePath -replace '\\', '\'
    if (-not (Test-Path $rulePath)) {
        Write-Host "[WARN] Rule path not found: $rulePath" -ForegroundColor Yellow
        exit 1
    }

    $ruleContent = Get-Content -Raw -Path $rulePath -Encoding UTF8

    if ($DryRun) {
        Write-Host "[DryRun] Would write rule content to: $RepoFile" -ForegroundColor Cyan
        Write-Host "         Source: $rulePath" -ForegroundColor Gray
        Write-Host "         Size  : $($ruleContent.Length) chars" -ForegroundColor Gray
    } else {
        [System.IO.File]::WriteAllText($RepoFile, $ruleContent, $utf8NoBom)
        Write-Host "[OK] Pulled global rule from Cursor" -ForegroundColor Green
        Write-Host "     Source: $rulePath" -ForegroundColor Gray
        Write-Host "     Written to: $RepoFile" -ForegroundColor Gray
    }
}

Write-Host ""
