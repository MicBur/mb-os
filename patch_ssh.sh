#!/bin/bash
# Patch laufende ISO: SSH-Key hinzufügen + PasswordAuth aktivieren
set -e

ISO="/mnt/d/MB-OS/mb-os.iso"
OUTISO="/mnt/d/MB-OS/mb-os-v9.iso"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoSIm6BfLUNinWvtQHljyckGno+hn47vFIyUTpI33E2 nutzer@LAPTOP-RBU7SDCN"

rm -rf /tmp/iso-patch
mkdir -p /tmp/iso-patch/mnt

echo ">>> Mount ISO..."
sudo mount -o loop "$ISO" /tmp/iso-patch/mnt

echo ">>> Entpacke squashfs..."
sudo unsquashfs -f -d /tmp/iso-patch/sqfs /tmp/iso-patch/mnt/casper/filesystem.squashfs

echo ">>> SSH-Key patchen..."
sudo mkdir -p /tmp/iso-patch/sqfs/home/mbuser/.ssh
echo "$PUBKEY" | sudo tee -a /tmp/iso-patch/sqfs/home/mbuser/.ssh/authorized_keys > /dev/null
sudo chmod 700 /tmp/iso-patch/sqfs/home/mbuser/.ssh
sudo chmod 600 /tmp/iso-patch/sqfs/home/mbuser/.ssh/authorized_keys
sudo chown -R 1000:1000 /tmp/iso-patch/sqfs/home/mbuser/.ssh

echo ">>> SSH PasswordAuth aktivieren..."
sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /tmp/iso-patch/sqfs/etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /tmp/iso-patch/sqfs/etc/ssh/sshd_config

echo ">>> Diagnose: Apps checken..."
echo "--- installed mb-* apps ---"
ls -la /tmp/iso-patch/sqfs/usr/local/bin/mb-* 2>/dev/null
ls -la /tmp/iso-patch/sqfs/usr/local/bin/launch-* 2>/dev/null
ls -la /tmp/iso-patch/sqfs/usr/local/bin/agy* 2>/dev/null
ls -la /tmp/iso-patch/sqfs/usr/local/bin/antigravity* 2>/dev/null
echo "--- launch-antigravity ---"
cat /tmp/iso-patch/sqfs/usr/local/bin/launch-antigravity 2>/dev/null || echo "MISSING"

echo ">>> Repacke squashfs..."
sudo cp -a /tmp/iso-patch/mnt/* /tmp/iso-patch/iso/ 2>/dev/null || mkdir -p /tmp/iso-patch/iso && sudo cp -a /tmp/iso-patch/mnt/* /tmp/iso-patch/iso/
sudo umount /tmp/iso-patch/mnt
rm -f /tmp/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs /tmp/iso-patch/sqfs /tmp/iso-patch/iso/casper/filesystem.squashfs -noappend

echo ">>> ISO bauen..."
sudo rm -rf /tmp/iso-patch/sqfs
sudo grub-mkrescue -o "$OUTISO" /tmp/iso-patch/iso/

ls -lh "$OUTISO"
echo "=== SSH PATCH DONE ==="
