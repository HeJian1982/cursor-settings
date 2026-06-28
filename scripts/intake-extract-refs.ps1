# Create intake/ index + extract reference files from cloned repos
$ErrorActionPreference = 'Stop'

$intake = "E:\HJ\cursor\intake"
$intakeRef = "E:\HJ\cursor\intake\references"
New-Item -ItemType Directory -Force -Path $intakeRef | Out-Null

# 1. Copy Cursor.md from system_prompts_leaks
$cursorLeakSrc = Join-Path $intake "system_prompts_leaks\cursor.md"
$cursorLeakDst = Join-Path $intakeRef "cursor-system-prompt-leak.md"
if (Test-Path $cursorLeakSrc) {
    Copy-Item $cursorLeakSrc $cursorLeakDst -Force
    Write-Host "[OK] cursor.md -> references/cursor-system-prompt-leak.md" -ForegroundColor Green
}

# 2. Copy multi-agent rule templates from OpenMontage
$openmontage = Join-Path $intake "OpenMontage"
$omFiles = @("CURSOR.md","COPILOT.md","CODEX.md","CLAUDE.md","AGENTS.md","AGENT_GUIDE.md")
foreach ($f in $omFiles) {
    $src = Join-Path $openmontage $f
    if (Test-Path $src) {
        $dst = Join-Path $intakeRef "openmontage-$($f.ToLower())"
        Copy-Item $src $dst -Force
        Write-Host "[OK] OpenMontage/$f -> references/openmontage-$($f.ToLower())" -ForegroundColor Green
    }
}

# 3. Copy no-mistakes' .no-mistakes.yaml + AGENTS.md as workflow templates
$nmSrc = Join-Path $intake "no-mistakes"
$nmFiles = @(".no-mistakes.yaml","AGENTS.md","CLAUDE.md")
foreach ($f in $nmFiles) {
    $src = Join-Path $nmSrc $f
    if (Test-Path $src) {
        $dst = Join-Path $intakeRef "no-mistakes-$($f.Replace('.','_').Replace('_yaml','_yaml'))"
        # Use a saner filename
        $dst = Join-Path $intakeRef ("no-mistakes-{0}" -f $f.Replace('.','_'))
        Copy-Item $src $dst -Force
        Write-Host "[OK] no-mistakes/$f -> references/no-mistakes-$($f.Replace('.','_'))" -ForegroundColor Green
    }
}

# 4. Copy taste-skill SKILL.md into refs for in-tree discovery
$tasteSkill = Join-Path $intake "taste-skill\SKILL.md"
if (Test-Path $tasteSkill) {
    Copy-Item $tasteSkill (Join-Path $intakeRef "taste-skill-SKILL.md") -Force
    Write-Host "[OK] taste-skill/SKILL.md -> references/" -ForegroundColor Green
}

Write-Host ""
Write-Host "References extracted:" -ForegroundColor Cyan
Get-ChildItem $intakeRef | ForEach-Object {
    Write-Host ("  {0,-60} {1,10:N0} bytes" -f $_.Name, $_.Length)
}