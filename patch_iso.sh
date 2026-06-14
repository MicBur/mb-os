#!/bin/bash
# Patche die bestehende ISO - xinitrc + .profile Fix
set -e

echo ">>> ISO patchen (xinitrc + .profile)..."
ISO="/mnt/d/MB-OS/mb-os-v5.iso"
OUTISO="/mnt/d/MB-OS/mb-os-v6.iso"

rm -rf /tmp/iso-patch
mkdir -p /tmp/iso-patch/mnt /tmp/iso-patch/sqfs /tmp/iso-patch/iso

# 1. ISO inhalt kopieren
sudo mount -o loop "$ISO" /tmp/iso-patch/mnt
cp -a /tmp/iso-patch/mnt/* /tmp/iso-patch/iso/
sudo umount /tmp/iso-patch/mnt

# 2. Squashfs entpacken
echo ">>> Entpacke squashfs..."
sudo unsquashfs -f -d /tmp/iso-patch/sqfs /tmp/iso-patch/iso/casper/filesystem.squashfs

# 3. xinitrc mit Fallback kopieren
echo ">>> Kopiere gefixte xinitrc..."
sudo cp /mnt/d/MB-OS/config/mb-os-xinitrc /tmp/iso-patch/sqfs/etc/mb-os/mb-os-xinitrc
sudo chmod +x /tmp/iso-patch/sqfs/etc/mb-os/mb-os-xinitrc

# 4. .profile fix (bereits korrekt in v5, aber sicherstellen)
sudo mkdir -p /tmp/iso-patch/sqfs/home/mbuser
sudo tee /tmp/iso-patch/sqfs/home/mbuser/.profile > /dev/null << 'PROFILE'
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
sudo chown 1000:1000 /tmp/iso-patch/sqfs/home/mbuser/.profile

# 5. Verify
echo ">>> Verifikation:"
echo "--- xinitrc (letzte 5 Zeilen) ---"
tail -5 /tmp/iso-patch/sqfs/etc/mb-os/mb-os-xinitrc
echo "--- .profile ---"
cat /tmp/iso-patch/sqfs/home/mbuser/.profile

# 6. Squashfs neu packen
echo ">>> Squashfs neu packen..."
rm -f /tmp/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs /tmp/iso-patch/sqfs /tmp/iso-patch/iso/casper/filesystem.squashfs -noappend

# 7. Rootfs loeschen fuer Platz
rm -rf /tmp/iso-patch/sqfs

# 8. ISO neu bauen
echo ">>> ISO bauen..."
sudo grub-mkrescue -o "$OUTISO" /tmp/iso-patch/iso/

ls -lh "$OUTISO"
echo "=== PATCH v6 FERTIG ==="
