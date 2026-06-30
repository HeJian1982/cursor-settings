# Download and install codebase-memory-mcp for Windows x64
$ErrorActionPreference = 'Stop'

$downloadDir = "$env:LOCALAPPDATA\Temp\cbm-temp"
$installDir = "$env:LOCALAPPDATA\Programs\codebase-memory-mcp"
$binName = "codebase-memory-mcp.exe"
$versionUrl = "https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest"

New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

Write-Host "[1/4] Fetching latest release info..." -ForegroundColor Cyan
try {
    $req = [System.Net.WebRequest]::Create($versionUrl)
    $req.UserAgent = "cursor-settings-bot/1.0"
    $req.Accept = "application/json"
    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $json = $reader.ReadToEnd()
    $reader.Close()
    $resp.Close()
    $data = $json | ConvertFrom-Json
    $tag = $data.tag_name
    Write-Host "  Latest tag: $tag"
} catch {
    Write-Host "[ERR] Could not fetch version info: $_" -ForegroundColor Red
    exit 1
}

# Find Windows x64 zip asset
$zipAsset = $null
foreach ($asset in $data.assets) {
    if ($asset.name -match "windows-amd64\.zip") {
        $zipAsset = $asset
        break
    }
}

if (-not $zipAsset) {
    Write-Host "[ERR] No windows-amd64.zip found in release $tag" -ForegroundColor Red
    Write-Host "  Available assets:"
    $data.assets | ForEach-Object { Write-Host "    $($_.name)" }
    exit 1
}

$downloadUrl = $zipAsset.browser_download_url
$zipPath = Join-Path $downloadDir $zipAsset.name

Write-Host "[2/4] Downloading $($zipAsset.name) ($([Math]::Round($zipAsset.size/1MB, 1)) MB)..." -ForegroundColor Cyan
Write-Host "  URL: $downloadUrl"

try {
    $req2 = [System.Net.WebRequest]::Create($downloadUrl)
    $req2.UserAgent = "cursor-settings-bot/1.0"
    $resp2 = $req2.GetResponse()
    $totalBytes = $resp2.ContentLength
    $respStream = $resp2.GetResponseStream()
    $fs = [System.IO.File]::Create($zipPath)
    $buffer = New-Object byte[] 8192
    $bytesRead = 0
    $lastPct = -1
    while (($read = $respStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $fs.Write($buffer, 0, $read)
        $bytesRead += $read
        if ($totalBytes -gt 0) {
            $pct = [Math]::Floor($bytesRead * 100 / $totalBytes)
            if ($pct -ne $lastPct -and $pct % 10 -eq 0) {
                Write-Host "  $pct%..." -NoNewline
                $lastPct = $pct
            }
        }
    }
    Write-Host " 100%" -NoNewline
    $fs.Close()
    $respStream.Close()
    $resp2.Close()
    Write-Host ""
    Write-Host "  Downloaded: $([Math]::Round((Get-Item $zipPath).Length/1MB, 1)) MB" -ForegroundColor Green
} catch {
    Write-Host "[ERR] Download failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[3/4] Extracting to $installDir..." -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path (Join-Path $downloadDir "codebase-memory-mcp-windows-amd64")) {
        Remove-Item -Recurse -Force (Join-Path $downloadDir "codebase-memory-mcp-windows-amd64")
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $downloadDir)
    $extractedDir = Get-ChildItem $downloadDir -Directory | Where-Object { $_.Name -like "*windows*" } | Select-Object -First 1
    if ($extractedDir) {
        Write-Host "  Extracted: $($extractedDir.FullName)" -ForegroundColor Gray
        Copy-Item "$($extractedDir.FullName)\*" -Destination $installDir -Recurse -Force
        Write-Host "  Copied to: $installDir" -ForegroundColor Green
    } else {
        # Fallback: copy all files from zip root
        Copy-Item "$downloadDir\*" -Destination $installDir -Recurse -Force
    }
} catch {
    Write-Host "[ERR] Extraction failed: $_" -ForegroundColor Red
    exit 1
}

# Find the exe
$exePath = Get-ChildItem $installDir -Filter "*.exe" -Recurse | Select-Object -First 1
if (-not $exePath) {
    Write-Host "[ERR] No .exe found in $installDir" -ForegroundColor Red
    exit 1
}
Write-Host "[4/4] Binary found: $($exePath.FullName)" -ForegroundColor Green
Write-Host ""

# Create mcp.json
$mcpJsonPath = "C:\Users\HJ2\AppData\Roaming\Cursor\User\mcp.json"
$mcpConfig = @{
    mcpServers = @{
        "codebase-memory-mcp" = @{
            command = $exePath.FullName
            args = @()
        }
    }
} | ConvertTo-Json -Depth 5

$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($mcpJsonPath, $mcpConfig + "`n", $utf8Bom)
Write-Host "[OK] mcp.json written to: $mcpJsonPath" -ForegroundColor Green

# Cleanup
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Installation Summary ===" -ForegroundColor Cyan
Write-Host "  Binary:  $($exePath.FullName)"
Write-Host "  Version: $tag"
Write-Host "  MCP JSON: $mcpJsonPath"
Write-Host ""
Write-Host "NEXT: Restart Cursor to activate the MCP server." -ForegroundColor Yellow