#!/bin/bash
# =====================================================================
# MB-OS Quick Calamares ISO Patcher
# =====================================================================
# This script performs a rapid patch of the existing mb-os.iso
# to inject the updated Calamares settings, shellprocess module,
# and the new fix-efi-boot.sh script. This avoids a full 15-minute rebuild.
# =====================================================================

set -e

ISO_IN="/mnt/d/MB-OS/mb-os.iso"
ISO_OUT="/mnt/d/MB-OS/mb-os.iso"
PATCH_DIR="/var/iso-patch"

echo ">>> Starting rapid ISO patch process..."
echo "Source ISO: $ISO_IN"
echo "Target ISO: $ISO_OUT"
echo "Staging directory: $PATCH_DIR"

# 1. Clean staging directory
sudo rm -rf "$PATCH_DIR"
mkdir -p "$PATCH_DIR/mnt" "$PATCH_DIR/iso"

# 2. Mount and copy ISO contents
echo ">>> Mounting and copying ISO contents..."
sudo mount -o loop "$ISO_IN" "$PATCH_DIR/mnt"
cp -a "$PATCH_DIR/mnt"/. "$PATCH_DIR/iso/"
sudo umount "$PATCH_DIR/mnt"

# 3. Unpack SquashFS
echo ">>> Unpacking SquashFS..."
sudo unsquashfs -d "$PATCH_DIR/sqfs" "$PATCH_DIR/iso/casper/filesystem.squashfs"

# 4. Inject updated Calamares and Boot Fix files
echo ">>> Injecting configurations and scripts..."

# Ensure target directories exist inside SquashFS
sudo mkdir -p "$PATCH_DIR/sqfs/etc/calamares/modules"
sudo mkdir -p "$PATCH_DIR/sqfs/usr/local/bin"

# Copy files from repository
sudo cp -v "/mnt/d/MB-OS/calamares/settings.conf" "$PATCH_DIR/sqfs/etc/calamares/settings.conf"
sudo cp -v "/mnt/d/MB-OS/calamares/modules/shellprocess.conf" "$PATCH_DIR/sqfs/etc/calamares/modules/shellprocess.conf"
sudo cp -v "/mnt/d/MB-OS/config/fix-efi-boot.sh" "$PATCH_DIR/sqfs/usr/local/bin/fix-efi-boot.sh"

# Ensure correct permissions
sudo chmod +x "$PATCH_DIR/sqfs/usr/local/bin/fix-efi-boot.sh"

# 4b. Install GRUB EFI packages into squashfs via chroot
echo ">>> Installing grub-efi-amd64 + efibootmgr into squashfs..."
sudo cp /etc/resolv.conf "$PATCH_DIR/sqfs/etc/resolv.conf" 2>/dev/null || echo "nameserver 8.8.8.8" | sudo tee "$PATCH_DIR/sqfs/etc/resolv.conf" > /dev/null
sudo mount --bind /proc "$PATCH_DIR/sqfs/proc"
sudo mount --bind /sys "$PATCH_DIR/sqfs/sys"
sudo mount --bind /dev "$PATCH_DIR/sqfs/dev"
sudo chroot "$PATCH_DIR/sqfs" apt-get update -qq 2>&1 | tail -3
sudo chroot "$PATCH_DIR/sqfs" apt-get install -y --no-install-recommends grub-efi-amd64 grub-efi-amd64-bin efibootmgr 2>&1 | tail -10
sudo chroot "$PATCH_DIR/sqfs" apt-get clean
sudo umount -lf "$PATCH_DIR/sqfs/proc" 2>/dev/null || true
sudo umount -lf "$PATCH_DIR/sqfs/sys" 2>/dev/null || true
sudo umount -lf "$PATCH_DIR/sqfs/dev" 2>/dev/null || true
echo ">>> GRUB EFI packages installed into squashfs"

# 5. Repack SquashFS
echo ">>> Repacking SquashFS..."
sudo rm -f "$PATCH_DIR/iso/casper/filesystem.squashfs"
sudo mksquashfs "$PATCH_DIR/sqfs" "$PATCH_DIR/iso/casper/filesystem.squashfs" -noappend

# Clean SquashFS folder to free up disk space
sudo rm -rf "$PATCH_DIR/sqfs"

# 6. Rebuild bootable ISO
echo ">>> Generating patched bootable ISO..."
TEMP_ISO="/tmp/mb-os-patched.iso"
sudo grub-mkrescue -o "$TEMP_ISO" "$PATCH_DIR/iso"

# Copy back to target destination
sudo cp -f "$TEMP_ISO" "$ISO_OUT"
rm -f "$TEMP_ISO"

# Clean up remaining folders
sudo rm -rf "$PATCH_DIR"

echo ">>> Rapid ISO patch process completed successfully!"
ls -lh "$ISO_OUT"
