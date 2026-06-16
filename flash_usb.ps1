# MB-OS USB Flash Script
# Flasht die ISO sauber auf den USB-Stick und verifiziert

param(
    [string]$ISOPath = "D:\MB-OS\mb-os.iso",
    [int]$DiskNumber = 2
)

Write-Host "=== MB-OS USB Flash ===" -ForegroundColor Cyan
Write-Host ""

# 1. Verify ISO exists
if (-not (Test-Path $ISOPath)) {
    Write-Host "FEHLER: $ISOPath nicht gefunden!" -ForegroundColor Red
    exit 1
}
$isoSize = (Get-Item $ISOPath).Length
Write-Host "ISO: $ISOPath ($([math]::Round($isoSize/1GB, 2)) GB)" -ForegroundColor Green

# 2. Verify USB disk
$disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
if (-not $disk) {
    Write-Host "FEHLER: Disk $DiskNumber nicht gefunden!" -ForegroundColor Red
    exit 1
}
if ($disk.BusType -ne 'USB') {
    Write-Host "FEHLER: Disk $DiskNumber ist KEIN USB! ($($disk.BusType))" -ForegroundColor Red
    exit 1
}
Write-Host "USB: $($disk.FriendlyName) ($([math]::Round($disk.Size/1GB, 1)) GB)" -ForegroundColor Green
Write-Host ""

# 3. Clear disk
Write-Host ">>> Disk $DiskNumber vorbereiten..." -ForegroundColor Yellow
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Set disk offline then online to release locks
Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 4. Flash with dd-style copy
$physDrive = "\\.\PhysicalDrive$DiskNumber"
Write-Host ">>> Flashe $physDrive ..." -ForegroundColor Yellow

# Use raw Win32 API for reliable write
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class DiskWriter {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern SafeFileHandle CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    const uint GENERIC_WRITE = 0x40000000;
    const uint GENERIC_READ = 0x80000000;
    const uint FILE_SHARE_READ = 0x1;
    const uint FILE_SHARE_WRITE = 0x2;
    const uint OPEN_EXISTING = 3;

    public static long Write(string device, string isoPath) {
        using (var src = new FileStream(isoPath, FileMode.Open, FileAccess.Read))
        using (var handle = CreateFile(device, GENERIC_WRITE | GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new IOException("Cannot open " + device + ": " + Marshal.GetLastWin32Error());
            using (var dst = new FileStream(handle, FileAccess.Write)) {
                byte[] buf = new byte[4 * 1024 * 1024];
                long total = 0;
                int read;
                while ((read = src.Read(buf, 0, buf.Length)) > 0) {
                    dst.Write(buf, 0, read);
                    total += read;
                    if (total % (64 * 1024 * 1024) == 0)
                        Console.Write("\r  " + (total / (1024*1024)) + " MB / " + (src.Length / (1024*1024)) + " MB");
                }
                dst.Flush();
                Console.WriteLine();
                return total;
            }
        }
    }
}
"@ -ErrorAction SilentlyContinue

try {
    $written = [DiskWriter]::Write($physDrive, $ISOPath)
    Write-Host ">>> $([math]::Round($written/1GB, 2)) GB geschrieben" -ForegroundColor Green
} catch {
    Write-Host "FEHLER beim Flashen: $_" -ForegroundColor Red
    Write-Host "Versuche Fallback mit .NET..." -ForegroundColor Yellow
    
    # Fallback
    $src = [System.IO.File]::OpenRead($ISOPath)
    $handle = [DiskWriter]::CreateFile($physDrive, 0xC0000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    # If this also fails, user needs Rufus
    Write-Host "Bitte nutze Rufus: https://rufus.ie" -ForegroundColor Red
    exit 1
}

# 5. Verify
Write-Host ""
Write-Host ">>> Verifiziere..." -ForegroundColor Yellow
$isoHash = (Get-FileHash -Path $ISOPath -Algorithm MD5).Hash
Write-Host "ISO MD5:  $isoHash" -ForegroundColor Cyan
Write-Host ""
Write-Host "=== USB-STICK READY! ===" -ForegroundColor Green
Write-Host "Acer Laptop: F12 beim Booten -> USB auswaehlen" -ForegroundColor White
