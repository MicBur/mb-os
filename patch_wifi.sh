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

SQFS="/var/iso-patch/sqfs"

# === FIX 1: launch-installer mit xterm ===
echo ">>> Fix launch-installer..."
sudo tee "$SQFS/usr/local/bin/launch-installer" > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
export TERM=xterm-256color
if [ -x /usr/local/bin/mb-installer ]; then
    xterm -fa Monospace -fs 11 -bg '#0a0c16' -fg '#d1d5db' -T 'MB-OS Installer' -maximized -e sudo /usr/local/bin/mb-installer
else
    xterm -e bash -c 'echo Installer nicht gefunden!; read'
fi
EOF
sudo chmod +x "$SQFS/usr/local/bin/launch-installer"

# === FIX 2: WiFi Auto-Connect "iPhone von mic" ===
echo ">>> WiFi Auto-Connect konfigurieren..."
sudo mkdir -p "$SQFS/etc/NetworkManager/system-connections"
sudo tee "$SQFS/etc/NetworkManager/system-connections/iPhone-von-mic.nmconnection" > /dev/null << 'WIFI'
[connection]
id=iPhone von mic
type=wifi
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=iPhone von mic

[wifi-security]
key-mgmt=wpa-psk
psk=00070008

[ipv4]
method=auto

[ipv6]
method=auto
WIFI
sudo chmod 600 "$SQFS/etc/NetworkManager/system-connections/iPhone-von-mic.nmconnection"

# === FIX 3: NetworkManager auto-start sichern ===
sudo tee "$SQFS/etc/NetworkManager/conf.d/10-manage-all.conf" > /dev/null << 'NM'
[device]
wifi.scan-rand-mac-address=no

[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true
NM

# === FIX 4: SSH auto-start sichern ===
sudo mkdir -p "$SQFS/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /lib/systemd/system/ssh.service "$SQFS/etc/systemd/system/multi-user.target.wants/ssh.service" 2>/dev/null || true
sudo ln -sf /lib/systemd/system/NetworkManager.service "$SQFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service" 2>/dev/null || true

echo ">>> Repack squashfs..."
sudo rm -f /var/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs "$SQFS" /var/iso-patch/iso/casper/filesystem.squashfs -noappend
sudo rm -rf "$SQFS"

echo ">>> Build ISO..."
sudo grub-mkrescue -o /mnt/d/MB-OS/mb-os.iso /var/iso-patch/iso/
sudo rm -rf /var/iso-patch
ls -lh /mnt/d/MB-OS/mb-os.iso
echo "=== PATCH DONE: Installer + WiFi + SSH ==="
