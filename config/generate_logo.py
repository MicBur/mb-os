from PIL import Image, ImageDraw, ImageFont
import os

def generate_logo():
    print("Generating custom MB-OS boot logos...")
    text = "MB-OS"
    
    # 1. Create watermark.png (248 x 87, transparent RGBA)
    img = Image.new("RGBA", (248, 87), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Search for clean system fonts in Linux
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
    ]
    font = None
    for path in font_paths:
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, 36)
                print(f"Loaded font: {path}")
                break
            except Exception:
                pass
                
    if not font:
        font = ImageFont.load_default()
        print("Using fallback default font")

    # Measure text size to center it
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
    except AttributeError:
        # Fallback for older Pillow versions
        text_width, text_height = draw.textsize(text, font=font)

    x = (248 - text_width) // 2
    y = (87 - text_height) // 2 - 5

    # Draw soft drop shadow
    draw.text((x + 2, y + 2), text, font=font, fill=(0, 0, 0, 120))
    # Draw text in clean white
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))
    
    img.save("config/watermark.png", "PNG")
    print("Saved config/watermark.png")

    # 2. Create bgrt-fallback.png (128 x 128, transparent RGBA)
    img_fb = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw_fb = ImageDraw.Draw(img_fb)

    font_fb = None
    for path in font_paths:
        if os.path.exists(path):
            try:
                font_fb = ImageFont.truetype(path, 24)
                break
            except Exception:
                pass
                
    if not font_fb:
        font_fb = ImageFont.load_default()

    try:
        bbox_fb = draw_fb.textbbox((0, 0), text, font=font_fb)
        tw_fb = bbox_fb[2] - bbox_fb[0]
        th_fb = bbox_fb[3] - bbox_fb[1]
    except AttributeError:
        tw_fb, th_fb = draw_fb.textsize(text, font=font_fb)

    xfb = (128 - tw_fb) // 2
    yfb = (128 - th_fb) // 2

    draw_fb.text((xfb + 1, yfb + 1), text, font=font_fb, fill=(0, 0, 0, 120))
    draw_fb.text((xfb, yfb), text, font=font_fb, fill=(255, 255, 255, 255))
    
    # Save as 8-bit indexed PNG (P mode) adaptive to match original bgrt-fallback format
    img_fb.convert("P", palette=Image.Palette.ADAPTIVE).save("config/bgrt-fallback.png", "PNG")
    print("Saved config/bgrt-fallback.png")

if __name__ == "__main__":
    generate_logo()
