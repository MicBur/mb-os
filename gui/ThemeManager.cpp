#include "ThemeManager.h"
#include <QImage>
#include <QColor>
#include <QDebug>

ThemeManager::ThemeManager(QObject *parent) : QObject(parent) {
    loadTheme();
}

void ThemeManager::loadTheme() {
    qDebug() << "ThemeManager: Loading wallpaper for color extraction...";
    
    // Default fallback values (Cyan/Purple theme)
    m_accentColor = "#00f0ff";
    m_secondaryColor = "#bd00ff";
    m_glassBgColor = "#8c07080f";
    m_glassBorderColor = "#2dffffff";
    m_glowColor = "#2000f0ff";
    m_glowColor2 = "#18bd00ff";

    QImage img(":/assets/wallpaper.png");
    if (img.isNull()) {
        // Fallback if not compiled in resources yet
        img.load("assets/wallpaper.png");
    }

    if (img.isNull()) {
        qWarning() << "ThemeManager: Failed to load wallpaper.png, using default theme.";
        emit themeChanged();
        return;
    }

    // Subsample the image to extract dominant hues
    // Use HSL space to filter out grayscale, black, and white pixels
    int hueBuckets[12] = {0};
    int totalVibrantPixels = 0;

    int width = img.width();
    int height = img.height();
    int sampleStep = 20; // Sample every 20th pixel in X and Y

    for (int y = 0; y < height; y += sampleStep) {
        for (int x = 0; x < width; x += sampleStep) {
            QColor color = img.pixelColor(x, y);
            int h, s, l, a;
            color.getHsl(&h, &s, &l, &a);

            // Filter for vibrant colors:
            // Saturation must be reasonable (e.g. > 45/255)
            // Lightness must not be too dark (e.g. > 30/255) and not too light (e.g. < 220/255)
            if (s > 45 && l > 30 && l < 220) {
                if (h >= 0 && h < 360) {
                    int bucket = h / 30; // 0 to 11
                    if (bucket >= 0 && bucket < 12) {
                        hueBuckets[bucket]++;
                        totalVibrantPixels++;
                    }
                }
            }
        }
    }

    int dominantHue = 270; // Default to purple if no vibrant colors found
    int maxCount = 0;
    
    for (int i = 0; i < 12; ++i) {
        if (hueBuckets[i] > maxCount) {
            maxCount = hueBuckets[i];
            dominantHue = i * 30 + 15; // Center of the bucket
        }
    }

    qDebug() << "ThemeManager: Extracted dominant hue:" << dominantHue << "with count:" << maxCount;

    // Construct palette colors based on dominant hue
    // Accent: vibrant dominant color
    QColor accent = QColor::fromHsl(dominantHue, 240, 140); // vibrant mid lightness
    m_accentColor = accent.name();

    // Secondary Accent: complimentary or triad color (Dominant + 120 or + 180 degrees)
    QColor secondary = QColor::fromHsl((dominantHue + 120) % 360, 240, 140);
    m_secondaryColor = secondary.name();

    // Dark glass background: tinted with dominant hue (very low saturation, low lightness)
    QColor glassBg = QColor::fromHsl(dominantHue, 40, 18);
    // Alpha transparency around 55% (140 out of 255) -> 8c in hex
    m_glassBgColor = QString("#8c%1%2%3")
        .arg(glassBg.red(), 2, 16, QChar('0'))
        .arg(glassBg.green(), 2, 16, QChar('0'))
        .arg(glassBg.blue(), 2, 16, QChar('0'));

    // Glass border: slightly brighter tint of dominant hue, low saturation
    QColor glassBorder = QColor::fromHsl(dominantHue, 80, 80);
    // Alpha transparency around 18% (45 out of 255) -> 2d in hex
    m_glassBorderColor = QString("#2d%1%2%3")
        .arg(glassBorder.red(), 2, 16, QChar('0'))
        .arg(glassBorder.green(), 2, 16, QChar('0'))
        .arg(glassBorder.blue(), 2, 16, QChar('0'));

    // Glows: bright saturated accents with low opacity (alpha 0x20 and 0x18)
    QColor glow1 = QColor::fromHsl(dominantHue, 255, 128);
    m_glowColor = QString("#20%1%2%3")
        .arg(glow1.red(), 2, 16, QChar('0'))
        .arg(glow1.green(), 2, 16, QChar('0'))
        .arg(glow1.blue(), 2, 16, QChar('0'));

    QColor glow2 = QColor::fromHsl((dominantHue + 120) % 360, 255, 128);
    m_glowColor2 = QString("#18%1%2%3")
        .arg(glow2.red(), 2, 16, QChar('0'))
        .arg(glow2.green(), 2, 16, QChar('0'))
        .arg(glow2.blue(), 2, 16, QChar('0'));

    qDebug() << "ThemeManager: Accent:" << m_accentColor 
             << "Secondary:" << m_secondaryColor 
             << "GlassBg:" << m_glassBgColor 
             << "GlassBorder:" << m_glassBorderColor;

    emit themeChanged();
}
