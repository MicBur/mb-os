#!/bin/bash
# Full patch: SSH-Key + alle Launchers
set -e

ISO="/mnt/d/MB-OS/mb-os.iso"
OUTISO="/mnt/d/MB-OS/mb-os-v9.iso"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPoSIm6BfLUNinWvtQHljyckGno+hn47vFIyUTpI33E2 nutzer@LAPTOP-RBU7SDCN"

rm -rf /var/iso-patch
mkdir -p /var/iso-patch/mnt /var/iso-patch/iso

echo ">>> Mount ISO..."
sudo mount -o loop "$ISO" /var/iso-patch/mnt
sudo cp -a /var/iso-patch/mnt/* /var/iso-patch/iso/
sudo umount /var/iso-patch/mnt

echo ">>> Entpacke squashfs..."
sudo unsquashfs -f -d /var/iso-patch/sqfs /var/iso-patch/iso/casper/filesystem.squashfs

SQFS="/var/iso-patch/sqfs"

# === SSH FIX ===
echo ">>> SSH-Key patchen..."
sudo mkdir -p "$SQFS/home/mbuser/.ssh"
echo "$PUBKEY" | sudo tee "$SQFS/home/mbuser/.ssh/authorized_keys" > /dev/null
sudo chmod 700 "$SQFS/home/mbuser/.ssh"
sudo chmod 600 "$SQFS/home/mbuser/.ssh/authorized_keys"
sudo chown -R 1000:1000 "$SQFS/home/mbuser/.ssh"
sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' "$SQFS/etc/ssh/sshd_config"
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SQFS/etc/ssh/sshd_config"
echo "  ✓ SSH"

# === LAUNCHER SCRIPTS ===
echo ">>> Launcher-Scripts installieren..."

sudo tee "$SQFS/usr/local/bin/launch-antigravity" > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
firefox --new-window "https://gemini.google.com" &
EOF

sudo tee "$SQFS/usr/local/bin/launch-installer" > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
if [ -x /usr/local/bin/mb-installer ]; then
    sudo /usr/local/bin/mb-installer
else
    echo "Installer nicht gefunden!"; read
fi
EOF

sudo tee "$SQFS/usr/local/bin/launch-android" > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
if command -v waydroid &>/dev/null; then
    waydroid show-full-ui &
else
    xterm -bg black -fg yellow -fs 12 -e bash -c '
echo "=== Android (Waydroid) Setup ==="
echo "Waydroid ist noch nicht installiert."
read -p "Installieren? [j/n] " yn
if [ "$yn" = "j" ]; then
    sudo apt-get update && sudo apt-get install -y waydroid
    sudo waydroid init -s GAPPS
    echo "Fertig! Starte Android neu."
fi
read' &
fi
EOF

sudo tee "$SQFS/usr/local/bin/mb-lock" > /dev/null << 'EOF'
#!/bin/bash
i3lock -c 0a0c16 -e
EOF

sudo tee "$SQFS/usr/local/bin/mb-screenshot" > /dev/null << 'EOF'
#!/bin/bash
DEST="/home/mbuser/Screenshots"
mkdir -p "$DEST"
FILE="$DEST/screenshot_$(date +%Y%m%d_%H%M%S).png"
scrot "$FILE"
feh "$FILE" &
EOF

sudo tee "$SQFS/usr/local/bin/mb-update" > /dev/null << 'EOF'
#!/bin/bash
echo "=== MB-OS System Update ==="
apt-get update
apt-get upgrade -y
apt-get autoremove -y
echo "Update abgeschlossen!"
read -p "Enter zum Schliessen..."
EOF

sudo tee "$SQFS/usr/local/bin/mb-browser" > /dev/null << 'EOF'
#!/bin/bash
export DISPLAY=:0
if echo "$@" | grep -q "\-\-url"; then
    URL=$(echo "$@" | sed 's/.*--url //')
    firefox --new-window "$URL" &
elif [ -n "$1" ]; then
    firefox --new-window "$1" &
else
    firefox &
fi
EOF

sudo chmod +x "$SQFS/usr/local/bin/launch-antigravity"
sudo chmod +x "$SQFS/usr/local/bin/launch-installer"
sudo chmod +x "$SQFS/usr/local/bin/launch-android"
sudo chmod +x "$SQFS/usr/local/bin/mb-lock"
sudo chmod +x "$SQFS/usr/local/bin/mb-screenshot"
sudo chmod +x "$SQFS/usr/local/bin/mb-update"
sudo chmod +x "$SQFS/usr/local/bin/mb-browser"

echo "  ✓ 7 Launcher installiert"
ls "$SQFS/usr/local/bin/launch-"* "$SQFS/usr/local/bin/mb-"*

# === REPACK ===
echo ">>> mksquashfs..."
rm -f /var/iso-patch/iso/casper/filesystem.squashfs
sudo mksquashfs "$SQFS" /var/iso-patch/iso/casper/filesystem.squashfs -noappend

echo ">>> Cleanup squashfs..."
sudo rm -rf "$SQFS"

echo ">>> grub-mkrescue..."
sudo grub-mkrescue -o "$OUTISO" /var/iso-patch/iso/

sudo rm -rf /var/iso-patch

ls -lh "$OUTISO"
echo "=== FULL PATCH DONE ==="
