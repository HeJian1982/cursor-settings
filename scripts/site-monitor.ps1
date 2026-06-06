<#
.SYNOPSIS
  网站健康快检 — 支持多站点并行检查

.DESCRIPTION
  对指定站点做 30 秒内轻量级健康检查，输出格式严格遵循 bot 输出规范。
  支持多站点（hj1982.cn / 1982.cn 及子路径）并行检测。

  执行策略：
  - 正常时只输出一行状态行
  - 失败时输出场景 B 告警
  - 性能劣化时输出场景 C 提示
  - 同一异常连续 3 次自动升级

  巡检结果写入 memory/site-monitor/state.json（无需 Memory skill，JSON 文件实现）

.PARAMETER Sites
  要检查的站点列表，逗号分隔。
  默认: hj1982.cn,1982.cn

.PARAMETER OutputJson
  输出 JSON 格式结果（供外部调用）

.EXAMPLE
  .\site-monitor.ps1
  .\site-monitor.ps1 -Sites "hj1982.cn,1982.cn,blog.hj1982.cn"
  .\site-monitor.ps1 -OutputJson
#>

[CmdletBinding()]
param(
    [string]$Sites = "hj1982.cn,1982.cn",
    [switch]$OutputJson
)

$ErrorActionPreference = 'Continue'

# ── 站点配置 ────────────────────────────────────────────
$SiteList = $Sites -split ',' | ForEach-Object { $_.Trim() }

$RepoRoot  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$StateFile  = Join-Path $RepoRoot "memory\site-monitor\state.json"
$LogDir     = Join-Path $RepoRoot "logs"
$utf8Bom    = New-Object System.Text.UTF8Encoding $true

# ── 记忆读写 ────────────────────────────────────────────
function Get-Memory {
    param([string]$Key, $Default = $null)
    if (-not (Test-Path $StateFile)) { return $Default }
    try {
        $json = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.PSObject.Properties.Name -contains $Key) {
            return $json.$Key
        }
        return $Default
    } catch { return $Default }
}

function Set-Memory {
    param([string]$Key, $Value)
    $obj = @{}
    if (Test-Path $StateFile) {
        try {
            $obj = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        } catch { $obj = @{} }
    }
    $obj[$Key] = $Value
    $dir = Split-Path $StateFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $obj | ConvertTo-Json -Depth 10 | ForEach-Object { [System.IO.File]::WriteAllText($StateFile, $_, $utf8Bom) }
}

# ── HTTP 检查 ───────────────────────────────────────────
function Get-ResponseTime {
    param([string]$Url, [int]$TimeoutMs = 8000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutMs
        $req.UserAgent = "SiteMonitorBot/1.0"
        $req.AllowAutoRedirect = $true
        $req.MaximumAutomaticRedirections = 3
        $resp = $req.GetResponse()
        $statusCode = [int]$resp.StatusCode
        $resp.Close()
        $sw.Stop()
        return @{ ok = $true; statusCode = $statusCode; ms = $sw.ElapsedMilliseconds; error = $null }
    } catch {
        $sw.Stop()
        $msg = $_.Exception.Message
        $statusCode = 0
        if ($_.Exception -is [System.Net.WebException]) {
            $we = $_.Exception -as [System.Net.WebException]
            if ($we.Response) {
                $statusCode = [int]$we.Response.StatusCode
            }
        }
        return @{ ok = $false; statusCode = $statusCode; ms = $sw.ElapsedMilliseconds; error = $msg }
    }
}

function Get-CertDaysLeft {
    param([string]$Host)
    try {
        $req = [Net.HttpWebRequest]::Create("https://$Host/")
        $req.Method = "HEAD"
        $req.Timeout = 5000
        $req.ServicePoint.Certificate | Out-Null
        $cert = $req.ServicePoint.Certificate
        if (-not $cert) { return $null }
        $expiry = [DateTime]::Parse($cert.GetExpirationDateString())
        $days = ($expiry - (Get-Date)).Days
        $req.Abort()
        return $days
    } catch {
        return $null
    }
}

