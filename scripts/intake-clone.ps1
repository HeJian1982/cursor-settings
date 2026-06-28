# Clone all 15 candidate repos into E:\HJ\cursor\intake\ for integration review
$ErrorActionPreference = 'Stop'
$intakeRoot = "E:\HJ\cursor\intake"
if (-not (Test-Path $intakeRoot)) {
    New-Item -ItemType Directory -Force -Path $intakeRoot | Out-Null
}

$repos = @(
    @{ owner = "DeusData";       repo = "codebase-memory-mcp" },
    @{ owner = "Panniantong";    repo = "Agent-Reach" },
    @{ owner = "harry0703";      repo = "MoneyPrinterTurbo" },
    @{ owner = "mvanhorn";       repo = "last30days-skill" },
    @{ owner = "microsoft";      repo = "markitdown" },
    @{ owner = "Leonxlnx";       repo = "taste-skill" },
    @{ owner = "mukul975";       repo = "Anthropic-Cybersecurity-Skills" },
    @{ owner = "asgeirtj";       repo = "system_prompts_leaks" },
    @{ owner = "Egonex-AI";      repo = "Understand-Anything" },
    @{ owner = "supermemoryai";  repo = "supermemory" },
    @{ owner = "calesthio";      repo = "OpenMontage" },
    @{ owner = "kunchenguid";    repo = "no-mistakes" },
    @{ owner = "JCodesMore";     repo = "ai-website-cloner-template" },
    @{ owner = "koala73";        repo = "worldmonitor" },
    @{ owner = "topoteretes";    repo = "cognee" }
)

foreach ($r in $repos) {
    $dir = Join-Path $intakeRoot $r.repo
    if (Test-Path $dir) {
        Write-Host "[SKIP] $dir exists" -ForegroundColor Yellow
        continue
    }
    $url = "https://github.com/$($r.owner)/$($r.repo).git"
    Write-Host "[CLONE] $url -> $dir" -ForegroundColor Cyan
    $p = Start-Process -FilePath "git" -ArgumentList "clone","--depth=1",$url,$dir -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -eq 0) {
        Write-Host "  OK" -ForegroundColor Green
    } else {
        Write-Host "  FAIL (exit=$($p.ExitCode))" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done. Intake root: $intakeRoot" -ForegroundColor Green
Get-ChildItem $intakeRoot | Select-Object Name, Length