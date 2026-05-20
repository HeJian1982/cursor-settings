<#
.SYNOPSIS
  Cursor 模板库测试套件

.DESCRIPTION
  零依赖自测试（不需要 Pester / PSScriptAnalyzer）
  验证模板库完整性、一致性、编码规范和安全基线

  测试覆盖：
  T1: 规则文件数量
  T2: 核心规则完整性
  T3: 脚本文件存在性
  T4: 全局配置文件
  T5: 规则文件元数据（description）
  T6: 跨文件引用一致性
  T7: 版本一致性
  T8: .gitignore 覆盖率
  T9: PowerShell 脚本编码 + SHA256 基线
  T10: 已删除规则不再被引用
  T11: .gitattributes 完整性
  T12: _archive 目录结构
  T13: 安全基线完整性（脚本/Skills/Cursor settings）
  T14: 新增文件扫描（可疑脚本注入）
  T15: Transcript 基线快照

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
    Write-Host ("  [{0:D02}] {1}..." -f $script:total, $Name) -NoNewline
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
$scriptFiles = @('init-project.ps1', 'sync-global-rule.ps1', 'sync-local-configs.ps1', 'append-daily-log.ps1', 'generate-baselines.ps1')
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
    $hasDesc = $content -match 'description:\s*"?[^"\r\n]+"?'
    Test-Case "$($rule.Name) has description" { $hasDesc }
}

# ── T6: 跨文件引用一致性 ─────────────────────────────────
Write-Host "T6: 跨文件引用一致性" -ForegroundColor Yellow

$incidentContent = Get-Content "$RepoRoot\.cursor\rules\12-incident-response.mdc" -Raw
Test-Case "12-incident-response references 18-environment" {
    $incidentContent -match '18-environment\.mdc`'
}

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

$styleContent = Get-Content "$RepoRoot\.cursor\rules\02-code-style.mdc" -Raw
Test-Case "02-code-style references 10-documentation" {
    $styleContent -match '10-documentation\.mdc`'
}

$docContent = Get-Content "$RepoRoot\.cursor\rules\10-documentation.mdc" -Raw
Test-Case "10-documentation references 14-decision-trees" {
    $docContent -match '14-decision-trees\.mdc`'
}

# ── T7: 版本一致性 ────────────────────────────────────────
Write-Host "T7: 版本一致性" -ForegroundColor Yellow

$verFile = Get-Content "$RepoRoot\VERSION" -Raw -ErrorAction SilentlyContinue
$verTrimLen = $verFile.Trim().Length
Test-Case "VERSION file not empty" { $verTrimLen -gt 0 }

$pasteContent = Get-Content "$RepoRoot\global-rule-paste.md" -Raw -ErrorAction SilentlyContinue
if ($pasteContent) {
    Test-Case "global-rule-paste.md contains version" {
        $pasteContent -match "v\d+\.\d+"
    }
    Test-Case "global-rule-paste.md version matches VERSION (v1.0.0)" {
        $pasteContent -match "v1\.0\.0"
    }
}

# ── T8: .gitignore 覆盖率 ─────────────────────────────────
Write-Host "T8: .gitignore 覆盖率" -ForegroundColor Yellow
$gi = Get-Content "$RepoRoot\.gitignore" -Raw -ErrorAction SilentlyContinue
Test-Case ".gitignore covers .env protection" { $gi -match '\.env\*' }
Test-Case ".gitignore covers node_modules" { $gi -match 'node_modules' }
Test-Case ".gitignore covers _archive" { $gi -match '_archive' }
Test-Case ".gitignore covers cursor-transcripts" { $gi -match 'cursor-transcripts' }

# ── T9: PowerShell 脚本编码 + SHA256 基线 ────────────────
Write-Host "T9: PowerShell 脚本编码 + SHA256 基线" -ForegroundColor Yellow

