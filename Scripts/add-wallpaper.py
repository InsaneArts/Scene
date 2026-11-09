#!/usr/bin/env python3
"""Adds a wallpaper to a Scene theme: checks it, writes it into Themes/, and records where it came from.

    python3 Scripts/add-wallpaper.py THEME LOOK ORDER IMAGE --name SLUG --source SOURCE --author AUTHOR --license LICENSE \\
        [--attribution TEXT] [--page-url URL] [--image-url URL] [--prompt TEXT] [--notes TEXT] [--format heic|png|jpg] [--check]

THEME is the theme folder (phosphor), LOOK is dark or light, ORDER is 1 to 3 (1 is the default wallpaper).
The file lands at Themes/THEME/wallpapers/LOOK-SLUG.heic. HEIC (quality 70, through macOS's sips) is a third of
a JPEG's size and looks the same. --format png keeps pixel art and flat colors crisp, and small. --check only
prints the checks.
The entry for THEME, LOOK, and ORDER in Themes/WALLPAPER_SOURCES.json is replaced. Run
Scripts/make-bundled-themes.py afterwards to put the wallpaper into theme.json.
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image

from themekit import BANNED_SOURCES, SCENE_PALETTES, SOURCES, THEMES, image_stats, palette, palette_fit, spdx

Image.MAX_IMAGE_PIXELS = None
MB = 1024 * 1024


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("theme")
    ap.add_argument("look", choices=["dark", "light"])
    ap.add_argument("order", type=int, choices=[1, 2, 3])
    ap.add_argument("image")
    ap.add_argument("--name", required=True, help="short slug, for example 'phosphor-grid'")
    ap.add_argument("--source", required=True, help="generated, procedural, nasa, wikimedia, unsplash, ...")
    ap.add_argument("--author", required=True)
    ap.add_argument("--license", required=True, help="free text; it starts with the license name, e.g. 'Scene original (...)'")
    ap.add_argument("--attribution", help="the credit line Scene shows; defaults to the author")
    ap.add_argument("--page-url", default="")
    ap.add_argument("--image-url", default="")
    ap.add_argument("--prompt", help="the prompt, for generated images")
    ap.add_argument("--notes")
    ap.add_argument("--format", choices=["heic", "png", "jpg"], default="heic")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    image = Image.open(a.image)
    width, height = image.size
    errors, warnings = [], []
    if any(b in f"{a.source} {a.license} {a.page_url} {a.image_url}".lower() for b in BANNED_SOURCES):
        errors.append("Unsplash, Pexels, and Pixabay ban wallpaper apps in their terms; find the picture elsewhere")
    if spdx(a.license) == "NOASSERTION":
        errors.append(f"license '{a.license}' is unknown; start it with a known name (see WALLPAPERS.md, Licenses)")
    long_side = max(width, height)
    if not 1024 <= long_side <= 8192:
        errors.append(f"long side {long_side}px is outside 1024 to 8192, the theme loader's limits")
    elif long_side < 3840:
        warnings.append(f"long side {long_side}px looks soft on a Retina display; 3840px or more is the target")
    if not 1.45 <= width / height <= 1.95:
        warnings.append(f"aspect {width / height:.2f} is far from 16:10 and 16:9, so 'fill' crops a lot")

    # The bytes Scene will ship.
    ext = a.format
    if ext == "png":
        buffer = io.BytesIO()
        image.save(buffer, "PNG", optimize=True)
        data = buffer.getvalue()
    elif ext == "jpg" and image.format == "JPEG":
        data = open(a.image, "rb").read()
    elif ext == "jpg":
        buffer = io.BytesIO()
        image.convert("RGB").save(buffer, "JPEG", quality=92, subsampling=0, optimize=True, progressive=True)
        data = buffer.getvalue()
    else:
        with tempfile.TemporaryDirectory() as folder:
            source, out = os.path.join(folder, "in.png"), os.path.join(folder, "out.heic")
            image.convert("RGB").save(source, "PNG")
            # sips reads formatOptions as a percentage; a fraction such as 0.7 means almost no quality.
            subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "70", source, "--out", out],
                           check=True, capture_output=True)
            data = open(out, "rb").read()
    if len(data) > 20 * MB:
        errors.append(f"{len(data) / MB:.1f} MB is over the 20 MB limit per image")
    elif len(data) > 6 * MB:
        warnings.append(f"{len(data) / MB:.1f} MB is large; the app ships every byte")

    lightness, dominant = image_stats(image)
    if a.look == "dark" and lightness > 0.62:
        warnings.append(f"lightness {lightness:.2f} is bright for a dark look")
    if a.look == "light" and lightness < 0.55:
        warnings.append(f"lightness {lightness:.2f} is dim for a light look")
    palette_path = os.path.join(SCENE_PALETTES, a.theme, f"{a.look}.toml")
    fit = None
    if os.path.exists(palette_path):
        fit = palette_fit(dominant, palette(palette_path))
        if fit > 0.10:
            warnings.append(f"palette fit {fit:.3f} is loose (recolored art scores about 0.01, matched photos 0.04 to 0.09)")

    file = f"{a.theme}/wallpapers/{a.look}-{a.name}.{ext}"
    print(f"{file}: {width}x{height}, {len(data) / MB:.1f} MB, lightness {lightness:.2f}"
          + (f", palette fit {fit:.3f}" if fit is not None else "")
          + "\n  dominant: " + ", ".join(f"{c} {s:.0%}" for c, s in dominant))
    for e in errors:
        print(f"  error   {e}")
    for w in warnings:
        print(f"  warning {w}")
    if errors:
        return 1
    if a.check:
        return 0

    sources = json.load(open(SOURCES)) if os.path.exists(SOURCES) else []
    old = [s for s in sources if (s["theme"], s["variant"], s["order"]) == (a.theme, a.look, a.order)]
    sources = [s for s in sources if s not in old]
    for s in old:   # A replaced wallpaper leaves no file behind, unless another entry still uses it.
        if s["file"] != file and all(o["file"] != s["file"] for o in sources):
            path = os.path.join(THEMES, s["file"])
            if os.path.exists(path):
                os.remove(path)
    folder = os.path.join(THEMES, a.theme, "wallpapers")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(THEMES, file), "wb") as f:
        f.write(data)
    total = sum(os.path.getsize(os.path.join(folder, n)) for n in os.listdir(folder))
    if total > 36 * MB:
        print(f"  warning the theme's wallpapers take {total / MB:.1f} MB of the 40 MB a theme may use")

    entry = {"theme": a.theme, "variant": a.look, "order": a.order, "file": file, "source": a.source,
             "imageURL": a.image_url, "pageURL": a.page_url, "author": a.author, "license": a.license,
             "attribution": a.attribution or a.author, "sha256": hashlib.sha256(data).hexdigest(),
             "width": width, "height": height}
    if a.prompt:
        entry["prompt"] = a.prompt
    if a.notes:
        entry["notes"] = a.notes
    sources.append(entry)
    sources.sort(key=lambda s: (s["theme"], s["variant"], s["order"]))
    with open(SOURCES, "w") as f:
        json.dump(sources, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"  recorded in {os.path.relpath(SOURCES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
