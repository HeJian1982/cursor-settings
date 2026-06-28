# Install A-class skills from intake/ into user skill directories
$ErrorActionPreference = 'Stop'

$intake = "E:\HJ\cursor\intake"
$agentsRoot = "$env:USERPROFILE\.agents\skills"
$cursorRoot = "$env:USERPROFILE\.cursor\skills-cursor"

# A-class skills to install
$skills = @(
    # source dir, target root, target name
    @{ src = "last30days-skill";              dstRoot = $agentsRoot; name = "last30days-skill" },
    @{ src = "taste-skill";                  dstRoot = $agentsRoot; name = "taste-skill" },
    @{ src = "Understand-Anything";          dstRoot = $agentsRoot; name = "understand-anything" },
    @{ src = "Anthropic-Cybersecurity-Skills"; dstRoot = $agentsRoot; name = "anthropic-cybersecurity-skills" },
    @{ src = "no-mistakes";                  dstRoot = $agentsRoot; name = "no-mistakes-tool" }
)

foreach ($s in $skills) {
    $srcDir = Join-Path $intake $s.src
    $dstDir = Join-Path $s.dstRoot $s.name

    if (-not (Test-Path $srcDir)) {
        Write-Host "[MISS] $srcDir" -ForegroundColor Red
        continue
    }
    if (Test-Path $dstDir) {
        Write-Host "[SKIP] $dstDir already exists" -ForegroundColor Yellow
        continue
    }

    Write-Host "[COPY] $($s.src) -> $dstDir" -ForegroundColor Cyan
    Copy-Item -Path $srcDir -Destination $dstDir -Recurse -Force

    # Remove .git directory from cloned repo to keep skill clean
    $gitDir = Join-Path $dstDir ".git"
    if (Test-Path $gitDir) {
        Remove-Item -Recurse -Force $gitDir
        Write-Host "  removed .git" -ForegroundColor DarkGray
    }
}

# Optional: create symlinks in .claude/skills for compat
$claudeRoot = "$env:USERPROFILE\.claude\skills"
foreach ($s in $skills) {
    $agentsPath = Join-Path $agentsRoot $s.name
    $claudeLink = Join-Path $claudeRoot $s.name
    if ((Test-Path $agentsPath) -and -not (Test-Path $claudeLink)) {
        Write-Host "[LINK] .claude\skills\$($s.name)" -ForegroundColor Magenta
        cmd /c "mklink /J `"$claudeLink`" `"$agentsPath`"" 2>&1 | Out-Null
    }
}

Write-Host ""
Write-Host "Installed skills summary:" -ForegroundColor Green
Get-ChildItem $agentsRoot | Where-Object { $_.PSIsContainer -and $_.Name -in $skills.name } | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host ("  {0,-40} {1,12:N0} bytes" -f $_.Name, $size)
}