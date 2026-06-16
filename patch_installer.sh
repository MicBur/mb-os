#!/bin/bash
set -e
rm -rf /var/iso-patch
mkdir -p /var/iso-patch/mnt /var/iso-patch/iso

echo ">>> Mount ISO..."
sudo mount -o loop /mnt/d/MB-OS/mb-os.iso /var/iso-patch/mnt
sudo cp -a /var/iso-patch/mnt/* /var/iso-patch/iso/
sudo umount /var/iso-patch/mnt

echo ">>> Entpacke squashfs..."
sudo unsquashfs -f -d /var/iso-patch/sqfs /var/iso-patch/iso/casper/filesystem.squashfs

echo ">>> Fixe launch-installer..."
sudo tee /var/iso-patch/sqfs/usr/local/bin/launch-installer > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
export TERM=xterm-256color
if [ -x /usr/local/bin/mb-installer ]; then
    xterm -fa Monospace -fs 11 -bg '#0a0c16' -fg '#d1d5db' -T 'MB-OS Installer' -maximized -e sudo /usr/local/bin/mb-installer
else
    xterm -e bash -c 'echo Installer nicht gefunden!; read'
fi
EOF
sudo chmod +x /var/iso-patch/sqfs/usr/local/bin/launch-installer

echo ">>> Repack squashfs..."
sudo rm -f /var/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs /var/iso-patch/sqfs /var/iso-patch/iso/casper/filesystem.squashfs -noappend
sudo rm -rf /var/iso-patch/sqfs

echo ">>> Build ISO..."
sudo grub-mkrescue -o /mnt/d/MB-OS/mb-os.iso /var/iso-patch/iso/
sudo rm -rf /var/iso-patch
ls -lh /mnt/d/MB-OS/mb-os.iso
echo "=== PATCH DONE ==="
