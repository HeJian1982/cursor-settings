<#
.SYNOPSIS
  在新项目根目录下初始化 Cursor AI 协作规则

.DESCRIPTION
  自动复制所有规则文件到目标项目的 .cursor/rules/
  交互式填写项目信息，替换 .mdc 文件中的 {{占位符}}
  同时创建 .editorconfig、.gitignore 等配置文件

.PARAMETER ProjectPath
  目标项目根目录，默认当前目录

.PARAMETER TemplateRoot
  模板库根目录，默认 ~\.cursor-templates\ 或脚本所在目录的父目录

.PARAMETER SkipInteractive
  跳过交互式配置，使用默认值

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "E:\HJ\cursor\scripts\init-project.ps1"
  .\init-project.ps1 -ProjectPath "e:\HJ\MyProject" -SkipInteractive
#>

[CmdletBinding()]
param(
    [string]$ProjectPath = $PWD.Path,
    [string]$TemplateRoot = "",
    [switch]$SkipInteractive
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($TemplateRoot -eq "") {
    $TemplateRoot = Split-Path -Parent $ScriptDir
}
$RepoRoot = $TemplateRoot

Write-Host ""
Write-Host "===== Cursor AI 协作规则初始化 =====" -ForegroundColor Cyan
Write-Host "Project  : $ProjectPath" -ForegroundColor Gray
Write-Host "Template : $RepoRoot" -ForegroundColor Gray
Write-Host ""

# --- 收集项目信息 ---
$projectInfo = @{}

if ($SkipInteractive) {
    $projectInfo['PROJECT_NAME'] = Split-Path -Leaf $ProjectPath
    $projectInfo['AUTHOR'] = $env:USERNAME
    $projectInfo['GIT_REMOTE'] = ""
    $projectInfo['DEPLOY_ENV'] = ""
} else {
    Write-Host "=== 项目信息配置 ===" -ForegroundColor Yellow
    Write-Host "(直接回车使用默认值)" -ForegroundColor Gray
    Write-Host ""

    $defaultName = Split-Path -Leaf $ProjectPath
    $defaultAuthor = $env:USERNAME

    $projectInfo['PROJECT_NAME'] = Read-Host "项目名称" | ForEach-Object { if ($_ -eq "") { $defaultName } else { $_ } }
    $projectInfo['AUTHOR'] = Read-Host "作者" | ForEach-Object { if ($_ -eq "") { $defaultAuthor } else { $_ } }
    $projectInfo['GIT_REMOTE'] = Read-Host "Git 远端 (可选)"
    $projectInfo['DEPLOY_ENV'] = Read-Host "部署环境 (可选)"
}

Write-Host ""

# --- 检查并创建 .cursor/rules 目录 ---
$CursorRulesDir = Join-Path $ProjectPath ".cursor\rules"
if (Test-Path $CursorRulesDir) {
    Write-Host "[WARN] .cursor/rules/ 已存在" -ForegroundColor Yellow
    $ans = Read-Host "覆盖现有规则？(y/N)"
    if ($ans -notmatch '^[yY]') {
        Write-Host "已取消" -ForegroundColor Red
        exit 0
    }
    # 备份
    $backupDir = "$CursorRulesDir.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item $CursorRulesDir $backupDir -Force
    Write-Host "  备份到: $backupDir" -ForegroundColor Gray
}

New-Item -ItemType Directory -Force -Path $CursorRulesDir | Out-Null

# --- 复制规则文件并替换占位符 ---
$SrcRulesDir = Join-Path $RepoRoot ".cursor\rules"
if (-not (Test-Path $SrcRulesDir)) {
    throw "Source rules dir not found: $SrcRulesDir"
}

$count = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

Get-ChildItem "$SrcRulesDir\*.mdc" | ForEach-Object {
    $srcContent = Get-Content -Raw -Path $_.FullName -Encoding UTF8

    # 替换占位符
    $dstContent = $srcContent
    $dstContent = $dstContent -replace '\{\{PROJECT_NAME\}\}', $projectInfo['PROJECT_NAME']
    $dstContent = $dstContent -replace '\{\{AUTHOR\}\}', $projectInfo['AUTHOR']
    $dstContent = $dstContent -replace '\{\{GIT_REMOTE\}\}', ($projectInfo['GIT_REMOTE'] -replace '/', '\/')
    $dstContent = $dstContent -replace '\{\{DEPLOY_ENV\}\}', $projectInfo['DEPLOY_ENV']

    $dstPath = Join-Path $CursorRulesDir $_.Name
    [System.IO.File]::WriteAllText($dstPath, $dstContent, $utf8NoBom)
    $count++
}

Write-Host "[OK] 复制并替换了 $count 个规则文件" -ForegroundColor Green

# --- 复制配置文件 ---
Write-Host ""
Write-Host "=== 配置文件 ===" -ForegroundColor Yellow

$configFiles = @(
    @{ src = ".editorconfig"; dst = ".editorconfig"; desc = ".editorconfig" },
    @{ src = ".gitignore"; dst = ".gitignore"; desc = ".gitignore" }
)

foreach ($cf in $configFiles) {
    $srcPath = Join-Path $RepoRoot $cf.src
    if (Test-Path $srcPath) {
        $dstPath = Join-Path $ProjectPath $cf.dst
        Copy-Item $srcPath $dstPath -Force
        Write-Host "  [OK] $($cf.desc)" -ForegroundColor Green
    }
}

# --- 创建 .env.local.template ---
$envTemplatePath = Join-Path $ProjectPath ".env.local.template"
if (-not (Test-Path $envTemplatePath)) {
    $envTemplate = @"
# Cursor 项目环境变量模板
# 复制此文件为 .env.local 并填写实际值
# .env.local 不得提交到 git

# 数据库
DATABASE_URL=

# API 密钥
API_KEY=

# 其他
NEXT_PUBLIC_SITE_URL=http://localhost:3000
"@
    [System.IO.File]::WriteAllText($envTemplatePath, $envTemplate, $utf8NoBom)
    Write-Host "  [OK] .env.local.template" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  初始化完成！" -ForegroundColor Green
Write-Host "  项目: $($projectInfo['PROJECT_NAME'])" -ForegroundColor Gray
Write-Host "  规则: $CursorRulesDir" -ForegroundColor Gray
Write-Host ""
Write-Host "  下一步：" -ForegroundColor Yellow
Write-Host "  1. 重启 Cursor IDE 以加载新规则" -ForegroundColor Gray
Write-Host "  2. 编辑 .env.local.template 填写实际值" -ForegroundColor Gray
Write-Host "  3. 将 .env.local 添加到 .gitignore（如尚未）" -ForegroundColor Gray
Write-Host ""
