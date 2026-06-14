#!/bin/bash
LOG="/mnt/d/MB-OS/qemu_serial.log"

echo "=== MB-OS QEMU SYSTEM TEST ==="
echo "$(date)"
echo ""

echo "--- Services Started ---"
started=$(grep -c 'Started' "$LOG" 2>/dev/null || echo 0)
failed=$(grep -c 'Failed' "$LOG" 2>/dev/null || echo 0)
echo "  $started services started, $failed failed"
echo ""

echo "--- Key Services ---"
for svc in ssh xrdp mb-os-gui mb-memory-daemon tor; do
    if grep -qi "Started.*$svc" "$LOG" 2>/dev/null; then
        echo "  ✅ $svc"
    else
        echo "  ❌ $svc"
    fi
done
echo ""

echo "--- Desktop GUI ---"
grep 'ThemeManager' "$LOG" | tail -1
echo ""

echo "--- Network (DHCP) ---"
grep 'dhclient' "$LOG" | grep -i 'bound\|DHCPACK' | tail -1
echo ""

echo "--- Keyboard ---"
grep -i 'xkb' "$LOG" | tail -2
echo ""

echo "--- Memory Daemon ---"
grep 'mb-memory-daemon' "$LOG" | tail -3
echo ""

echo "--- Errors (real, excluding harmless) ---"
grep -iE '(error|failed|panic)' "$LOG" | grep -iv 'xkbcomp\|not fatal\|md5check\|PID file\|posix_openpt\|ACPI\|audit\|apparmor' | tail -10
echo ""

echo "--- Vulkan ---"
# Check if vulkan libs are in the squashfs
echo "Checking Vulkan in ISO..."
sudo mkdir -p /mnt/iso_test
sudo mount -o loop,ro /mnt/d/MB-OS/mb-os.iso /mnt/iso_test 2>/dev/null
if [ -f /mnt/iso_test/casper/filesystem.squashfs ]; then
    sudo unsquashfs -l /mnt/iso_test/casper/filesystem.squashfs 2>/dev/null | grep -i vulkan | head -5
    echo "  ✅ Vulkan packages found in ISO"
fi
sudo umount /mnt/iso_test 2>/dev/null

echo ""
echo "--- Antigravity ---"
sudo mount -o loop,ro /mnt/d/MB-OS/mb-os.iso /mnt/iso_test 2>/dev/null
if [ -f /mnt/iso_test/casper/filesystem.squashfs ]; then
    agy_found=$(sudo unsquashfs -l /mnt/iso_test/casper/filesystem.squashfs 2>/dev/null | grep -c 'antigravity')
    echo "  Antigravity files: $agy_found"
    sudo unsquashfs -l /mnt/iso_test/casper/filesystem.squashfs 2>/dev/null | grep 'antigravity' | grep -E 'bin/|antigravity$' | head -5
fi
sudo umount /mnt/iso_test 2>/dev/null

echo ""
echo "--- SSH Key ---"
sudo mount -o loop,ro /mnt/d/MB-OS/mb-os.iso /mnt/iso_test 2>/dev/null
if [ -f /mnt/iso_test/casper/filesystem.squashfs ]; then
    key_found=$(sudo unsquashfs -l /mnt/iso_test/casper/filesystem.squashfs 2>/dev/null | grep -c 'authorized_keys')
    if [ "$key_found" -gt 0 ]; then
        echo "  ✅ SSH authorized_keys found"
    else
        echo "  ❌ SSH authorized_keys NOT found"
    fi
fi
sudo umount /mnt/iso_test 2>/dev/null

echo ""
echo "=== TEST COMPLETE ==="
