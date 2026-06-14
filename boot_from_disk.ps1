# MB-OS: DVD entfernen + von Festplatte booten
# Selbst-elevierend - Doppelklick genuegt!

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$VMName = "MB-OS"

Write-Host ">>> VM stoppen..." -ForegroundColor Yellow
Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
Start-Sleep 3

Write-Host ">>> DVD-Laufwerk entfernen..." -ForegroundColor Cyan
Get-VMDvdDrive -VMName $VMName | Remove-VMDvdDrive -ErrorAction SilentlyContinue

Write-Host ">>> Boot-Reihenfolge: Nur Festplatte..." -ForegroundColor Cyan
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $hdd

Write-Host ">>> Starte VM von Festplatte..." -ForegroundColor Green
Start-VM -Name $VMName
Start-Sleep 2
vmconnect localhost $VMName

Write-Host ""
Write-Host "=== MB-OS bootet jetzt von der Festplatte! ===" -ForegroundColor Green
Write-Host "    DVD entfernt. Alle Daten bleiben erhalten." -ForegroundColor Gray
Write-Host ""
pause
