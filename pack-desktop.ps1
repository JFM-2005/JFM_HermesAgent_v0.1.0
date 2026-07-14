<#
.SYNOPSIS
    Build Windows single-exe portable Hermes Desktop (teacher-style green build).

.DESCRIPTION
    Produces one self-contained exe:
      apps\desktop\release\Hermes-Portable-<version>-<arch>.exe

    First launch:
      - Creates data\hermes beside the exe (HERMES_HOME)
      - Bootstraps Python runtime + clones JFM_HermesAgent from GitHub
      - Falls back to bundled install.ps1 if raw.githubusercontent.com is blocked

    Requires network (TUN/proxy) on first run for git clone / uv downloads.

.EXAMPLE
    .\pack-desktop.ps1
    .\pack-desktop.ps1 -SkipDeps
#>

[CmdletBinding()]
param(
    [string] $ProxyPort = $(if ($env:CLASH_PROXY_PORT) { $env:CLASH_PROXY_PORT } else { '7890' }),
    [switch] $SkipDeps,
    [switch] $SkipUv,
    [switch] $SkipProxy
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$DesktopDir = Join-Path $Root 'apps\desktop'
$ReleaseDir = Join-Path $DesktopDir 'release'
$LogTag = '[pack-desktop]'

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'White')
    Write-Host "$LogTag $Message" -ForegroundColor $Color
}

function Write-Step([string]$Message) { Write-Log $Message Cyan }

function Stop-DesktopLockingProcesses {
    $names = @('Hermes', 'electron')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "stopping $($_.ProcessName) (pid $($_.Id))" Yellow
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
}

function Test-WindowsIconIco {
    param([string]$IcoPath)
    if (-not (Test-Path $IcoPath)) {
        return @{ ok = $false; message = "missing $IcoPath" }
    }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        return @{ ok = $true; message = 'python not found; skip icon format check' }
    }
    $code = @'
import struct, sys
from pathlib import Path
p = Path(sys.argv[1])
data = p.read_bytes()
count = struct.unpack_from('<H', data, 4)[0]
if count < 3:
    print(f'FAIL: only {count} size(s); need 16/32/48/64/128/256')
    sys.exit(1)
bad = []
for i in range(count):
    off = 6 + 16 * i
    w, h, _, _, planes, _, size, offset = struct.unpack_from('<BBBBHHII', data, off)
    w = 256 if w == 0 else w
    h = 256 if h == 0 else h
    magic = data[offset:offset + 4]
    if planes != 1:
        bad.append(f'{w}x{h} planes={planes}')
    if magic == b'\x89PNG\r\n\x1a\n':
        bad.append(f'{w}x{h} PNG-compressed (use BMP/DIB ICO for Windows taskbar)')
if bad:
    print('FAIL: ' + '; '.join(bad))
    sys.exit(1)
print(f'OK: {count} entries, BMP/DIB, planes=1')
'@
    $out = & $py.Source -c $code $IcoPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return @{ ok = $false; message = $out.Trim() }
    }
    return @{ ok = $true; message = $out.Trim() }
}

function Repair-WindowsIconFromPng {
    param([string]$AssetsDir)
    $png = Join-Path $AssetsDir 'icon.png'
    $ico = Join-Path $AssetsDir 'icon.ico'
    if (-not (Test-Path $png)) {
        Write-Log "cannot auto-repair icon: missing $png" Yellow
        return $false
    }
    Write-Log 'auto-repair: regenerate icon.ico (BMP/DIB) from icon.png' Yellow
    $assetsDir = (Resolve-Path $AssetsDir).Path
    $code = @'
import struct, sys
from pathlib import Path
from PIL import Image

assets = Path(sys.argv[1])
src = Image.open(assets / 'icon.png').convert('RGBA')
sizes = [16, 32, 48, 64, 128, 256]
imgs = [src.resize((s, s), Image.Resampling.LANCZOS) for s in sizes]
out = assets / 'icon.ico'
entries, blobs = [], []
for img in imgs:
    w, h = img.size
    px = img.convert('RGBA').tobytes('raw', 'BGRA')
    row = w * 4
    color = b''.join(px[i:i+row] for i in range((h-1)*row, -1, -row))
    mask_row_bytes = ((w + 31) // 32) * 4
    and_mask = b'\x00' * (mask_row_bytes * h)
    dib = struct.pack('<IIIHHIIIIII', 40, w, h * 2, 1, 32, 0, len(color)+len(and_mask), 0, 0, 0, 0) + color + and_mask
    entries.append((w, h, len(dib)))
    blobs.append(dib)
with open(out, 'wb') as f:
    f.write(struct.pack('<HHH', 0, 1, len(imgs)))
    data_offset = 6 + 16 * len(imgs)
    for (w, h, size), blob in zip(entries, blobs):
        wb = 0 if w >= 256 else w
        hb = 0 if h >= 256 else h
        f.write(struct.pack('<BBBBHHII', wb, hb, 0, 0, 1, 32, size, data_offset))
        data_offset += size
    for blob in blobs:
        f.write(blob)
print('repaired', out)
'@
    & python -c $code $assetsDir
    return ($LASTEXITCODE -eq 0)
}

function Get-GitHeadSha {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $sha = & git -C $Root rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $sha.Trim()
}

function Get-GitHeadBranch {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return 'master' }
    $branch = & git -C $Root rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch -or $branch -eq 'HEAD') {
        return 'master'
    }
    return $branch.Trim()
}

