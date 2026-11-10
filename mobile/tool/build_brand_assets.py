#!/usr/bin/env python3
"""Export identical logo artwork to website and Android icon sizes (Pillow)."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
source = Image.open(root / 'design/logo-source.png').convert('RGBA')

def resized(size):
    return source.resize((size, size), Image.Resampling.LANCZOS)

resized(512).save(root / 'logo.png', optimize=True)
resized(32).save(root / 'favicon-32.png', optimize=True)
resized(180).save(root / 'apple-touch-icon.png', optimize=True)
source.save(root / 'favicon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
res = root / 'mobile/android/app/src/main/res'
for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    target = res / ('mipmap-' + density)
    target.mkdir(parents=True, exist_ok=True)
    resized(round(48 * scale)).save(target / 'ic_launcher.png', optimize=True)
    target = res / ('drawable-' + density)
    target.mkdir(parents=True, exist_ok=True)
    foreground = Image.new('RGBA', (round(108 * scale),) * 2)
    portrait = resized(round(66 * scale))
    at = (foreground.width - portrait.width) // 2
    foreground.alpha_composite(portrait, (at, at))
    foreground.save(target / 'ic_quartiers_foreground.png', optimize=True)
print('Website and Android icons exported from the same logo source.')
