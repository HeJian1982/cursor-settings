<#
.SYNOPSIS
  网站健康快检 — 多站点并行检查
.DESCRIPTION
  对目标站点做 30 秒内轻量级健康检查，输出场景 A/B/C 格式。
  巡检结果写入 memory/site-monitor/state.json。
.PARAMETER Sites
  逗号分隔的站点列表，默认: hj1982.cn,1982.cn
.PARAMETER OutputJson
  输出 JSON 格式
.EXAMPLE
  .\site-monitor.ps1
  .\site-monitor.ps1 -Sites "hj1982.cn,1982.cn" -OutputJson
#>

[CmdletBinding()]
param(
    [string]$Sites = "hj1982.cn,1982.cn",
    [switch]$OutputJson
)

$ErrorActionPreference = 'Continue'

$RepoRoot  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$StateFile = Join-Path $RepoRoot "memory\site-monitor\state.json"
$LogDir    = Join-Path $RepoRoot "logs"
$utf8Bom   = New-Object System.Text.UTF8Encoding $true

$now       = Get-Date
$beijingTs = $now.ToUniversalTime().AddHours(8).ToString("HH:mm")

# ── 记忆读写 ────────────────────────────────────────────
function Get-Mem {
    param([string]$Key, $Default = $null)
    if (-not (Test-Path $StateFile)) { return $Default }
    try {
        $j = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        if ($j -and $j.ContainsKey($Key)) { return $j[$Key] }
        return $Default
    } catch { return $Default }
}

function Set-Mem {
    param([string]$Key, $Value)
    $obj = @{}
    if (Test-Path $StateFile) {
        try { $obj = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch {}
    }
    $obj[$Key] = $Value
    $dir = Split-Path $StateFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($StateFile, ($obj | ConvertTo-Json -Depth 10), $utf8Bom)
}

# ── 读取记忆 ────────────────────────────────────────────
$prevVersion       = Get-Mem "prev_version"       $null
$consecutiveFails  = Get-Mem "consecutive_failures" 0
$lastFailureItem   = Get-Mem "last_failure_item"  $null
$baselineHomeMs    = Get-Mem "baseline_home_ms"   $null
$baselineApiMs     = Get-Mem "baseline_api_ms"    $null
$baselineHomeList  = Get-Mem "baseline_home_list" @()
$baselineApiList   = Get-Mem "baseline_api_list"  @()

# ── HTTP 检查函数 ──────────────────────────────────────
function Test-Site {
    param([string]$Url, [int]$TimeoutMs = 8000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutMs
        $req.UserAgent = "SiteMonitor/1.0"
        $req.AllowAutoRedirect = $true
        $req.MaximumAutomaticRedirections = 3
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        $sw.Stop()
        return @{ ok = $true; code = $code; ms = $sw.ElapsedMilliseconds; err = $null }
    } catch {
        $sw.Stop()
        $code = 0
        $msg = $_.Exception.Message
        $we = $_.Exception -as [System.Net.WebException]
        if ($we -and $we.Response) { $code = [int]$we.Response.StatusCode }
        return @{ ok = $false; code = $code; ms = $sw.ElapsedMilliseconds; err = $msg }
    }
}

function Get-SiteVersion {
    param([string]$Domain)
    $url = "https://$Domain/api/version"
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 6 -UserAgent "SiteMonitor/1.0" -ErrorAction Stop
        if ($r.version) { return @{ ok = $true; value = $r.version } }
        $body = $r | ConvertTo-Json -Compress -ErrorAction SilentlyContinue
        if ($body -match '"version"\s*:\s*"([^"]+)"') { return @{ ok = $true; value = $matches[1] } }
        return @{ ok = $false; value = $null }
    } catch { return @{ ok = $false; value = $null } }
}

function Get-SiteHealth {
    param([string]$Domain)
    $url = "https://$Domain/api/health"
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 6 -UserAgent "SiteMonitor/1.0" -ErrorAction Stop
        return @{ ok = $true; code = 200 }
    } catch {
        $we = $_.Exception -as [System.Net.WebException]
        if ($we -and $we.Response) {
            $code = [int]$we.Response.StatusCode
            return @{ ok = ($code -ne 404); code = $code; note = if ($code -eq 404) { "not_found" } else { $null } }
        }
        return @{ ok = $false; code = 0 }
    }
}

