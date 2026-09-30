#!/usr/bin/env python3
"""Draws a wallpaper from a Scene palette with code, so the colors match exactly and nobody else holds rights to it.

    python3 Scripts/make-wallpaper.py STYLE PALETTE OUT [--seed N] [--size 3840x2400] [--colors ROLE,ROLE,...]

STYLE is one of the names in STYLES below. PALETTE is a palette file (Scripts/scene-palettes/<theme>/dark.toml).
The same style, palette, seed, size, and colors always draw the same image, so the command is the wallpaper's provenance.
aura, flow, stars, and dither paint with the theme's family: the accent and the hues nearest it, so a red theme
stays red. --colors names the roles to use instead, for example yellow,red,magenta,blue for a rainbow.
Write OUT as .png for flat and pixel styles and .jpg for the rest; add it with Scripts/add-wallpaper.py.
"""
import argparse
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import gaussian_filter

from themekit import HUES, oklch, palette

Image.MAX_IMAGE_PIXELS = None


def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32) / 255


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def noise(rng, w, h, scale, octaves=4, persistence=0.5):
    """Smooth fractal value noise in 0...1: random grids at growing resolutions, resized with bicubic filtering."""
    total = np.zeros((h, w), np.float32)
    amplitude, norm = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        grid = rng.random((max(2, cells * h // w + 2), cells + 2)).astype(np.float32)
        layer = np.asarray(Image.fromarray(grid).resize((w + w // cells * 2, h + h // cells * 2), Image.BICUBIC))
        total += amplitude * layer[h // cells:h // cells + h, w // cells:w // cells + w]
        norm += amplitude
        amplitude *= persistence
    total /= norm
    return (total - total.min()) / (np.ptp(total) + 1e-6)


def finish(linear_rgb, rng, grain=0.012):
    """Linear light to sRGB with fine grain, which hides banding in soft gradients."""
    out = to_srgb(linear_rgb)
    if grain:
        out = out + rng.normal(0, grain, out.shape[:2])[..., None].astype(np.float32)
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))


def vignette(w, h, strength=0.35):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2)) / math.sqrt(2)
    return 1 - strength * d ** 2


def family(p, count=3):
    """The accent and the palette hues nearest it in hue angle: colors that belong together in this theme."""
    if p.get("_colors"):
        return [p[role] for role in p["_colors"]]
    accent_hue = oklch(p["accent"])[2]

    def gap(role):
        d = abs(oklch(p[role])[2] - accent_hue) % 360
        return min(d, 360 - d)
    near = sorted((r for r in HUES if gap(r) > 8), key=gap)
    return [p["accent"]] + [p[r] for r in near[:count - 1]]


def mix_hex(top, bottom, amount):
    """`top` over `bottom`, as sRGB hex: amount 1 gives top."""
    return "#" + "".join(f"{round(int(top[i:i + 2], 16) * amount + int(bottom[i:i + 2], 16) * (1 - amount)):02x}" for i in (1, 3, 5))


# MARK: - Styles

def aura(p, w, h, rng):
    """Light spilling in from beyond the edge of the screen, like a lamp or a monitor in a dark room: one strong source
    in the accent and a faint second one in the next family color. On a light look, pale washes of color on paper."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32) / w
    ground = to_linear(rgb(p["background"]))
    image = np.broadcast_to(ground, (h, w, 3)).copy()
    light = oklch(p["background"])[0] > 0.6
    warp = (noise(rng, w // 8, h // 8, 1.5, octaves=3) - 0.5)
    warp = np.asarray(Image.fromarray(warp).resize((w, h), Image.BICUBIC)) * 0.25
    colors = family(p, 3)
    if light:
        anchors = [(0.0, 0.62), (1.0, 0.05), (0.85, 0.62), (0.2, 0.0)]      # corners and edges, never the middle
        rng.shuffle(anchors)
        for (ax, ay), hex_color in zip(anchors, colors):
            cx, cy = ax + rng.uniform(-0.12, 0.12), ay + rng.uniform(-0.08, 0.08)
            d = np.hypot(x - cx, (y - cy) * 1.2) / rng.uniform(0.32, 0.5) + warp
            color = to_linear(rgb(mix_hex(hex_color, p["background"], 0.32)))
            image += (np.exp(-d * d * 1.6))[..., None] * (color - image) * 0.9
        return finish(image, rng, grain=0.01)
    # The main source sits just outside a corner or an edge; the second one across from it.
    side = rng.integers(4)
    along = rng.uniform(0.15, 0.85)
    ratio = h / w
    sources = [((along, -0.08), (along, ratio + 0.08), (-0.08, along * ratio), (1.08, along * ratio))[side]]
    sources.append((1 - sources[0][0], ratio - sources[0][1]))
    # Lightness follows the cube root of linear light, so a little light goes a long way: keep it faint, with a hot
    # core only where the light comes in.
    for (cx, cy), hex_color, strength, reach in zip(sources, colors, (0.16, 0.06), (0.5, 0.35)):
        d = np.maximum(np.hypot(x - cx, y - cy) / reach + warp, 0)
        glow = np.exp(-d * d * 2.2) + 1.2 * np.exp(-d * 7)
        image += glow[..., None] * to_linear(rgb(hex_color)) * strength
    image *= vignette(w, h, 0.2)[..., None]
    return finish(image, rng, grain=0.01)


def topo(p, w, h, rng):
    """Contour lines of an imaginary terrain, with every fifth line heavier, as on a survey map."""
    height = noise(rng, w, h, 2.2, octaves=4, persistence=0.45)
    levels = 34
    f = height * levels
    gy, gx = np.gradient(f)
    slope = np.hypot(gx, gy) + 1e-6
    distance = np.abs(f - np.round(f)) / slope                      # pixels to the nearest contour
    index = (np.round(f) % 5 == 0)
    width = np.where(index, 2.4, 1.1) * w / 3840
    line = np.clip(width + 0.5 - distance, 0, 1)
    background = to_linear(rgb(p["background"]))
    low, high = to_linear(rgb(p["muted"])), to_linear(rgb(p["accent"]))
    ink = low + (high - low) * (height ** 1.6)[..., None]
    ink = np.where(index[..., None], ink * 1.25, ink * 0.8)
    image = background + (ink - background) * line[..., None]
    image *= vignette(w, h, 0.25)[..., None]
    return finish(image, rng, grain=0.008)


def ridges(p, w, h, rng):
    """Stacked signal lines that rise in the middle, after the pulsar plot on a famous 1979 album cover."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    rows = 52
    left, right = W * 0.26, W * 0.74
    top, bottom = H * 0.2, H * 0.86
    xs = np.linspace(left, right, 600)
    center = (xs - W / 2) / ((right - left) / 2)
    envelope = np.exp(-(center * 1.9) ** 4)
    spacing = (bottom - top) / (rows - 1)
    for i in range(rows):
        base = top + spacing * i
        bumps = sum(rng.uniform(0.3, 1) * np.exp(-((center - rng.uniform(-0.4, 0.4)) / rng.uniform(0.06, 0.16)) ** 2)
                    for _ in range(rng.integers(2, 5)))
        wiggle = np.interp(np.linspace(0, 1, len(xs)), np.linspace(0, 1, 90), rng.normal(0, 0.05, 90))
        ys = base - spacing * 9 * envelope * bumps - spacing * 0.6 * wiggle * (0.3 + envelope)
        points = list(zip(xs, ys))
        draw.polygon(points + [(xs[-1], H), (xs[0], H)], fill=p["background"])
        glow = abs(i - rows * 0.6) < 2
        draw.line(points, fill=p["accent"] if glow else p["foreground"], width=round(2.6 * scale * w / 3840), joint="curve")
    return canvas.resize((w, h), Image.LANCZOS)


def maze(p, w, h, rng):
    """10 PRINT CHR$(205.5+RND(1)); : GOTO 10 — the one-line maze of the Commodore 64, drawn in the palette.
    Most of it stays close to the background; the accent shows where a slow glow passes over it."""
    cell = max(16, w // 64)
    scale = 3
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    heat = noise(rng, w // cell + 2, h // cell + 2, 1.3, octaves=2)
    stroke = max(2, int(cell * scale * 0.14))
    dim, mid, lit = p["lighter_background"], p["muted"], p["accent"]
    for row in range(h // cell + 2):
        for col in range(w // cell + 2):
            x0, y0 = col * cell * scale, row * cell * scale
            x1, y1 = x0 + cell * scale, y0 + cell * scale
            t = heat[row, col]
            color = lit if t > 0.8 else (mid if t > 0.55 else dim)
            if rng.random() < 0.5:
                draw.line([(x0, y0), (x1, y1)], fill=color, width=stroke)
            else:
                draw.line([(x0, y1), (x1, y0)], fill=color, width=stroke)
    return canvas.resize((w, h), Image.LANCZOS)


def dither(p, w, h, rng):
    """A sunrise of palette colors in ordered (Bayer) dithering, with chunky pixels like an early color display."""
    pixel = max(4, w // 480)
    gw, gh = w // pixel, h // pixel
    y, x = np.mgrid[0:gh, 0:gw].astype(np.float32)
    cx, cy = gw * rng.uniform(0.35, 0.65), gh * 1.08
    t = np.clip(np.hypot(x - cx, y - cy) / (gh * 1.05), 0, 1) ** 0.9
    t = np.clip(t + (noise(rng, gw, gh, 3, octaves=3) - 0.5) * 0.08, 0, 1)
    colors = family(p, 4)
    if not p.get("_colors"):
        colors.sort(key=lambda c: -oklch(c)[0])                           # the lightest at the sun's core
    ramp = colors + [p["dark_background"], p["background"]]
    bayer = np.array([[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
                      [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                      [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]], np.float32) / 64
    threshold = np.tile(bayer, (gh // 8 + 1, gw // 8 + 1))[:gh, :gw]
    position = t * (len(ramp) - 1)
    index = np.floor(position).astype(int)
    index = np.clip(index + (position - index > threshold), 0, len(ramp) - 1)
    colors = (np.stack([rgb(c) for c in ramp]) * 255).astype(np.uint8)
    return Image.fromarray(colors[index]).resize((gw * pixel, gh * pixel), Image.NEAREST).resize((w, h), Image.NEAREST)


def grid(p, w, h, rng):
    """A horizon at dusk: a striped sun over a glowing perspective grid, the way 1980s computers imagined the future."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    horizon = h * 0.62
    sky_top, sky_low = to_linear(rgb(p["dark_background"])), to_linear(rgb(p["magenta"]))
    t = np.clip(y / horizon, 0, 1)[..., None]
    image = sky_top + (sky_low - sky_top) * (t ** 3) * 0.55
    # The sun, striped near its base.
    cx, cy, r = w / 2, horizon - h * 0.06, h * 0.23
    inside = np.hypot(x - cx, y - cy) < r
    band = (y - (cy - r)) / (2 * r)
    lower = np.clip((band - 0.42) / 0.58, 0, 1) * 7                 # seven gaps, wider toward the horizon
    stripes = (band < 0.42) | (lower - np.floor(lower) > 0.12 + 0.05 * np.floor(lower))
    sun = to_linear(rgb(p["yellow"])) + (to_linear(rgb(p["red"])) - to_linear(rgb(p["yellow"]))) * np.clip(band, 0, 1)[..., None]
    mask = (inside & stripes & (y < horizon))[..., None]
    image = np.where(mask, sun, image)
    glow = np.exp(-((np.hypot(x - cx, y - cy) - r * 0.9) / (r * 0.5)) ** 2) * (y < horizon)
    image += glow[..., None] * to_linear(rgb(p["magenta"])) * 0.25
    # The floor and its grid.
    floor = y >= horizon
    image = np.where(floor[..., None], to_linear(rgb(p["background"])), image)
    depth = np.maximum(y - horizon, 1)
    z = h * 0.35 / depth                                            # distance into the scene
    across = (x - cx) * z / w * 12
    lines = np.minimum(np.abs(across - np.round(across)) / (z / w * 12 + 1e-6),
                       np.abs(z * 3 - np.round(z * 3)) / (np.abs(np.gradient(z * 3, axis=0)) + 1e-6))
    line = np.clip(1.6 - lines, 0, 1) * floor * np.clip((y - horizon) / (h * 0.12), 0, 1) ** 0.7
    line += np.exp(-((y - horizon) / (h * 0.004)) ** 2) * 0.9     # the horizon itself
    color = to_linear(rgb(p["accent"]))
    image += line[..., None] * (color - image)
    blurred = np.asarray(Image.fromarray((line * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(w / 500)), np.float32) / 255
    image += blurred[..., None] * color * 0.8
    return finish(image, rng)


def stars(p, w, h, rng):
    """A nebula in two palette colors over a field of stars."""
    cloud = noise(rng, w, h, 1.4, octaves=7, persistence=0.58)
    detail = noise(rng, w, h, 6, octaves=4, persistence=0.5)
    tint = noise(rng, w, h, 1.1, octaves=2)
    base = to_linear(rgb(p["background"]))
    first, second = family(p, 3)[:2]
    a, b = to_linear(rgb(first)), to_linear(rgb(second))
    color = a + (b - a) * tint[..., None]
    density = np.clip((cloud * 0.8 + detail * 0.2 - 0.45) / 0.4, 0, 1) ** 2
    image = base + color * density[..., None] * 0.75
    count = int(w * h / 2600)
    xs, ys = rng.integers(0, w, count), rng.integers(0, h, count)
    brightness = rng.power(0.35, count) * 0.9 + 0.05
    image[ys, xs] = image[ys, xs] + brightness[:, None] * to_linear(rgb(p["bright_foreground"]))
    halo = np.zeros((h, w), np.float32)
    bright = brightness > 0.75
    halo[ys[bright], xs[bright]] = brightness[bright] * 60
    image += gaussian_filter(halo, w / 1400)[..., None] * to_linear(rgb(p["bright_foreground"])) * 0.6
    image *= vignette(w, h, 0.45)[..., None]
    return finish(image, rng, grain=0.006)


def flow(p, w, h, rng):
    """Thousands of short strokes that follow a smooth current, colored by where they start."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    angle = noise(rng, w // 8, h // 8, 1.8, octaves=3) * math.tau * 1.5
    palette_colors = family(p, 3) + [p["muted"]]
    zone = noise(rng, w // 8, h // 8, 1.0, octaves=2)
    step, length = w / 520, 70
    for _ in range(5000):
        px, py = rng.uniform(0, w), rng.uniform(0, h)
        color = palette_colors[min(len(palette_colors) - 1, int(zone[int(py) // 8 % (h // 8), int(px) // 8 % (w // 8)] * len(palette_colors)))]
        color = mix_hex(color, p["background"], rng.uniform(0.25, 1) ** 0.7)     # near and far strokes
        points = [(px * scale, py * scale)]
        for _ in range(length):
            a = angle[min(h // 8 - 1, int(py) // 8), min(w // 8 - 1, int(px) // 8)]
            px, py = px + math.cos(a) * step, py + math.sin(a) * step
            if not (0 <= px < w and 0 <= py < h):
                break
            points.append((px * scale, py * scale))
        if len(points) > 4:
            draw.line(points, fill=color, width=max(1, int(1.6 * scale * w / 3840)), joint="curve")
    return canvas.resize((w, h), Image.LANCZOS)


def scope(p, w, h, rng):
    """An oscilloscope: a graticule, a glowing trace in the accent color, and the scanlines of a tube."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    base = to_linear(rgb(p["background"]))
    image = np.broadcast_to(base, (h, w, 3)).copy()
    image *= (1 + 0.5 * np.exp(-(((x - w / 2) / (w * 0.45)) ** 2 + ((y - h / 2) / (h * 0.45)) ** 2)))[..., None]
    # Graticule: 10 by 8 divisions with small ticks on the center lines.
    div = min(w / 12, h / 9)
    gx, gy = (x - w / 2) / div, (y - h / 2) / div
    inside = (np.abs(gx) <= 5) & (np.abs(gy) <= 4)
    grid_line = np.minimum(np.abs(gx - np.round(gx)), np.abs(gy - np.round(gy))) * div
    ticks = np.minimum(np.abs(gx * 5 - np.round(gx * 5)) * div / 5 + (np.abs(gy) > 0.08) * 99,
                       np.abs(gy * 5 - np.round(gy * 5)) * div / 5 + (np.abs(gx) > 0.08) * 99)
    graticule = np.clip(1.2 - np.minimum(grid_line, ticks), 0, 1) * inside
    image += graticule[..., None] * (to_linear(rgb(p["muted"])) - image) * 0.8
    # The trace: a slow sum of sines, drawn as distance to the curve.
    cols = np.linspace(-5, 5, w)
    f1, f2, phase = rng.uniform(0.6, 1.4), rng.uniform(2, 4), rng.uniform(0, math.tau)
    curve = (1.6 * np.sin(cols * f1 + phase) + 0.6 * np.sin(cols * f2 + phase * 2)) * np.exp(-(cols / 6) ** 2)
    trace_y = h / 2 - curve * div
    d = np.abs(y - trace_y[None, :])
    core = np.clip(1.5 - d / (w / 1600), 0, 1)
    glow = np.exp(-(d / (w / 160)) ** 2) * 0.45 + np.exp(-(d / (w / 40)) ** 2) * 0.12
    color = to_linear(rgb(p["accent"]))
    image += (core + glow)[..., None] * color
    image *= (1 - 0.18 * (np.floor(y / max(2, h // 600)) % 2 == 0))[..., None]      # scanlines
    image *= vignette(w, h, 0.5)[..., None]
    return finish(image, rng, grain=0.008)


def greenbar(p, w, h, rng):
    """Tractor-feed printer paper: pale bands, perforations, and sprocket holes down both edges."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    band = H / 18
    margin = W * 0.045
    tint = "#" + "".join(f"{round(int(p['background'][i:i + 2], 16) * 0.82 + int(p['green'][i:i + 2], 16) * 0.18):02x}" for i in (1, 3, 5))
    for i in range(0, 19, 2):
        draw.rectangle([margin, i * band, W - margin, (i + 1) * band], fill=tint)
    hole = W * 0.009
    for i in range(int(H / (band / 1.5)) + 1):
        cy = (i + 0.5) * band / 1.5
        for cx in (margin / 2, W - margin / 2):
            draw.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=p["dark_background"])
    for cx in (margin, W - margin):
        for y0 in range(0, H, int(W * 0.004)):
            draw.line([(cx, y0), (cx, y0 + W * 0.002)], fill=p["muted"], width=max(1, int(W * 0.0006)))
    return canvas.resize((w, h), Image.LANCZOS)


def bauhaus(p, w, h, rng):
    """Tiles of circles, halves, quarters, and bars in the palette, like a poster from a 1920s design school."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    cols, rows = 8, 5
    size = min(W / cols, H / rows)
    ox, oy = (W - size * cols) / 2, (H - size * rows) / 2
    colors = [p["red"], p["yellow"], p["blue"], p["foreground"], p["accent"], p["dark_background"]]
    for r in range(rows):
        for c in range(cols):
            x0, y0 = ox + c * size, oy + r * size
            x1, y1 = x0 + size, y0 + size
            # Shapes gather at the edges; the middle stays mostly paper, where the windows are.
            middle = 1 <= r <= rows - 2 and 1 <= c <= cols - 2
            if rng.random() < (0.85 if middle else 0.15):
                continue
            if rng.random() < 0.25:
                draw.rectangle([x0, y0, x1, y1], fill=colors[rng.integers(len(colors))])
            kind, color = rng.integers(5), colors[rng.integers(len(colors))]
            if kind == 0:
                pad = size * 0.12
                draw.ellipse([x0 + pad, y0 + pad, x1 - pad, y1 - pad], fill=color)
            elif kind == 1:
                start = 90 * rng.integers(4)
                draw.pieslice([x0, y0, x1, y1], start, start + 180, fill=color)
            elif kind == 2:
                corner = rng.integers(4)
                cx, cy = (x0, x1, x1, x0)[corner], (y0, y0, y1, y1)[corner]
                draw.pieslice([cx - size, cy - size, cx + size, cy + size], 90 * ((corner + 2) % 4), 90 * ((corner + 2) % 4) + 90, fill=color)
            elif kind == 3:
                for k in range(3):
                    draw.rectangle([x0, y0 + size * (0.12 + k * 0.3), x1, y0 + size * (0.26 + k * 0.3)], fill=color)
    return canvas.resize((w, h), Image.LANCZOS)


def blueprint(p, w, h, rng):
    """A drafting sheet: a fine and a coarse grid, circles, arcs, and dimension lines in pale ink on the palette's ground."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    fine, coarse = W / 160, W / 32
    faint = "#" + "".join(f"{round(int(p['background'][i:i + 2], 16) * 0.82 + int(p['foreground'][i:i + 2], 16) * 0.18):02x}" for i in (1, 3, 5))
    ink = p["foreground"]
    for i in range(int(W / fine) + 1):
        draw.line([(i * fine, 0), (i * fine, H)], fill=faint, width=max(1, int(W / 4000)) if i % 5 else max(2, int(W / 1800)))
    for i in range(int(H / fine) + 1):
        draw.line([(0, i * fine), (W, i * fine)], fill=faint, width=max(1, int(W / 4000)) if i % 5 else max(2, int(W / 1800)))
    stroke = max(2, int(W / 1400))
    cx, cy = W * rng.uniform(0.55, 0.72), H * rng.uniform(0.4, 0.6)
    for radius in (coarse * k for k in (1.2, 2.2, 3.4, 5.0)):
        draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], outline=ink, width=stroke)
    for angle in range(0, 360, 30):
        a = math.radians(angle)
        draw.line([(cx + math.cos(a) * coarse * 1.2, cy + math.sin(a) * coarse * 1.2),
                   (cx + math.cos(a) * coarse * 5.6, cy + math.sin(a) * coarse * 5.6)], fill=faint, width=stroke)
    draw.arc([cx - coarse * 7, cy - coarse * 7, cx + coarse * 7, cy + coarse * 7], 200, 330, fill=p["accent"], width=stroke * 2)
    y_dim = cy + coarse * 6.5
    draw.line([(cx - coarse * 5, y_dim), (cx + coarse * 5, y_dim)], fill=ink, width=stroke)
    for x_end in (cx - coarse * 5, cx + coarse * 5):
        draw.line([(x_end, y_dim - coarse * 0.4), (x_end, y_dim + coarse * 0.4)], fill=ink, width=stroke)
    return canvas.resize((w, h), Image.LANCZOS)


def mosaic(p, w, h, rng):
    """A landscape in block mosaic, the chunky graphics of a broadcast teletext page: sky, sun, hills, and water."""
    cols = 96
    rows = cols * h // w
    y, x = np.mgrid[0:rows, 0:cols].astype(np.float32)
    horizon = rows * 0.64
    ramp = [p["dark_background"], p["blue"], p["magenta"], p["red"], p["orange"], p["yellow"]]
    sky = np.clip(y / horizon, 0, 1) ** 1.25 * (len(ramp) - 1)
    index = np.floor(sky + (rng.random((rows, cols)) - 0.5) * 0.3).clip(0, len(ramp) - 1).astype(int)
    image = np.stack([rgb(c) for c in ramp])[index]
    sun_x, sun_r = cols * rng.uniform(0.35, 0.65), rows * 0.24
    sun = (np.hypot(x - sun_x, y - horizon) < sun_r) & (y < horizon)
    image[sun] = rgb(p["yellow"])
    image[sun & (y > horizon - sun_r * 0.45) & (y.astype(int) % 2 == 0)] = rgb(p["orange"])
    ridge = horizon - rows * 0.02 - noise(rng, cols, 1, 2.2, octaves=3)[0] * rows * 0.1
    hills = (y > ridge[None, :]) & (y < horizon)
    image[hills] = rgb(p["green"])
    image[hills & (y > ridge[None, :] + rows * 0.035)] = rgb(p["cyan"])
    water = y >= horizon
    image[water] = rgb(p["background"])
    depth = (y - horizon) / (rows - horizon)
    shimmer = water & (np.abs(x - sun_x) < sun_r * (1 - depth * 0.7)) & (y.astype(int) % 3 == 0)
    image[shimmer] = rgb(p["orange"])
    # Separated graphics: each block sits in its cell with a thin gap of the background around it.
    cell = w / cols
    canvas = Image.new("RGB", (w, h), p["background"])
    draw = ImageDraw.Draw(canvas)
    gap = max(1, round(cell * 0.08))
    for r in range(rows):
        for c in range(cols):
            fill = tuple(int(v * 255 + 0.5) for v in image[r, c])
            draw.rectangle([round(c * cell) + gap, round(r * cell) + gap, round((c + 1) * cell) - gap, round((r + 1) * cell) - gap], fill=fill)
    return canvas


def rasterbars(p, w, h, rng):
    """Demoscene copper bars: separate glowing bars, each lit from its center like a metal tube, frozen mid-wave."""
    y = np.arange(h, dtype=np.float32)[:, None, None]
    image = np.broadcast_to(to_linear(rgb(p["background"])), (h, 1, 3)).copy()
    hues = ["magenta", "red", "orange", "yellow", "green", "cyan", "blue"]
    phase = rng.uniform(0, math.tau)
    half = h * 0.018                                          # half the height of one bar
    bars = []
    for i, name in enumerate(hues + hues[:3]):
        center = h * 0.72 + math.sin(phase + i * 0.62) * h * 0.14 + (i - 5) * h * 0.012
        bars.append((center, name))
    # Draw back to front: bars lower on the screen sit in front, as in the effect.
    for center, name in sorted(bars):
        t = np.clip(1 - np.abs(y - center) / half, 0, 1)
        inside = t > 0
        light = 0.25 + 0.95 * t ** 1.5                        # dark edges, bright middle
        color = to_linear(rgb(p[name])) * light
        highlight = np.clip(t - 0.8, 0, 1) * 2.5              # a thin specular line along the middle
        color = color + highlight * to_linear(rgb(p["bright_foreground"])) * 0.6
        image = np.where(inside, color, image)
    image = np.broadcast_to(image, (h, w, 3)).copy()
    image *= vignette(w, h, 0.2)[..., None]
    return finish(image, rng, grain=0.005)


def stripes(p, w, h, rng):
    """1970s supergraphics: four bands run along the bottom and sweep up the right edge through a quarter circle."""
    scale = 2
    W, H = w * scale, h * scale
    canvas = Image.new("RGB", (W, H), p["background"])
    draw = ImageDraw.Draw(canvas)
    colors = [p["dark_foreground"], p["red"], p["yellow"], p["accent"]]   # inside to outside
    band, gap = H * 0.05, H * 0.012
    cx, cy = W * 0.72, H * 0.52                          # the turn's center: bands go left along the bottom, up on the right
    base = H * 0.14                                      # radius of the innermost edge
    for i, color in enumerate(colors):
        inner = base + i * (band + gap)
        outer = inner + band
        # Horizontal run under the center, from the left edge to the turn.
        draw.rectangle([-1, cy + inner, cx, cy + outer], fill=color)
        # The quarter circle from the bottom (90°) to the right (0°).
        ring = Image.new("L", (W, H), 0)
        ring_draw = ImageDraw.Draw(ring)
        ring_draw.pieslice([cx - outer, cy - outer, cx + outer, cy + outer], 0, 90, fill=255)
        ring_draw.pieslice([cx - inner, cy - inner, cx + inner, cy + inner], 0, 90, fill=0)
        canvas.paste(color, mask=ring)
        # Vertical run on the right, from the turn to the top edge.
        draw.rectangle([cx + inner, -1, cx + outer, cy], fill=color)
    return canvas.resize((w, h), Image.LANCZOS)


STYLES = {"aura": aura, "topo": topo, "ridges": ridges, "maze": maze, "dither": dither, "grid": grid, "stars": stars, "flow": flow,
          "scope": scope, "greenbar": greenbar, "bauhaus": bauhaus, "blueprint": blueprint, "mosaic": mosaic,
          "rasterbars": rasterbars, "stripes": stripes}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("style", choices=sorted(STYLES))
    ap.add_argument("palette")
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--size", default="3840x2400")
    ap.add_argument("--colors", help="roles for aura, flow, stars, and dither, in order, instead of the family")
    a = ap.parse_args()
    w, h = (int(n) for n in a.size.split("x"))
    p = palette(a.palette)
    if a.colors:
        p["_colors"] = a.colors.split(",")
    image = STYLES[a.style](p, w, h, np.random.default_rng(a.seed))
    if a.out.endswith(".png"):
        image.save(a.out, optimize=True)
    else:
        image.convert("RGB").save(a.out, quality=92, subsampling=0, optimize=True)
    print(f"{a.out}: {a.style}, seed {a.seed}, {w}x{h}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