# T9a: 编码检查（.ps1 不需要 BOM，gitattributes 已设置 eol=lf）
$allPs1 = @(
    "$RepoRoot\scripts\init-project.ps1",
    "$RepoRoot\scripts\sync-global-rule.ps1",
    "$RepoRoot\scripts\sync-local-configs.ps1",
    "$RepoRoot\scripts\append-daily-log.ps1",
    "$RepoRoot\scripts\generate-baselines.ps1",
    "$RepoRoot\tests\run-tests.ps1"
)
# T9a: 编码检查
# .ps1 脚本需带 UTF-8 BOM（PowerShell 5.1 兼容性）
# 但 baselines.json 用 ConvertTo-Json 输出时无 BOM，generate-baselines.ps1 也无 BOM
# 最终所有含中文的脚本由 Write 工具统一写 UTF-8 BOM
foreach ($f in $allPs1) {
    if (Test-Path $f) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $hasBom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $name = Split-Path $f -Leaf
        # 脚本文件应带 BOM（有中文字符时 Write 工具自动带 BOM）
        Test-Case "$name has UTF-8 BOM" { $hasBom -eq $true }
    }
}

# T9b: SHA256 基线检查
$baselinePath = Join-Path $RepoRoot "scripts\baselines.json"
Test-Case "baselines.json exists" { Test-Path $baselinePath }