function Get-Version {
    param([string]$Host)
    $url = "https://$Host/api/version"
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 5 -UserAgent "SiteMonitorBot/1.0"
        if ($resp.version) { return $resp.version }
        $body = $resp | ConvertTo-Json -Compress
        if ($body -match '"version"\s*:\s*"([^"]+)"') { return $matches[1] }
        return $null
    } catch {
        return $null
    }
}

function Get-ApiHealth {
    param([string]$Host)
    $url = "https://$Host/api/health"
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 5 -UserAgent "SiteMonitorBot/1.0"
        return @{ ok = $true; statusCode = 200; body = $resp }
    } catch {
        if ($_.Exception -is [System.Net.WebException]) {
            $we = $_.Exception -as [System.Net.WebException]
            if ($we.Response) {
                $code = [int]$we.Response.StatusCode
                return @{ ok = $code -ne 404; statusCode = $code; body = $null; note = "not_found" }
            }
        }
        return @{ ok = $false; statusCode = 0; body = $null; error = $_.Exception.Message }
    }
}

# ── 记忆读取（巡检前）─────────────────────────────────
$lastVersion       = Get-Memory "last_version"       $null
$consecutiveFails  = Get-Memory "consecutive_failures" 0
$lastFailureItem   = Get-Memory "last_failure_item"  $null
$baselineHome      = Get-Memory "baseline_home_ms"   $null
$baselineApi       = Get-Memory "baseline_api_ms"    $null
$baselineList      = Get-Memory "baseline_home_list" @()
$baselineApiList   = Get-Memory "baseline_api_list"  @()
$prevVersion       = Get-Memory "prev_version"        $null

# ── 执行巡检 ──────────────────────────────────────────
$now = Get-Date
$timestamp = $now.ToString("HH:mm")
$beijingNow = $now.ToUniversalTime().AddHours(8)
$beijingTs  = $beijingNow.ToString("HH:mm")

$results = @()
$globalFailure = $false
$globalFailureItems = @()

foreach ($site in $SiteList) {
    $r = @{ site = $site; ok = $true; items = @{}; failures = @() }

    # 1. 首页检查
    $homeResult = Get-ResponseTime -Url "https://$site/" -TimeoutMs 8000
    $r.items["home"] = $homeResult
    $r.homeMs = $homeResult.ms

    # 2. API version
    $ver = Get-Version -Host $site
    $r.items["version"] = @{ value = $ver }

    # 3. API health
    $health = Get-ApiHealth -Host $site
    $r.items["health"] = $health

    # 4. HTTPS 证书
    $certDays = Get-CertDaysLeft -Host $site
    $r.items["cert"] = @{ daysLeft = $certDays }

    # 5. 关键字检查（复用首页内容）
    if ($homeResult.ok -and $homeResult.ms -lt 5000) {
        try {
            $req2 = [System.Net.HttpWebRequest]::Create("https://$site/")
            $req2.Timeout = 8000
            $req2.UserAgent = "SiteMonitorBot/1.0"
            $resp2 = $req2.GetResponse()
            $sr = New-Object System.IO.StreamReader($resp2.GetResponseStream())
            $html = $sr.ReadToEnd()
            $sr.Close()
            $resp2.Close()
            $r.items["keyword"] = @{ found = ($html -match '何健') }
        } catch {
            $r.items["keyword"] = @{ found = $null; error = $_.Exception.Message }
        }
    } else {
        $r.items["keyword"] = @{ found = $null; note = "home_failed" }
    }

    # 判断失败项
    if (-not $homeResult.ok) {
        $r.failures += "首页"
        $r.ok = $false
    }
    if ($homeResult.ok -and $homeResult.ms -gt 5000) {
        $r.perfDegraded = $true
    }
    if ($ver -eq $null -and $homeResult.ok) {
        $r.failures += "Version字段"
    }
    if (-not $health.ok) {
        $r.failures += "Health接口"
    }
    if ($certDays -ne $null -and $certDays -le 7) {
        $r.failures += "证书过期"
    }

    if (-not $r.ok) { $globalFailure = $true }
    $results += $r
}

