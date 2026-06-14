# MB-OS: ISO wieder einhaengen zum Reparieren
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$VMName = "MB-OS"
$ISOPath = "D:\MB-OS\mb-os-full.iso"

Write-Host ">>> VM stoppen..." -ForegroundColor Yellow
Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
Start-Sleep 3

Write-Host ">>> DVD hinzufuegen fuer Reparatur..." -ForegroundColor Cyan
Add-VMDvdDrive -VMName $VMName -Path $ISOPath -ErrorAction SilentlyContinue

# DVD zuerst booten
$dvd = Get-VMDvdDrive -VMName $VMName
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd

Write-Host ">>> Starte VM von ISO (Reparatur)..." -ForegroundColor Green
Start-VM -Name $VMName
Start-Sleep 2
vmconnect localhost $VMName

Write-Host ""
Write-Host "=== VM bootet von ISO zum Reparieren ===" -ForegroundColor Green
pause
