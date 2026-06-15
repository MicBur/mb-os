#!/bin/bash
# Alle fehlenden App-Launcher in die ISO patchen
set -e

SQFS="/tmp/iso-patch/sqfs"

# Warte bis squashfs entpackt ist
if [ ! -d "$SQFS/usr/local/bin" ]; then
    echo "ERROR: Squashfs nicht entpackt!"
    exit 1
fi

echo ">>> Installiere fehlende Launcher-Scripts..."

# 1. launch-antigravity
cat > "$SQFS/usr/local/bin/launch-antigravity" << 'EOF'
#!/bin/bash
export DISPLAY=:0
if [ -x /usr/local/bin/antigravity-desktop ]; then
    /usr/local/bin/antigravity-desktop --no-sandbox &
elif [ -x /usr/local/bin/agy ]; then
    xterm -bg black -fg white -fs 12 -e /usr/local/bin/agy &
else
    firefox --new-window "https://gemini.google.com" &
fi
EOF
chmod +x "$SQFS/usr/local/bin/launch-antigravity"
echo "  ✓ launch-antigravity"

# 2. launch-installer
cat > "$SQFS/usr/local/bin/launch-installer" << 'EOF'
#!/bin/bash
export DISPLAY=:0
if [ -x /usr/local/bin/mb-installer ]; then
    sudo /usr/local/bin/mb-installer
else
    echo "Installer nicht gefunden!"
    read
fi
EOF
chmod +x "$SQFS/usr/local/bin/launch-installer"
echo "  ✓ launch-installer"

# 3. launch-android (Waydroid)
cat > "$SQFS/usr/local/bin/launch-android" << 'EOF'
#!/bin/bash
export DISPLAY=:0
if command -v waydroid &>/dev/null; then
    waydroid show-full-ui &
else
    xterm -bg black -fg yellow -fs 12 -e bash -c '
        echo "=== Android (Waydroid) Setup ==="
        echo "Waydroid ist noch nicht installiert."
        echo ""
        echo "Installieren? (dauert ~5 Min)"
        read -p "[j/n] " yn
        if [ "$yn" = "j" ]; then
            sudo apt-get update && sudo apt-get install -y waydroid
            sudo waydroid init -s GAPPS
            echo "Fertig! Starte Android neu über den App Drawer."
        fi
        read
    ' &
fi
EOF
chmod +x "$SQFS/usr/local/bin/launch-android"
echo "  ✓ launch-android"

# 4. mb-lock (Bildschirmsperre)
cat > "$SQFS/usr/local/bin/mb-lock" << 'EOF'
#!/bin/bash
i3lock -c 0a0c16 -e
EOF
chmod +x "$SQFS/usr/local/bin/mb-lock"
echo "  ✓ mb-lock"

# 5. mb-screenshot
cat > "$SQFS/usr/local/bin/mb-screenshot" << 'EOF'
#!/bin/bash
DEST="/home/mbuser/Screenshots"
mkdir -p "$DEST"
FILE="$DEST/screenshot_$(date +%Y%m%d_%H%M%S).png"
scrot "$FILE"
feh "$FILE" &
echo "Screenshot: $FILE"
EOF
chmod +x "$SQFS/usr/local/bin/mb-screenshot"
echo "  ✓ mb-screenshot"

# 6. mb-update
cat > "$SQFS/usr/local/bin/mb-update" << 'EOF'
#!/bin/bash
echo "=== MB-OS System Update ==="
echo ""
apt-get update
apt-get upgrade -y
apt-get autoremove -y
echo ""
echo "✅ Update abgeschlossen!"
read -p "Enter zum Schließen..."
EOF
chmod +x "$SQFS/usr/local/bin/mb-update"
echo "  ✓ mb-update"

# 7. mb-browser fix (falls es nicht richtig funktioniert)
cat > "$SQFS/usr/local/bin/mb-browser" << 'EOF'
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
chmod +x "$SQFS/usr/local/bin/mb-browser"
echo "  ✓ mb-browser (firefox wrapper)"

echo ">>> Alle Launcher installiert!"
ls -la "$SQFS/usr/local/bin/launch-"* "$SQFS/usr/local/bin/mb-"*
