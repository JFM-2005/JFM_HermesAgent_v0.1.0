<#
.SYNOPSIS
    Launch packaged Hermes Desktop (win-unpacked) with portable workspace.

.DESCRIPTION
    Unlike start-desktop.ps1 (--source / electron.exe), this runs:
      apps\desktop\release\win-unpacked\Hermes.exe

    Use after .\pack-desktop.ps1.

.EXAMPLE
    .\start-desktop-pack.ps1
    .\start-desktop-pack.ps1 -SkipSearxng
#>

[CmdletBinding()]
param(
    [string] $SearxngDir = $(if ($env:SEARXNG_DIR) { $env:SEARXNG_DIR } else { 'D:\searxng' }),
    [string] $SearxngUrl  = $(if ($env:SEARXNG_URL) { $env:SEARXNG_URL } else { 'http://127.0.0.1:8888' }),
    [switch] $SkipSearxng
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$PackExe = Join-Path $Root 'apps\desktop\release\win-unpacked\Hermes.exe'
$LogTag = '[start-desktop-pack]'

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'White')
    Write-Host "$LogTag $Message" -ForegroundColor $Color
}

if (-not (Test-Path $PackExe)) {
    Write-Log "packaged app not found: $PackExe" Red
    Write-Log 'build first: .\pack-desktop.ps1' Yellow
    exit 1
}

$env:HERMES_HOME = Join-Path $Root 'workspace'
$env:HERMES_DESKTOP_HERMES_ROOT = $Root

if (-not $SkipSearxng) {
    $probe = "$SearxngUrl/search?q=ping&format=json"
    $searxngOk = $false
    try {
        $null = Invoke-WebRequest -Uri $probe -TimeoutSec 5 -UseBasicParsing
        $searxngOk = $true
    } catch {
        $searxngOk = $false
    }
    if ($searxngOk) {
        Write-Log "SearXNG ready at $SearxngUrl" DarkGray
    } else {
        Write-Log "WARN: SearXNG not reachable at $SearxngUrl" Yellow
        Write-Log 'WARN: run .\start-desktop.ps1 -SkipSearxng once to boot Docker, or use -SkipSearxng here' Yellow
    }
}

Write-Log "HERMES_HOME = $env:HERMES_HOME" DarkGray
Write-Log "launch $PackExe" Cyan
& $PackExe
exit $LASTEXITCODE
