param(
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

function Show-Check([string]$Name, [scriptblock]$Action) {
  try {
    $value = & $Action
    Write-Host "[OK] $Name" -ForegroundColor Green
    if ($null -ne $value -and "$value".Trim()) { Write-Host "$value" }
    return $true
  } catch {
    Write-Host "[FAIL] $Name" -ForegroundColor Red
    Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow
    return $false
  }
}

Write-Host "VibeSlopik WSL diagnostic"
$actualUser = (& whoami.exe).Trim()
Write-Host "Windows token user: $actualUser"
Write-Host "Environment user: $env:USERDOMAIN\$env:USERNAME"
if ($actualUser -notmatch [regex]::Escape($env:USERNAME)) {
  Write-Host "[WARN] Process token and USERNAME differ; WSL may see another user's per-user registrations." -ForegroundColor Yellow
}
Write-Host "Repository: $PSScriptRoot\.."

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) { throw "wsl.exe is not installed." }

# WSL service names and trigger-start behaviour differ between Windows/WSL
# versions. A stopped LxssManager is not an error when wsl.exe can launch the
# distro, so report services as context and use an actual launch as the gate.
$serviceNames = @('WslService', 'LxssManager', 'vmcompute')
foreach ($serviceName in $serviceNames) {
  $service = Get-Service $serviceName -ErrorAction SilentlyContinue
  if ($service) {
    Write-Host "[INFO] $serviceName service: $($service.Status)" -ForegroundColor Cyan
  }
}

$listed = @(& wsl.exe -l -q 2>$null | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
if (-not $listed.Count) {
  Write-Host "[FAIL] No WSL distributions are visible for this Windows user." -ForegroundColor Red
  Write-Host "       WSL registrations are per-user. Run this script from the same Windows account that installed Ubuntu." -ForegroundColor Yellow
  exit 2
}

Write-Host "[OK] Visible distributions:" -ForegroundColor Green
$listed | ForEach-Object { Write-Host "     $_" }
if ($listed -notcontains $Distro) {
  Write-Host "[FAIL] Build distro '$Distro' is not visible." -ForegroundColor Red
  exit 3
}

$launchOK = Show-Check "Distro launch" {
  $result = & wsl.exe -d $Distro -- bash -lc 'set -e; echo READY; echo MAKE=$(command -v make); test -x "$HOME/theos/toolchain/linux/iphone/bin/clang"; echo THEOS_CLANG=$HOME/theos/toolchain/linux/iphone/bin/clang; test -d "$HOME/theos"; echo THEOS_READY' 2>&1
  if ($LASTEXITCODE -ne 0 -or "$result" -notmatch 'READY') { throw "$result" }
  "$result"
}
if (-not $launchOK) { exit 4 }

Write-Host "Diagnostic completed."