# --- 1. toolchain ---
Write-Step 'preflight: toolchain'
foreach ($cmd in @('node', 'npm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd not found. Install Node.js LTS first."
    }
}
Write-Log "node = $(node -v)" DarkGray

# --- 2. close locking processes ---
Write-Step 'preflight: stop running Hermes / electron'
Stop-DesktopLockingProcesses

# --- 3. icon.ico ---
Write-Step 'preflight: validate assets\icon.ico'
$iconPath = Join-Path $DesktopDir 'assets\icon.ico'
$iconCheck = Test-WindowsIconIco -IcoPath $iconPath
if (-not $iconCheck.ok) {
    Write-Log $iconCheck.message Yellow
    if (Repair-WindowsIconFromPng -AssetsDir (Join-Path $DesktopDir 'assets')) {
        $iconCheck = Test-WindowsIconIco -IcoPath $iconPath
    }
}
if (-not $iconCheck.ok) {
    throw "icon.ico invalid: $($iconCheck.message)"
}
Write-Log $iconCheck.message Green

# --- 4. network mirrors ---
if (-not $SkipProxy) {
    $proxy = "http://127.0.0.1:$ProxyPort"
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
    $env:ELECTRON_BUILDER_BINARIES_MIRROR = 'https://npmmirror.com/mirrors/electron-builder-binaries/'
    $env:NPM_CONFIG_REGISTRY = 'https://registry.npmmirror.com'
    Write-Log "proxy = $proxy" DarkGray
}

# --- 5. build stamp (git commit + JFM repo) ---
$headSha = Get-GitHeadSha
if ($headSha) {
    $env:GITHUB_SHA = $headSha
    $env:GITHUB_REF_NAME = Get-GitHeadBranch
    Write-Log "GITHUB_SHA = $($headSha.Substring(0, 12)) ($($env:GITHUB_REF_NAME))" DarkGray
} else {
    Write-Log 'WARN: git HEAD not found; write-build-stamp may fail' Yellow
}
$env:HERMES_BUILD_REPOSITORY = 'JFM-2005/JFM_HermesAgent_v0.1.0'

# --- 6. signing trap ---
$env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'

# --- 7. npm ci ---
if (-not $SkipDeps) {
    Write-Step 'npm ci (root lockfile)'
    Push-Location $Root
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed (exit $LASTEXITCODE)" }
    } finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
}

# --- 8. uv sync (optional) ---
if (-not $SkipUv -and (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Step 'uv sync --locked'
    Push-Location $Root
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & uv sync --locked
    } finally {
        $ErrorActionPreference = $prevEAP
        Pop-Location
    }
}

# --- 9. pack portable single exe ---
Write-Step 'npm run desktop:package:portable:win'
Push-Location $Root
$prevEAP = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & npm run desktop:package:portable:win
    if ($LASTEXITCODE -ne 0) { throw "portable pack failed (exit $LASTEXITCODE)" }
} finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
}

# --- 10. verify output ---
$portableExe = Get-ChildItem -Path $ReleaseDir -Filter 'Hermes-Portable-*.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $portableExe) {
    throw "pack finished but no Hermes-Portable-*.exe found under $ReleaseDir"
}

$sizeMb = [math]::Round($portableExe.Length / 1MB, 1)
Write-Host ''
Write-Log "SUCCESS: $($portableExe.FullName) ($sizeMb MB)" Green
Write-Log 'distribute: copy this single exe anywhere and double-click' Cyan
Write-Log 'first launch creates:  <exe-dir>\data\hermes\  (config + runtime)' DarkGray
Write-Log 'first launch needs network (TUN/proxy) for bootstrap' Yellow
Write-Host ''