function Get-CertDays {
    param([string]$Domain)
    try {
        $req = [System.Net.HttpWebRequest]::Create("https://$Domain/")
        $req.Method = "HEAD"
        $req.Timeout = 5000
        $req.ServicePoint.Certificate | Out-Null
        $cert = $req.ServicePoint.Certificate
        if (-not $cert) { return $null }
        $expiry = [DateTime]::Parse($cert.GetExpirationDateString())
        $days = ($expiry - $now).Days
        $req.Abort()
        return $days
    } catch { return $null }
}

# ── 执行巡检 ────────────────────────────────────────────
$domainList = $Sites -split ',' | ForEach-Object { $_.Trim() }
$allResults = @()
$globalFailure = $false
$versionChanged = $false

foreach ($domain in $domainList) {
    # 首页
    $homeResult = Test-Site -Url "https://$domain/" -TimeoutMs 8000

    # Version
    $verResult = Get-SiteVersion -Domain $domain
    $ver = $verResult.value

    # Health
    $healthResult = Get-SiteHealth -Domain $domain

    # 证书
    $certDays = Get-CertDays -Domain $domain

    # 关键字
    $keywordFound = $null
    if ($homeResult.ok -and $homeResult.ms -lt 5000) {
        try {
            $req2 = [System.Net.HttpWebRequest]::Create("https://$domain/")
            $req2.Timeout = 8000
            $req2.UserAgent = "SiteMonitor/1.0"
            $rp2 = $req2.GetResponse()
            $sr2 = New-Object System.IO.StreamReader($rp2.GetResponseStream())
            $html = $sr2.ReadToEnd()
            $sr2.Close(); $rp2.Close()
            $keywordFound = $html -match '何健'
        } catch { $keywordFound = $null }
    }

    # 失败项
    $failures = @()
    if (-not $homeResult.ok) { $failures += "首页" }
    if ($homeResult.ok -and $homeResult.ms -gt 5000) { $failures += "性能劣化" }
    if (-not $verResult.ok -and $homeResult.ok) { $failures += "Version字段" }
    if (-not $healthResult.ok) { $failures += "Health接口" }
    if ($null -ne $certDays -and $certDays -le 7) { $failures += "证书过期" }

    if ($failures.Count -gt 0) { $globalFailure = $true }
    if ($ver -and $prevVersion -and $ver -ne $prevVersion) { $versionChanged = $true }

    $obj = @{
        site = $domain
        homeOk = $homeResult.ok
        homeCode = $homeResult.code
        homeMs = $homeResult.ms
        homeErr = $homeResult.err
        version = $ver
        versionOk = $verResult.ok
        healthOk = $healthResult.ok
        healthCode = $healthResult.code
        certDays = $certDays
        keywordFound = $keywordFound
        failures = $failures
        perfDegraded = ($homeResult.ok -and $homeResult.ms -gt 5000)
        ok = ($failures.Count -eq 0)
    }
    $allResults += $obj
}

# ── 连续失败计数 ──────────────────────────────────────
if ($globalFailure) {
    $failStr = ($allResults[0].failures -join ',')
    if ($lastFailureItem -eq $failStr) {
        $consecutiveFails = [int]$consecutiveFails + 1
    } else {
        $consecutiveFails = 1
    }
} else {
    $consecutiveFails = 0
}

# ── 更新基线 ───────────────────────────────────────────
if (-not $globalFailure) {
    $h = $allResults[0].homeMs
    if ($null -ne $h) {
        $list = @($h) + @($baselineHomeList)
        $list = $list | Select-Object -First 3
        $avg = [int](($list | Measure-Object -Average).Average)
        Set-Mem "baseline_home_list" $list
        Set-Mem "baseline_home_ms" $avg
    }
}

# ── 写记忆 ────────────────────────────────────────────
if ($allResults[0].version) { Set-Mem "prev_version" $allResults[0].version }
Set-Mem "consecutive_failures" $consecutiveFails
Set-Mem "last_failure_item" $(if ($globalFailure) { ($allResults[0].failures -join ',') } else { $null })
Set-Mem "last_check" $now.ToString("yyyy-MM-dd HH:mm:ss")

# ── 输出 ───────────────────────────────────────────────
function Out-Row($r) {
    $st = if ($r.ok) { "OK" } else { "FAIL" }
    $hm = if ($null -ne $r.homeMs) { "$($r.homeMs)ms" } else { "N/A" }
    $vr = if ($r.version) { "v=$($r.version)" } else { "v=N/A" }
    $ct = if ($null -ne $r.certDays) { "cert=$($r.certDays)d" } else { "cert=N/A" }
    return "  $($r.site): home=$hm | $vr | $ct"
}

