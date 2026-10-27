#!/usr/bin/env python3
"""Generates the camo patterns and stickers shipped with the CamoAndStickers mod.

Every camo is seamlessly tileable (built from periodic noise), so the mod can
tile it across a weapon's UVs. Stickers are RGBA with a transparent background.

Usage: python3 tools/generate_textures.py [--size 1024] [--out CamoAndStickers]
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


# ---------------------------------------------------------------- noise utils

def periodic_noise(size, cells, rng, octaves=4):
    """Tileable value noise in [0, 1]: bicubic-upsampled random grids that wrap."""
    out = np.zeros((size, size), dtype=np.float64)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = cells * (2 ** o)
        grid = rng.random((n, n))
        # Tile 3x3 so the resample wraps cleanly, then crop the center.
        big = np.tile(grid, (3, 3))
        img = Image.fromarray((big * 255).astype(np.uint8), "L")
        img = img.resize((size * 3, size * 3), Image.BICUBIC)
        layer = np.asarray(img, dtype=np.float64)[size:2 * size, size:2 * size] / 255.0
        out += layer * amp
        total += amp
        amp *= 0.5
    out /= total
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def layered_camo(size, rng, palette, cells, octaves, thresholds):
    """Classic blob camo: each palette color above the base is a thresholded noise field."""
    rgb = np.zeros((size, size, 3), dtype=np.uint8)
    rgb[:] = palette[0]
    for color, thr in zip(palette[1:], thresholds):
        mask = periodic_noise(size, cells, rng, octaves) > thr
        rgb[mask] = color
    return Image.fromarray(rgb, "RGB")


def pixelate(img, block):
    small = img.resize((img.width // block, img.height // block), Image.NEAREST)
    return small.resize(img.size, Image.NEAREST)


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- camo

def camo_woodland(size, rng):
    pal = [hex2rgb(c) for c in ("#6b6b47", "#3f4a2a", "#5a3d26", "#1e1e1a")]
    return layered_camo(size, rng, pal, 4, 4, (0.55, 0.6, 0.68))


def camo_desert(size, rng):
    pal = [hex2rgb(c) for c in ("#c8b38a", "#a68b62", "#8a6d4a", "#e0d2b0")]
    return layered_camo(size, rng, pal, 3, 3, (0.5, 0.62, 0.7))


def camo_snow(size, rng):
    pal = [hex2rgb(c) for c in ("#e8ebee", "#b9c0c6", "#7f8890", "#3c4248")]
    return layered_camo(size, rng, pal, 4, 4, (0.55, 0.66, 0.76))


def camo_urban(size, rng):
    pal = [hex2rgb(c) for c in ("#8e9196", "#5c6066", "#2f3236", "#c4c6c8")]
    return layered_camo(size, rng, pal, 5, 3, (0.5, 0.6, 0.7))


def camo_digital_forest(size, rng):
    pal = [hex2rgb(c) for c in ("#6f7a52", "#47522f", "#2d3020", "#8c7a58")]
    return pixelate(layered_camo(size, rng, pal, 6, 4, (0.52, 0.6, 0.66)), max(4, size // 128))


def camo_digital_desert(size, rng):
    pal = [hex2rgb(c) for c in ("#cdbb92", "#a99470", "#7d6a4e", "#e2d6b9")]
    return pixelate(layered_camo(size, rng, pal, 6, 4, (0.52, 0.6, 0.68)), max(4, size // 128))


def camo_tiger(size, rng):
    """Vertical-ish brush stripes, wrapped in both axes."""
    base = np.zeros((size, size, 3), dtype=np.uint8)
    base[:] = hex2rgb("#6e7552")
    n = periodic_noise(size, 3, rng, 3)
    x = np.linspace(0, 1, size, endpoint=False)[None, :]
    stripes = np.sin((x * 9 + n * 1.6) * 2 * math.pi)
    stripes2 = np.sin((x * 9 + n * 1.6 + 0.18) * 2 * math.pi)
    base[stripes > 0.55] = hex2rgb("#3c4027")
    base[stripes2 > 0.85] = hex2rgb("#1c1d16")
    return Image.fromarray(base, "RGB")


def camo_flora(size, rng):
    """Soviet 'Berezka'-style leaf speckle on a light base, a nod to the Zone."""
    base = np.zeros((size, size, 3), dtype=np.uint8)
    base[:] = hex2rgb("#8f9468")
    big = periodic_noise(size, 3, rng, 3) > 0.58
    base[big] = hex2rgb("#5f6b3c")
    speck = periodic_noise(size, 24, rng, 2) > 0.7
    base[speck & ~big] = hex2rgb("#c8c39a")
    base[speck & big] = hex2rgb("#3e4527")
    return Image.fromarray(base, "RGB")


def camo_hunter_red(size, rng):
    pal = [hex2rgb(c) for c in ("#7a2a20", "#4a1a14", "#1c1412", "#a5523a")]
    return layered_camo(size, rng, pal, 4, 3, (0.55, 0.65, 0.72))


def camo_anomaly(size, rng):
    """A glowy, unnatural pattern — paint made from what you find out there."""
    n1 = periodic_noise(size, 2, rng, 5)
    n2 = periodic_noise(size, 5, rng, 3)
    r = (0.15 + 0.35 * n1) * 255
    g = (0.25 + 0.6 * (n1 * n2) ** 0.7) * 255
    b = (0.35 + 0.55 * n2) * 255
    ring = np.abs(np.sin(n1 * 14 * math.pi)) < 0.12
    rgb = np.stack([r, g, b], -1)
    rgb[ring] = (40, 255, 220)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def camo_carbon(size, rng):
    """Carbon-fibre weave (procedural, exactly periodic)."""
    cells = 32
    c = size // cells
    y, x = np.mgrid[0:size, 0:size]
    cx, cy = (x // c) % 2, (y // c) % 2
    u, v = (x % c) / c, (y % c) / c
    along = np.where(cx == cy, u, v)
    shade = 0.35 + 0.65 * np.sin(along * math.pi) ** 2
    across = np.where(cx == cy, v, u)
    shade *= 0.8 + 0.2 * np.sin(across * math.pi * 6) ** 2
    g = (18 + shade * 50).astype(np.uint8)
    return Image.fromarray(np.stack([g, g, (g * 1.08).clip(0, 255).astype(np.uint8)], -1), "RGB")


def camo_gold(size, rng):
    n = periodic_noise(size, 8, rng, 4)
    r = 170 + n * 70
    g = 130 + n * 60
    b = 40 + n * 40
    return Image.fromarray(np.stack([r, g, b], -1).clip(0, 255).astype(np.uint8), "RGB")


CAMOS = {
    "01_Woodland": camo_woodland,
    "02_Desert": camo_desert,
    "03_Snow": camo_snow,
    "04_Urban": camo_urban,
    "05_DigitalForest": camo_digital_forest,
    "06_DigitalDesert": camo_digital_desert,
    "07_Tiger": camo_tiger,
    "08_Flora": camo_flora,
    "09_HunterRed": camo_hunter_red,
    "10_Anomaly": camo_anomaly,
    "11_Carbon": camo_carbon,
    "12_Gold": camo_gold,
}


# ---------------------------------------------------------------- stickers

def _font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _canvas(s):
    return Image.new("RGBA", (s, s), (0, 0, 0, 0))


def _outline(img, width, color=(20, 20, 20, 255)):
    """Adds a die-cut sticker border around the opaque area."""
    a = img.getchannel("A").filter(ImageFilter.MaxFilter(width * 2 + 1))
    border = Image.new("RGBA", img.size, color)
    border.putalpha(a)
    border.alpha_composite(img)
    return border


def sticker_radiation(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    c, r = s / 2, s * 0.46
    d.ellipse([c - r, c - r, c + r, c + r], fill=(250, 205, 30, 255))
    for k in range(3):
        a0 = -90 + k * 120 - 30
        d.pieslice([c - r * 0.85, c - r * 0.85, c + r * 0.85, c + r * 0.85], a0, a0 + 60, fill=(20, 20, 20, 255))
    d.ellipse([c - r * 0.27, c - r * 0.27, c + r * 0.27, c + r * 0.27], fill=(250, 205, 30, 255))
    d.ellipse([c - r * 0.18, c - r * 0.18, c + r * 0.18, c + r * 0.18], fill=(20, 20, 20, 255))
    return _outline(img, s // 64)


def sticker_biohazard(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    c, r = s / 2, s * 0.46
    d.regular_polygon((c, c + s * 0.03, r), 3, fill=(250, 205, 30, 255), outline=(20, 20, 20, 255), width=s // 40)
    for k in range(3):
        ang = math.radians(-90 + k * 120)
        ox, oy = c + math.cos(ang) * r * 0.25, c + s * 0.06 + math.sin(ang) * r * 0.25
        rr = r * 0.22
        d.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], outline=(20, 20, 20, 255), width=s // 36)
    d.ellipse([c - r * 0.1, c + s * 0.06 - r * 0.1, c + r * 0.1, c + s * 0.06 + r * 0.1], fill=(20, 20, 20, 255))
    return img


def sticker_star(s, color=(200, 30, 30, 255)):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    c, R, r = s / 2, s * 0.46, s * 0.19
    pts = []
    for k in range(10):
        rad = R if k % 2 == 0 else r
        a = math.radians(-90 + k * 36)
        pts.append((c + math.cos(a) * rad, c + s * 0.03 + math.sin(a) * rad))
    d.polygon(pts, fill=color)
    return _outline(img, s // 48, (240, 240, 240, 255))


def sticker_skull(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    w = (235, 230, 215, 255)
    k = (20, 20, 20, 255)
    d.ellipse([s * 0.18, s * 0.1, s * 0.82, s * 0.68], fill=w)
    d.rounded_rectangle([s * 0.32, s * 0.55, s * 0.68, s * 0.82], radius=s * 0.05, fill=w)
    d.ellipse([s * 0.28, s * 0.33, s * 0.46, s * 0.52], fill=k)
    d.ellipse([s * 0.54, s * 0.33, s * 0.72, s * 0.52], fill=k)
    d.polygon([(s * 0.5, s * 0.52), (s * 0.45, s * 0.62), (s * 0.55, s * 0.62)], fill=k)
    for i in range(4):
        x = s * (0.37 + i * 0.075)
        d.line([x, s * 0.7, x, s * 0.82], fill=k, width=max(2, s // 80))
    return _outline(img, s // 48)


def sticker_smiley(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    c, r = s / 2, s * 0.46
    d.ellipse([c - r, c - r, c + r, c + r], fill=(255, 215, 0, 255), outline=(20, 20, 20, 255), width=s // 40)
    d.ellipse([s * 0.33, s * 0.3, s * 0.42, s * 0.45], fill=(20, 20, 20, 255))
    d.ellipse([s * 0.58, s * 0.3, s * 0.67, s * 0.45], fill=(20, 20, 20, 255))
    d.arc([s * 0.27, s * 0.3, s * 0.73, s * 0.75], 20, 160, fill=(20, 20, 20, 255), width=s // 30)
    return img


def sticker_text(text, bg, fg, s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    h = s * 0.42
    d.rounded_rectangle([s * 0.04, s / 2 - h / 2, s * 0.96, s / 2 + h / 2], radius=s * 0.06, fill=bg)
    size = int(s * 0.3)
    font = _font(size)
    while d.textlength(text, font=font) > s * 0.84 and size > 8:
        size -= 2
        font = _font(size)
    d.text((s / 2, s / 2), text, font=font, fill=fg, anchor="mm")
    return _outline(img, s // 64)


def sticker_tally(s):
    """Kill-count tally marks."""
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    col = (240, 240, 240, 255)
    wdt = max(3, s // 28)
    for i in range(4):
        x = s * (0.22 + i * 0.15)
        d.line([x, s * 0.25, x, s * 0.75], fill=col, width=wdt)
    d.line([s * 0.12, s * 0.68, s * 0.8, s * 0.32], fill=col, width=wdt)
    return _outline(img, s // 64)


def sticker_target(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    c = s / 2
    for i, col in enumerate([(200, 30, 30, 255), (240, 240, 240, 255)] * 3):
        r = s * (0.46 - i * 0.075)
        d.ellipse([c - r, c - r, c + r, c + r], fill=col)
    return img


def sticker_hazard_stripes(s):
    img = _canvas(s)
    d = ImageDraw.Draw(img)
    d.rectangle([0, s * 0.3, s, s * 0.7], fill=(250, 205, 30, 255))
    step = s // 6
    for x in range(-s, s * 2, step * 2):
        d.polygon([(x, s * 0.7), (x + step, s * 0.7), (x + step + s * 0.4, s * 0.3), (x + s * 0.4, s * 0.3)],
                  fill=(20, 20, 20, 255))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rectangle([0, s * 0.3, s, s * 0.7], fill=255)
    img.putalpha(mask)
    return img


STICKERS = {
    "01_Radiation": sticker_radiation,
    "02_Biohazard": sticker_biohazard,
    "03_RedStar": sticker_star,
    "04_Skull": sticker_skull,
    "05_Smiley": sticker_smiley,
    "06_Stalker": lambda s: sticker_text("STALKER", (40, 40, 40, 255), (250, 205, 30, 255), s),
    "07_Pechorsk": lambda s: sticker_text("PECHORSK", (190, 190, 180, 255), (30, 30, 30, 255), s),
    "08_NoFear": lambda s: sticker_text("NO FEAR", (160, 20, 20, 255), (245, 245, 245, 255), s),
    "09_Tally": sticker_tally,
    "10_Target": sticker_target,
    "11_HazardStripes": sticker_hazard_stripes,
    "12_GreenStar": lambda s: sticker_star(s, (40, 160, 60, 255)),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024, help="camo texture size (power of two)")
    ap.add_argument("--sticker-size", type=int, default=256)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "CamoAndStickers"))
    ap.add_argument("--seed", type=int, default=1986)
    args = ap.parse_args()

    camo_dir = os.path.join(args.out, "Camo")
    sticker_dir = os.path.join(args.out, "Stickers")
    os.makedirs(camo_dir, exist_ok=True)
    os.makedirs(sticker_dir, exist_ok=True)

    for i, (name, fn) in enumerate(CAMOS.items()):
        rng = np.random.default_rng(args.seed + i)
        fn(args.size, rng).save(os.path.join(camo_dir, name + ".png"), optimize=True)
        print("camo   ", name)

    for name, fn in STICKERS.items():
        # Supersample for smooth edges.
        big = fn(args.sticker_size * 2)
        big.resize((args.sticker_size, args.sticker_size), Image.LANCZOS).save(
            os.path.join(sticker_dir, name + ".png"), optimize=True)
        print("sticker", name)


if __name__ == "__main__":
    main()
