#!/usr/bin/env python3
"""Split android/icon.png into an Android adaptive icon's two layers.

  make-adaptive-icon.py ICON.png OUT_DIR

Writes OUT_DIR/ic_launcher_background.png (the navy gradient) and
OUT_DIR/ic_launcher_foreground.png (the book, on transparency), both 432x432
(a 108dp canvas at 4x). Launchers cut the canvas to a circle, squircle or
rounded square of about 72dp, and only the middle 66dp circle is never cut,
so the book is scaled down to sit inside that.
"""
import sys
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
CANVAS = 432
SCALE = 0.70                 # the icon's size on the canvas, as a fraction of it

im = Image.open(SRC).convert("RGB")
w, h = im.size
px = im.load()

# The gradient is the same along each row: read it from the left edge.
bg_rows = [px[6, y] for y in range(h)]

fg = Image.new("RGBA", (w, h))
fpx = fg.load()
for y in range(h):
    br, bgc, bb = bg_rows[y]
    for x in range(w):
        r, g, b = px[x, y]
        d = max(abs(r - br), abs(g - bgc), abs(b - bb))
        a = max(0, min(255, (d - 4) * 255 // 24))     # the soft shadow stays, faintly
        fpx[x, y] = (r, g, b, a)

size = round(CANVAS * SCALE)
fg = fg.resize((size, size), Image.LANCZOS)
layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
layer.paste(fg, ((CANVAS - size) // 2, (CANVAS - size) // 2))
layer.save(OUT + "/ic_launcher_foreground.png")

bg = Image.new("RGB", (CANVAS, CANVAS))
bpx = bg.load()
for y in range(CANVAS):
    c = bg_rows[min(h - 1, y * h // CANVAS)]
    for x in range(CANVAS):
        bpx[x, y] = c
bg.save(OUT + "/ic_launcher_background.png")