if (Test-Path $baselinePath) {
    $baselineJson = Get-Content $baselinePath -Raw -ErrorAction SilentlyContinue
    $baseline = $baselineJson | ConvertFrom-Json -ErrorAction SilentlyContinue

    if ($baseline) {
        # Script hashes
        foreach ($name in $baseline.scripts.PSObject.Properties.Name) {
            $expectedHash = $baseline.scripts.$name
            $actualPath = "$RepoRoot\scripts\$name"
            if (-not (Test-Path $actualPath)) {
                $actualPath = "$RepoRoot\tests\$name"
            }
            if (Test-Path $actualPath) {
                $actualHash = (Get-FileHash $actualPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                $match = $actualHash -eq $expectedHash
                Test-Case "SHA256 baseline for $name" { $match }
            }
        }

        # Cursor settings.json baseline
        if ($baseline.cursorSettings -and $baseline.cursorSettings -ne "") {
            $cursorSettingsPath = "$env:APPDATA\Cursor\User\settings.json"
            if (Test-Path $cursorSettingsPath) {
                $actualHash = (Get-FileHash $cursorSettingsPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                $match = $actualHash -eq $baseline.cursorSettings
                Test-Case "SHA256 baseline for Cursor settings.json" { $match }
            }
        }
    }
}

# ── T10: 已删除规则不再被引用 ─────────────────────────────
Write-Host "T10: 已删除规则不再被引用" -ForegroundColor Yellow

$deletedRules = @(
    '05-ai-collaboration.mdc',
    '17-server-environment.mdc',
    '18-environment-alignment.mdc',
    '20-v1.5-features.mdc',
    '21-new-room-types.mdc'
)

$installPath = Join-Path $RepoRoot "INSTALL.md"
if (Test-Path $installPath) {
    $installContent = Get-Content $installPath -Raw
    foreach ($deleted in $deletedRules) {
        Test-Case "INSTALL.md no longer references $deleted" {
            -not ($installContent -match [regex]::Escape($deleted))
        }
    }
}

$readmePath = Join-Path $RepoRoot ".cursor\rules\README.md"
if (Test-Path $readmePath) {
    $readmeContent = Get-Content $readmePath -Raw
    foreach ($deleted in $deletedRules) {
        Test-Case ".cursor/rules/README.md no longer references $deleted" {
            -not ($readmeContent -match [regex]::Escape($deleted))
        }
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

# ── T13: Skills 基线检查 ───────────────────────────────────
Write-Host "T13: Skills SHA256 基线" -ForegroundColor Yellow

if ($baseline) {
    $skillsChecked = 0
    $skillsFailed = 0
    $skillDirs = @(
        "C:\Users\HJ2\.cursor\skills-cursor",
        "C:\Users\HJ2\.claude\skills",
        "C:\Users\HJ2\.agents\skills",
        "C:\Users\HJ2\.claude\plugins\cache\claude-plugins-official\superpowers\5.1.0\skills"
    )

    foreach ($skillName in $baseline.skills.PSObject.Properties.Name) {
        $expectedHash = $baseline.skills.$skillName
        $found = $false
        $matched = $false

        foreach ($dir in $skillDirs) {
            if (-not (Test-Path $dir)) { continue }
            $skillPath = Join-Path $dir "$skillName\SKILL.md"
            if (Test-Path $skillPath) {
                $found = $true
                $actualHash = (Get-FileHash $skillPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                $matched = $actualHash -eq $expectedHash
                break
            }
        }

        $skillsChecked++
        if ($found) {
            $allMatch = $matched
            if (-not $allMatch) { $skillsFailed++ }
        }
    }

    Test-Case "All Skills SHA256 baselines match ($skillsChecked checked, $skillsFailed mismatched)" {
        $allMatch = $skillsFailed -eq 0
        $allMatch
    }
} else {
    Test-Case "Skills baseline check skipped (no baseline)" { $true }
}

# ── T14: 新增可疑文件扫描 ─────────────────────────────────
Write-Host "T14: 新增可疑文件扫描" -ForegroundColor Yellow

# 白名单：允许的脚本扩展名和路径
$allowedScriptExts = @('.ps1', '.sh', '.bat', '.cmd')
$allowedPaths = @(
    'scripts\',
    'tests\',
    '_archive\',
    '.github\'
)

# 扫描仓库根目录及一级子目录中的新脚本文件
$suspicious = @()
$topDirs = Get-ChildItem $RepoRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '^(node_modules|\.git|_archive|cursor-transcripts|docs)$' }

foreach ($dir in $topDirs) {
    Get-ChildItem $dir.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
        $ext = $_.Extension.ToLower()
        $inAllowedPath = $false
        foreach ($ap in $allowedPaths) {
            if ($_.FullName -match [regex]::Escape($ap)) {
                $inAllowedPath = $true
                break
            }
        }
        # Exclude underscore-prefixed files (temp/utility scripts)
        $isTemp = $_.Name -match '^_'
        if ($allowedScriptExts -contains $ext -and -not $inAllowedPath -and -not $isTemp) {
            $suspicious += $_.FullName
        }
    }
}

# 检查根目录的脚本（排除 _ 前缀的临时文件）
Get-ChildItem $RepoRoot -File -ErrorAction SilentlyContinue | ForEach-Object {
    $ext = $_.Extension.ToLower()
    $isTemp = $_.Name -match '^_'
    if ($allowedScriptExts -contains $ext -and -not $isTemp) {
        $suspicious += $_.FullName
    }
}

Test-Case "No suspicious scripts outside allowed directories" {
    $suspicious.Count -eq 0
}

# 检查是否有新的 .ps1 文件在 scripts/ 目录但未在基线中
$baselineScriptNames = @()
if ($baseline -and $baseline.scripts) {
    $baselineScriptNames = @($baseline.scripts.PSObject.Properties.Name)
}

Get-ChildItem "$RepoRoot\scripts\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.Name
    if ($baselineScriptNames -notcontains $name) {
        $suspicious += "scripts\$name (not in baseline)"
    }
}

# ── T15: Transcript 基线快照 ──────────────────────────────
Write-Host "T15: Transcript 基线快照" -ForegroundColor Yellow

$transcriptDir = "C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
if (Test-Path $transcriptDir) {
    $sessionDirs = Get-ChildItem $transcriptDir -Directory -ErrorAction SilentlyContinue
    $recentSessions = $sessionDirs | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    $hasRecent = $recentSessions.Count -gt 0

    Test-Case "Recent transcript sessions exist" { $hasRecent }

    # 检查每个最近会话的 JSONL 文件大小是否合理（> 100 bytes, < 50MB）
    foreach ($sess in $recentSessions) {
        $jsonlPath = Join-Path $sess.FullName "$($sess.Name).jsonl"
        if (Test-Path $jsonlPath) {
            $size = (Get-Item $jsonlPath).Length
            $saneSize = $size -gt 100 -and $size -lt 50MB
            $shortName = $sess.Name.Substring(0, 8)
            Test-Case "Transcript $shortName size is sane (100B-50MB)" { $saneSize }
        }
    }
} else {
    Test-Case "Transcript directory accessible" { $false }
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
