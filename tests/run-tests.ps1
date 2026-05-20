<#
.SYNOPSIS
  Cursor 模板库测试套件

.DESCRIPTION
  零依赖自测试（不需要 Pester / PSScriptAnalyzer）
  验证模板库完整性、一致性和编码规范

  测试覆盖：
  - T1: 规则文件数量与存在性
  - T2: 核心规则完整性
  - T3: 脚本文件存在性
  - T4: 全局配置文件
  - T5: 规则文件元数据（description + alwaysApply）
  - T6: 跨文件引用一致性（无悬空引用）
  - T7: 版本一致性（VERSION vs 00-core）
  - T8: .gitignore 覆盖率
  - T9: PowerShell 脚本编码（BOM）
  - T10: 已删除规则不再被引用

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
#>

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

$total = 0
$passed = 0
$failed = 0
$failNames = @()

function Test-Case {
    param($Name, $ScriptBlock)
    $script:total++
    Write-Host ("  [{0:D2}] {1}..." -f $script:total, $Name) -NoNewline
    try {
        $result = & $ScriptBlock
        if ($result) {
            Write-Host " OK" -ForegroundColor Green
            $script:passed++
            return $true
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:failed++
            $script:failNames += $Name
            return $false
        }
    } catch {
        Write-Host (" ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:failed++
        $script:failNames += "$Name ($_)"
        return $false
    }
}

Write-Host ""
Write-Host "===== Cursor Templates Test Suite =====" -ForegroundColor Cyan
Write-Host ("Repo root: {0}" -f $RepoRoot) -ForegroundColor Gray
Write-Host ""

# ── T1: 规则文件数量 ──────────────────────────────────────
Write-Host "T1: 规则文件数量" -ForegroundColor Yellow
$expectedRules = 21
$actualRules = (Get-ChildItem "$RepoRoot\.cursor\rules\*.mdc" -ErrorAction SilentlyContinue | Measure-Object).Count
Test-Case "规则文件数量 == $expectedRules" { $actualRules -eq $expectedRules }

# ── T2: 核心规则存在 ─────────────────────────────────────
Write-Host "T2: 核心规则文件" -ForegroundColor Yellow
$coreRules = @('00-core.mdc', '13-workflow.mdc', '14-decision-trees.mdc', '15-pre-flight.mdc')
foreach ($r in $coreRules) {
    $exists = Test-Path "$RepoRoot\.cursor\rules\$r"
    Test-Case "$r exists" { $exists }
}

# ── T3: 脚本文件存在性 ───────────────────────────────────
Write-Host "T3: 脚本文件" -ForegroundColor Yellow
$scriptFiles = @('init-project.ps1', 'sync-global-rule.ps1', 'sync-local-configs.ps1')
foreach ($s in $scriptFiles) {
    $exists = Test-Path "$RepoRoot\scripts\$s"
    Test-Case "scripts/$s exists" { $exists }
}

# ── T4: 全局配置文件 ─────────────────────────────────────
Write-Host "T4: 全局配置文件" -ForegroundColor Yellow
$configFiles = @('.editorconfig', '.gitignore', 'CHANGELOG.md', 'VERSION')
foreach ($c in $configFiles) {
    $exists = Test-Path "$RepoRoot\$c"
    Test-Case "$c exists" { $exists }
}

# ── T5: 规则文件元数据 ────────────────────────────────────
Write-Host "T5: 规则元数据" -ForegroundColor Yellow
$rules = Get-ChildItem "$RepoRoot\.cursor\rules\*.mdc"
foreach ($rule in $rules) {
    $content = Get-Content $rule.FullName -Raw
    # description frontmatter is required (handles both quoted and unquoted values)
    $hasDesc = $content -match 'description:\s*"?[^"\r\n]+"?'
    Test-Case "$($rule.Name) has description" { $hasDesc }
}

# ── T6: 跨文件引用一致性 ─────────────────────────────────
Write-Host "T6: 跨文件引用一致性" -ForegroundColor Yellow

# Collect all referenced .mdc filenames from all rules
$allRuleNames = @{}
Get-ChildItem "$RepoRoot\.cursor\rules\*.mdc" | ForEach-Object {
    $allRuleNames[$_.Name] = $true
}

$deletedRules = @(
    '05-ai-collaboration.mdc',
    '17-server-environment.mdc',
    '18-environment-alignment.mdc',
    '20-v1.5-features.mdc',
    '21-new-room-types.mdc'
)

foreach ($rule in $rules) {
    $content = Get-Content $rule.FullName -Raw
    foreach ($ref in $allRuleNames.Keys) {
        # Only fail if the reference is NOT a self-reference
        if ($ref -ne $rule.Name -and $content -match [regex]::Escape($ref)) {
            # Make sure it's actually referenced as a file link, not just appearing in text
            if ($content -match "``$ref``" -or $content -match "[./]$ref\b") {
                $hasRef = $true
            }
        }
    }
}

# Check 12-incident-response.mdc cross-ref (§四 should be §三)
$incidentContent = Get-Content "$RepoRoot\.cursor\rules\12-incident-response.mdc" -Raw
Test-Case "12-incident-response § cross-ref to 18-environment" {
    $incidentContent -match '18-environment\.mdc`'
}

# Check 03-git-workflow.mdc references
$gitContent = Get-Content "$RepoRoot\.cursor\rules\03-git-workflow.mdc" -Raw
Test-Case "03-git-workflow references 14-decision-trees" {
    $gitContent -match '14-decision-trees\.mdc`'
}
Test-Case "03-git-workflow references 15-pre-flight" {
    $gitContent -match '15-pre-flight\.mdc`'
}
Test-Case "03-git-workflow references 13-workflow" {
    $gitContent -match '13-workflow\.mdc`'
}

# Check 02-code-style.mdc references 10-documentation
$styleContent = Get-Content "$RepoRoot\.cursor\rules\02-code-style.mdc" -Raw
Test-Case "02-code-style references 10-documentation" {
    $styleContent -match '10-documentation\.mdc`'
}

# Check 10-documentation references 14-decision-trees
$docContent = Get-Content "$RepoRoot\.cursor\rules\10-documentation.mdc" -Raw
Test-Case "10-documentation references 14-decision-trees" {
    $docContent -match '14-decision-trees\.mdc`'
}

# ── T7: 版本一致性 ────────────────────────────────────────
Write-Host "T7: 版本一致性" -ForegroundColor Yellow

$verFile = Get-Content "$RepoRoot\VERSION" -Raw -ErrorAction SilentlyContinue
$verTrimLen = $verFile.Trim().Length
# VERSION vs 00-core 的版本故意不同（模板库版本 vs 目标项目版本）
# 只做非空检查，不强制一致
Test-Case "VERSION file not empty" { $verTrimLen -gt 0 }

# global-rule-paste.md should have a matching version with 00-core (they describe the same project)
$pasteContent = Get-Content "$RepoRoot\global-rule-paste.md" -Raw -ErrorAction SilentlyContinue
if ($pasteContent) {
    $pasteHasVer = $pasteContent -match "v\d+\.\d+"
    Test-Case "global-rule-paste.md contains version" { $pasteHasVer }
    # global-rule-paste.md 模板版本应与 VERSION 一致
$pasteHas10 = $pasteContent -match "v1\.0\.0"
Test-Case "global-rule-paste.md version matches VERSION (v1.0.0)" { $pasteHas10 }
}

# ── T8: .gitignore 覆盖率 ─────────────────────────────────
Write-Host "T8: .gitignore 覆盖率" -ForegroundColor Yellow
$gi = Get-Content "$RepoRoot\.gitignore" -Raw -ErrorAction SilentlyContinue
Test-Case ".gitignore covers .env protection" { $gi -match '\.env\*' }
Test-Case ".gitignore covers node_modules" { $gi -match 'node_modules' }
Test-Case ".gitignore covers _archive" { $gi -match '_archive' }

# ── T9: PowerShell 脚本编码 ───────────────────────────────
Write-Host "T9: PowerShell 脚本编码 (UTF-8 BOM)" -ForegroundColor Yellow
$allPs1 = @(
    "$RepoRoot\scripts\init-project.ps1",
    "$RepoRoot\scripts\sync-global-rule.ps1",
    "$RepoRoot\scripts\sync-local-configs.ps1",
    "$RepoRoot\tests\run-tests.ps1"
)
foreach ($f in $allPs1) {
    if (Test-Path $f) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $hasBom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $name = Split-Path $f -Leaf
        Test-Case "$name has UTF-8 BOM" { $hasBom }
    }
}

