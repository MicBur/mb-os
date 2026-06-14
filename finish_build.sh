#!/bin/bash
set -e

ROOTFS=/tmp/mb-os-build/rootfs
ISO_DIR=/tmp/mb-os-build/iso

echo ">>> Configs schreiben..."

# casper.conf
sudo tee "$ROOTFS/etc/casper.conf" > /dev/null << 'CASPERCONF'
export USERNAME="mbuser"
export USERFULLNAME="MB-OS User"
export HOST="MB-OS"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="MB-OS"
CASPERCONF

# autologin
sudo mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
sudo tee "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" > /dev/null << 'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin mbuser --noclear %I $TERM
AUTOLOGIN

# .profile
sudo mkdir -p "$ROOTFS/home/mbuser"
sudo tee "$ROOTFS/home/mbuser/.profile" > /dev/null << 'PROFILE'
# Starte GUI automatisch auf tty1 (mit Loop-Schutz)
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ ! -f /tmp/.mb-gui-started ]; then
    touch /tmp/.mb-gui-started
    echo ">>> MB-OS GUI startet..." > /tmp/mb-gui.log 2>&1
    sudo /usr/bin/xinit /etc/mb-os/mb-os-xinitrc -- :0 vt1 -keeptty >> /tmp/mb-gui.log 2>&1
    echo ">>> xinit beendet mit Code: $?" >> /tmp/mb-gui.log 2>&1
    echo ""
    echo "  GUI konnte nicht gestartet werden."
    echo "  Log: cat /tmp/mb-gui.log"
    echo "  Neustart: rm /tmp/.mb-gui-started && startx"
    echo ""
fi
PROFILE
sudo chown -R 1000:1000 "$ROOTFS/home/mbuser" 2>/dev/null || true

echo ">>> xinitrc kopieren..."
sudo cp /mnt/d/MB-OS/config/mb-os-xinitrc "$ROOTFS/etc/mb-os/mb-os-xinitrc"
sudo chmod +x "$ROOTFS/etc/mb-os/mb-os-xinitrc"

echo ">>> ldd check..."
sudo chroot "$ROOTFS" ldd /usr/local/bin/mb-os-shell 2>&1 | grep -i 'not found' || echo "Alle deps OK!"

echo ">>> mksquashfs..."
sudo mksquashfs "$ROOTFS" "$ISO_DIR/casper/filesystem.squashfs" -noappend

echo ">>> grub-mkrescue..."
sudo grub-mkrescue -o /mnt/d/MB-OS/mb-os-v8.iso "$ISO_DIR/"

ls -lh /mnt/d/MB-OS/mb-os-v8.iso
echo "=== BUILD v8 COMPLETE ==="
