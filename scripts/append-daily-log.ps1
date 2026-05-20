<#
.SYNOPSIS
  Append daily cursor transcript to log file

.DESCRIPTION
  Reads Cursor transcript JSONL, extracts user requests and key actions,
  appends to cursor-transcripts/YYYY-MM-DD.md daily log.

.PARAMETER TranscriptDir
  Cursor transcript directory (default: auto-detect)

.PARAMETER LogDir
  Daily log output directory (default: auto-detect)

.PARAMETER SessionId
  Specific session UUID (default: latest)

.PARAMETER DryRun
  Preview only, no file writes

.EXAMPLE
  .\append-daily-log.ps1 -DryRun
  .\append-daily-log.ps1
#>

[CmdletBinding()]
param(
    [string]$TranscriptDir = "",
    [string]$LogDir = "",
    [string]$SessionId = "",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($TranscriptDir -eq "") {
    $TranscriptDir = "C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts"
}
if ($LogDir -eq "") {
    $LogDir = "e:\HJ\cursor\cursor-transcripts"
}

Write-Host ""
Write-Host "===== Append Daily Log =====" -ForegroundColor Cyan

# Determine session ID
$targetSession = $SessionId
if ($targetSession -eq "") {
    $latestDir = Get-ChildItem $TranscriptDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestDir) {
        $targetSession = $latestDir.Name
    }
}

if (-not $targetSession) {
    Write-Host "[ERROR] No session found" -ForegroundColor Red
    exit 1
}

Write-Host ("Session ID : {0}" -f $targetSession) -ForegroundColor Gray

$sessionDir = Join-Path $TranscriptDir $targetSession
$jsonlPath = Join-Path $sessionDir "$targetSession.jsonl"

if (-not (Test-Path $jsonlPath)) {
    Write-Host ("[ERROR] JSONL not found: {0}" -f $jsonlPath) -ForegroundColor Red
    exit 1
}

# Parse JSONL
Write-Host "Parsing JSONL..." -ForegroundColor Gray
$rawLines = Get-Content $jsonlPath -Raw
$entries = @()
foreach ($line in ($rawLines -split "`n")) {
    if ($line.Trim() -ne "") {
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry) {
                $entries += $entry
            }
        } catch { }
    }
}

Write-Host ("  Entries : {0}" -f $entries.Count) -ForegroundColor Gray

# Extract user messages
$userMessages = @()
foreach ($entry in $entries) {
    if ($entry.role -eq "user") {
        $msg = $entry.message
        $text = ""
        if ($msg.content -is [array]) {
            foreach ($block in $msg.content) {
                if ($block.type -eq "text") {
                    $text = $block.text -replace '<[^>]+>', ''
                    break
                }
            }
        } elseif ($msg.content -is [string]) {
            $text = $msg.content -replace '<[^>]+>', ''
        }
        if ($text.Trim()) {
            $truncated = $text.Trim().Substring(0, [Math]::Min(300, $text.Trim().Length))
            $userMessages += $truncated
        }
    }
}

# Extract file operations and git commits
$fileOps = @()
$commitHash = ""
$gitStatus = "未提交"

foreach ($entry in $entries) {
    if ($entry.role -eq "assistant") {
        $msg = $entry.message
        if ($msg.content -is [array]) {
            foreach ($block in $msg.content) {
                if ($block.type -eq "tool_use") {
                    $toolName = $block.name
                    $toolInput = $block.input
                    if ($toolName -match "^(Write|StrReplace|Delete)$" -or $toolName -eq "EditNotebook") {
                        $path = $toolInput.path
                        if ($path) {
                            $fileName = Split-Path $path -Leaf
                            if ($fileOps -notcontains $fileName) {
                                $fileOps += $fileName
                            }
                        }
                    }
                    if ($toolName -eq "Shell" -and $toolInput.command) {
                        if ($toolInput.command -match 'git commit') {
                            $gitStatus = "已提交"
                            if ($toolInput.command -match '[a-f0-9]{7,40}') {
                                $commitHash = $matches[0]
                            }
                        }
                    }
                }
            }
        }
    }
}