# ── Version 变化检测 ──────────────────────────────────
$versionChanged = $false
foreach ($r in $results) {
    if ($r.items.version.value -and $prevVersion -and $r.items.version.value -ne $prevVersion) {
        $versionChanged = $true
        break
    }
}

# ── 连续失败计数 ──────────────────────────────────────
if ($globalFailure) {
    if ($lastFailureItem -eq "global" -or $lastFailureItem -eq ($results[0].failures -join ',')) {
        $consecutiveFails++
    } else {
        $consecutiveFails = 1
    }
} else {
    $consecutiveFails = 0
}

# ── 更新基线 ──────────────────────────────────────────
foreach ($r in $results) {
    if ($r.ok -and -not $r.perfDegraded) {
        # 首页基线：滑动平均（保留最近 3 次）
        $newList = @($r.homeMs) + @($baselineList) | Select-Object -First 3
        $newBaseline = [int](($newList | Measure-Object -Average).Average)
        Set-Memory "baseline_home_list" $newList
        Set-Memory "baseline_home_ms" $newBaseline

        # API 基线
        if ($r.items.health.ok) {
            $apiMs = Get-ResponseTime -Url "https://$($r.site)/api/version" -TimeoutMs 5000
            $newApiList = @($apiMs.ms) + @($baselineApiList) | Select-Object -First 3
            $newApiBaseline = [int](($newApiList | Measure-Object -Average).Average)
            Set-Memory "baseline_api_list" $newApiList
            Set-Memory "baseline_api_ms" $newApiBaseline
        }
    }
}

# ── 写记忆 ────────────────────────────────────────────
if ($results[0].items.version.value) {
    Set-Memory "prev_version" $results[0].items.version.value
}
Set-Memory "consecutive_failures" $consecutiveFails
Set-Memory "last_failure_item" $(if ($globalFailure) { $results[0].failures -join ',' } else { $null })
Set-Memory "last_check" $now.ToString("yyyy-MM-dd HH:mm:ss")
Set-Memory "last_sites" $SiteList

# ── 性能基线（全局）──────────────────────────────────
$currentBaselineHome = Get-Memory "baseline_home_ms" 0
$currentBaselineApi  = Get-Memory "baseline_api_ms" 0

# ── 输出 ─────────────────────────────────────────────
function Get-Row {
    param($r, $baselineHome, $baselineApi)
    $status = if ($r.ok) { "✅" } else { "❌" }
    $homeMs = if ($r.homeMs) { "$($r.homeMs)ms" } else { "N/A" }
    $ver = if ($r.items.version.value) { "v=$($r.items.version.value)" } else { "v=N/A" }
    $cert = if ($r.items.cert.daysLeft -ne $null) { "cert=$($r.items.cert.daysLeft)d" } else { "cert=N/A" }
    return "$status $($r.site) | home=$homeMs | $ver | $cert"
}

# 构建输出
$outputLines = @()

# 场景 A：全部正常
$allOk = ($results | Where-Object { -not $_.ok -and -not $_.perfDegraded } | Measure-Object).Count -eq 0
$noDegraded = ($results | Where-Object { $_.perfDegraded } | Measure-Object).Count -eq 0

