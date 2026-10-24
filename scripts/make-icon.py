#!/usr/bin/env python3
"""Draw the Gamut Pro app icon (1024 × 1024 PNG) and store it as the
versioned base64 source that build-assets.py turns into AppIcon.icns.

The design: a machined tuning knob inside a glowing spectrum ring, on a
graphite tile that follows the macOS icon grid (an 824 pt rounded square
centred on the 1024 canvas, with a soft shadow).

Needs Pillow and NumPy. Usage: python3 scripts/make-icon.py [preview.png]
"""
from pathlib import Path
import base64, io, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048            # draw at 2× and downsample for clean edges
K = S / 1024        # scale from the 1024 design grid
CX, CY = 512, 512   # dial centre


def px(v):
    return int(round(v * K))


def blank():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def grid():
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    return xs / K, ys / K


XS, YS = grid()
DIST = np.hypot(XS - CX, YS - CY)
ANGLE = np.arctan2(YS - CY, XS - CX)   # radians, 0 = 3 o'clock, clockwise (y down)


def rgba(rgb, alpha):
    rgb = np.clip(rgb, 0, 255)
    return Image.fromarray(np.dstack([rgb, np.clip(alpha, 0, 255)]).astype(np.uint8), "RGBA")


def hsv_to_rgb(h, s, v):
    h6 = (h % 1.0) * 6
    i = np.floor(h6).astype(int) % 6
    f = h6 - np.floor(h6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1) * 255


def smooth_band(d, inner, outer, soft=1.2):
    """1 inside [inner, outer], antialiased edges (in design units)."""
    return np.clip((d - inner) / soft + 0.5, 0, 1) * np.clip((outer - d) / soft + 0.5, 0, 1)


