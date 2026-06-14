#!/bin/bash
set -e
echo "=== MB-OS GRUB Reparatur (Final) ==="

# Cleanup and mount
umount /mnt/sys/firmware/efi/efivars 2>/dev/null || true
umount /mnt/sys 2>/dev/null || true
umount /mnt/proc 2>/dev/null || true
umount /mnt/dev 2>/dev/null || true
umount /mnt/boot/efi 2>/dev/null || true
umount /mnt 2>/dev/null || true

mount /dev/sda3 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

ROOT_UUID=$(blkid -s UUID -o value /dev/sda3)
echo "Root UUID: $ROOT_UUID"

# 1. Write FULL grub.cfg to /boot/grub/
mkdir -p /mnt/boot/grub
cat > /mnt/boot/grub/grub.cfg << GRUBCFG
set default=0
set timeout=5
set menu_color_normal=cyan/black
set menu_color_highlight=white/blue

menuentry "MB-OS - Starten" {
    linux /boot/vmlinuz-6.8.0-124-generic root=UUID=${ROOT_UUID} ro quiet splash
    initrd /boot/initrd.img-6.8.0-124-generic
}

menuentry "MB-OS - Recovery" {
    linux /boot/vmlinuz-6.8.0-124-generic root=UUID=${ROOT_UUID} ro single
    initrd /boot/initrd.img-6.8.0-124-generic
}
GRUBCFG

# 2. Write redirect grub.cfg into EFI/MB-OS/ that points to /boot/grub/
cat > /mnt/boot/efi/EFI/MB-OS/grub.cfg << EFICFG
search.fs_uuid ${ROOT_UUID} root
set prefix=(\$root)'/boot/grub'
configfile \$prefix/grub.cfg
EFICFG

# 3. ALSO write redirect into EFI/BOOT/ for fallback
mkdir -p /mnt/boot/efi/EFI/BOOT
cp /mnt/boot/efi/EFI/MB-OS/grubx64.efi /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI
cp /mnt/boot/efi/EFI/MB-OS/grub.cfg /mnt/boot/efi/EFI/BOOT/grub.cfg

echo ""
echo "=== /boot/grub/grub.cfg ==="
cat /mnt/boot/grub/grub.cfg
echo ""
echo "=== EFI/MB-OS/grub.cfg ==="
cat /mnt/boot/efi/EFI/MB-OS/grub.cfg
echo ""
echo "=== EFI/BOOT/ ==="
ls -la /mnt/boot/efi/EFI/BOOT/

# fstab
cat > /mnt/etc/fstab << FSTAB
UUID=${ROOT_UUID}  /         ext4  errors=remount-ro  0 1
UUID=$(blkid -s UUID -o value /dev/sda1)  /boot/efi  vfat  umask=0077  0 1
UUID=$(blkid -s UUID -o value /dev/sda2)  none       swap  sw          0 0
FSTAB

echo ""
echo "=== /etc/fstab ==="
cat /mnt/etc/fstab

umount /mnt/boot/efi
umount /mnt

echo ""
echo "=== GRUB REPARATUR FERTIG! ==="
