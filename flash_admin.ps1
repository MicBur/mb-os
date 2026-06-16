# Flash MB-OS ISO to USB with Admin privileges
# Run as: Start-Process powershell -Verb RunAs -ArgumentList "-File D:\MB-OS\flash_admin.ps1"

Write-Host "=== MB-OS USB Flash (Admin) ===" -ForegroundColor Cyan

# 1. Dismount all volumes on disk 2
Write-Host ">>> Volumes dismounten..." -ForegroundColor Yellow
Get-Partition -DiskNumber 2 -ErrorAction SilentlyContinue | ForEach-Object {
    $vol = $_ | Get-Volume -ErrorAction SilentlyContinue
    if ($vol -and $vol.DriveLetter) {
        $letter = $vol.DriveLetter
        Write-Host "  Dismount $letter`:"
        $vol | Dismount-DiskImage -ErrorAction SilentlyContinue
    }
    Remove-PartitionAccessPath -DiskNumber 2 -PartitionNumber $_.PartitionNumber -AccessPath $_.AccessPaths[0] -ErrorAction SilentlyContinue
}

# 2. Set offline
Write-Host ">>> Disk offline..." -ForegroundColor Yellow
Set-Disk -Number 2 -IsOffline $true -ErrorAction SilentlyContinue
Start-Sleep 2
Set-Disk -Number 2 -IsOffline $false
Start-Sleep 1

# 3. Clear disk completely
Write-Host ">>> Disk clearen..." -ForegroundColor Yellow
Clear-Disk -Number 2 -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep 2

# 4. Use diskpart for raw access
$diskpartScript = @"
select disk 2
clean
"@
$diskpartScript | diskpart

Start-Sleep 2

# 5. Mount in WSL and dd
Write-Host ">>> WSL mount + dd..." -ForegroundColor Yellow
wsl --mount \\.\PhysicalDrive2 --bare
Start-Sleep 2

# Find the device in WSL
wsl -d Ubuntu bash -c "
DEV=\$(lsblk -d -n -o NAME,SIZE | grep '58' | awk '{print \"/dev/\" \$1}' | head -1)
if [ -z \"\$DEV\" ]; then
    echo 'USB nicht gefunden in WSL!'
    lsblk -d
    exit 1
fi
echo \">>> dd to \$DEV ...\"
sudo dd if=/mnt/d/MB-OS/mb-os.iso of=\$DEV bs=4M status=progress conv=fsync
echo '=== FLASH DONE ==='
sync
"

wsl --unmount \\.\PhysicalDrive2 2>$null
Write-Host "=== USB STICK READY ===" -ForegroundColor Green
Write-Host "F12 am Acer -> USB booten" -ForegroundColor White
Read-Host "Enter zum Beenden"
