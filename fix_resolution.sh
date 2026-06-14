#!/bin/bash
# Quick-Fix: Nur GRUB-Config in der ISO aendern (kein Komplett-Rebuild!)
set -e

cd /tmp
mkdir -p iso_fix

# GRUB config erstellen OHNE nomodeset
cat > iso_fix/grub.cfg << 'GRUBEOF'
set default=0
set timeout=3

set menu_color_normal=light-blue/black
set menu_color_highlight=light-cyan/blue

set gfxmode=1280x1024x32
set gfxpayload=keep
load_video
terminal_output gfxterm

menuentry "MB-OS (Custom Qt 6 Linux Environment)" {
    linux /casper/vmlinuz boot=casper hostname=MB-OS video=hyperv_fb:1280x1024 console=tty1 console=ttyS0 systemd.journald.forward_to_console=1 ---
    initrd /casper/initrd.img
}
GRUBEOF

# ISO kopieren und GRUB ersetzen
cp /mnt/d/MB-OS/mb-os.iso iso_fix/mb-os-fixed.iso
xorriso -indev iso_fix/mb-os-fixed.iso -outdev iso_fix/mb-os-fixed.iso \
    -boot_image any keep \
    -update iso_fix/grub.cfg /boot/grub/grub.cfg -- 2>&1 || true

cp iso_fix/mb-os-fixed.iso /mnt/d/MB-OS/mb-os.iso
rm -rf iso_fix
echo "DONE - nomodeset entfernt, Aufloesung 1280x1024!"
