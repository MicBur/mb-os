# MB-OS VM Neustarten
Stop-VM -Name "MB-OS" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-VM -Name "MB-OS"
Write-Host "VM gestartet!" -ForegroundColor Green
vmconnect localhost "MB-OS"
