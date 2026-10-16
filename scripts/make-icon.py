#!/usr/bin/env python3
"""Draw the Display Tuner app icon (1024 × 1024 PNG) and store it as the
versioned base64 source that build-assets.py turns into AppIcon.icns.

The artwork follows the macOS icon grid: an 824 pt rounded square centred on
a 1024 canvas, with a soft shadow. Inside, a display whose screen shows an
RGB colour-gamut triangle and its white point, the idea the app is built on.

Usage: python3 scripts/make-icon.py [preview.png]
"""
from pathlib import Path
import base64, io, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048            # draw at 2× and downsample for clean edges
K = S / 1024        # scale from the 1024 design grid


def px(v):
    return int(round(v * K))


def rounded_mask(box, radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([px(c) for c in box], radius=px(radius), fill=255)
    return mask


def vertical_gradient(top, bottom):
    t = np.linspace(0, 1, S)[:, None, None]
    rgb = (np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t)
    rgb = np.repeat(rgb, S, axis=1)
    return Image.fromarray(np.dstack([rgb, np.full((S, S, 1), 255)]).astype(np.uint8), "RGBA")


def gamut_triangle(vertices):
    """RGB triangle with colours blended across it (barycentric)."""
    (x1, y1), (x2, y2), (x3, y3) = [(px(x), px(y)) for x, y in vertices]
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    a = ((y2 - y3) * (xs - x3) + (x3 - x2) * (ys - y3)) / det
    b = ((y3 - y1) * (xs - x3) + (x1 - x3) * (ys - y3)) / det
    c = 1 - a - b
    inside = (a >= 0) & (b >= 0) & (c >= 0)
    red, green, blue = np.array([255, 59, 72]), np.array([52, 232, 120]), np.array([64, 110, 255])
    rgb = a[..., None] * red + b[..., None] * green + c[..., None] * blue
    # Push towards full saturation like a chromaticity diagram, lighter at the centre.
    rgb = rgb / np.maximum(rgb.max(axis=2, keepdims=True), 1) * 255
    centre = np.clip(1 - 3 * np.minimum(np.minimum(a, b), c), 0, 1)[..., None]
    rgb = rgb * (0.55 + 0.45 * centre) + 255 * (1 - (0.55 + 0.45 * centre)) * 0.35
    alpha = np.where(inside, 255, 0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8), "RGBA")


def build():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body = (100, 100, 924, 924)
    radius = 185

    # Shadow under the tile.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([px(c) for c in (110, 128, 914, 940)], radius=px(radius), fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(18))))

    # Graphite tile with a faint top sheen and a hairline edge.
    tile = vertical_gradient((48, 53, 66), (14, 16, 23))
    mask = rounded_mask(body, radius)
    canvas.paste(tile, (0, 0), mask)
    sheen = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    ImageDraw.Draw(sheen).ellipse([px(c) for c in (40, -380, 984, 430)], fill=(255, 255, 255, 22))
    sheen.putalpha(Image.fromarray(np.minimum(np.array(sheen.getchannel("A")), np.array(mask))))
    canvas.alpha_composite(sheen)
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([px(c) for c in body], radius=px(radius), outline=(255, 255, 255, 34), width=px(3))
    canvas.alpha_composite(edge)

    # Display: bezel, screen, stand.
    draw = ImageDraw.Draw(canvas)
    stand_neck = (468, 676, 556, 752)
    draw.rounded_rectangle([px(c) for c in stand_neck], radius=px(10), fill=(150, 156, 170, 255))
    draw.rounded_rectangle([px(c) for c in (372, 742, 652, 772)], radius=px(15), fill=(178, 184, 198, 255))
    bezel = (196, 244, 828, 690)
    draw.rounded_rectangle([px(c) for c in bezel], radius=px(34), fill=(196, 202, 214, 255))
    screen = (214, 262, 810, 672)
    draw.rounded_rectangle([px(c) for c in screen], radius=px(20), fill=(10, 12, 18, 255))

    # Gamut triangle with a glow, clipped to the screen.
    vertices = [(618, 610), (452, 300), (300, 612)]   # red, green, blue
    tri = gamut_triangle(vertices)
    glow = tri.filter(ImageFilter.GaussianBlur(px(38)))
    glow.putalpha(glow.getchannel("A").point(lambda a: int(a * 0.85)))
    screen_mask = rounded_mask(screen, 20)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.alpha_composite(glow)
    layer.alpha_composite(tri)
    layer.putalpha(Image.fromarray(np.minimum(np.array(layer.getchannel("A")), np.array(screen_mask))))
    canvas.alpha_composite(layer)

    # Triangle outline and the white point.
    outline = ImageDraw.Draw(canvas)
    outline.line([px(v) for p in vertices + [vertices[0]] for v in p], fill=(255, 255, 255, 150), width=px(4), joint="curve")
    wx, wy = 458, 512
    outline.ellipse([px(wx - 15), px(wy - 15), px(wx + 15), px(wy + 15)], fill=(255, 255, 255, 255))

    # A small "tuning" slider along the bottom of the screen.
    outline.rounded_rectangle([px(c) for c in (668, 300, 680, 630)], radius=px(6), fill=(255, 255, 255, 46))
    outline.rounded_rectangle([px(c) for c in (668, 420, 680, 630)], radius=px(6), fill=(255, 255, 255, 120))
    outline.ellipse([px(c) for c in (650, 398, 698, 446)], fill=(245, 247, 250, 255))
    outline.rounded_rectangle([px(c) for c in (728, 300, 740, 630)], radius=px(6), fill=(255, 255, 255, 46))
    outline.rounded_rectangle([px(c) for c in (728, 520, 740, 630)], radius=px(6), fill=(255, 255, 255, 120))
    outline.ellipse([px(c) for c in (710, 498, 758, 546)], fill=(245, 247, 250, 255))

    return canvas.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    icon = build()
    root = Path(__file__).resolve().parents[1]
    buffer = io.BytesIO()
    icon.save(buffer, "PNG", optimize=True)
    encoded = base64.encodebytes(buffer.getvalue()).decode()
    (root / "DisplayTuner/Resources/AppIcon.base64").write_text(encoded)
    if len(sys.argv) > 1:
        icon.save(sys.argv[1])
    print(f"Icon written ({len(buffer.getvalue()) // 1024} KB PNG)")
