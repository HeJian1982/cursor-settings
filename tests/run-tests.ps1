<#
.SYNOPSIS
  Cursor 模板库测试套件

.DESCRIPTION
  零依赖自测试（不需要 Pester / PSScriptAnalyzer）
  在临时目录验证模板库完整性

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
#>

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

$total = 0
$passed = 0
$failed = 0

function Test-Case {
    param($Name, $ScriptBlock)
    $script:total++
    Write-Host "  [$script:total] $Name..." -NoNewline
    try {
        $result = & $ScriptBlock
        if ($result) {
            Write-Host " OK" -ForegroundColor Green
            $script:passed++
            return $true
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:failed++
            return $false
        }
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
        $script:failed++
        return $false
    }
}

Write-Host ""
Write-Host "===== Cursor Templates Test Suite =====" -ForegroundColor Cyan
Write-Host "Repo root: $RepoRoot" -ForegroundColor Gray
Write-Host ""

# --- T1: 规则文件数量 ---
Write-Host "T1: 规则文件数量" -ForegroundColor Yellow
$expectedRules = 21
$actualRules = (Get-ChildItem "$RepoRoot\.cursor\rules\*.mdc" -ErrorAction SilentlyContinue | Measure-Object).Count
Test-Case "规则文件数量 == $expectedRules" { $actualRules -eq $expectedRules }

# --- T2: 核心规则存在 ---
Write-Host "T2: 核心规则文件" -ForegroundColor Yellow
$coreRules = @('00-core.mdc', '13-workflow.mdc', '14-decision-trees.mdc', '15-pre-flight.mdc')
foreach ($r in $coreRules) {
    $exists = Test-Path "$RepoRoot\.cursor\rules\$r"
    Test-Case "$r 存在" { $exists }
}

# --- T3: 脚本文件数量 ---
Write-Host "T3: 脚本文件" -ForegroundColor Yellow
$scriptFiles = @('init-project.ps1', 'sync-global-rule.ps1', 'sync-local-configs.ps1')
foreach ($s in $scriptFiles) {
    $exists = Test-Path "$RepoRoot\scripts\$s"
    Test-Case "scripts/$s 存在" { $exists }
}

# --- T4: 全局规则存在 ---
Write-Host "T4: 全局规则" -ForegroundColor Yellow
Test-Case "global-rule-paste.md 存在" { (Test-Path "$RepoRoot\global-rule-paste.md") }

# --- T5: 配置文件存在 ---
Write-Host "T5: 配置文件" -ForegroundColor Yellow
$configFiles = @('.editorconfig', '.gitignore', 'CHANGELOG.md', 'VERSION')
foreach ($c in $configFiles) {
    $exists = Test-Path "$RepoRoot\$c"
    Test-Case "$c 存在" { $exists }
}

# --- T6: 版本一致性 ---
Write-Host "T6: 版本一致性" -ForegroundColor Yellow
$verFile = Get-Content "$RepoRoot\VERSION" -Raw -ErrorAction SilentlyContinue
Test-Case "VERSION 文件非空" { $verFile.Trim().Length -gt 0 }

# --- T7: 规则内容检查 ---
Write-Host "T7: 规则内容" -ForegroundColor Yellow
$coreContent = Get-Content "$RepoRoot\.cursor\rules\00-core.mdc" -Raw -ErrorAction SilentlyContinue
Test-Case "00-core.mdc 包含项目名" { $coreContent -match "何健个人网站" }
Test-Case "00-core.mdc 包含绝对禁止" { $coreContent -match "绝对禁止" }

# --- T8: .gitignore 覆盖关键项 ---
Write-Host "T8: .gitignore" -ForegroundColor Yellow
$gi = Get-Content "$RepoRoot\.gitignore" -Raw -ErrorAction SilentlyContinue
Test-Case ".gitignore 包含 .env 保护" { $gi -match '\.env\*' }
Test-Case ".gitignore 包含 node_modules" { $gi -match 'node_modules' }
Test-Case ".gitignore 包含 _archive" { $gi -match '_archive' }

# --- T9: PowerShell 脚本 UTF-8 BOM ---
Write-Host "T9: PowerShell 脚本编码" -ForegroundColor Yellow
Get-ChildItem "$RepoRoot\scripts\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $hasBom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
    Test-Case "$($_.Name) UTF-8 BOM" { $hasBom }
}

# --- Summary ---
Write-Host ""
Write-Host "===== Summary =====" -ForegroundColor Cyan
Write-Host "Total : $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host ""

if ($failed -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "SOME CHECKS FAILED" -ForegroundColor Red
    exit 1
}
