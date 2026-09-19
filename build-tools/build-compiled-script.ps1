<#
  Concatenates skynet-iads-source/*.lua, per build-tools/listToMerge.txt, into the shipped
  artifact demo-missions/skynet-iads-compiled.lua, stamping the version read from
  skynet-iads-source/skynet-iads.lua.

  Paths are resolved from this script's own location, so it runs from any working
  directory, on any platform pwsh runs on (including the Linux CI runner).
#>

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot "skynet-iads-source"
$manifestPath = Join-Path $PSScriptRoot "listToMerge.txt"
$outputPath = Join-Path $repoRoot "demo-missions/skynet-iads-compiled.lua"

$versionFile = Join-Path $sourceRoot "skynet-iads.lua"
$versionSource = Get-Content $versionFile -Raw
if ($versionSource -notmatch 'SkynetIADS\.version\s*=\s*"([^"]+)"') {
    Write-Error "Could not find SkynetIADS.version in $versionFile"
    exit 1
}
$version = $Matches[1]

$files = Get-Content $manifestPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

$missing = $files | Where-Object { -not (Test-Path (Join-Path $sourceRoot $_)) }
if ($missing) {
    Write-Error "Missing source file(s) listed in listToMerge.txt: $($missing -join ', ')"
    exit 1
}

$buildTime = (Get-Date).ToUniversalTime().ToString("dd.MM.yyyy HHmm") + "Z"
$banner = "env.info(`"--- SKYNET VERSION: $version | BUILD TIME: $buildTime ---`")"

$body = $files | ForEach-Object { Get-Content (Join-Path $sourceRoot $_) }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
Set-Content -Path $outputPath -Value $banner
Add-Content -Path $outputPath -Value $body

Write-Host "Built $outputPath ($version, $buildTime)"
