#!/usr/bin/env python3
"""Generate EncoreMoment's app icon (original artwork, no third-party assets).

Design "Stage Lights": colorful spotlight beams sweeping over a concert crowd
with confetti — a fun, event-forward mark for a platform built around live
events. Rendered at high resolution and downscaled for clean, anti-aliased edges
and saved as a flat RGB PNG (no alpha) for the App Store icon slot.
"""
import os
import random
from PIL import Image, ImageDraw, ImageFilter

OUT = "App/EncoreMoment/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
SS = 4
FINAL = 1024
S = FINAL * SS
CX = S / 2

CONFETTI = [(244, 114, 182), (251, 191, 36), (34, 211, 238),
            (52, 211, 153), (251, 146, 60), (167, 139, 250), (248, 113, 113)]


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(top, bottom):
    strip = Image.new("RGB", (1, 512))
    sp = strip.load()
    for i in range(512):
        sp[0, i] = lerp(top, bottom, i / 511)
    return strip.resize((S, S), Image.BILINEAR).convert("RGBA")


def radial_glow(cx, cy, r, color, alpha=255):
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    return g.filter(ImageFilter.GaussianBlur(r * 0.5))


def confetti(img, rng, n, ymin, ymax, xmin=0.08, xmax=0.92, size=0.022):
    for _ in range(n):
        x = rng.uniform(S * xmin, S * xmax)
        y = rng.uniform(S * ymin, S * ymax)
        s = S * size * rng.uniform(0.6, 1.4)
        col = rng.choice(CONFETTI)
        bit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bit)
        if rng.random() < 0.4:
            bd.ellipse([x - s / 2, y - s / 2, x + s / 2, y + s / 2], fill=col + (255,))
        else:
            bd.rounded_rectangle([x - s / 2, y - s * 0.32, x + s / 2, y + s * 0.32],
                                 radius=s * 0.15, fill=col + (255,))
            bit = bit.rotate(rng.uniform(0, 360), center=(x, y), resample=Image.BICUBIC)
        img.alpha_composite(bit)


def make():
    rng = random.Random(7)
    base = gradient((76, 29, 149), (10, 8, 35))

    # spotlight beams from two rigs at the top
    beams = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rigs = [(S * 0.26, S * 0.10), (S * 0.74, S * 0.10)]
    cols = [(34, 211, 238), (244, 114, 182), (251, 191, 36)]
    for (ax, ay) in rigs:
        for k, col in enumerate(cols):
            spread = (k - 1) * S * 0.16
            bx = ax + spread + (S * 0.5 - ax) * 0.5
            tri = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            ImageDraw.Draw(tri).polygon(
                [(ax, ay), (bx - S * 0.09, S * 0.72), (bx + S * 0.09, S * 0.72)],
                fill=col + (60,))
            beams.alpha_composite(tri)
    beams = beams.filter(ImageFilter.GaussianBlur(S * 0.006))
    base.alpha_composite(beams)

    confetti(base, rng, 26, 0.06, 0.55)

    # light rigs with glow
    d = ImageDraw.Draw(base)
    for (ax, ay) in rigs:
        d.ellipse([ax - S * 0.03, ay - S * 0.03, ax + S * 0.03, ay + S * 0.03],
                  fill=(255, 255, 240, 255))
        base.alpha_composite(radial_glow(ax, ay, S * 0.06, (255, 255, 220), 180))

    # stage + crowd silhouette
    d = ImageDraw.Draw(base)
    d.rectangle([0, S * 0.80, S, S], fill=(8, 6, 24, 255))
    d.rounded_rectangle([S * 0.10, S * 0.76, S * 0.90, S * 0.82], radius=S * 0.02,
                        fill=(20, 14, 50, 255))
    crowd = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crowd)
    for i, xf in enumerate([0.18, 0.31, 0.44, 0.57, 0.70, 0.83]):
        hx = S * xf
        hy = S * (0.80 - (0.01 if i % 2 else 0.0))
        cd.ellipse([hx - S * 0.045, hy - S * 0.045, hx + S * 0.045, hy + S * 0.045],
                   fill=(4, 3, 14, 255))
        cd.line([(hx - S * 0.03, hy), (hx - S * 0.06, hy - S * 0.10)],
                fill=(4, 3, 14, 255), width=int(S * 0.018))
        cd.line([(hx + S * 0.03, hy), (hx + S * 0.06, hy - S * 0.10)],
                fill=(4, 3, 14, 255), width=int(S * 0.018))
    base.alpha_composite(crowd)

    out = base.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("wrote", OUT, out.size, out.mode)


if __name__ == "__main__":
    make()
