#!/usr/bin/env python3
"""Turns any picture into a ready-to-use camo or sticker for the CamoAndStickers mod.

Optional: the mod loads plain PNG/JPG files as they are. This helper just makes them look
better on a gun.

  camo:    crops to a square, resizes, and makes the edges seamless so the pattern tiles
           without visible seams.
  sticker: optionally removes a solid background, trims empty borders, adds a die-cut
           outline and saves a PNG with transparency.

Examples:
  python3 tools/prepare_image.py camo   photo.jpg
  python3 tools/prepare_image.py camo   pattern.png --mirror --size 2048
  python3 tools/prepare_image.py sticker logo.jpg --remove-bg --outline 6
  python3 tools/prepare_image.py sticker logo.png --out "C:/Users/Me/Pictures/ITR2 Stickers"

Needs Pillow and numpy (pip install pillow numpy).
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def center_square(img):
    s = min(img.size)
    left, top = (img.width - s) // 2, (img.height - s) // 2
    return img.crop((left, top, left + s, top + s))


def make_seamless(img, overlap=0.25):
    """Per axis, blends the image with a copy shifted by half its size: the copy's seam sits
    in the middle, where the original is fully opaque, and the original's edges are covered
    by the copy. Doing X then Y keeps the first pass tileable through the second."""
    a = np.asarray(img, dtype=np.float64)

    def ramp(n):
        x = np.minimum(np.arange(n), np.arange(n)[::-1]) / (n * overlap)
        return np.clip(x, 0, 1)  # 0 at the borders, 1 inside

    for axis in (1, 0):
        n = a.shape[axis]
        shape = [1, 1, 1]
        shape[axis] = n
        weight = ramp(n).reshape(shape)
        a = a * weight + np.roll(a, n // 2, axis=axis) * (1 - weight)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), img.mode)


def mirror_tile(img):
    """2x2 mirrored tiling: always perfectly seamless, but symmetric."""
    w, h = img.size
    out = Image.new(img.mode, (w * 2, h * 2))
    out.paste(img, (0, 0))
    out.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
    out.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
    out.paste(img.transpose(Image.ROTATE_180), (w, h))
    return out


def remove_background(img, tolerance):
    """Makes pixels close to the corner color transparent (for logos on a flat backdrop)."""
    a = np.asarray(img.convert("RGBA"), dtype=np.int32)
    corners = np.array([a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]])[:, :3]
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((a[..., :3] - bg) ** 2).sum(-1))
    alpha = np.clip((dist - tolerance) / max(1, tolerance * 0.5), 0, 1) * 255
    a[..., 3] = np.minimum(a[..., 3], alpha.astype(np.int32))
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def add_outline(img, width, color=(255, 255, 255, 255)):
    alpha = img.getchannel("A").point(lambda v: 255 if v > 32 else 0)
    alpha = alpha.filter(ImageFilter.MaxFilter(width * 2 + 1)).filter(ImageFilter.GaussianBlur(0.8))
    border = Image.new("RGBA", img.size, color)
    border.putalpha(alpha)
    border.alpha_composite(img)
    return border


def prepare_camo(args):
    img = center_square(Image.open(args.input).convert("RGB"))
    if args.mirror:
        img = mirror_tile(img.resize((args.size // 2, args.size // 2), Image.LANCZOS))
    else:
        img = make_seamless(img.resize((args.size, args.size), Image.LANCZOS))
    return img


def prepare_sticker(args):
    img = Image.open(args.input).convert("RGBA")
    if args.remove_bg:
        img = remove_background(img, args.tolerance)
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    # Pad to a square with room for the outline, keep the aspect ratio.
    pad = args.outline * 2 + 2
    side = max(img.size) + pad * 2
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    if args.outline > 0:
        square = add_outline(square, args.outline)
    if side > args.size:
        square = square.resize((args.size, args.size), Image.LANCZOS)
    return square


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", choices=["camo", "sticker"])
    ap.add_argument("input")
    ap.add_argument("--out", help="output folder (default: the mod's Camo/ or Stickers/ folder)")
    ap.add_argument("--name", help="output file name without extension (default: input name)")
    ap.add_argument("--size", type=int, help="camo size (default 1024) / max sticker size (default 512)")
    ap.add_argument("--mirror", action="store_true", help="camo: mirror-tile instead of blending the seams")
    ap.add_argument("--remove-bg", action="store_true", help="sticker: make the flat background transparent")
    ap.add_argument("--tolerance", type=float, default=40, help="sticker: background color tolerance (0-255)")
    ap.add_argument("--outline", type=int, default=0, help="sticker: white die-cut outline width in pixels")
    args = ap.parse_args()

    if args.size is None:
        args.size = 1024 if args.kind == "camo" else 512
    img = prepare_camo(args) if args.kind == "camo" else prepare_sticker(args)

    out_dir = args.out or os.path.join(ROOT, "CamoAndStickers", "Camo" if args.kind == "camo" else "Stickers")
    os.makedirs(out_dir, exist_ok=True)
    name = args.name or os.path.splitext(os.path.basename(args.input))[0]
    path = os.path.join(out_dir, name + ".png")
    img.save(path, optimize=True)
    print(path)


if __name__ == "__main__":
    main()
