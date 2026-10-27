#!/usr/bin/env python3
"""Packs the mod into dist/CamoAndStickers-<version>.zip, laid out like the game folder,
so the archive can be extracted straight into the Into the Radius 2 install directory
(or installed with Vortex)."""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "CamoAndStickers")
PREFIX = "IntoTheRadius2/Binaries/Win64/ue4ss/Mods/CamoAndStickers"
SKIP = {"presets.lua"}
SKIP_DIRS = {"Sync", "__pycache__"}


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "1.0.0"
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", f"CamoAndStickers-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirs, files in os.walk(MOD):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in sorted(files):
                if name in SKIP:
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, MOD).replace(os.sep, "/")
                z.write(path, f"{PREFIX}/{rel}")
        z.write(os.path.join(ROOT, "README.md"), f"{PREFIX}/README.md")
    print(out)


if __name__ == "__main__":
    main()
