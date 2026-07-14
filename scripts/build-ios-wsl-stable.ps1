param(
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'diagnose-wsl.ps1') -Distro $Distro
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$drive = $root.Substring(0, 1).ToLowerInvariant()
$relative = $root.Substring(2).Replace('\', '/')
$linuxRoot = "/mnt/$drive$relative"

$command = "cd '$linuxRoot' && bash ./scripts/build-ios-wsl-local.sh 2>&1"
& wsl.exe -d $Distro -- bash -lc $command
if ($LASTEXITCODE -ne 0) { throw "iOS build failed. Run scripts/diagnose-wsl.ps1 for the environment report." }

$ipa = Join-Path $root 'dist\VibeSlopik.ipa'
if (-not (Test-Path $ipa)) { throw "Build completed without $ipa" }
Write-Host "IPA: $ipa" -ForegroundColor Green
