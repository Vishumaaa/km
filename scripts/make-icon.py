#!/usr/bin/env python3
"""Draws the Glide app icon and writes the asset catalogs for the iPhone and Mac apps.

Requires Pillow:  pip3 install pillow
Run from the repo root:  python3 scripts/make-icon.py
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # master art is drawn at 2x and downsampled for smooth edges

TOP_LEFT = (92, 58, 245)      # violet
BOTTOM_RIGHT = (20, 168, 255) # electric blue


def gradient(size):
    a = Image.new("RGB", (size, size), TOP_LEFT)
    b = Image.new("RGB", (size, size), BOTTOM_RIGHT)
    base = Image.linear_gradient("L").resize((size, size))
    horizontal = base.rotate(90)
    mask = ImageChops.add(base, horizontal, scale=2)
    return Image.composite(b, a, mask).convert("RGBA")


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(
        u**3 * p0[i] + 3 * u**2 * t * p1[i] + 3 * u * t**2 * p2[i] + t**3 * p3[i]
        for i in range(2)
    )


def draw_art():
    img = gradient(S)

    # Soft highlight in the top-left corner.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-S * 0.25, -S * 0.3, S * 0.65, S * 0.5), fill=(255, 255, 255, 58))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(S * 0.16)))

    # The "trackpad": a frosted rounded rectangle.
    pad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(pad)
    box = (S * 0.15, S * 0.24, S * 0.85, S * 0.76)
    d.rounded_rectangle(box, radius=S * 0.085, fill=(255, 255, 255, 40),
                        outline=(255, 255, 255, 120), width=int(S * 0.008))
    img = Image.alpha_composite(img, pad)

    # The glide trail: a curve that thickens and brightens toward the cursor.
    p0, p1, p2, p3 = (S * 0.32, S * 0.61), (S * 0.44, S * 0.70), (S * 0.47, S * 0.37), (S * 0.65, S * 0.385)
    trail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(trail)
    steps = 500
    for i in range(steps + 1):
        t = i / steps
        x, y = bezier(p0, p1, p2, p3, t)
        r = S * (0.007 + 0.021 * t ** 1.3)
        alpha = int(30 + 225 * t ** 1.1)
        td.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, alpha))
    halo = trail.filter(ImageFilter.GaussianBlur(S * 0.012))
    img = Image.alpha_composite(img, halo)
    img = Image.alpha_composite(img, trail)

    # Touch ripples where the finger lands.
    ripple = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ripple)
    cx, cy = p0
    for radius, alpha in ((S * 0.050, 230), (S * 0.088, 130), (S * 0.126, 60)):
        rd.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                   outline=(255, 255, 255, alpha), width=int(S * 0.009))
    core = S * 0.026
    rd.ellipse((cx - core, cy - core, cx + core, cy + core), fill=(255, 255, 255, 245))
    img = Image.alpha_composite(img, ripple)

    # Cursor arrow at the end of the trail.
    unit = S * 0.20
    shape = [(0, 0), (0, 1.0), (0.235, 0.775), (0.395, 1.12), (0.54, 1.05), (0.385, 0.72), (0.68, 0.72)]
    tip = (p3[0] - S * 0.012, p3[1] - S * 0.012)
    pts = [(tip[0] + x * unit, tip[1] + y * unit) for x, y in shape]

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + S * 0.012, y + S * 0.02) for x, y in pts], fill=(10, 8, 60, 150))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(S * 0.014)))

    cur = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cur)
    cd.polygon(pts, fill=(255, 255, 255, 255))
    cd.line(pts + [pts[0]], fill=(24, 16, 84, 255), width=int(S * 0.012), joint="curve")
    img = Image.alpha_composite(img, cur)
    return img


def mac_icon(art, size=1024):
    """Apple's macOS icon template: an ~80% rounded square with a soft shadow, transparent margin."""
    body = int(size * 0.8047)
    offset = (size - body) // 2
    shape = art.resize((body, body), Image.LANCZOS)
    mask = Image.new("L", (body * 4, body * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, body * 4 - 1, body * 4 - 1), radius=int(body * 4 * 0.2237), fill=255)
    mask = mask.resize((body, body), Image.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (offset, offset + int(size * 0.012)), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(size * 0.012)))
    canvas.paste(shape, (offset, offset), mask)
    return canvas


def write_catalog(folder, images, contents):
    os.makedirs(folder, exist_ok=True)
    for name, image in images.items():
        image.save(os.path.join(folder, name))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": contents, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    root = os.path.dirname(folder)
    with open(os.path.join(root, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


def main():
    art = draw_art()

    # iPhone/iPad: one full-bleed 1024 square, no transparency (iOS applies the corner mask).
    ios = art.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    write_catalog(
        "iOS/Glide/Assets.xcassets/AppIcon.appiconset",
        {"icon-1024.png": ios},
        [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    )

    # Mac: the full set of sizes.
    master = mac_icon(art, 1024)
    images, contents = {}, []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon-{points}@{scale}x.png"
            images[name] = master.resize((px, px), Image.LANCZOS)
            contents.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    write_catalog("Mac/GlideMac/Assets.xcassets/AppIcon.appiconset", images, contents)

    art.resize((512, 512), Image.LANCZOS).save("docs/icon-preview.png")
    master.resize((512, 512), Image.LANCZOS).save("docs/icon-preview-mac.png")
    print("Icon written.")


if __name__ == "__main__":
    main()
