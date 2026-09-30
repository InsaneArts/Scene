#!/usr/bin/env python3
"""Prepares the film's data and images in build/film/.

    python3 Marketing/film/prepare.py

Writes build/film/data.js (every Scene theme's colors, resolved, and the lines the app shows about it) and
converts each theme's three wallpapers per look to JPEG, because Chrome cannot show HEIC. Only Scene's own themes
appear in the film: their wallpapers were generated or drawn for Scene, so the film carries no third-party image.
"""
import colorsys
import json
import math
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


def license_words(spdx):
    """An SPDX id in words, as ThemeCredits.license shows it."""
    if spdx == "NOASSERTION":
        return "license unknown"
    if spdx == "LicenseRef-PublicDomain":
        return "public domain"
    return spdx[len("LicenseRef-"):] + " license" if spdx.startswith("LicenseRef-") else spdx


def accent_name(p, system):
    """The macOS accent a variant asks for, as ThemeLoader.nearestAccent resolves "auto"."""
    value = system.get("accentColor")
    if value != "auto":
        return value
    r, g, b = (int(p["accent"][i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if s < 0.15 or l < 0.08 or l > 0.95:
        return "graphite"
    h *= 360
    for limit, name in ((15, "red"), (40, "orange"), (65, "yellow"), (165, "green"), (255, "blue"), (290, "purple"), (345, "pink")):
        if h < limit:
            return name
    return "red"


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


def chaos():
    """The desktop before Scene: a loud stock gradient that matches none of the apps on it."""
    import numpy as np
    w, h = 2880, 1800
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    corners = np.array([[255, 61, 154], [255, 176, 0], [0, 194, 255], [124, 255, 79]], float)
    top = corners[0] * (1 - x[..., None]) + corners[1] * x[..., None]
    bottom = corners[2] * (1 - x[..., None]) + corners[3] * x[..., None]
    image = top * (1 - y[..., None]) + bottom * y[..., None]
    glow = np.exp(-(((x - 0.62) / 0.25) ** 2 + ((y - 0.38) / 0.3) ** 2))[..., None]
    image = image * (1 - 0.45 * glow) + 255 * 0.45 * glow
    Image.fromarray(image.clip(0, 255).astype("uint8")).save(os.path.join(OUT, "assets", "chaos.jpg"), quality=92)


def grain():
    """Fine noise, laid over every frame so dark gradients do not band in 8-bit video."""
    import numpy as np
    noise = np.random.default_rng(3).normal(128, 42, (256, 256)).clip(0, 255).astype("uint8")
    Image.fromarray(noise).convert("RGB").save(os.path.join(OUT, "assets", "grain.png"))


def main():
    for folder in ("assets/wall", "assets/preview"):
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    sources = json.load(open(os.path.join(THEMES, "WALLPAPER_SOURCES.json")))
    data = {}
    for folder in SCENE:
        manifest = json.load(open(os.path.join(THEMES, folder, "theme.json")))
        assets = {a["file"]: a for a in manifest.get("assets", [])}
        for look, variant in manifest["variants"].items():
            p = variant["palette"]
            key = f"{folder}:{look}"
            walls, credits = [], []
            for i, wallpaper in enumerate(variant["wallpapers"]):
                entry = next(s for s in sources if s["theme"] == folder and s["file"] == f"{folder}/{wallpaper['file']}")
                assert entry["license"].startswith("Scene original"), entry["file"]
                source = os.path.join(THEMES, folder, wallpaper["file"])
                convert(source, os.path.join(OUT, "assets", "wall", f"{folder}-{look}-{i}.jpg"), 2880)
                convert(source, os.path.join(OUT, "assets", "wall", f"{folder}-{look}-{i}-small.jpg"), 480)
                walls.append(f"assets/wall/{folder}-{look}-{i}")
                asset = assets.get(wallpaper["file"], {})
                credits.append(f"Wallpaper: {asset.get('attribution', wallpaper['file'])} · {license_words(asset.get('license', 'NOASSERTION'))}")
            term = {k: resolve(v, p) for k, v in variant["terminal"].items() if k != "ansi"}
            ansi_order = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "brightBlack", "brightRed",
                          "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite"]
            term["ansi"] = [resolve(variant["terminal"]["ansi"][name], p) for name in ansi_order]
            system = variant.get("system", {})
            accent = accent_name(p, system)
            macos = None
            if accent:
                macos = f"macOS: {accent.capitalize()} accent" + (f", {system['iconStyle']} icons" if system.get("iconStyle") else "") + " (experimental)"
            authors = ", ".join(a["name"] for a in manifest["authors"])
            data[key] = {
                "key": key, "folder": folder, "look": look, "name": manifest["name"], "summary": manifest["summary"],
                "looks": sorted(manifest["variants"]),
                "ui": {k: v.lower() for k, v in p.items()}, "onAccent": on_accent(p),
                "term": term, "syn": {k: resolve(v, p) for k, v in variant["syntax"].items()},
                "walls": walls, "previews": [w.replace("/wall/", "/preview/") for w in walls],
                "credits": {"by": f"By {authors} · {license_words(manifest['license'])} · Version {manifest['version']}",
                            "macos": macos, "wallpapers": credits},
            }
    # Every bundled theme's name, in the app's order, so the switcher can say "12 of 75".
    names = sorted((json.load(open(os.path.join(THEMES, d, "theme.json")))["name"] for d in os.listdir(THEMES)
                    if os.path.exists(os.path.join(THEMES, d, "theme.json"))), key=str.casefold)
    with open(os.path.join(OUT, "data.js"), "w") as f:
        f.write("window.FILM_THEMES = " + json.dumps(data, indent=1) + ";\n")
        f.write("window.FILM_ALL = " + json.dumps(names) + ";\n")
    icon()
    chaos()
    grain()
    print(f"{len(data)} looks from {len(SCENE)} themes, {len(names)} themes in all -> {os.path.relpath(OUT, REPO)}")


if __name__ == "__main__":
    main()
