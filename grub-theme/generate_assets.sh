#!/bin/bash
cd /mnt/d/MB-OS/grub-theme

# Create selection highlight images (9-slice PNG)
python3 << 'PYEOF'
from PIL import Image, ImageDraw
# Center piece
img = Image.new('RGBA', (8, 8), (32, 194, 248, 40))
img.save('select_c.png')

# Corners
for name in ['select_nw', 'select_ne', 'select_sw', 'select_se']:
    img = Image.new('RGBA', (4, 4), (32, 194, 248, 60))
    img.save(name + '.png')

# Top/Bottom edges
for name in ['select_n', 'select_s']:
    img = Image.new('RGBA', (8, 2), (32, 194, 248, 80))
    img.save(name + '.png')

# Left/Right edges
for name in ['select_e', 'select_w']:
    img = Image.new('RGBA', (2, 8), (32, 194, 248, 80))
    img.save(name + '.png')

print('Selection images created!')
PYEOF

# Generate GRUB fonts
grub-mkfont -s 36 -o dejavu_36.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf 2>/dev/null
grub-mkfont -s 16 -o dejavu_16.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null
grub-mkfont -s 16 -o dejavu_bold_16.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf 2>/dev/null
grub-mkfont -s 14 -o dejavu_14.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null
grub-mkfont -s 12 -o dejavu_12.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null
grub-mkfont -s 11 -o dejavu_11.pf2 /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null

echo 'Fonts generated!'
ls -la *.pf2 *.png 2>/dev/null
