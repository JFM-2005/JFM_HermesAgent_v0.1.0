# Create/update the dev Start Menu shortcut so Windows taskbar icon resolution
# works for `hermes desktop --source` (unpackaged Electron launches).
#
# Uses a dedicated .ico for IconLocation (install.ps1 pattern). AppUserModelID
# on the shortcut is best-effort — the process also sets the same ID via env.

param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$IconLocation,
    [Parameter(Mandatory = $true)][string]$AppId,
    [string]$ShortcutPath = $(Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs\Hermes Dev.lnk')
)

$ErrorActionPreference = 'Stop'

$parent = Split-Path -Parent $ShortcutPath
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

if (Test-Path $ShortcutPath) {
    Remove-Item -Force $ShortcutPath
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $TargetPath
$shortcut.WorkingDirectory = $WorkingDirectory
$shortcut.IconLocation = $IconLocation
$shortcut.Description = 'Hermes Agent (development)'
$shortcut.Save()

Start-Sleep -Milliseconds 150

try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct PROPERTYKEY {
    public Guid fmtid;
    public uint pid;
}

[StructLayout(LayoutKind.Explicit, Size = 16)]
public struct PropVariant {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pointerValue;
}

[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
    void GetCount(out uint cProps);
    void GetAt(uint iProp, out PROPERTYKEY pkey);
    void GetValue(ref PROPERTYKEY key, out PropVariant pv);
    void SetValue(ref PROPERTYKEY key, ref PropVariant pv);
    void Commit();
}

[ComImport, Guid("0000010b-0000-0000-c000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPersistFile {
    void GetClassID(out Guid pClassID);
    [PreserveSig] int IsDirty();
    [PreserveSig] int Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
    [PreserveSig] int Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [In, MarshalAs(UnmanagedType.Bool)] bool fRemember);
    [PreserveSig] int SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
    void GetCurFile([Out, MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
}

[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
public class ShellLink { }

public static class DevShortcutAppId {
    public static void Apply(string shortcutPath, string appId) {
        const uint STGM_READWRITE = 0x00000002;
        var link = new ShellLink();
        var persist = (IPersistFile)link;
        int hr = persist.Load(shortcutPath, STGM_READWRITE);
        if (hr != 0) {
            throw new InvalidOperationException("IPersistFile.Load failed: 0x" + hr.ToString("X8"));
        }

        var propertyStore = (IPropertyStore)link;
        var key = new PROPERTYKEY {
            fmtid = new Guid("9F4C2855-9F79-4FD4-8ADF-6816AFDB2596"),
            pid = 5
        };

        var pv = new PropVariant { vt = 31, pointerValue = Marshal.StringToCoTaskMemUni(appId) };
        try {
            propertyStore.SetValue(ref key, ref pv);
            propertyStore.Commit();
            persist.Save(shortcutPath, true);
        } finally {
            if (pv.pointerValue != IntPtr.Zero) {
                Marshal.FreeCoTaskMem(pv.pointerValue);
            }
        }
    }
}
'@ -ErrorAction Stop

    [DevShortcutAppId]::Apply($ShortcutPath, $AppId)
} catch {
    Write-Warning "Could not set AppUserModelID on shortcut (taskbar may still work via Hermes-dev.exe): $($_.Exception.Message)"
}

try {
    & ie4uinit.exe -show 2>$null
} catch {
    # Best-effort icon cache refresh (install.ps1 pattern).
}

Write-Host "[ensure-dev-windows-shortcut] updated: $ShortcutPath"
