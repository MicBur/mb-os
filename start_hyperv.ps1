# MB-OS: UEFI (Gen2) VM mit 20GB Installationsdisk
# MUSS ALS ADMIN AUSGEFÜHRT WERDEN!

$VMName = "MB-OS"
$ISOPath = "D:\MB-OS\mb-os-v4.iso"
$VHDPath = "D:\MB-OS-Install.vhdx"
$VHDSize = 20GB

# 1. VM komplett entfernen
Write-Host ">>> Entferne alte VM..." -ForegroundColor Yellow
Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue

# 2. Hyper-V Dienst neustarten
Write-Host ">>> Starte Hyper-V Dienst neu..." -ForegroundColor Yellow
Restart-Service vmms -Force
Start-Sleep 3

# 3. 20GB Disk erstellen (falls nicht vorhanden)
if (-Not (Test-Path $VHDPath)) {
    Write-Host ">>> Erstelle 20GB Installationsdisk: $VHDPath ..." -ForegroundColor Cyan
    New-VHD -Path $VHDPath -SizeBytes $VHDSize -Dynamic
} else {
    Write-Host ">>> Installationsdisk existiert bereits: $VHDPath" -ForegroundColor Gray
}

# 4. Neue Gen2 (UEFI) VM erstellen
Write-Host ">>> Erstelle Gen2 (UEFI) VM mit 20GB Disk..." -ForegroundColor Cyan
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -NoVHD -SwitchName "Default Switch"
Set-VMProcessor -VMName $VMName -Count 4

# 5. Secure Boot DEAKTIVIEREN (noetig fuer custom Linux)
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

# 6. 20GB Disk anhaengen
Add-VMHardDiskDrive -VMName $VMName -Path $VHDPath

# 7. DVD hinzufuegen
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# 8. Boot-Reihenfolge: DVD zuerst, dann Festplatte
$dvd = Get-VMDvdDrive -VMName $VMName
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd

# 9. Starten
Write-Host ">>> Starte UEFI VM..." -ForegroundColor Green
Start-VM -Name $VMName
Start-Sleep 2
vmconnect localhost $VMName

Write-Host ""
Write-Host "=== Gen2 UEFI VM laeuft! ===" -ForegroundColor Green
Write-Host "  - ISO: $ISOPath" -ForegroundColor Gray
Write-Host "  - Disk: $VHDPath (20GB)" -ForegroundColor Gray
Write-Host "  - Secure Boot: AUS" -ForegroundColor Gray
Write-Host "  - GRUB Theme sollte jetzt grafisch sein!" -ForegroundColor Cyan
