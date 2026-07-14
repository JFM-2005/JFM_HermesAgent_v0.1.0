<#
.SYNOPSIS
    Launch dev-tree win-unpacked Hermes.exe with workspace (developer testing).

.DESCRIPTION
    For the teacher-style single portable exe, just double-click:
      apps\desktop\release\Hermes-Portable-<version>-<arch>.exe

    This script is for testing the unpacked build from `npm run pack` only.

.EXAMPLE
    .\start-desktop-pack.ps1
#>

[CmdletBinding()]
param(
    [switch] $SkipSearxng
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$PackExe = Join-Path $Root 'apps\desktop\release\win-unpacked\Hermes.exe'
$PortableGlob = Join-Path $Root 'apps\desktop\release\Hermes-Portable-*.exe'
$LogTag = '[start-desktop-pack]'

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'White')
    Write-Host "$LogTag $Message" -ForegroundColor $Color
}

$portable = Get-ChildItem -Path $PortableGlob -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($portable) {
    Write-Log "portable exe found: $($portable.FullName)" Cyan
    Write-Log 'launching portable build (data folder created beside exe on first run)' DarkGray
    & $portable.FullName
    exit $LASTEXITCODE
}

if (-not (Test-Path $PackExe)) {
    Write-Log "no portable exe and no win-unpacked build" Red
    Write-Log 'build first: .\pack-desktop.ps1' Yellow
    exit 1
}

Write-Log 'WARN: using win-unpacked dev layout (not teacher-style portable)' Yellow
$env:HERMES_HOME = Join-Path $Root 'workspace'
$env:HERMES_DESKTOP_HERMES_ROOT = $Root
Write-Log "HERMES_HOME = $env:HERMES_HOME" DarkGray
& $PackExe
exit $LASTEXITCODE
