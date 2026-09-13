$version=$args[0]
if ($version -eq $null){
	echo "No Version supplied, not bulding script"
	return
}
if (Test-Path ./tmp/){
	Remove-Item ./tmp/
}
New-Item ./tmp/ -ItemType Directory
if (Test-Path ./tmp/skynet-iads-compiled.lua) {
	Remove-Item ./tmp/skynet-iads-compiled.lua
}
Add-Content ./tmp/tmp-time.lua ("env.info(`"--- SKYNET VERSION: "+$version+" | BUILD TIME: "+(Get-Date -date (Get-Date).ToUniversalTime()-uformat "%d.%m.%Y %H%MZ")+" ---`")")  
cat ../skynet-iads-source/skynet-iads-utils.lua, ../skynet-iads-source/skynet-iads-supported-types.lua,../skynet-iads-source/highdigitsams/skynet-iads-high-digit-sams-suported-types.lua, ../skynet-iads-source/skynet-iads-logger.lua, ../skynet-iads-source/skynet-iads.lua, ../skynet-iads-source/skynet-mooose-a2a-dispatcher-connector.lua, ../skynet-iads-source/skynet-iads-table-delegator.lua, ../skynet-iads-source/skynet-iads-abstract-dcs-object-wrapper.lua, ../skynet-iads-source/skynet-iads-abstract-element.lua, ../skynet-iads-source/skynet-iads-abstract-radar-element.lua, ../skynet-iads-source/skynet-iads-awacs-radar.lua, ../skynet-iads-source/skynet-iads-command-center.lua, ../skynet-iads-source/skynet-iads-contact.lua, ../skynet-iads-source/skynet-iads-early-warning-radar.lua, ../skynet-iads-source/skynet-iads-jammer.lua, ../skynet-iads-source/skynet-iads-sam-search-radar.lua, ../skynet-iads-source/skynet-iads-sam-site.lua, ../skynet-iads-source/skynet-iads-sam-tracking-radar.lua, ../skynet-iads-source/skynet-iads-sam-launcher.lua, ../skynet-iads-source/skynet-iads-harm-detection.lua | Set-Content ./tmp/tmp-code.lua
# 'sc' used to be an alias of Set-Content in Windows PowerShell 5.1. PowerShell 7 removed it, so
# there it resolves to sc.exe (Service Control) and the build silently produced a file holding
# nothing but the version banner.
$code = Get-Content ./tmp/tmp-code.lua
Add-Content ./tmp/tmp-time.lua $code
Rename-Item -Path ./tmp/tmp-time.lua -NewName skynet-iads-compiled.lua
Remove-Item ./tmp/tmp-code.lua

if (Test-Path ../demo-missions/skynet-iads-compiled.lua) {
	Remove-Item ../demo-missions/skynet-iads-compiled.lua
}

Move-Item -Path ./tmp/skynet-iads-compiled.lua ../demo-missions/skynet-iads-compiled.lua

$toc = ./bin/gh-md-toc.exe --hide-footer ../skynet-iads-source/README_source.md
# VEAF #4: gh-md-toc.exe needs network. On failure it still exits 0 but emits only
# the "Table of Contents" header with no entries, which then silently replaces the
# README's TOC with a blank line. Bail (leave README.md untouched) when gh-md-toc
# failed: a non-zero exit, empty output, or output with no anchor links '](#' (the
# header-only shape it emits with no network, still exit 0).
$tocJoined = ($toc -join "`n")
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tocJoined) -or $tocJoined -notmatch '\]\(#') {
    Write-Error "Table of contents generation failed; leaving README.md untouched."
    exit 1
}
$toc = $toc -replace "=================", "=================`n"
$toc = $toc -replace "Table of Contents", "Table of Contents`n"
$toc = $toc -replace "\)", "`)`n"
$readme = Get-Content ../skynet-iads-source/README_source.md
$readmeWithTOC = $readme -replace "{TOC_PLACEHOLDER}", $toc

if (Test-Path ../README.md) {
	Remove-Item ../README.md
}

Add-Content ../README.md $readmeWithTOC
Remove-Item ./tmp/