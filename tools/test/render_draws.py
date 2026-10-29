#!/usr/bin/env python3
"""Test helper for the fake game (run_mock.lua with FAKE_GAME set): replays the canvas draw
calls the mod made into a render target, so the panel gets a real preview PNG.

Input lines: size<TAB>N, then draw<TAB>path<TAB>x<TAB>y<TAB>w<TAB>h<TAB>uvw<TAB>uvh<TAB>alpha<TAB>blend<TAB>rot
"""
import sys

from PIL import Image, ImageDraw


def fake_weapon_texture(out_path):
    """A stand-in for a gun's base color texture: receiver, grip, a round part."""
    im = Image.new("RGB", (512, 512), (52, 54, 50))
    d = ImageDraw.Draw(im)
    d.rectangle([20, 60, 492, 200], fill=(38, 40, 37), outline=(90, 92, 88), width=4)
    d.rectangle([40, 260, 300, 470], fill=(70, 50, 34), outline=(110, 80, 50), width=4)
    d.ellipse([340, 280, 480, 420], fill=(30, 30, 30), outline=(90, 92, 88), width=4)
    for x in range(40, 480, 24):
        d.line([x, 80, x, 180], fill=(60, 62, 58), width=2)
    im.save(out_path)


def main(ops_path, out_path):
    size, canvas = 512, None
    with open(ops_path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "size":
                size = int(float(p[1]))
                canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
            elif p[0] == "draw":
                path = p[1]
                x, y, w, h, uvw, uvh, alpha = map(float, p[2:9])
                blend, rot = int(p[9]), float(p[10])
                src = Image.open(path).convert("RGBA")
                if uvw != 1 or uvh != 1:  # tiled camo
                    tw, th = max(1, int(w / uvw)), max(1, int(h / uvh))
                    tile = src.resize((tw, th))
                    src = Image.new("RGBA", (int(w), int(h)))
                    for tx in range(0, int(w), tw):
                        for ty in range(0, int(h), th):
                            src.paste(tile, (tx, ty))
                else:
                    src = src.resize((max(1, int(w)), max(1, int(h))))
                if rot:
                    src = src.rotate(-rot, expand=True, resample=Image.BICUBIC)
                    x -= (src.width - w) / 2
                    y -= (src.height - h) / 2
                if blend == 0:
                    src.putalpha(255)
                else:
                    a = src.getchannel("A").point(lambda v: int(v * alpha))
                    src.putalpha(a)
                canvas.paste(src, (int(x), int(y)), src)  # paste allows negative offsets
    canvas.convert("RGB").save(out_path)


if __name__ == "__main__":
    if sys.argv[1] == "--fake-texture":
        fake_weapon_texture(sys.argv[2])
    else:
        main(sys.argv[1], sys.argv[2])
