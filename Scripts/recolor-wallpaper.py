#!/usr/bin/env python3
"""Recolors an image into a Scene palette, so a photo or a generated picture belongs to its theme.

    python3 Scripts/recolor-wallpaper.py IN PALETTE OUT [--mode blend|gradient] [--strength 0.85] [--ramp ROLES]

blend     pulls every color toward the palette colors near it (a smooth lookup table, like lutgen) and keeps
          the image's own light and shade. Good for photos and paintings.
gradient  maps brightness onto a ramp of palette colors, darkest to lightest, like a duotone print.
          --ramp picks the roles, for example background,blue,magenta,bright_foreground.
--strength mixes the result with the original: 1 is all palette, 0 is the original.
The result is a derived work: record the original's license and source when you add it.
"""
import argparse
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

from themekit import HUES, from_oklab_array as from_oklab, luminance, palette, to_oklab_array as to_oklab

Image.MAX_IMAGE_PIXELS = None


def hex_rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], np.float64) / 255


def blend_lut(p, size=33, sigma=0.09):
    """A size³ table from sRGB to sRGB: each color moves to a weighted mix of nearby palette colors, keeping its lightness."""
    roles = ["background", "dark_background", "lighter_background", "muted", "dark_foreground", "foreground",
             "bright_foreground", "accent", *HUES]
    swatches = to_oklab(np.stack([hex_rgb(p[r]) for r in roles]))
    axis = np.linspace(0, 1, size)
    grid = np.stack(np.meshgrid(axis, axis, axis, indexing="ij"), -1)            # [r][g][b] -> rgb
    lab = to_oklab(grid)
    d2 = ((lab[..., None, :] - swatches) ** 2).sum(-1)
    weights = np.exp(-d2 / (2 * sigma ** 2)) + 1e-12
    mapped = (weights[..., None] * swatches).sum(-2) / weights.sum(-1)[..., None]
    mapped[..., 0] = lab[..., 0] * 0.6 + mapped[..., 0] * 0.4                      # mostly the image's own light and shade
    return from_oklab(mapped)


def apply_lut(image, lut):
    size = lut.shape[0]
    coords = np.moveaxis(image, -1, 0) * (size - 1)
    return np.stack([map_coordinates(lut[..., c], coords, order=1, mode="nearest") for c in range(3)], -1)


def gradient(image, p, ramp):
    colors = sorted((hex_rgb(p[r]) for r in ramp), key=lambda c: luminance("#%02x%02x%02x" % tuple(int(v * 255) for v in c)))
    lab = to_oklab(np.stack(colors))
    light = to_oklab(image)[..., 0]
    low, high = np.percentile(light, [1, 99])
    t = np.clip((light - low) / (high - low + 1e-6), 0, 1) * (len(colors) - 1)
    i = np.clip(np.floor(t).astype(int), 0, len(colors) - 2)
    f = (t - i)[..., None]
    return from_oklab(lab[i] * (1 - f) + lab[i + 1] * f)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("palette")
    ap.add_argument("output")
    ap.add_argument("--mode", choices=["blend", "gradient"], default="blend")
    ap.add_argument("--strength", type=float, default=0.85)
    ap.add_argument("--ramp", default="background,blue,magenta,bright_foreground")
    a = ap.parse_args()
    p = palette(a.palette)
    image = np.asarray(Image.open(a.input).convert("RGB"), np.float64) / 255
    result = apply_lut(image, blend_lut(p)) if a.mode == "blend" else gradient(image, p, a.ramp.split(","))
    out = image * (1 - a.strength) + result * a.strength
    picture = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))
    if a.output.endswith(".png"):
        picture.save(a.output, optimize=True)
    else:
        picture.save(a.output, quality=92, subsampling=0, optimize=True)
    print(f"{a.output}: {a.mode}, strength {a.strength}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