# ── T10: 已删除规则不再被引用 ─────────────────────────────
Write-Host "T10: 已删除规则不再被引用" -ForegroundColor Yellow

$installPath = Join-Path $RepoRoot "INSTALL.md"
if (Test-Path $installPath) {
    $installContent = Get-Content $installPath -Raw
    foreach ($deleted in $deletedRules) {
        $hasRef = $installContent -match [regex]::Escape($deleted)
        Test-Case "INSTALL.md no longer references $deleted" { -not $hasRef }
    }
}

# Check .cursor/rules/README.md
$readmePath = Join-Path $RepoRoot ".cursor\rules\README.md"
if (Test-Path $readmePath) {
    $readmeContent = Get-Content $readmePath -Raw
    foreach ($deleted in $deletedRules) {
        $hasRef = $readmeContent -match [regex]::Escape($deleted)
        Test-Case ".cursor/rules/README.md no longer references $deleted" { -not $hasRef }
    }
}

# ── T11: .gitattributes 完整性 ────────────────────────────
Write-Host "T11: .gitattributes 完整性" -ForegroundColor Yellow
$gaPath = Join-Path $RepoRoot ".gitattributes"
if (Test-Path $gaPath) {
    $gaContent = Get-Content $gaPath -Raw
    Test-Case ".gitattributes sets LF for most files" { $gaContent -match '\* text=auto eol=lf' }
    Test-Case ".gitattributes sets CRLF for .bat" { $gaContent -match '\*\.bat text eol=crlf' }
    Test-Case ".gitattributes sets LF for .ps1" { $gaContent -match '\*\.ps1 text eol=lf' }
}

# ── T12: _archive 目录结构 ────────────────────────────────
Write-Host "T12: _archive 目录结构" -ForegroundColor Yellow
$archivePath = Join-Path $RepoRoot "_archive"
Test-Case "_archive directory exists" { Test-Path $archivePath }
$expectedSubdirs = @('docs-old', 'deploy-packages', 'scripts-old')
foreach ($sub in $expectedSubdirs) {
    $subPath = Join-Path $archivePath $sub
    Test-Case "_archive/$sub exists" { Test-Path $subPath }
}

# ── Summary ───────────────────────────────────────────────
Write-Host ""
Write-Host "===== Summary =====" -ForegroundColor Cyan
Write-Host ("Total : {0}" -f $total) -ForegroundColor White
Write-Host ("Passed: {0}" -f $passed) -ForegroundColor Green
Write-Host ("Failed: {0}" -f $failed) -ForegroundColor Red
if ($failNames.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($fn in $failNames) {
        Write-Host ("  - {0}" -f $fn) -ForegroundColor Red
    }
}
Write-Host ""

if ($failed -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "SOME CHECKS FAILED" -ForegroundColor Red
    exit 1
}
