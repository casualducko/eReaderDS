#!/usr/bin/env python3
"""Draw the Ports menu icon: the device's two screens as an open book, with
"eReaderDS" below. Needs Pillow and Literata's variable font (OFL), from
https://github.com/google/fonts/tree/main/ofl/literata

    port/art/make-icon.py Literata[opsz,wght].ttf

Writes icon-full.png (1280x1160) and eReaderDS.png (320x290, the menu size).
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1280, 1160
S = 0.8                                  # scale of the book


def page(side):
    """One screen: dark bezel, sepia page, lines of text."""
    sw, sh = round(520 * S), round(700 * S)
    im = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    g = ImageDraw.Draw(im)
    g.rounded_rectangle((0, 0, sw - 1, sh - 1), radius=round(46 * S), fill=(28, 31, 38, 255))
    m = round(34 * S)
    g.rounded_rectangle((m, m, sw - m, sh - m), radius=round(18 * S), fill=(244, 234, 214, 255))
    ink, bar, step = (120, 98, 76, 255), round(16 * S), round(36 * S)
    x0, x1 = m + round(44 * S), sw - m - round(44 * S)
    y = m + round(60 * S)
    if side == "left":                   # chapter title
        g.rounded_rectangle((x0 + round(90 * S), y, x1 - round(90 * S), y + round(30 * S)),
                            radius=round(15 * S), fill=(92, 72, 54, 255))
        y += round(84 * S)
    for i in range(12 if side == "left" else 14):
        indent = round(26 * S) if i % 5 == 0 else 0
        end = x1 - (round(70 * S) if i % 5 == 4 else 0)
        g.rounded_rectangle((x0 + indent, y, end, y + bar), radius=bar // 2, fill=ink)
        y += step
    return im


def main(font_path):
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):                   # deep navy, lighter towards the bottom
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(40 + 18 * t), int(52 + 14 * t), int(78 + 10 * t)))

    left, right = page("left"), page("right")
    cx, top = W // 2, 150
    gap, overlap = round(30 * S), round(8 * S)

    shadow = Image.new("L", (W, H), 0)
    sy = top + left.height + 40
    ImageDraw.Draw(shadow).ellipse((cx - 400, sy - 30, cx + 400, sy + 50), fill=150)
    bg.paste((18, 24, 38), (0, 0), shadow.filter(ImageFilter.GaussianBlur(26)))

    bg.paste(left, (cx - gap - left.width + overlap, top), left)
    bg.paste(right, (cx + gap - overlap, top), right)
    d = ImageDraw.Draw(bg)
    # Hinge, like a book's spine.
    d.rounded_rectangle((cx - gap, top + 16, cx + gap, top + left.height - 16), radius=gap, fill=(20, 22, 28))
    d.rounded_rectangle((cx - round(12 * S), top + 40, cx + round(12 * S), top + left.height - 40),
                        radius=round(12 * S), fill=(52, 56, 66))
    # Bookmark ribbon on the right page.
    rx = cx + gap - overlap + right.width - round(34 * S) - round(100 * S)
    rw, rt, rb = round(54 * S), top + round(34 * S), top + round(210 * S)
    d.polygon([(rx, rt), (rx + rw, rt), (rx + rw, rb), (rx + rw // 2, rb - round(28 * S)), (rx, rb)],
              fill=(206, 62, 58))

    # The name, in Literata Medium (optical size 24: sturdy at the menu size).
    font = ImageFont.truetype(font_path, 150)
    font.set_variation_by_axes([24, 500])
    d.text((cx, 935), "eReaderDS", font=font, fill=(255, 255, 255), anchor="mm")

    bg.save(os.path.join(HERE, "icon-full.png"))
    bg.resize((320, 290), Image.LANCZOS).save(os.path.join(HERE, "eReaderDS.png"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