if ($allOk -and $noDegraded) {
    $rows = $results | ForEach-Object { Get-Row $_ $currentBaselineHome $currentBaselineApi }
    $line = "✅ $beijingTs 全部正常 | $($rows -join ' | ')"
    if ($OutputJson) {
        $outputLines += $line
    } else {
        Write-Output $line
    }
    # Version 变化
    if ($versionChanged -and $results[0].items.version.value) {
        $vLine = "📦 检测到发版：$prevVersion → $($results[0].items.version.value)"
        $outputLines += $vLine
        if (-not $OutputJson) { Write-Output $vLine }
    }
} else {
    # 场景 B：失败 / 场景 C：性能劣化
    foreach ($r in $results) {
        $failureLines = @()

        if (-not $r.ok) {
            # 场景 B
            $failureLines += "🚨 [$beijingTs] $($r.site) 异常告警"
            foreach ($fi in $r.failures) {
                $phenomenon = switch ($fi) {
                    "首页" {
                        $hr = $r.items.home
                        if ($hr.statusCode) { "HTTP $($hr.statusCode)，耗时 $($hr.ms)ms，错误：$($hr.error)" }
                        else { "连接失败，耗时 $($hr.ms)ms，错误：$($hr.error)" }
                    }
                    "Version字段" { "无法获取 Version 字段（接口返回空或错误）" }
                    "Health接口" {
                        $h = $r.items.health
                        "HTTP $($h.statusCode)，错误：$($h.error)"
                    }
                    "证书过期" { "证书剩余 $($r.items.cert.daysLeft) 天（≤7天告警）" }
                    default { "未知故障" }
                }
                $severity = switch ($fi) {
                    "首页"     { "P0" }
                    "证书过期" { "P1" }
                    default    { "P1" }
                }
                $suggestion = switch ($fi) {
                    "首页"     { "立即登录阿里云控制台检查 ECS 状态，或联系主机商确认网络连通性" }
                    "Version字段" { "检查后端服务是否正常响应 /api/version" }
                    "Health接口" { "检查后端 health 接口，排查服务健康状态" }
                    "证书过期" { "立即在阿里云证书控制台更新 SSL 证书" }
                    default    { "登录服务器检查相关服务日志" }
                }
                $failureLines += "失败项：$fi"
                $failureLines += "现象：$phenomenon"
                $failureLines += "严重度：$severity"
                $failureLines += "建议立即操作：$suggestion"
            }

            # 版本变化
            if ($versionChanged -and $r.items.version.value) {
                $failureLines += "📦 检测到发版：$prevVersion → $($r.items.version.value)"
            }

            # 连续失败升级
            if ($consecutiveFails -ge 3) {
                $failureLines += "⚠️ 建议人工介入：同一异常已连续出现 $consecutiveFails 次（约 $([int]($consecutiveFails * 0.5)) 小时）"
            }

            foreach ($l in $failureLines) {
                $outputLines += $l
                if (-not $OutputJson) { Write-Output $l }
            }
        } elseif ($r.perfDegraded) {
            # 场景 C
            $baseline = if ($r.homeMs -gt $currentBaselineHome) { $currentBaselineHome } else { $r.homeMs }
            $degradedLine = "⚠️ [$beijingTs] $($r.site) 性能劣化 | 首页 $($r.homeMs)ms（基线 ${currentBaselineHome}ms）"
            $outputLines += $degradedLine
            if (-not $OutputJson) { Write-Output $degradedLine }

            if ($versionChanged -and $r.items.version.value) {
                $vLine = "📦 检测到发版：$prevVersion → $($r.items.version.value)"
                $outputLines += $vLine
                if (-not $OutputJson) { Write-Output $vLine }
            }
        }
    }
}

# 写日志
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$logLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss')) $beijingTs | $($results | ForEach-Object { "$($_.site):ok=$($_.ok),ms=$($_.homeMs),v=$($_.items.version.value)" } -join ' | ')`n"
[System.IO.File]::AppendAllText((Join-Path $LogDir "site-monitor.log"), $logLine, $utf8Bom)

# JSON 输出
if ($OutputJson) {
    $json = @{
        timestamp = $now.ToString("yyyy-MM-dd HH:mm:ss")
        beijingTime = $beijingTs
        allOk = $allOk -and $noDegraded
        versionChanged = $versionChanged
        consecutiveFails = $consecutiveFails
        sites = @()
    }
    foreach ($r in $results) {
        $json.sites += @{
            site = $r.site
            ok = $r.ok
            homeMs = $r.homeMs
            homeOk = $r.items.home.ok
            homeStatusCode = $r.items.home.statusCode
            version = $r.items.version.value
            healthOk = $r.items.health.ok
            healthStatusCode = $r.items.health.statusCode
            certDaysLeft = $r.items.cert.daysLeft
            keywordFound = $r.items.keyword.found
            failures = $r.failures
            perfDegraded = $r.perfDegraded
        }
    }
    Write-Output ($json | ConvertTo-Json -Depth 5 -Compress)
}
