#!/usr/bin/env python3
"""Generates a wallpaper with OpenAI's image API.

    OPENAI_API_KEY=... python3 Scripts/generate-wallpaper.py OUT --subject "..." [--palette PALETTE | --look dark|light]
        [--reference IMAGE ...] [--size 3840x2160] [--quality high] [--dry-run]

--subject says what the picture shows. The script adds Scene's composition rules and prints the full prompt to record
with the wallpaper. --dry-run prints the request without sending it.

With --palette (Scripts/scene-palettes/<theme>/dark.toml), the prompt asks for the palette's colors. No model matches
hex colors exactly, so check the fit when you add the image. Without it, the picture chooses its own colors: that is how
a theme starts from its art, and Scripts/palette-from-image.py then derives the palette. --look says whether it should be
a dark or a light picture.

--reference sends earlier pictures (PNG or JPEG) through the edits endpoint and asks for their style, so a theme's
wallpapers look like one set. The largest size is 3840x2160 (16:9); a 16:10 frame tops out at 3632x2272.
"""
import argparse
import base64
import io
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

from themekit import luminance, palette

API = "https://api.openai.com/v1/images"
MODEL = "gpt-image-2.5-sunburst"

RULES = ("A desktop wallpaper, edge to edge, with no frame and no border. Keep the middle calm and uncluttered, because "
         "windows cover it; put detail toward the edges or low in the frame, and keep the top strip quiet for a menu bar. "
         "No text, letters, numbers, logos, signatures, watermarks, user interface, brands, or people's faces.")
REFERENCE = ("Match the reference image's style exactly: the same medium, technique, brushwork, texture, and colors. "
             "Paint a new scene with its own composition: arrange the sky, the land, and the light differently from the reference.")


def prompt_for(subject, p=None, look=None, references=False):
    lines = [RULES]
    if references:
        lines.append(REFERENCE)
    if p:
        look = "dark" if luminance(p["background"]) < 0.4 else "light"
        colors = ", ".join(f"{role} {p[key]}" for role, key in (
            ("ground", "background"), ("deep shade", "dark_background"), ("signature", "accent"), ("text-light", "foreground"),
            ("red", "red"), ("green", "green"), ("yellow", "yellow"), ("blue", "blue"), ("magenta", "magenta"), ("cyan", "cyan")))
        lines.append(f"A {look} image: its overall tone is as {look} as the ground color. "
                     f"Use only this palette, mostly the ground, deep shade, and signature colors, the rest as small touches: {colors}.")
    elif look == "dark":
        lines.append("A dark image: mostly deep shadow and night tones, so light text reads on it.")
    elif look == "light":
        lines.append("A light image: mostly pale, airy tones, so dark text reads on it.")
    return f"{subject}\n\n" + "\n".join(lines)


def reference_part(path):
    """A reference picture as a JPEG no larger than 1536 px: enough for its style, and fewer input tokens."""
    from PIL import Image
    image = Image.open(path).convert("RGB")
    image.thumbnail((1536, 1536))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=90)
    return buffer.getvalue()


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    for index, data in enumerate(files):
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="image[]"; filename="reference-{index}.jpg"\r\n'
                 f"Content-Type: image/jpeg\r\n\r\n").encode() + data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--subject", required=True, help="what the picture shows, in one or two sentences")
    ap.add_argument("--palette", help="a palette file whose colors the picture should use")
    ap.add_argument("--look", choices=["dark", "light"], help="without --palette: a dark or a light picture")
    ap.add_argument("--reference", action="append", default=[], help="an earlier picture whose style to match; repeatable")
    ap.add_argument("--size", default="3840x2160")
    ap.add_argument("--quality", default="high", choices=["low", "medium", "high", "xhigh", "max", "auto"])
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    w, h = (int(n) for n in a.size.split("x"))
    if w % 16 or h % 16 or max(w, h) > 3840 or w * h > 8_294_400:
        print(f"{a.size}: sides must be multiples of 16, at most 3840, and at most 8,294,400 pixels in all", file=sys.stderr)
        return 2
    prompt = prompt_for(a.subject, palette(a.palette) if a.palette else None, a.look, bool(a.reference))
    fields = {"model": a.model, "prompt": prompt, "size": a.size, "quality": a.quality, "output_format": "png", "n": 1}
    if a.dry_run:
        print(json.dumps({**fields, "references": a.reference}, indent=2))
        return 0
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        print("Set OPENAI_API_KEY to generate. --dry-run shows the request without it.", file=sys.stderr)
        return 2
    headers = {"Authorization": f"Bearer {key}"}
    if a.reference:
        body, headers["Content-Type"] = multipart(fields, [reference_part(r) for r in a.reference])
        url = f"{API}/edits"
    else:
        body, headers["Content-Type"] = json.dumps(fields).encode(), "application/json"
        url = f"{API}/generations"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=body, method="POST", headers=headers), timeout=900) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        print(f"OpenAI returned {error.code}: {error.read().decode(errors='replace')[:800]}", file=sys.stderr)
        return 1
    with open(a.out, "wb") as f:
        f.write(base64.b64decode(result["data"][0]["b64_json"]))
    references = "".join(f"\nreference: {r}" for r in a.reference)
    print(f"{a.out}: {a.model}, {a.size}, {a.quality}, usage {json.dumps(result.get('usage', {}))}{references}\nprompt: {prompt}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
