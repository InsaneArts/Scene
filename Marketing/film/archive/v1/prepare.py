#!/usr/bin/env python3
"""Prepares the film's data and images in build/film/.

    python3 Marketing/film/prepare.py

Writes build/film/data.js (every Scene theme's colors, resolved) and converts each theme's first wallpaper
to JPEG, because Chrome cannot show HEIC. Only Scene's own themes appear in the film: their wallpapers were
generated or drawn for Scene, so the film carries no third-party image.
"""
import json
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "Scripts"))
from themekit import contrast, luminance  # noqa: E402

OUT = os.path.join(REPO, "build", "film")
THEMES = os.path.join(REPO, "Themes")
SCENE = sorted(d for d in os.listdir(os.path.join(REPO, "Scripts", "scene-palettes"))
               if os.path.isdir(os.path.join(REPO, "Scripts", "scene-palettes", d)))


def resolve(value, palette):
    if isinstance(value, dict):
        return {**value, "color": resolve(value["color"], palette)}
    return palette[value[1:]] if value.startswith("@") else value.lower()


def on_accent(p):
    """Text on the accent color, as Design.swift picks it."""
    if contrast(p["accent"], p["background"]) >= 3:
        return p["background"]
    return "#000000" if luminance(p["accent"]) > 0.3 else "#ffffff"


def convert(source, target, width):
    """A JPEG copy of an image, at most `width` pixels wide."""
    if os.path.exists(target) and os.path.getmtime(target) >= os.path.getmtime(source):
        return
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "92", "-Z", str(width), source, "--out", target],
                   check=True, capture_output=True)


def icon():
    """The app icon as macOS draws it: the artwork in a continuous-corner square with a soft rim."""
    art = Image.open(os.path.join(REPO, "Assets", "Scene.icon", "Assets", "Scene-1024x1024.png")).convert("RGBA")
    size, inset = 1024, 100
    shape = 824
    scale = 4
    mask = Image.new("L", (size * scale, size * scale), 0)
    # A superellipse (n = 5) is close to Apple's continuous corners.
    n, r = 5.0, shape * scale / 2
    cx = cy = size * scale / 2
    points = []
    for i in range(2000):
        import math
        a = 2 * math.pi * i / 2000
        ca, sa = math.cos(a), math.sin(a)
        points.append((cx + r * abs(ca) ** (2 / n) * (1 if ca >= 0 else -1), cy + r * abs(sa) ** (2 / n) * (1 if sa >= 0 else -1)))
    ImageDraw.Draw(mask).polygon(points, fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body.paste(art.resize((shape, shape), Image.LANCZOS), (inset, inset))
    body.putalpha(ImageChops.multiply(body.getchannel("A"), mask))
    # A light rim at the top and a darker one at the bottom, like the glass edge of macOS 26 icons.
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    rim = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    gradient = Image.linear_gradient("L").resize((size, size))
    top = ImageChops.multiply(edge, ImageChops.invert(gradient))
    rim.putalpha(top.point(lambda v: int(v * 0.55)))
    body = Image.alpha_composite(body, rim)
    dark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dark.putalpha(ImageChops.multiply(edge, gradient).point(lambda v: int(v * 0.35)))
    body = Image.alpha_composite(body, dark)
    body.crop((inset, inset, inset + shape, inset + shape)).save(os.path.join(OUT, "assets", "icon.png"))


def grain():
    """Fine noise, laid over every frame so dark gradients do not band in 8-bit video."""
    import numpy as np
    noise = np.random.default_rng(3).normal(128, 42, (256, 256)).clip(0, 255).astype("uint8")
    Image.fromarray(noise).convert("RGB").save(os.path.join(OUT, "assets", "grain.png"))


def main():
    for folder in ("assets/wall", "assets/thumb"):
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    sources = json.load(open(os.path.join(THEMES, "WALLPAPER_SOURCES.json")))
    data = {}
    for folder in SCENE:
        manifest = json.load(open(os.path.join(THEMES, folder, "theme.json")))
        for look, variant in manifest["variants"].items():
            p = variant["palette"]
            first = next(s for s in sorted(sources, key=lambda s: s["order"])
                         if s["theme"] == folder and s["variant"] == look)
            assert first["license"].startswith("Scene original"), first["file"]
            key = f"{folder}:{look}"
            source = os.path.join(THEMES, first["file"])
            convert(source, os.path.join(OUT, "assets", "wall", f"{folder}-{look}.jpg"), 2880)
            convert(source, os.path.join(OUT, "assets", "wall", f"{folder}-{look}-small.jpg"), 480)
            term = {k: resolve(v, p) for k, v in variant["terminal"].items() if k != "ansi"}
            ansi_order = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "brightBlack", "brightRed",
                          "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite"]
            term["ansi"] = [resolve(variant["terminal"]["ansi"][name], p) for name in ansi_order]
            data[key] = {
                "key": key, "folder": folder, "look": look, "name": manifest["name"], "summary": manifest["summary"],
                "looks": sorted(manifest["variants"]),
                "ui": {k: v.lower() for k, v in p.items()}, "onAccent": on_accent(p),
                "term": term, "syn": {k: resolve(v, p) for k, v in variant["syntax"].items()},
                "wallpaper": f"assets/wall/{folder}-{look}.jpg", "wallpaperSmall": f"assets/wall/{folder}-{look}-small.jpg",
                "thumb": f"assets/thumb/{folder}-{look}.jpg", "thumbSmall": f"assets/thumb/{folder}-{look}-small.jpg",
            }
    with open(os.path.join(OUT, "data.js"), "w") as f:
        f.write("window.FILM_THEMES = " + json.dumps(data, indent=1) + ";\n")
    icon()
    grain()
    print(f"{len(data)} looks from {len(SCENE)} themes -> {os.path.relpath(OUT, REPO)}")


if __name__ == "__main__":
    main()
