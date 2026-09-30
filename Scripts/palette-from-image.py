#!/usr/bin/env python3
"""Derives a Scene palette from a picture, for a theme that starts from its art.

    python3 Scripts/palette-from-image.py IMAGE [IMAGE ...] --look dark|light --out Scripts/scene-palettes/<theme>/<look>.toml

The ground, the accent, the text tint, and the terminal hues come from the picture's colors, measured in OKLab.
Lightness follows the rules in .claude/skills/scene-theme/PALETTES.md, so code stays readable on any art. A hue the
picture lacks keeps its usual angle, turned a little toward the accent and softened, so it still belongs.
Writes the palette, runs Scripts/check-palette.py on it, and saves a swatch sheet as <out>.png to compare with the art.
IMAGE is PNG or JPEG (convert HEIC with `sips -s format png`).
"""
import argparse
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.cluster.vq import kmeans2

from themekit import ANGLES, build_palette, to_oklab_array, write_palette

HERE = os.path.dirname(os.path.abspath(__file__))
# How far a hue may move from its usual angle: half the gap to its neighbours, less a margin, so hues stay apart.
ORDER = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
REACH = {}
for i, role in enumerate(ORDER):
    before, after = ANGLES[ORDER[i - 1]], ANGLES[ORDER[(i + 1) % len(ORDER)]]
    REACH[role] = min((ANGLES[role] - before) % 360, (after - ANGLES[role]) % 360) / 2 - 8


def clusters(paths, k=12):
    """The picture's main colors as (L, C, h) with their shares, from k-means in OKLab."""
    pixels = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        image.thumbnail((240, 240))
        pixels.append(np.asarray(image, np.float64).reshape(-1, 3) / 255)
    lab = to_oklab_array(np.concatenate(pixels))
    centers, labels = kmeans2(lab, k, minit="++", seed=1)
    shares = np.bincount(labels, minlength=k) / len(labels)
    return [(float(L), float(math.hypot(a, b)), math.degrees(math.atan2(b, a)) % 360, float(share))
            for (L, a, b), share in zip(centers, shares) if share > 0]


def mean_hue(colors):
    """The chroma- and share-weighted circular mean hue of (L, C, h, share) colors, and their mean chroma."""
    x = sum(C * s * math.cos(math.radians(h)) for L, C, h, s in colors)
    y = sum(C * s * math.sin(math.radians(h)) for L, C, h, s in colors)
    weight = sum(s for *_, s in colors) or 1
    return math.degrees(math.atan2(y, x)) % 360, sum(C * s for L, C, h, s in colors) / weight


def gap(a, b):
    """The signed shortest turn from hue a to hue b, in degrees."""
    return (b - a + 180) % 360 - 180


