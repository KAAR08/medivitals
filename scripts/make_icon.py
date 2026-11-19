"""Draws the app icon: a white heart with an ECG pulse line, on brand teal.

    python scripts/make_icon.py        # writes assets/icon/*.png
    dart run flutter_launcher_icons    # generates every platform's icons

Drawn at 4x and downscaled for smooth edges. Two variants:
- icon.png: full square (iOS masks the corners itself; web; Windows)
- icon_foreground.png: transparent, artwork inside Android's adaptive-icon
  safe zone (the inner 66%), on the background colour set in pubspec.yaml.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "icon"
SIZE = 1024
SS = 4  # supersampling factor

TEAL_DARK = (16, 72, 88)
TEAL = (26, 95, 115)  # AppPalette.brand #1A5F73
TEAL_LIGHT = (42, 143, 166)  # AppPalette.brandMid
WHITE = (255, 255, 255)


def heart_points(cx: float, cy: float, scale: float, steps: int = 720) -> list[tuple[float, float]]:
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts


def ecg_points(cx: float, cy: float, width: float, height: float) -> list[tuple[float, float]]:
    """Flat, small bump, sharp spike up, deep dip, back to flat."""
    shape = [
        (-0.50, 0.00),
        (-0.22, 0.00),
        (-0.15, -0.10),
        (-0.08, 0.00),
        (-0.03, 0.00),
        (0.02, -0.62),
        (0.09, 0.42),
        (0.15, 0.00),
        (0.22, 0.00),
        (0.28, -0.14),
        (0.34, 0.00),
        (0.50, 0.00),
    ]
    return [(cx + x * width, cy + y * height) for x, y in shape]


def draw_artwork(img: Image.Image, cx: float, cy: float, unit: float) -> None:
    heart = heart_points(cx, cy + unit * 0.02, unit * 0.0205)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(heart, fill=255)

    # The pulse line, cut out of the heart (clipped to it).
    line_layer = Image.new("L", img.size, 0)
    line = ecg_points(cx, cy + unit * 0.02, unit * 0.82, unit * 0.30)
    ImageDraw.Draw(line_layer).line(line, fill=255, width=int(unit * 0.05), joint="curve")
    line_in_heart = Image.composite(line_layer, Image.new("L", img.size, 0), mask)

    white = Image.new(img.mode, img.size, WHITE if img.mode == "RGB" else (*WHITE, 255))
    img.paste(white, (0, 0), mask)
    colour = Image.new(img.mode, img.size, TEAL if img.mode == "RGB" else (*TEAL, 255))
    img.paste(colour, (0, 0), line_in_heart)


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)  # top-left light -> bottom-right dark
            a, b = (TEAL_LIGHT, TEAL) if t < 0.5 else (TEAL, TEAL_DARK)
            u = t * 2 if t < 0.5 else (t - 0.5) * 2
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    big = SIZE * SS

    full = gradient(256).resize((big, big), Image.BICUBIC)
    draw_artwork(full, big / 2, big / 2, big * 0.80)
    full.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon.png")

    fg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw_artwork(fg, big / 2, big / 2, big * 0.56)  # within the 66% safe zone
    fg.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / "icon_foreground.png")
    print(f"Wrote {OUT.relative_to(ROOT)}/icon.png and icon_foreground.png")


if __name__ == "__main__":
    main()
