<#
.SYNOPSIS
    Build Windows portable (green) Hermes Desktop — adapted for JFM_HermesAgent.

.DESCRIPTION
    Teacher workflow equivalent:
      npm ci
      uv sync --locked
      npm run desktop:package:portable:win

    This script adds preflight checks for our portable setup:
      - proxy / Electron mirrors (China network)
      - close running Hermes.exe / electron.exe (Access denied)
      - GITHUB_SHA fallback (build stamp)
      - Windows icon.ico format (BMP/DIB, not PNG-in-ICO)
      - CSC_IDENTITY_AUTO_DISCOVERY=false (avoid winCodeSign symlink trap)

    Output:
      apps\desktop\release\win-unpacked\Hermes.exe

    Run the packaged app with workspace config:
      .\start-desktop-pack.ps1

.EXAMPLE
    .\pack-desktop.ps1
    .\pack-desktop.ps1 -SkipDeps
    .\pack-desktop.ps1 -SkipProxy
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
$ReleaseExe = Join-Path $DesktopDir 'release\win-unpacked\Hermes.exe'
$LogTag = '[pack-desktop]'

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'White')
    Write-Host "$LogTag $Message" -ForegroundColor $Color
}

function Write-Step([string]$Message) { Write-Log $Message Cyan }

function Stop-DesktopLockingProcesses {
    $names = @('Hermes', 'electron')
    $stopped = @()
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "stopping $($_.ProcessName) (pid $($_.Id))" Yellow
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            $stopped += $_.ProcessName
        }
    }
    if ($stopped.Count -gt 0) {
        Start-Sleep -Seconds 2
    }
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
    if ($LASTEXITCODE -ne 0) {
        Write-Log 'icon auto-repair failed (need: pip install pillow)' Red
        return $false
    }
    return $true
}

# --- 0. portable env (for hermes CLI if used later) ---
$env:HERMES_HOME = Join-Path $Root 'workspace'
$env:HERMES_DESKTOP_HERMES_ROOT = $Root

# --- 1. toolchain ---
Write-Step 'preflight: toolchain'
foreach ($cmd in @('node', 'npm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd not found. Install Node.js LTS first."
    }
}
Write-Log "node = $(node -v)" DarkGray
Write-Log "npm  = $(npm -v)" DarkGray

# --- 2. close locking processes ---
Write-Step 'preflight: stop running Hermes / electron'
Stop-DesktopLockingProcesses

# --- 3. icon.ico (Windows taskbar / rcedit) ---
Write-Step 'preflight: validate assets\icon.ico'
$iconPath = Join-Path $DesktopDir 'assets\icon.ico'
$iconCheck = Test-WindowsIconIco -IcoPath $iconPath
if (-not $iconCheck.ok) {
    Write-Log $iconCheck.message Yellow
    if (Repair-WindowsIconFromPng -AssetsDir (Join-Path $DesktopDir 'assets')) {
        $iconCheck = Test-WindowsIconIco -IcoPath $iconPath
    }
}
if ($iconCheck.ok) {
    Write-Log $iconCheck.message Green
} else {
    throw "icon.ico invalid: $($iconCheck.message). Copy a working BMP/DIB icon.ico into apps\desktop\assets\."
}

# --- 4. network mirrors ---
if (-not $SkipProxy) {
    $proxy = "http://127.0.0.1:$ProxyPort"
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
    $env:ELECTRON_BUILDER_BINARIES_MIRROR = 'https://npmmirror.com/mirrors/electron-builder-binaries/'
    $env:NPM_CONFIG_REGISTRY = 'https://registry.npmmirror.com'
    Write-Log "proxy = $proxy" DarkGray
    Write-Log "ELECTRON_MIRROR = $($env:ELECTRON_MIRROR)" DarkGray
}

# --- 5. build stamp ---
if (-not $env:GITHUB_SHA) {
    $env:GITHUB_SHA = '0000000000000000000000000000000000000000'
    Write-Log 'GITHUB_SHA fallback set (no git commit)' DarkGray
}

# --- 6. signing trap (Windows) ---
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
    Write-Log 'npm ci OK' Green
} else {
    Write-Log 'skipped npm ci (-SkipDeps)' DarkGray
}

# --- 8. uv sync (Python backend; teacher step) ---
if (-not $SkipUv) {
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if ($uv) {
        Write-Step 'uv sync --locked'
        Push-Location $Root
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & uv sync --locked
            if ($LASTEXITCODE -ne 0) { throw "uv sync --locked failed (exit $LASTEXITCODE)" }
        } finally {
            $ErrorActionPreference = $prevEAP
            Pop-Location
        }
        Write-Log 'uv sync OK' Green
    } else {
        Write-Log 'WARN: uv not found; skip Python sync (desktop pack may still work)' Yellow
    }
} else {
    Write-Log 'skipped uv sync (-SkipUv)' DarkGray
}

# --- 9. pack (teacher: npm run desktop:package:portable:win) ---
Write-Step 'npm run desktop:package:portable:win'
Push-Location $Root
$prevEAP = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & npm run desktop:package:portable:win
    if ($LASTEXITCODE -ne 0) { throw "desktop pack failed (exit $LASTEXITCODE)" }
} finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
}

# --- 10. verify output ---
if (-not (Test-Path $ReleaseExe)) {
    throw "pack finished but missing: $ReleaseExe"
}

$sizeMb = [math]::Round((Get-Item $ReleaseExe).Length / 1MB, 1)
Write-Host ''
Write-Log "SUCCESS: $ReleaseExe ($sizeMb MB)" Green
Write-Log 'launch packaged app with portable workspace:' Cyan
Write-Log '  .\start-desktop-pack.ps1' Cyan
Write-Host ''
Write-Log 'distribute: zip the entire folder' DarkGray
Write-Log '  apps\desktop\release\win-unpacked\' DarkGray
Write-Log 'do NOT commit: workspace\.env, sessions\, *.db' DarkGray
Write-Host ''
