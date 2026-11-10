#!/usr/bin/env python3
"""Écran titre en pixel art (original, procédural) : ciel de nuit violet,
étoiles, planète, nuages, îles flottantes avec cascades, château de cristal
et rayon de lumière ; et le logo « LEGENDERS » dessiné avec la police du jeu.

Usage : python3 tools/make_title.py   →  assets/ui/title_bg.png, title_logo.png
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "ui")
W, H = 480, 270


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def sky(img):
    stops = [(0.0, hexc("120c3c")), (0.45, hexc("2b1e78")), (0.75, hexc("5b45c2")), (1.0, hexc("9a7ae0"))]
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                # Tramage en bandes (pixel art) plutôt qu'un dégradé lisse.
                k = round(k * 6) / 6
                c = mix(stops[i][1], stops[i + 1][1], k)
                break
        for x in range(W):
            px[x, y] = c


def stars(img, rng):
    px = img.load()
    for _ in range(140):
        x, y = rng.randrange(W), rng.randrange(int(H * 0.6))
        b = rng.choice([hexc("ffffff"), hexc("d9ccff"), hexc("fff2b0")])
        px[x, y] = b
        if rng.random() < 0.12 and 1 < x < W - 2 and 1 < y < H - 2:
            for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                px[x + dx, y + dy] = mix(b, px[x + dx, y + dy], 0.5)


def planet(d, cx, cy, r):
    for i in range(r, 0, -1):
        t = i / r
        d.ellipse([cx - i, cy - i, cx + i, cy + i], fill=mix(hexc("6a58c8"), hexc("2c2275"), 1 - t))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=hexc("9a88f0"))
    # Croissant éclairé.
    d.chord([cx - r, cy - r, cx + r, cy + r], 200, 330, fill=hexc("8c78e6"))


def cloud(d, rng, cx, cy, w, tone):
    light, mid, dark = tone
    n = max(3, w // 14)
    blobs = []
    for i in range(n):
        x = cx - w // 2 + int(i * w / n) + rng.randrange(-4, 5)
        r = rng.randrange(8, 16)
        blobs.append((x, cy - rng.randrange(0, 8), r))
    for x, y, r in blobs:
        d.ellipse([x - r, y - r + 3, x + r, y + r + 3], fill=dark)
    for x, y, r in blobs:
        d.ellipse([x - r, y - r, x + r, y + r - 2], fill=mid)
    for x, y, r in blobs:
        d.ellipse([x - r + 3, y - r, x + r - 5, y + r - 8], fill=light)
    d.rectangle([cx - w // 2, cy + 2, cx + w // 2, cy + 10], fill=dark)


def island(d, rng, cx, cy, w, waterfall=False):
    h = int(w * 0.75)
    # Rocher en pointe.
    pts = [(cx - w // 2, cy)]
    steps = 7
    for i in range(1, steps):
        t = i / steps
        x = cx - w // 2 + int(w * t)
        depth = int(h * (1 - abs(t - 0.5) * 2) ** 0.8) + rng.randrange(-3, 4)
        pts.append((x, cy + max(4, depth)))
    pts.append((cx + w // 2, cy))
    d.polygon(pts, fill=hexc("5a3f6e"))
    d.polygon([(x, y) for x, y in pts[:len(pts) // 2 + 1]] + [(cx, cy)], fill=hexc("7a5684"))
    for i in range(4):
        x = cx - w // 3 + rng.randrange(0, w * 2 // 3)
        d.line([(x, cy + 3), (x + rng.randrange(-2, 3), cy + h // 3)], fill=hexc("3e2a52"))
    # Herbe.
    d.ellipse([cx - w // 2 - 2, cy - 5, cx + w // 2 + 2, cy + 4], fill=hexc("2f8a4a"))
    d.ellipse([cx - w // 2, cy - 6, cx + w // 2, cy + 1], fill=hexc("4fb85e"))
    for i in range(w // 8):
        x = cx - w // 2 + rng.randrange(0, w)
        d.point((x, cy - 6), fill=hexc("9be07a"))
    # Petits arbres.
    for i in range(max(1, w // 30)):
        x = cx - w // 3 + rng.randrange(0, w * 2 // 3)
        d.ellipse([x - 4, cy - 14, x + 4, cy - 4], fill=hexc("2c6e44"))
        d.ellipse([x - 3, cy - 13, x + 2, cy - 7], fill=hexc("3f9a52"))
    if waterfall:
        x = cx + rng.randrange(-w // 4, w // 4)
        for y in range(cy, min(H, cy + h + 60)):
            a = 255 if y < cy + h + 30 else max(0, 255 - (y - cy - h - 30) * 8)
            d.line([(x, y), (x + 2, y)], fill=hexc("bfe8ff", a))
            if y % 3 == 0:
                d.point((x + 1, y), fill=hexc("ffffff", a))


def castle(d, cx, base):
    stone, shade, light, roof, win = hexc("d8ccf2"), hexc("a596d6"), hexc("f4efff"), hexc("8c7ce0"), hexc("6fd4ff")

    def tower(x, w, h, spire):
        d.rectangle([x - w // 2, base - h, x + w // 2, base], fill=stone)
        d.rectangle([x + w // 2 - max(1, w // 4), base - h, x + w // 2, base], fill=shade)
        d.rectangle([x - w // 2, base - h, x - w // 2 + 1, base], fill=light)
        for yy in range(base - h + 6, base - 4, 9):
            d.rectangle([x - 1, yy, x, yy + 3], fill=win)
        d.polygon([(x - w // 2 - 2, base - h), (x + w // 2 + 2, base - h), (x, base - h - spire)], fill=roof)
        d.line([(x, base - h - spire), (x, base - h - spire - 4)], fill=hexc("ffe9a0"))

    tower(cx - 46, 12, 52, 20)
    tower(cx + 46, 12, 56, 22)
    tower(cx - 26, 14, 78, 26)
    tower(cx + 26, 14, 72, 24)
    tower(cx, 22, 118, 40)
    # Rempart.
    d.rectangle([cx - 54, base - 26, cx + 54, base], fill=stone)
    d.rectangle([cx - 54, base - 8, cx + 54, base], fill=shade)
    for x in range(cx - 54, cx + 54, 6):
        d.rectangle([x, base - 30, x + 3, base - 26], fill=stone)
    d.rectangle([cx - 6, base - 18, cx + 6, base], fill=hexc("3a2a70"))
    d.ellipse([cx - 6, base - 24, cx + 6, base - 12], fill=hexc("3a2a70"))


def beam(img, cx, top, bottom):
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for w, a in [(9, 40), (5, 80), (2, 200)]:
        d.rectangle([cx - w // 2, 0, cx + w // 2, bottom], fill=hexc("b8f0ff", a))
    # Anneau de lumière autour de la flèche.
    d.ellipse([cx - 60, top - 8, cx + 60, top + 10], outline=hexc("c9e8ff", 150))
    d.ellipse([cx - 58, top - 7, cx + 58, top + 9], outline=hexc("ffffff", 60))
    img.alpha_composite(over)


def make_bg():
    rng = random.Random(11)
    img = Image.new("RGBA", (W, H))
    sky(img)
    stars(img, rng)
    d = ImageDraw.Draw(img)
    planet(d, 360, 44, 22)
    far = (hexc("8f7ad8"), hexc("6e5ac0"), hexc("54439e"))
    near = (hexc("f2ecff"), hexc("cfc2f4"), hexc("9c8ad8"))
    for i in range(6):
        cloud(d, rng, rng.randrange(0, W), rng.randrange(130, 190), rng.randrange(50, 110), far)
    # Îles lointaines.
    for x, y, w in [(60, 150, 30), (420, 120, 36), (110, 95, 22), (330, 160, 26), (470, 200, 30)]:
        island(d, rng, x, y, w, waterfall=rng.random() < 0.4)
    # Grande île du château.
    cx = 300
    beam(img, cx, 72, 150)
    d = ImageDraw.Draw(img)
    castle(d, cx, 196)
    island(d, rng, cx, 198, 170, waterfall=True)
    island(d, rng, 190, 214, 50, waterfall=True)
    for i in range(5):
        cloud(d, rng, rng.randrange(-20, W + 20), rng.randrange(228, 262), rng.randrange(70, 150), near)
    img.save(os.path.join(OUT, "title_bg.png"))


def make_logo():
    font_path = os.path.join(ROOT, "assets", "fonts", "PixelifySans.ttf")
    font = ImageFont.truetype(font_path, 64)
    try:
        font.set_variation_by_axes([700])
    except Exception:
        pass
    text = "LEGENDERS"
    box = font.getbbox(text)
    tw, th = box[2] - box[0], box[3] - box[1]
    pad = 18
    w, h = tw + pad * 2, th + pad * 2 + 34
    # Lettres : masque, puis dégradé vertical blanc → lavande → violet.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((pad - box[0], pad - box[1] + 14), text, font=font, fill=255)
    grad = Image.new("RGBA", (w, h))
    gp = grad.load()
    for y in range(h):
        t = max(0.0, min(1.0, (y - pad - 14) / max(1, th)))
        c = mix(hexc("ffffff"), hexc("c9b4ff"), min(1.0, t * 1.6)) if t < 0.6 else mix(hexc("c9b4ff"), hexc("7a52e0"), (t - 0.6) / 0.4)
        for x in range(w):
            gp[x, y] = c
    logo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Contours : violet sombre épais, puis liseré doré.
    for r, col in [(6, hexc("1a0c40")), (4, hexc("e8a830")), (2, hexc("3a1c80"))]:
        m = mask.filter(ImageFilter.MaxFilter(r * 2 + 1))
        layer = Image.new("RGBA", (w, h), col)
        logo.paste(layer, (0, 0), m)
    logo.paste(grad, (0, 0), mask)
    # Petit astre doré au-dessus.
    d = ImageDraw.Draw(logo)
    cx = w // 2
    d.polygon([(cx, 0), (cx + 5, 10), (cx + 16, 12), (cx + 5, 15), (cx, 26), (cx - 5, 15), (cx - 16, 12), (cx - 5, 10)], fill=hexc("ffc84a"), outline=hexc("6a3a08"))
    d.point((cx, 8), fill=hexc("ffffff"))
    # Bannière sous le titre.
    by = h - 26
    d.rectangle([cx - 120, by, cx + 120, by + 18], fill=hexc("2a1660"), outline=hexc("e8a830"))
    d.polygon([(cx - 120, by), (cx - 132, by + 9), (cx - 120, by + 18)], fill=hexc("e8a830"))
    d.polygon([(cx + 120, by), (cx + 132, by + 9), (cx + 120, by + 18)], fill=hexc("e8a830"))
    small = ImageFont.truetype(font_path, 13)
    try:
        small.set_variation_by_axes([600])
    except Exception:
        pass
    sub = "LE JEU DE RÔLE ENTRE AMIS"
    sb = small.getbbox(sub)
    d.text((cx - (sb[2] - sb[0]) // 2 - sb[0], by + 2 - sb[1] + 1), sub, font=small, fill=hexc("ffd36a"))
    logo.save(os.path.join(OUT, "title_logo.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_bg()
    make_logo()
    print("écran titre écrit dans", os.path.normpath(OUT))