def derive(colors, look, accent_hue=None):
    dark = look == "dark"
    # The ground: the darkest (or lightest) third of the picture, tinted as the picture is.
    ordered = sorted(colors, key=lambda c: c[0] if dark else -c[0])
    ground_colors, total = [], 0
    for c in ordered:
        ground_colors.append(c)
        total += c[3]
        if total >= 0.33:
            break
    ground_hue, ground_chroma = mean_hue(ground_colors)
    ground_l = sum(c[0] * c[3] for c in ground_colors) / total
    ground = ((min(max(ground_l, 0.15), 0.23), min(ground_chroma * 0.6, 0.05), ground_hue) if dark
              else (min(max(ground_l, 0.94), 0.975), min(ground_chroma * 0.5, 0.03), ground_hue))
    # The text: tinted like the far end of the picture's light.
    text_colors = sorted(colors, key=lambda c: -c[0] if dark else c[0])[:3]
    text_hue, text_chroma = mean_hue(text_colors)
    fg = (text_hue, min(text_chroma * 0.4, 0.03 if dark else 0.04))
    # The accent: a vivid color that covers some of the picture and stands apart from the ground, like stars on a night sky.
    vivid = sorted((c for c in colors if c[1] > 0.05 and 0.3 < c[0] < 0.97),
                   key=lambda c: -c[1] * c[3] ** 0.35 * (1 + 0.8 * abs(gap(ground_hue, c[2])) / 180))
    if accent_hue is not None and vivid:
        vivid.sort(key=lambda c: abs(gap(accent_hue, c[2])))
    if vivid:
        L, C, h, s = vivid[0]
        accent = (0.8 if dark else 0.55, min(max(C, 0.1), 0.19), h)
    else:
        accent = (0.8 if dark else 0.55, 0.1, ground_hue)
    print("accent candidates (hue): " + ", ".join(f"{c[2]:.0f}° {'(picked)' if i == 0 else ''}".strip() for i, c in enumerate(vivid[:4])))
    # The hues: the picture's own when it has them near the usual angle, otherwise the usual angle turned toward the accent.
    hues = {}
    for role, angle in ANGLES.items():
        near = [c for c in colors if c[1] >= 0.035 and abs(gap(angle, c[2])) <= 32]
        if near:
            h, C = mean_hue(near)
            h = angle + max(-REACH[role], min(REACH[role], gap(angle, h)))
            hues[role] = (h % 360, min(max(C, 0.08), 0.17))
        else:
            turn = gap(angle, accent[2])
            hues[role] = ((angle + max(-12, min(12, turn * 0.2))) % 360, 0.085 if dark else 0.1)
    # Neighbours pulled toward the same color would look alike in code: push them apart again.
    for _ in range(3):
        for i, role in enumerate(ORDER):
            after = ORDER[(i + 1) % len(ORDER)]
            wanted = min((ANGLES[after] - ANGLES[role]) % 360, 42)
            short = wanted - gap(hues[role][0], hues[after][0])
            if short > 0:
                hues[role] = ((hues[role][0] - short / 2) % 360, hues[role][1])
                hues[after] = ((hues[after][0] + short / 2) % 360, hues[after][1])
    return build_palette(look, ground, accent, fg=fg, hues=hues)


def swatches(images, p, out):
    """The art above a row of the palette's colors, with a line of code-colored text on the ground."""
    art = Image.open(images[0]).convert("RGB")
    art.thumbnail((1200, 675))
    roles = ["background", "lighter_background", "selection", "muted", "dark_foreground", "foreground", "accent",
             "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
    size = art.width // len(roles)
    sheet = Image.new("RGB", (art.width, art.height + size + 70), p["background"])
    sheet.paste(art, (0, 0))
    draw = ImageDraw.Draw(sheet)
    for i, role in enumerate(roles):
        draw.rectangle([i * size, art.height, (i + 1) * size - 2, art.height + size], fill=p[role])
    font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 26)
    x, y = 16, art.height + size + 20
    for text, role in [("func ", "magenta"), ("apply", "blue"), ("(theme: ", "foreground"), ("Theme", "yellow"),
                       (") -> ", "foreground"), ('"done"', "green"), ("  // ", "dark_foreground"), ("42", "orange"),
                       (" error", "red"), (" ok", "cyan"), (" accent", "accent")]:
        draw.text((x, y), text, font=font, fill=p[role])
        x += draw.textlength(text, font=font)
    sheet.save(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+")
    ap.add_argument("--look", choices=["dark", "light"], required=True)
    ap.add_argument("--out", required=True, help="the palette file to write, e.g. Scripts/scene-palettes/<theme>/dark.toml")
    ap.add_argument("--accent-hue", type=float, help="pick the vivid color nearest this OKLCH hue as the accent, e.g. 90 for yellow")
    ap.add_argument("--tinted", action="store_true", help="tint macOS icons with the accent (dark looks)")
    a = ap.parse_args()
    p = derive(clusters(a.images), a.look, a.accent_hue)
    p["accent_color"] = "auto"
    if a.look == "dark":
        p["icon_style"] = "tinted" if a.tinted else "dark"
        if a.tinted:
            p["icon_tint"] = "accent"
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    write_palette(a.out, p)
    swatches(a.images, p, a.out + ".png")
    print(f"{a.out}: ground {p['background']}, accent {p['accent']}, text {p['foreground']}; swatches in {a.out}.png", flush=True)
    return subprocess.run([sys.executable, os.path.join(HERE, "check-palette.py"), a.out]).returncode


if __name__ == "__main__":
    sys.exit(main())
