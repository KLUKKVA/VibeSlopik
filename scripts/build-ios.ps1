param(
  [string]$TheosPath = $env:THEOS
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $TheosPath) {
  throw "THEOS is not set. Install Theos in WSL/macOS/Linux and run scripts/build-ios.sh, or pass -TheosPath."
}

$make = Get-Command make -ErrorAction SilentlyContinue
if (-not $make) {
  throw "make is not available in this PowerShell environment. Use WSL or macOS for Theos builds."
}

$env:THEOS = $TheosPath
Push-Location (Join-Path $root 'ios\LegacyRemote')
try {
  make clean package FINALPACKAGE=1
} finally {
  Pop-Location
}

$app = Get-ChildItem (Join-Path $root 'ios\LegacyRemote\.theos') -Recurse -Directory -Filter VibeSlopik.app -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
  & (Join-Path $root 'scripts\package-ipa.ps1') -AppPath $app.FullName -OutPath (Join-Path $root 'dist\VibeSlopik.ipa')
}
