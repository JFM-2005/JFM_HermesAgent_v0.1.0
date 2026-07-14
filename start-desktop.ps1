<#
.SYNOPSIS
    Hermes desktop one-click launcher (Windows / PowerShell)

.DESCRIPTION
    1. Start SearXNG (Docker Compose) for web search
    2. Set HERMES_HOME / HERMES_DESKTOP_HERMES_ROOT (portable workspace)
    3. Run run.ps1 desktop --source

.EXAMPLE
    .\start-desktop.ps1
    .\start-desktop.ps1 -SkipSearxng
    .\start-desktop.ps1 -SearxngDir D:\searxng
#>

[CmdletBinding()]
param(
    [string] $SearxngDir = $(if ($env:SEARXNG_DIR) { $env:SEARXNG_DIR } else { 'D:\searxng' }),
    [string] $SearxngUrl  = $(if ($env:SEARXNG_URL) { $env:SEARXNG_URL } else { 'http://127.0.0.1:8888' }),
    [string] $ProxyPort   = $(if ($env:CLASH_PROXY_PORT) { $env:CLASH_PROXY_PORT } else { '7890' }),
    [switch] $SkipSearxng,
    [switch] $SkipProxy
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$LogTag = '[start-desktop]'

function Write-Log {
    param(
        [string] $Message,
        [ConsoleColor] $Color = 'White'
    )
    Write-Host "$LogTag $Message" -ForegroundColor $Color
}

function Write-Step([string]$Message) {
    Write-Log $Message Cyan
}

function Test-SearxngReady([string]$Url) {
    $probe = "$Url/search?q=ping&format=json"
    $ok = $false
    try {
        $null = Invoke-WebRequest -Uri $probe -TimeoutSec 8 -UseBasicParsing
        $ok = $true
    } catch {
        $ok = $false
    }
    return $ok
}

function Start-SearxngStack {
    param([string]$Dir, [string]$Url)

    $composeFile = Join-Path $Dir 'docker-compose.yml'
    if (-not (Test-Path $composeFile)) {
        Write-Log "WARN: missing $composeFile, skip SearXNG start" Yellow
        Write-Log "WARN: ensure SearXNG is reachable at $Url" Yellow
        return
    }

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Log 'WARN: docker not found, skip SearXNG start' Yellow
        return
    }

    Write-Step "check SearXNG ($Url) ..."
    if (Test-SearxngReady $Url) {
        Write-Log 'SearXNG already running' DarkGray
        return
    }

    Write-Step "start SearXNG: $Dir"
    Push-Location $Dir
    # Docker Compose writes progress to stderr; with $ErrorActionPreference='Stop'
    # PowerShell treats that as a terminating NativeCommandError even on success.
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & docker compose up -d
        $composeExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    if ($composeExit -ne 0) {
        Pop-Location
        Write-Log "WARN: docker compose up -d failed (exit $composeExit)" Yellow
        Write-Log "WARN: start Docker Desktop, or run: .\start-desktop.ps1 -SkipSearxng" Yellow
        return
    }

    $deadline = (Get-Date).AddSeconds(45)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-SearxngReady $Url) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    Pop-Location

    if ($ready) {
        Write-Log 'SearXNG ready' Green
    } else {
        Write-Log "WARN: SearXNG started but $Url not responding yet" Yellow
    }
}

# --- 1. portable HERMES_HOME ---
$env:HERMES_HOME = Join-Path $Root 'workspace'
$env:HERMES_DESKTOP_HERMES_ROOT = $Root
if (-not (Test-Path $env:HERMES_HOME)) {
    New-Item -ItemType Directory -Force -Path $env:HERMES_HOME | Out-Null
}

# --- 2. .env bootstrap (same as run.ps1) ---
$envFile    = Join-Path $env:HERMES_HOME '.env'
$envExample = Join-Path $env:HERMES_HOME '.env.example'
if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
        Write-Host ''
        Write-Log 'first run: created workspace\.env from .env.example' Yellow
        Write-Log 'fill API keys then run this script again' Yellow
        Write-Log $envFile Cyan
        Write-Host ''
        exit 1
    }
    Write-Log 'WARN: missing workspace\.env' Yellow
}

# --- 3. proxy for npm/electron rebuilds ---
if (-not $SkipProxy) {
    $proxy = "http://127.0.0.1:$ProxyPort"
    $env:HTTP_PROXY  = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
    $env:NPM_CONFIG_REGISTRY = 'https://registry.npmmirror.com'
    Write-Log "proxy = $proxy" DarkGray
}

# --- 4. build stamp fallback when no git commit ---
if (-not $env:GITHUB_SHA) {
    $env:GITHUB_SHA = '0000000000000000000000000000000000000000'
}

# --- 5. SearXNG ---
if (-not $SkipSearxng) {
    Start-SearxngStack -Dir $SearxngDir -Url $SearxngUrl
} else {
    Write-Log 'skipped SearXNG (-SkipSearxng)' DarkGray
}

# --- 6. launch desktop ---
Write-Step "HERMES_HOME = $env:HERMES_HOME"
Write-Step 'launch Hermes Desktop ...'
& (Join-Path $Root 'run.ps1') desktop --source
exit $LASTEXITCODE