def build():
    canvas = blank()
    body = (100, 100, 924, 924)
    radius = 185

    # Tile shadow.
    shadow = blank()
    ImageDraw.Draw(shadow).rounded_rectangle([px(c) for c in (112, 132, 912, 944)], radius=px(radius), fill=(0, 0, 0, 120))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px(20))))

    # Graphite tile: vertical gradient, darker towards the bottom.
    tile_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle([px(c) for c in body], radius=px(radius), fill=255)
    t = np.clip((YS - 100) / 824, 0, 1)[..., None]
    tile_rgb = np.array([44, 48, 62]) * (1 - t) + np.array([10, 11, 16]) * t
    tile = rgba(tile_rgb, np.array(tile_mask))
    canvas.alpha_composite(tile)

    # Spectrum: hue runs clockwise from red at the top.
    hue = ((ANGLE + math.pi / 2) / (2 * math.pi)) % 1.0
    spectrum = hsv_to_rgb(hue, np.full_like(hue, 0.82), np.ones_like(hue))

    # Soft glow behind the ring, kept inside the tile.
    glow_alpha = smooth_band(DIST, 250, 330, soft=1.0) * 255
    glow = rgba(spectrum, glow_alpha).filter(ImageFilter.GaussianBlur(px(34)))
    glow_a = np.minimum(np.array(glow.getchannel("A")) * 0.75, np.array(tile_mask))
    glow.putalpha(Image.fromarray(glow_a.astype(np.uint8)))
    canvas.alpha_composite(glow)

    # The ring, with a subtle inner shade so it reads as a groove of light.
    ring_alpha = smooth_band(DIST, 262, 322) * 255
    shade = 1 - 0.18 * np.clip(1 - np.abs(DIST - 292) / 30, 0, 1) ** 0
    ring_rgb = spectrum * (0.88 + 0.12 * np.clip((DIST - 262) / 60, 0, 1))[..., None]
    canvas.alpha_composite(rgba(ring_rgb, ring_alpha))

    # Tick marks between the ring and the knob.
    ticks = blank()
    draw = ImageDraw.Draw(ticks)
    for k in range(36):
        a = math.radians(k * 10 - 90)
        r1, r2 = (236, 252) if k % 3 == 0 else (242, 250)
        width = 5 if k % 3 == 0 else 3
        draw.line([px(CX + r1 * math.cos(a)), px(CY + r1 * math.sin(a)),
                   px(CX + r2 * math.cos(a)), px(CY + r2 * math.sin(a))],
                  fill=(255, 255, 255, 120 if k % 3 == 0 else 60), width=px(width))
    canvas.alpha_composite(ticks)

    # Knob shadow.
    knob_shadow = blank()
    ImageDraw.Draw(knob_shadow).ellipse([px(v) for v in (CX - 210, CY - 186, CX + 210, CY + 240)], fill=(0, 0, 0, 170))
    canvas.alpha_composite(knob_shadow.filter(ImageFilter.GaussianBlur(px(22))))

    # Knob rim: metal lit from the top left, with fine knurling.
    rim_alpha = smooth_band(DIST, 0, 214) * 255
    light = np.cos(ANGLE - math.radians(-135))                       # +1 facing the light
    knurl = 0.5 + 0.5 * np.cos(ANGLE * 120)
    rim_level = 150 + 60 * light + 14 * knurl * smooth_band(DIST, 188, 214, soft=1.0)
    canvas.alpha_composite(rgba(np.repeat(rim_level[..., None], 3, -1) * np.array([1.0, 1.01, 1.05]), rim_alpha))

    # Knob face: brushed, slightly concave.
    face_alpha = smooth_band(DIST, 0, 184) * 255
    brushed = 4 * np.sin(DIST * 1.7) * np.clip(DIST / 184, 0, 1)
    face_level = 192 - 26 * light * np.clip(DIST / 184, 0, 1) + brushed - 18 * (DIST / 184) ** 2
    canvas.alpha_composite(rgba(np.repeat(face_level[..., None], 3, -1) * np.array([1.0, 1.01, 1.05]), face_alpha))

    # Thin highlight on the rim edge.
    edge = blank()
    ImageDraw.Draw(edge).arc([px(v) for v in (CX - 212, CY - 212, CX + 212, CY + 212)], start=190, end=300,
                             fill=(255, 255, 255, 150), width=px(4))
    canvas.alpha_composite(edge.filter(ImageFilter.GaussianBlur(px(1.5))))

    # Indicator: a short bar pointing to about one o'clock.
    a = math.radians(-58)
    ind = blank()
    d = ImageDraw.Draw(ind)
    x1, y1 = CX + 108 * math.cos(a), CY + 108 * math.sin(a)
    x2, y2 = CX + 160 * math.cos(a), CY + 160 * math.sin(a)
    d.line([px(x1), px(y1), px(x2), px(y2)], fill=(28, 32, 44, 255), width=px(24))
    for (x, y) in ((x1, y1), (x2, y2)):
        d.ellipse([px(x - 12), px(y - 12), px(x + 12), px(y + 12)], fill=(28, 32, 44, 255))
    canvas.alpha_composite(ind)

    # Tile sheen and hairline edge.
    sheen = blank()
    ImageDraw.Draw(sheen).ellipse([px(v) for v in (60, -440, 964, 400)], fill=(255, 255, 255, 16))
    sheen_a = np.minimum(np.array(sheen.getchannel("A")), np.array(tile_mask))
    sheen.putalpha(Image.fromarray(sheen_a.astype(np.uint8)))
    canvas.alpha_composite(sheen)
    hairline = blank()
    ImageDraw.Draw(hairline).rounded_rectangle([px(c) for c in body], radius=px(radius), outline=(255, 255, 255, 36), width=px(3))
    canvas.alpha_composite(hairline)

    return canvas.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    icon = build()
    root = Path(__file__).resolve().parents[1]
    buffer = io.BytesIO()
    icon.save(buffer, "PNG", optimize=True)
    (root / "DisplayTuner/Resources/AppIcon.base64").write_text(base64.encodebytes(buffer.getvalue()).decode())
    (root / "docs").mkdir(exist_ok=True)
    icon.resize((256, 256), Image.LANCZOS).save(root / "docs/icon.png", optimize=True)
    if len(sys.argv) > 1:
        icon.save(sys.argv[1])
    print(f"Icon written ({len(buffer.getvalue()) // 1024} KB PNG)")
