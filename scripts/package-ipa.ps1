param(
  [Parameter(Mandatory=$true)][string]$AppPath,
  [string]$OutPath = "VibeSlopik.ipa"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $AppPath -PathType Container)) {
  throw "App bundle not found: $AppPath"
}

$infoPlist = Join-Path $AppPath "Info.plist"
if (-not (Test-Path $infoPlist -PathType Leaf)) {
  throw "Info.plist not found in app bundle: $infoPlist"
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vibeslopik-ipa-" + [Guid]::NewGuid().ToString("N"))
$payload = Join-Path $temp "Payload"
try {
  New-Item -ItemType Directory -Path $payload | Out-Null
  Copy-Item -Recurse -Path $AppPath -Destination $payload

  $dsym = Join-Path $payload ((Split-Path $AppPath -Leaf) + ".dSYM")
  if (Test-Path $dsym) {
    Remove-Item -Recurse -Force $dsym
  }

  $parent = Split-Path -Parent $OutPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $zipPath = if ($OutPath.EndsWith(".ipa")) { $OutPath.Substring(0, $OutPath.Length - 4) + ".zip" } else { "$OutPath.zip" }
  if (Test-Path $zipPath) { Remove-Item $zipPath }
  Compress-Archive -Path $payload -DestinationPath $zipPath
  if (Test-Path $OutPath) { Remove-Item $OutPath }
  Move-Item $zipPath $OutPath
} finally {
  if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
}

Write-Host "Wrote $OutPath"
