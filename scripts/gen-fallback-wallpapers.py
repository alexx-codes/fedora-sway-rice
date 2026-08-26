#!/usr/bin/env python3
"""Generate the committed fallback wallpapers (wallpapers/night.png, day.png).

These are minimal palette-matched gradients with a little cat silhouette, so
the rice works out of the box. Drop your real art in as wallpapers/night.jpg
and day.jpg — .jpg is preferred over .png at runtime, so the fallbacks
simply stop being used. Requires: pip install pillow.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1440
OUT = Path(__file__).resolve().parent.parent / "wallpapers"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(stops):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    n = len(stops) - 1
    for y in range(H):
        t = y / (H - 1)
        seg = min(int(t * n), n - 1)
        local = t * n - seg
        d.line([(0, y), (W, y)], fill=lerp(stops[seg], stops[seg + 1], local))
    return img


def glow(img, xy, radius, color, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = xy
    d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    img.paste(Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB"))


def cat(draw, cx, base_y, s, color):
    """Minimal sitting-cat silhouette: body, head, ears, tail."""
    draw.ellipse([cx - 0.62 * s, base_y - 1.05 * s, cx + 0.62 * s, base_y], fill=color)  # body
    hy = base_y - 1.28 * s
    draw.ellipse([cx - 0.40 * s, hy - 0.40 * s, cx + 0.40 * s, hy + 0.40 * s], fill=color)  # head
    for sx in (-1, 1):  # ears
        ex = cx + sx * 0.26 * s
        draw.polygon(
            [(ex - 0.16 * s, hy - 0.28 * s), (ex + 0.16 * s, hy - 0.28 * s), (ex + sx * 0.06 * s, hy - 0.62 * s)],
            fill=color,
        )
    draw.arc(  # tail
        [cx + 0.30 * s, base_y - 0.85 * s, cx + 1.35 * s, base_y + 0.05 * s],
        start=270, end=90, fill=color, width=max(3, int(0.13 * s)),
    )


def night():
    img = vgrad([(13, 13, 23), (26, 27, 38), (36, 40, 59), (55, 44, 78)])
    import random

    rnd = random.Random(7)
    d = ImageDraw.Draw(img)
    for _ in range(240):  # stars, denser near the top
        x, y = rnd.randrange(W), int(abs(rnd.gauss(0, 0.33)) * H) % H
        r = rnd.choice([1, 1, 1, 2])
        c = rnd.choice([(192, 202, 245), (187, 154, 247), (255, 154, 193)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    glow(img, (int(W * 0.78), int(H * 0.22)), 130, (187, 154, 247), 70)   # moon glow
    d = ImageDraw.Draw(img)
    d.ellipse([int(W * 0.78) - 46, int(H * 0.22) - 46, int(W * 0.78) + 46, int(H * 0.22) + 46], fill=(230, 225, 250))
    cat(d, int(W * 0.18), int(H * 0.93), 150, (10, 10, 18))
    img.save(OUT / "night.png", optimize=True)


def day():
    img = vgrad([(205, 180, 219), (231, 201, 233), (255, 215, 232), (255, 244, 236)])
    for cx, cy, s in [(0.22, 0.28, 1.0), (0.60, 0.16, 1.2), (0.86, 0.40, 0.8), (0.42, 0.50, 0.9)]:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        x, y = int(cx * W), int(cy * H)
        # puffy cloud: overlapping solid ellipses, then one soft blur pass
        for dx, dy, rw, rh in [(-130, 10, 130, 55), (0, -25, 150, 70), (130, 10, 130, 55), (0, 25, 190, 55)]:
            ld.ellipse(
                [x + dx * s - rw * s, y + dy * s - rh * s, x + dx * s + rw * s, y + dy * s + rh * s],
                fill=(255, 251, 250, 200),
            )
        layer = layer.filter(ImageFilter.GaussianBlur(18))
        img.paste(Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB"))
    d = ImageDraw.Draw(img)
    cat(d, int(W * 0.18), int(H * 0.93), 150, (120, 95, 140))
    img.save(OUT / "day.png", optimize=True)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    night()
    day()
    print("wrote wallpapers/night.png and wallpapers/day.png")