$uniqueFiles = $fileOps | Select-Object -First 8

# Extract timestamp
$sessionTime = $null
foreach ($msg in $userMessages) {
    if ($msg -match '(\d{4}-\d{2}-\d{2})') {
        try {
            $sessionTime = [DateTime]::ParseExact($matches[0], "yyyy-MM-dd", $null)
            break
        } catch { }
    }
}

if (-not $sessionTime) {
    $sessionTime = (Get-Item $jsonlPath).LastWriteTime
}

$dateStr = $sessionTime.ToString("yyyy-MM-dd")
$timeStr = $sessionTime.ToString("HH:mm")
$dateHeader = $sessionTime.ToString("yyyy年MM月dd日")

# Topic
$topic = ""
if ($userMessages.Count -gt 0) {
    $firstMsg = $userMessages[0]
    if ($firstMsg.Length -gt 80) {
        $topic = $firstMsg.Substring(0, 80) + "..."
    } else {
        $topic = $firstMsg
    }
    $topic = $topic -replace '[\r\n]+', ' ' -replace '\s+', ' '
}

# Build file list
$fileListStr = ""
if ($uniqueFiles.Count -gt 0) {
    $fileListParts = @()
    foreach ($f in $uniqueFiles) {
        $fileListParts += "- ``$f``"
    }
    $fileListStr = $fileListParts -join "`n"
} else {
    $fileListStr = "- （无文件改动）"
}

# Commit status
$commitStatusStr = $gitStatus
if ($commitHash -ne "") {
    $commitStatusStr = "$gitStatus ($commitHash)"
}

# Transcript integrity signature
$transcriptHash = ""
if (Test-Path $jsonlPath) {
    $transcriptHash = (Get-FileHash $jsonlPath -Algorithm SHA256).Hash
}

# Build log entry
$logEntry = @"

### $timeStr 左右
**会话 ID**: ``$targetSession``

| 项目 | 内容 |
|------|------|
| 主题 | $topic |
| 触发条件 | 用户主动发起 |
| 动作 | 详见 git commit |
| 结果 | $commitStatusStr |

#### 改动文件
$fileListStr

#### Transcript 完整性签名
- SHA256: ``$transcriptHash``
- 文件大小: $((Get-Item $jsonlPath).Length) bytes
- 生成时间: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')

"@

# Write log file
$logPath = Join-Path $LogDir "$dateStr.md"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Write-Host ("[INFO] Created: {0}" -f $LogDir) -ForegroundColor Cyan
}

if (Test-Path $logPath) {
    # Append before final ---
    $content = Get-Content $logPath -Raw
    $separator = "`n---`n`n"
    if ($content -match "`n---\s*$") {
        $logEntry = $separator + $logEntry.Trim() + "`n`n---`n"
        $newContent = $content -replace "`n---\s*$", $logEntry
    } else {
        $logEntry = "`n`n---\n" + $logEntry.Trim() + "`n`n---`n"
        $newContent = $content.TrimEnd() + $logEntry
    }
} else {
    # Create new file
    $header = "# Cursor AI 每日会话日志`n`n> 每条会话自动追加至此，按日期归档。格式：每轮对话一行，包含时间、主题、结果。`n`n---`n`n## $dateHeader`n`n"
    $footer = "`n`n---`n"
    $newContent = $header + $logEntry.Trim() + $footer
}

if ($DryRun) {
    Write-Host ""
    Write-Host "===== DRY RUN =====" -ForegroundColor Yellow
    Write-Host ("Would write to: {0}" -f $logPath) -ForegroundColor Gray
    Write-Host ""
    Write-Host $logEntry -ForegroundColor White
} else {
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($logPath, $newContent, $utf8Bom)
    Write-Host ""
    Write-Host "[OK] Appended to: $logPath" -ForegroundColor Green
    Write-Host ("     Session : {0}" -f $targetSession) -ForegroundColor Gray
    Write-Host ("     Files   : {0} changed" -f $uniqueFiles.Count) -ForegroundColor Gray
    Write-Host ("     Commit  : {0}" -f $gitStatus) -ForegroundColor Gray
}

Write-Host ""
