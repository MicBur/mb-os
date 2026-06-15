#!/bin/bash
# Download + install Antigravity Desktop App
set -e

echo ">>> Suche Antigravity Desktop App..."

# Try known download URLs
BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
for manifest in desktop/linux_amd64.json desktop-app/linux_amd64.json app/linux-x64.json; do
    echo -n "  $manifest: "
    result=$(curl -fsSL "$BASE/manifests/$manifest" 2>/dev/null) && echo "$result" | head -1 || echo "not found"
done

# Try direct storage URL patterns
echo ""
echo ">>> Suche Storage URLs..."
for pattern in \
    "https://storage.googleapis.com/antigravity-public/antigravity-desktop/latest/linux-x64/Antigravity.tar.gz" \
    "https://storage.googleapis.com/antigravity-public/desktop/latest/linux-x64/Antigravity.tar.gz" \
    "https://storage.googleapis.com/antigravity-public/antigravity/latest/linux-x64/antigravity-linux-x64.tar.gz" \
    "https://dl.antigravity.google/linux/x64/Antigravity.tar.gz" \
    "https://antigravity.google/api/download/desktop/linux-x64" \
    ; do
    echo -n "  $pattern: "
    code=$(curl -o /dev/null -s -w "%{http_code}" -L "$pattern" 2>/dev/null)
    echo "$code"
    if [ "$code" = "200" ]; then
        echo ">>> FOUND! Downloading..."
        cd /opt/antigravity
        curl -fsSL -o Antigravity.tar.gz "$pattern"
        ls -lh Antigravity.tar.gz
        tar xzf Antigravity.tar.gz
        rm -f Antigravity.tar.gz
        # Find binary
        AGBIN=$(find /opt/antigravity -maxdepth 3 -type f \( -name "antigravity" -o -name "Antigravity" \) ! -name "*.tar.gz" 2>/dev/null | head -1)
        if [ -n "$AGBIN" ]; then
            chmod +x "$AGBIN"
            sudo ln -sf "$AGBIN" /usr/local/bin/antigravity-desktop
            echo ">>> Antigravity Desktop installiert: $AGBIN"
        else
            echo ">>> Dateien:"
            ls -la /opt/antigravity/
        fi
        exit 0
    fi
done

echo ">>> Desktop App Download nicht gefunden. Check https://antigravity.google/download manuell."
