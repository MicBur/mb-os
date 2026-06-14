# MB-OS VM komplett neu erstellen + starten
$VMName = "MB-OS"
$ISOPath = "D:\MB-OS\mb-os.iso"
$VHDPath = "D:\MB-OS\MB-OS.vhdx"
$SwitchName = "Default Switch"

# Alte VM entfernen falls vorhanden
Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Remove-Item $VHDPath -Force -ErrorAction SilentlyContinue

Write-Host ">>> Erstelle neue VM..." -ForegroundColor Cyan

# VM erstellen (Gen 1 fuer BIOS-Boot)
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 1 -SwitchName $SwitchName
New-VHD -Path $VHDPath -SizeBytes 40GB -Dynamic
Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

# DVD mit ISO
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# CPU
Set-VMProcessor -VMName $VMName -Count 4

# Boot-Reihenfolge: DVD zuerst
$dvd = Get-VMDvdDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd -ErrorAction SilentlyContinue
# Gen1: Boot order via BIOS
Set-VMBios -VMName $VMName -StartupOrder @("CD","IDE","LegacyNetworkAdapter","Floppy") -ErrorAction SilentlyContinue

# Enhanced Session erlauben
Set-VM -VMName $VMName -EnhancedSessionTransportType HvSocket -ErrorAction SilentlyContinue

Write-Host ">>> Starte VM..." -ForegroundColor Green
Start-VM -Name $VMName

Write-Host ">>> Oeffne VMConnect..." -ForegroundColor Green
vmconnect localhost $VMName

Write-Host "Fertig! VM laeuft." -ForegroundColor Cyan
