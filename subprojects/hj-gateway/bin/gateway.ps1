<#
hj-gateway · 个人 AI 助手本地网关 (PowerShell 入口)
集合 6 个 GitHub 热门项目的特长:
  - openclaw         · 多渠道接入范本 (HTTP API 入口)
  - claude-code-router · provider 路由抽象
  - hermes-agent     · skill 库 + FTS5 检索 (本地化)
  - openhuman        · JSON-RPC + 进程内 tokio 范式
  - ai-api-integration · OpenAI 兼容协议输出
  - cursor2api       · 协议转换

用法:
  .\bin\gateway.ps1 start    # 后台启动
  .\bin\gateway.ps1 stop     # 停止
  .\bin\gateway.ps1 status   # 查状态
  .\bin\gateway.ps1 chat "你好"  # 一次性对话
  .\bin\gateway.ps1 skill list # 列 skill
  .\bin\gateway.ps1 skill run NAME [args...]
  .\bin\gateway.ps1 install-autostart   # 写开机自启
  .\bin\gateway.ps1 uninstall-autostart # 撤开机自启
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('start','stop','status','restart','chat','skill','repl','install-autostart','uninstall-autostart','help')]
    [string]$Command,

    [Parameter(Mandatory=$false, Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$RestArgs
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$LogDir = Join-Path $RootDir 'logs'
$StateDir = Join-Path $RootDir 'state'
$ConfigPath = Join-Path $RootDir 'config\gateway.json'
$PidFile = Join-Path $StateDir 'gateway.pid'
$Port = 7799  # 固定端口

# 强制 UTF-8 输出（避免 mojibake）
trap { continue }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# 强制 UTF-8 输入（处理中文命令行参数 mojibake）
# Windows console 默认 codepage 是 CP936/GBK，需切到 65001 (UTF-8)
$currentCp = [Console]::InputEncoding.CodePage
if ($currentCp -ne 65001) {
    try {
        $OutputEncoding = [System.Text.Encoding]::UTF8
        [Console]::InputEncoding = [System.Text.Encoding]::UTF8
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        cmd /c "chcp 65001 >nul" | Out-Null
    } catch {}
}

# ---- helper ----
function Write-Log {
    param([string]$Level, [string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'
    $line = "[$ts] [$Level] $Msg"
    Write-Host $line
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path (Join-Path $LogDir 'gateway.log') -Value $line -Encoding UTF8
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) {
        Write-Log 'ERROR' "config not found: $ConfigPath"
        exit 1
    }
    # 不用 ConvertFrom-Json（locale 问题），只校验存在即可
    return @{ valid = $true }
}

function Is-Running {
    if (-not (Test-Path $PidFile)) { return $false }
    $pidVal = Get-Content $PidFile -Raw -ErrorAction SilentlyContinue
    if (-not $pidVal) { return $false }
    $proc = Get-Process -Id ([int]$pidVal) -ErrorAction SilentlyContinue
    return $null -ne $proc
}

# ---- start ----
function Start-Gateway {
    [CmdletBinding()]
    param(
        [switch]$Watch
    )
    if (Is-Running) {
        Write-Log 'WARN' "already running (pid=$(Get-Content $PidFile -Raw))"
        return
    }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $pythonCmd) {
        Write-Log 'ERROR' 'python not found in PATH'
        exit 1
    }
    $pyServer = Join-Path $ScriptDir 'server.py'
    if (-not (Test-Path $pyServer)) {
        Write-Log 'ERROR' "server.py not found: $pyServer"
        exit 1
    }
    $cfg = Read-Config
    $logFile = Join-Path $LogDir 'server.log'
    Write-Log 'INFO' "starting gateway on port $Port (watch=$Watch)"
    $proc = Start-Process -FilePath $pythonCmd.Source -ArgumentList @($pyServer, '--port', $Port, '--root', $RootDir) `
        -RedirectStandardOutput $logFile -RedirectStandardError (Join-Path $LogDir 'server.err') `
        -NoNewWindow -PassThru
    Set-Content -Path $PidFile -Value $proc.Id -Encoding UTF8
    Write-Log 'INFO' "started pid=$($proc.Id) port=$Port"
    Start-Sleep -Seconds 1
    $status = Get-StatusInternal
    if ($status.ok) {
        Write-Log 'INFO' "gateway ready: $($status.banner)"
    } else {
        Write-Log 'ERROR' "gateway failed to start: $($status.error)"
    }

    if ($Watch) {
        # 守护模式：进程死了自动重启
        Write-Host "[watch] entering daemon mode; Ctrl+C to stop" -ForegroundColor Cyan
        while ($true) {
            $alive = $true
            try {
                Get-Process -Id $proc.Id -ErrorAction Stop | Out-Null
            } catch { $alive = $false }
            if (-not $alive) {
                Write-Host "[watch] gateway pid=$($proc.Id) died, restarting..." -ForegroundColor Yellow
                $proc = Start-Process -FilePath $pythonCmd.Source -ArgumentList @($pyServer, '--port', $Port, '--root', $RootDir) `
                    -RedirectStandardOutput $logFile -RedirectStandardError (Join-Path $LogDir 'server.err') `
                    -NoNewWindow -PassThru
                Set-Content -Path $PidFile -Value $proc.Id -Encoding UTF8
                Write-Host "[watch] restarted pid=$($proc.Id)" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            Start-Sleep -Seconds 5
        }
    }
}

function Stop-Gateway {
    if (-not (Is-Running)) {
        Write-Log 'WARN' 'not running'
        if (Test-Path $PidFile) { Remove-Item $PidFile -Force }
        return
    }
    $pidVal = [int](Get-Content $PidFile -Raw)
    Write-Log 'INFO' "stopping pid=$pidVal"
    Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (Test-Path $PidFile) { Remove-Item $PidFile -Force }
    Write-Log 'INFO' 'stopped'
}

function Get-StatusInternal {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 3
        return @{ ok = $true; banner = "$($resp.service) v$($resp.version) provider=$($resp.provider)"; error = $null }
    } catch {
        return @{ ok = $false; banner = $null; error = $_.Exception.Message }
    }
}

function Show-Status {
    if (Is-Running) {
        $pidVal = Get-Content $PidFile -Raw
        Write-Host "running (pid=$pidVal)"
    } else {
        Write-Host 'stopped'
    }
    $s = Get-StatusInternal
    if ($s.ok) { Write-Host $s.banner -ForegroundColor Green } else { Write-Host $s.error -ForegroundColor Red }
}

function Send-Chat {
    param([string]$Message)
    if (-not (Is-Running)) { Start-Gateway | Out-Null; Start-Sleep -Seconds 1 }
    $body = @{ message = $Message; ts = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
    $tmpBody = [System.IO.Path]::GetTempFileName() + '.json'
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmpBody, $body, $utf8Bom)
    try {
        $bodyText = [System.IO.File]::ReadAllText($tmpBody, [System.Text.Encoding]::UTF8)
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat" -Method Post -Body $bodyText -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
        Write-Host $resp.reply
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    } finally {
        Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Skill {
    param([string[]]$Args2)
    if (-not (Is-Running)) { Start-Gateway | Out-Null; Start-Sleep -Seconds 1 }
    if ($Args2.Count -eq 0) { $Args2 = @('list') }
    $sub = $Args2[0]
    $rest = @($Args2 | Select-Object -Skip 1)
    switch ($sub) {
        'list' {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/skills" -TimeoutSec 5
            $resp.skills | ForEach-Object { Write-Host "  $($_.name) - $($_.description)" }
        }
        'run' {
            if ($rest.Count -lt 1) { Write-Host 'usage: skill run NAME [args...]' -ForegroundColor Yellow; exit 1 }
            $name = $rest[0]
            $skillArgs = @($rest | Select-Object -Skip 1)
            $body = @{ name = $name; args = $skillArgs } | ConvertTo-Json -Compress
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/skills/run" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
            Write-Host $resp.output
        }
        'new' {
            if ($rest.Count -lt 1) { Write-Host 'usage: skill new NAME [kind=literal|shell|http]' -ForegroundColor Yellow; exit 1 }
            $name = $rest[0].ToLower()
            $kind = if ($rest.Count -gt 1) { $rest[1].ToLower() } else { 'literal' }
            if ($kind -notin @('literal','shell','http')) {
                Write-Host 'kind must be: literal, shell, or http' -ForegroundColor Yellow; exit 1
            }
            $skillsDir = Join-Path $RootDir 'skills'
            if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }
            $path = Join-Path $skillsDir "$name.json"
            if (Test-Path $path) { Write-Host "exists: $path" -ForegroundColor Yellow; exit 1 }
            $template = switch ($kind) {
                'literal' { @{ name=$name; description='[说明]'; keywords=@($name); kind='literal'; response="[回显文本 $args]" } }
                'shell'   { @{ name=$name; description='[说明]'; keywords=@($name); kind='shell'; command='powershell -NoProfile -Command "echo hello $args"' } }
                'http'    { @{ name=$name; description='[说明]'; keywords=@($name); kind='http'; url='https://api.example.com/$arg0' } }
            }
            $template | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8
            Write-Host "✅ 已创建: $path" -ForegroundColor Green
            Write-Host "   下一步: 编辑这个 JSON，加 keywords, 编辑完成后 gateway 会热加载"
        }
        default {
            Write-Host "unknown subcommand: $sub  (可用: list|run|new)" -ForegroundColor Yellow
            exit 1
        }
    }
}

function Install-AutoStart {
    $taskName = 'HJ-Personal-AI-Gateway'
    $exe = (Get-Command powershell -ErrorAction SilentlyContinue).Source
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\gateway.ps1`" start"

    # 优先用 schtasks.exe 创计划任务（更稳，避开 New-ScheduledTaskPrincipal 的 bug）
    $schtasksExe = (Get-Command schtasks -ErrorAction SilentlyContinue).Source
    if (-not $schtasksExe) { $schtasksExe = "$env:SystemRoot\System32\schtasks.exe" }
    $schArgs = "/Create /TN `"$taskName`" /TR `"$exe $arg`" /SC ONLOGON /RL LIMITED /F"
    Write-Log 'INFO' "schtasks args: $schArgs"
    $proc = Start-Process -FilePath $schtasksExe -ArgumentList $schArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $LogDir 'schtasks.out') -RedirectStandardError (Join-Path $LogDir 'schtasks.err')
    if ($proc.ExitCode -ne 0) {
        Write-Log 'WARN' "schtasks exit code: $($proc.ExitCode); trying fallback via New-ScheduledTask"
        # 兜底：PowerShell 原生命令（可能 0x80070057）
        trap { Write-Log 'WARN' "PS native also failed: $_"; continue }
        $action = New-ScheduledTaskAction -Execute $exe -Argument $arg -WorkingDirectory $RootDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    } else {
        Write-Log 'INFO' "schtasks: created $taskName"
    }

    # 启动文件夹快捷方式（兜底 + 用户可视化可见）
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup 'HJ-Personal-AI-Gateway.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnkPath)
    $s.TargetPath = $exe
    $s.Arguments = $arg
    $s.WorkingDirectory = $RootDir
    $s.WindowStyle = 7
    $s.Save()
    Write-Log 'INFO' "autostart installed (task=$taskName, lnk=$lnkPath)"
    Write-Host "OK 开机自启已安装" -ForegroundColor Green
    Write-Host "   - 计划任务: $taskName (登录时启动, schtasks 兜底)"
    Write-Host "   - 启动文件夹快捷方式: $lnkPath"
}

function Uninstall-AutoStart {
    $taskName = 'HJ-Personal-AI-Gateway'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'HJ-Personal-AI-Gateway.lnk'
    if (Test-Path $lnk) { Remove-Item $lnk -Force }
    Write-Log 'INFO' "autostart uninstalled"
    Write-Host '[ok] 开机自启已卸载' -ForegroundColor Green
}

# ---- REPL 模式: 持续连接，一次启动多次对话 ----
function Start-Repl {
    $st = Get-StatusInternal
    if (-not $st.ok) {
        Write-Host '[repl] starting gateway first...' -ForegroundColor Yellow
        Start-Gateway
        Start-Sleep -Seconds 1
    }
    Write-Host ''
    Write-Host 'hj-gateway REPL - Ctrl+C to quit, /q to exit' -ForegroundColor Cyan
    Write-Host 'commands: /skills /memory /providers /status /help' -ForegroundColor Cyan
    Write-Host ''
    $running = $true
    while ($running) {
        try {
            Write-Host 'you> ' -NoNewline -ForegroundColor Green
            $line = [Console]::ReadLine()
        } catch {
            break
        }
        if ($null -eq $line) { break }
        $line = $line.Trim()
        if (-not $line) { continue }
        switch ($line) {
            '/q' { Write-Host 'bye.' -ForegroundColor Cyan; $running = $false; continue }
            '/quit' { Write-Host 'bye.' -ForegroundColor Cyan; $running = $false; continue }
            '/exit' { Write-Host 'bye.' -ForegroundColor Cyan; $running = $false; continue }
            '/help' {
                Write-Host '  /skills       list skills' -ForegroundColor Yellow
                Write-Host '  /memory       recent memory' -ForegroundColor Yellow
                Write-Host '  /providers    list providers' -ForegroundColor Yellow
                Write-Host '  /status       gateway status' -ForegroundColor Yellow
                Write-Host '  /q            quit' -ForegroundColor Yellow
                Write-Host '  <text>        send to gateway' -ForegroundColor Yellow
                continue
            }
            '/skills' {
                $uri = 'http://127.0.0.1:' + $Port + '/v1/skills'
                $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5
                foreach ($sk in $resp.skills) {
                    $entry = '  {0,-15}  {1}' -f $sk.name, $sk.description
                    Write-Host $entry
                }
                continue
            }
            '/memory' {
                $uri = 'http://127.0.0.1:' + $Port + '/v1/memory?limit=10'
                $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5
                foreach ($item in $resp.items) {
                    $role = $item.role
                    $len = [Math]::Min(120, $item.content.Length)
                    $preview = $item.content.Substring(0, $len)
                    $line2 = '[' + $role + '] ' + $preview
                    $color = 'Cyan'
                    if ($role -eq 'user') { $color = 'Green' }
                    Write-Host $line2 -ForegroundColor $color
                }
                continue
            }
            '/providers' {
                $uri = 'http://127.0.0.1:' + $Port + '/v1/providers'
                $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5
                foreach ($p in $resp.providers.PSObject.Properties) {
                    $entry = '  {0,-22}  {1}' -f $p.Name, $p.Value.description
                    Write-Host $entry -ForegroundColor Yellow
                }
                continue
            }
            '/status' {
                Show-Status
                continue
            }
            default {
                Send-Chat -Message $line
                Write-Host ''
            }
        }
    }
}


# ---- main dispatch ----
switch ($Command) {
    'start'           {
        $watch = ($RestArgs -contains '--watch')
        if ($watch) { Start-Gateway -Watch } else { Start-Gateway }
    }
    'stop'            { Stop-Gateway }
    'restart'         { Stop-Gateway; Start-Sleep -Seconds 1; Start-Gateway }
    'status'          { Show-Status }
    'chat'            {
        $msg = ($RestArgs -join ' ').Trim()
        if (-not $msg) {
            Write-Host 'usage: chat MESSAGE' -ForegroundColor Yellow
            exit 1
        }
        Send-Chat -Message $msg
    }
    'repl'            { Start-Repl }
    'skill'           { Invoke-Skill -Args2 $RestArgs }
    'install-autostart'   { Install-AutoStart }
    'uninstall-autostart' { Uninstall-AutoStart }
    'help' {
        Write-Host 'hj-gateway commands:' -ForegroundColor Cyan
        Write-Host '  start                start the gateway'
        Write-Host '  start watch          start with auto-restart on crash'
        Write-Host '  stop                 stop'
        Write-Host '  restart              restart'
        Write-Host '  status               show status'
        Write-Host '  chat MESSAGE         one-shot chat'
        Write-Host '  repl                 interactive REPL'
        Write-Host '  skill list           list skills'
        Write-Host '  skill run NAME       run a skill'
        Write-Host '  skill new NAME       scaffold a new skill JSON'
        Write-Host '  install-autostart    install autostart'
        Write-Host '  uninstall-autostart  remove autostart'
        Write-Host '  help                 show this help'
    }
}