$anyFailure   = ($allResults | Where-Object { -not $_.ok }).Count -gt 0
$anyDegraded  = ($allResults | Where-Object { $_.perfDegraded }).Count -gt 0

if (-not $anyFailure -and -not $anyDegraded) {
    # 场景 A
    $lines = @()
    $line = "✅ $beijingTs 全部正常"
    foreach ($r in $allResults) { $line += " | $(Out-Row $r)" }
    $lines += $line
    if ($versionChanged) {
        $lines += "📦 检测到发版：$prevVersion → $($allResults[0].version)"
    }
    if ($OutputJson) {
        Write-Output ($lines -join "`n")
    } else {
        foreach ($l in $lines) { Write-Output $l }
    }
} else {
    foreach ($r in $allResults) {
        if (-not $r.ok) {
            # 场景 B
            Write-Output "🚨 [$beijingTs] $($r.site) 异常告警"
            foreach ($f in $r.failures) {
                $phen = switch ($f) {
                    "首页" {
                        if ($r.homeCode -ne 0) { "HTTP $($r.homeCode)，耗时 $($r.homeMs)ms" }
                        else { "连接失败，耗时 $($r.homeMs)ms" }
                    }
                    "性能劣化" { "首页 $($r.homeMs)ms（基线 ${baselineHomeMs}ms）" }
                    "Version字段" { "无法获取 Version 字段" }
                    "Health接口" { "HTTP $($r.healthCode)" }
                    "证书过期" { "证书剩余 $($r.certDays) 天" }
                    default { "" }
                }
                $sev = if ($f -eq "首页") { "P0" } else { "P1" }
                $sug = switch ($f) {
                    "首页"     { "立即登录阿里云控制台检查 ECS 状态" }
                    "证书过期" { "立即在阿里云更新 SSL 证书" }
                    default    { "登录服务器检查相关服务" }
                }
                Write-Output "失败项：$f"
                Write-Output "现象：$phen"
                Write-Output "严重度：$sev"
                Write-Output "建议立即操作：$sug"
            }
            if ($versionChanged) {
                Write-Output "📦 检测到发版：$prevVersion → $($r.version)"
            }
            if ($consecutiveFails -ge 3) {
                $hours = [int]($consecutiveFails * 0.5)
                Write-Output "⚠️ 建议人工介入：同一异常已连续出现 $consecutiveFails 次（约 $hours 小时）"
            }
            Write-Output ""
        } elseif ($r.perfDegraded) {
            # 场景 C
            $base = if ($null -ne $baselineHomeMs) { $baselineHomeMs } else { "?" }
            Write-Output "⚠️ [$beijingTs] $($r.site) 性能劣化 | 首页 $($r.homeMs)ms（基线 ${base}ms）"
            if ($versionChanged) {
                Write-Output "📦 检测到发版：$prevVersion → $($r.version)"
            }
            Write-Output ""
        }
    }
}

# ── 写日志 ──────────────────────────────────────────────
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$logFile = Join-Path $LogDir "site-monitor.log"
$logLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) $beijingTs"
foreach ($r in $allResults) {
    $logLine += " | $($r.site):ok=$($r.ok),ms=$($r.homeMs),v=$($r.version)"
}
$logLine += "`n"
[System.IO.File]::AppendAllText($logFile, $logLine, $utf8Bom)

# ── JSON 输出 ───────────────────────────────────────────
if ($OutputJson) {
    $json = @{
        timestamp = $now.ToString("yyyy-MM-dd HH:mm:ss")
        beijingTime = $beijingTs
        allOk = (-not $anyFailure -and -not $anyDegraded)
        versionChanged = $versionChanged
        consecutiveFails = $consecutiveFails
        sites = @()
    }
    foreach ($r in $allResults) {
        $json.sites += @{
            site = $r.site
            ok = $r.ok
            homeMs = $r.homeMs
            homeCode = $r.homeCode
            version = $r.version
            certDays = $r.certDays
            failures = $r.failures
            perfDegraded = $r.perfDegraded
        }
    }
    Write-Output ($json | ConvertTo-Json -Depth 5 -Compress)
}
