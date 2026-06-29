#!/usr/bin/env python3
"""Generate QuotaPulse app and menu bar icons.

The mark is intentionally simple: a Q-shaped quota ring with a pulse line.
It avoids app-name text so the same identity scales down to status bar size.
"""

from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
APPICON_DIR = ROOT / "Sources/App/Resources/Assets.xcassets/AppIcon.appiconset"
MENUBAR_DIR = ROOT / "Sources/App/Resources/Assets.xcassets/MenuBarIcon.imageset"
LEGACY_MENUBAR = ROOT / "Sources/App/Resources/MenuBarIconWhite.png"
ICNS_PATH = ROOT / "Sources/App/Resources/AppIcon.icns"

APP_ICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def rounded_gradient_background(size: int, scale: int) -> Image.Image:
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    radius = int(size * scale * 0.22)
    rect = [0, 0, size * scale - 1, size * scale - 1]

    gradient = Image.new("RGBA", canvas.size)
    gpx = gradient.load()
    for y in range(gradient.height):
        for x in range(gradient.width):
            tx = x / max(1, gradient.width - 1)
            ty = y / max(1, gradient.height - 1)
            t = min(1.0, max(0.0, (tx * 0.45 + ty * 0.75)))
            r = lerp(20, 8, t)
            g = lerp(35, 15, t)
            b = lerp(43, 27, t)
            gpx[x, y] = (r, g, b, 255)

    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
    canvas.alpha_composite(Image.composite(gradient, Image.new("RGBA", canvas.size), mask))

    inset = int(size * scale * 0.035)
    draw.rounded_rectangle(
        [inset, inset, size * scale - inset - 1, size * scale - inset - 1],
        radius=max(1, radius - inset),
        outline=(255, 255, 255, 28),
        width=max(1, int(size * scale * 0.012)),
    )
    return canvas


def draw_q_pulse_mark(
    image: Image.Image,
    box: tuple[int, int, int, int],
    *,
    ring_color: tuple[int, int, int, int],
    pulse_color: tuple[int, int, int, int],
    scale: int,
    simplified: bool = False,
) -> None:
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = box
    width = right - left
    stroke = max(2 * scale, int(width * (0.14 if simplified else 0.125)))

    if not simplified:
        glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        glow_draw.arc(box, start=130, end=398, fill=(39, 214, 209, 78), width=int(stroke * 1.35))
        glow = glow.filter(ImageFilter.GaussianBlur(max(1, int(width * 0.025))))
        image.alpha_composite(glow)

    draw.arc(box, start=130, end=398, fill=ring_color, width=stroke)

    cx = (left + right) / 2
    cy = (top + bottom) / 2
    radius = width / 2
    angle = math.radians(42)
    tail_start = (
        int(cx + math.cos(angle) * radius * 0.58),
        int(cy + math.sin(angle) * radius * 0.58),
    )
    tail_end = (
        int(cx + math.cos(angle) * radius * 0.92),
        int(cy + math.sin(angle) * radius * 0.92),
    )
    draw.line([tail_start, tail_end], fill=ring_color, width=stroke, joint="curve")

    pulse_width = max(1 * scale, int(stroke * 0.34))
    if simplified:
        points = [
            (left + int(width * 0.32), int(cy)),
            (left + int(width * 0.48), int(cy)),
            (left + int(width * 0.57), int(cy - width * 0.12)),
            (left + int(width * 0.68), int(cy)),
        ]
    else:
        points = [
            (left + int(width * 0.25), int(cy)),
            (left + int(width * 0.39), int(cy)),
            (left + int(width * 0.47), int(cy - width * 0.12)),
            (left + int(width * 0.56), int(cy + width * 0.12)),
            (left + int(width * 0.65), int(cy - width * 0.04)),
            (left + int(width * 0.78), int(cy - width * 0.04)),
        ]
    draw.line(points, fill=pulse_color, width=pulse_width, joint="curve")
    dot_r = max(1 * scale, int(pulse_width * 0.9))
    dot_x, dot_y = points[-1]
    draw.ellipse(
        [dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r],
        fill=pulse_color,
    )


def app_icon(size: int) -> Image.Image:
    scale = 4 if size < 128 else 3
    image = rounded_gradient_background(size, scale)
    margin = int(size * scale * (0.18 if size < 64 else 0.16))
    box = (margin, margin, size * scale - margin, size * scale - margin)
    draw_q_pulse_mark(
        image,
        box,
        ring_color=(236, 249, 255, 255),
        pulse_color=(52, 226, 205, 255),
        scale=scale,
        simplified=size <= 32,
    )
    return image.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def menu_bar_icon(size: int = 128, color: tuple[int, int, int, int] = (0, 0, 0, 255)) -> Image.Image:
    scale = 4
    image = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    margin = int(size * scale * 0.11)
    draw_q_pulse_mark(
        image,
        (margin, margin, size * scale - margin, size * scale - margin),
        ring_color=color,
        pulse_color=color,
        scale=scale,
        simplified=True,
    )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def write_app_icons() -> None:
    for size in APP_ICON_SIZES:
        app_icon(size).save(APPICON_DIR / f"icon_{size}x{size}.png")


def write_menu_bar_icons() -> None:
    black = menu_bar_icon(color=(0, 0, 0, 255))
    white = menu_bar_icon(color=(255, 255, 255, 255))
    black.save(MENUBAR_DIR / "menubar-light.png")
    black.save(MENUBAR_DIR / "menubar-dark.png")
    white.resize((64, 64), Image.Resampling.LANCZOS).save(LEGACY_MENUBAR)


def write_icns() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        mapping = {
            "icon_16x16.png": 16,
            "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32,
            "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128,
            "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256,
            "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512,
            "icon_512x512@2x.png": 1024,
        }
        for filename, size in mapping.items():
            shutil.copyfile(APPICON_DIR / f"icon_{size}x{size}.png", iconset / filename)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS_PATH)], check=True)


def main() -> None:
    write_app_icons()
    write_menu_bar_icons()
    write_icns()
    print("Generated QuotaPulse app icon, menu bar icon, and icns assets.")


if __name__ == "__main__":
    main()
