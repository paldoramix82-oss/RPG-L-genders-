#!/usr/bin/env python3
"""Cadres de l'interface en pixel art (assets/ui) : panneaux indigo à bord
violet lumineux et coins ornés, boutons, bouton doré (choix en cours),
cases d'inventaire, étiquette de nom, bannière dorée. Dessinés à l'échelle 1
puis agrandis ×2 (pixels nets), utilisés en « 9-patch » par le thème.

Usage : python3 tools/make_ui.py
"""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
K = 2  # agrandissement (un pixel du dessin = 2 pixels écran)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def lerp(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(4))


def frame(w, h, fill_top, fill_bottom, border, inner, outline="0b0720", corner=None, glow=None, notch=2):
    """Cadre : contour sombre, bord clair, liseré intérieur, fond en dégradé,
    coins coupés (notch) et ornement de coin optionnel (losange)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    ft, fb, bd, inn, ol = hexc(fill_top), hexc(fill_bottom), hexc(border), hexc(inner), hexc(outline)
    gl = hexc(glow, 110) if glow else None

    def inside(x, y, m):
        # Rectangle à coins coupés, rentré de m pixels.
        x0, y0, x1, y1 = m, m, w - 1 - m, h - 1 - m
        if x < x0 or y < y0 or x > x1 or y > y1:
            return False
        c = max(0, notch - m) if notch > m else 0
        c = notch
        dx = min(x - x0, x1 - x)
        dy = min(y - y0, y1 - y)
        return dx + dy >= c

    for y in range(h):
        for x in range(w):
            if inside(x, y, 3):
                px[x, y] = lerp(ft, fb, y / max(1, h - 1))
            elif inside(x, y, 2):
                px[x, y] = inn
            elif inside(x, y, 1):
                px[x, y] = bd
            elif inside(x, y, 0):
                px[x, y] = ol
    if gl:
        # Lueur : un pixel translucide autour du bord (à l'intérieur du contour).
        for y in range(h):
            for x in range(w):
                if inside(x, y, 3) and not inside(x, y, 4):
                    px[x, y] = lerp(px[x, y], gl, 0.45)
    # Reflet en haut.
    for x in range(notch + 3, w - notch - 3):
        px[x, 3] = lerp(px[x, 3], (255, 255, 255, 255), 0.12)
    if corner:
        cc, cl = hexc(corner[0]), hexc(corner[1])
        for (cx, cy) in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]:
            for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
                if 0 <= cx + dx < w and 0 <= cy + dy < h:
                    px[cx + dx, cy + dy] = cc
            px[cx, cy] = cl
    return img


def save(img, name):
    img = img.resize((img.width * K, img.height * K), Image.NEAREST)
    img.save(os.path.join(OUT, name + ".png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    S = 24  # taille du dessin (9-patch : 8 px de bord de chaque côté)
    # Panneaux.
    save(frame(S, S, "2a1f63", "1b1444", "8c6cff", "4b38a6", corner=("b48cff", "ffffff"), glow="8c6cff", notch=3), "panel")
    save(frame(S, S, "160f38", "120b2e", "3e2f86", "241a57", notch=2), "panel_inset")
    save(frame(S, S, "2c1f5c", "1d1442", "e7b24a", "7a5a2a", corner=("ffd76a", "fff6c8"), glow="e7b24a", notch=3), "panel_gold")
    save(frame(S, S, "3a2380", "251557", "b48cff", "6a4bc4", corner=("d9c2ff", "ffffff"), glow="b48cff", notch=3), "panel_magic")
    save(frame(S, S, "3b1630", "240d1d", "e0566a", "7a2b3a", corner=("ff8fa0", "ffffff"), notch=3), "panel_danger")
    save(frame(S, S, "1d1548", "120c30", "5a46b8", "2c2170", notch=0), "bar")
    # Bannière dorée (quête mise à jour) : fond or, texte sombre.
    save(frame(S, S, "f8c44c", "d68c1c", "fff0b0", "b8741a", outline="3a2008", corner=("fff6c8", "ffffff"), notch=3), "banner_gold")
    # Boutons.
    save(frame(S, S, "2e2470", "221a58", "5d49c0", "3a2d8a", notch=2), "button")
    save(frame(S, S, "3a2e8a", "2a2068", "9a7cff", "5040b0", notch=2), "button_hover")
    save(frame(S, S, "f9c84e", "e0961e", "fff3b8", "b06e12", outline="3a2008", notch=2), "button_gold")
    save(frame(S, S, "ffd86a", "eaa630", "fffbe0", "c07c18", outline="3a2008", notch=2), "button_gold_hover")
    save(frame(S, S, "c98a1c", "a86c10", "e8c060", "7a4a08", outline="3a2008", notch=2), "button_gold_pressed")
    save(frame(S, S, "1a1440", "15102f", "3a2f6e", "241c4c", notch=2), "button_disabled")
    save(frame(S, S, "4a1a2a", "33101c", "e0566a", "7a2b3a", notch=2), "button_danger")
    # Cases d'inventaire.
    save(frame(S, S, "1e1650", "150f3a", "4c3aa8", "2a2070", notch=3), "slot")
    save(frame(S, S, "3a2a70", "241a50", "ffd24a", "c08a1a", outline="3a2008", glow="ffd24a", notch=3), "slot_selected")
    # Étiquette de nom (dialogues) : rose-rouge.
    save(frame(S, S, "e2455e", "b82a44", "ff9aaa", "8a1c30", outline="2a0810", notch=2), "name_tag")
    # Champ de saisie.
    save(frame(S, S, "120c2e", "100a28", "4c3aa8", "1d1546", notch=2), "field")
    save(frame(S, S, "140e34", "120b2e", "ffd24a", "5a4520", notch=2), "field_focus")
    print("cadres écrits dans", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
