#!/bin/bash
cd /mnt/d/MB-OS/grub-theme

echo "=== Current format ==="
file background.png

# Convert JPEG to real PNG (1024x768 for GRUB)
python3 << 'PYEOF'
from PIL import Image
img = Image.open('background.png')
img = img.resize((1024, 768))
img.save('background_fixed.png', 'PNG')
print('Converted to real PNG! Size:', img.size)
PYEOF

mv background_fixed.png background.png

echo "=== New format ==="
file background.png
ls -la background.png
