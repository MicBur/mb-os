# MB-OS Hyper-V VM Setup Script
# Muss als Administrator ausgeführt werden!

Write-Host "=== MB-OS Hyper-V VM Setup ===" -ForegroundColor Cyan

# Prüfe ob VM bereits existiert
if (Get-VM -Name "MB-OS" -ErrorAction SilentlyContinue) {
    Write-Host "VM 'MB-OS' existiert bereits. Lösche alte VM..." -ForegroundColor Yellow
    Stop-VM -Name "MB-OS" -Force -ErrorAction SilentlyContinue
    Remove-VM -Name "MB-OS" -Force
    Remove-Item "D:\MB-OS\mb-os.vhdx" -Force -ErrorAction SilentlyContinue
}

# VM erstellen (Gen 1 = BIOS Boot)
Write-Host "[1/6] VM erstellen (Gen 1, 4GB RAM)..." -ForegroundColor Green
New-VM -Name "MB-OS" `
       -MemoryStartupBytes 4GB `
       -Generation 1 `
       -NewVHDPath "D:\MB-OS\mb-os.vhdx" `
       -NewVHDSizeBytes 20GB `
       -SwitchName "Default Switch"

# CPU-Kerne
Write-Host "[2/6] 4 CPU-Kerne zuweisen..." -ForegroundColor Green
Set-VMProcessor -VMName "MB-OS" -Count 4

# Dynamic Memory
Write-Host "[3/6] Dynamic Memory (2-8 GB)..." -ForegroundColor Green
Set-VMMemory -VMName "MB-OS" -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB

# ISO einlegen
Write-Host "[4/6] ISO einlegen..." -ForegroundColor Green
Set-VMDvdDrive -VMName "MB-OS" -Path "D:\MB-OS\mb-os.iso"

# Enhanced Session Mode
Write-Host "[5/6] Enhanced Session Mode aktivieren..." -ForegroundColor Green
Set-VM -VMName "MB-OS" -EnhancedSessionTransportType HvSocket

# Checkpoints deaktivieren (Performance)
Write-Host "[6/6] Automatische Checkpoints deaktivieren..." -ForegroundColor Green
Set-VM -VMName "MB-OS" -CheckpointType Disabled

Write-Host ""
Write-Host "=== VM 'MB-OS' erfolgreich erstellt! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starte VM..." -ForegroundColor Green

# VM starten
Start-VM -VMName "MB-OS"

Write-Host ""
Write-Host "VM laeuft! Oeffne VMConnect..." -ForegroundColor Green

# VMConnect öffnen
vmconnect localhost "MB-OS"

Write-Host ""
Write-Host "Fertig! MB-OS laeuft in Hyper-V." -ForegroundColor Cyan
Write-Host "Druecke Enter zum Beenden..." -ForegroundColor Gray
Read-Host
