# MB-OS USB-Stick schreiben (Raw Disk Write)
# Kein WSL, kein dd - reines PowerShell!

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$DiskNumber = 2
$ISOPath = "D:\MB-OS\mb-os-full.iso"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MB-OS USB-Stick (Raw Write)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$disk = Get-Disk -Number $DiskNumber
if ($disk.BusType -ne "USB") {
    Write-Host "FEHLER: Disk $DiskNumber ist kein USB!" -ForegroundColor Red
    pause; exit 1
}

$isoSize = (Get-Item $ISOPath).Length
Write-Host "USB: $($disk.FriendlyName) ($([math]::Round($disk.Size/1GB,1)) GB)" -ForegroundColor Yellow
Write-Host "ISO: $([math]::Round($isoSize/1MB)) MB" -ForegroundColor Yellow
Write-Host ""
Write-Host "ALLE DATEN WERDEN GELOESCHT!" -ForegroundColor Red
$confirm = Read-Host "Fortfahren? (j/n)"
if ($confirm -ne "j") { exit }

# Schritt 1: Diskpart clean
Write-Host ""
Write-Host ">>> Disk bereinigen mit diskpart..." -ForegroundColor Cyan
$dpScript = @"
select disk $DiskNumber
clean
"@
$dpScript | diskpart

Start-Sleep 2

# Schritt 2: Volumes dismounten
Write-Host ">>> Volumes dismounten..." -ForegroundColor Cyan
Get-Disk -Number $DiskNumber | Get-Partition -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_ | Remove-PartitionAccessPath -AccessPath "$($_.DriveLetter):\" -ErrorAction SilentlyContinue } catch {}
}

# Schritt 3: Raw write
Write-Host ">>> ISO auf USB schreiben..." -ForegroundColor Cyan
Write-Host "    $([math]::Round($isoSize/1MB)) MB - dauert ca. 3-5 Minuten..." -ForegroundColor Gray

$physPath = "\\.\PhysicalDrive$DiskNumber"
$bufferSize = 4 * 1024 * 1024  # 4 MB Buffer

try {
    # Open ISO for reading
    $isoStream = [System.IO.File]::OpenRead($ISOPath)
    
    # Open physical disk for writing
    $diskHandle = [System.IO.File]::Open($physPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    
    $buffer = New-Object byte[] $bufferSize
    $totalWritten = 0
    $startTime = Get-Date
    
    while (($bytesRead = $isoStream.Read($buffer, 0, $bufferSize)) -gt 0) {
        $diskHandle.Write($buffer, 0, $bytesRead)
        $totalWritten += $bytesRead
        $pct = [math]::Round(($totalWritten / $isoSize) * 100)
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $speed = if ($elapsed -gt 0) { [math]::Round($totalWritten / $elapsed / 1MB, 1) } else { 0 }
        Write-Host "`r    $pct% ($([math]::Round($totalWritten/1MB)) MB / $([math]::Round($isoSize/1MB)) MB) - ${speed} MB/s   " -NoNewline -ForegroundColor Green
    }
    
    $diskHandle.Flush()
    $diskHandle.Close()
    $isoStream.Close()
    
    Write-Host ""
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  USB-Stick ist fertig!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. Stick in den Acer stecken" -ForegroundColor White
    Write-Host "  2. F2 -> Secure Boot AUS" -ForegroundColor White
    Write-Host "  3. F12 -> USB Boot auswaehlen" -ForegroundColor White
    Write-Host "  4. MB-OS startet!" -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "FEHLER: $_" -ForegroundColor Red
    if ($isoStream) { $isoStream.Close() }
    if ($diskHandle) { $diskHandle.Close() }
}

Write-Host ""
pause
