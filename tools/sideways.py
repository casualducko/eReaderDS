#!/usr/bin/env python3
"""Turn a raw 2048x768 frame into how it looks with the device held sideways.

    tools/sideways.py frame.png out.png [left|right]

The framebuffer puts the top screen at x 0..1023 and the bottom screen at
1024..2047. Stack them as they sit physically, then rotate the device.
"""
import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
orient = sys.argv[3] if len(sys.argv) > 3 else "left"
im = Image.open(src).convert("RGB")
top, bottom = im.crop((0, 0, 1024, 768)), im.crop((1024, 0, 2048, 768))
gap = 40
dev = Image.new("RGB", (1024, 768 * 2 + gap), (40, 40, 40))
dev.paste(top, (0, 0))
dev.paste(bottom, (0, 768 + gap))
dev = dev.rotate(90 if orient == "left" else -90, expand=True)
dev.thumbnail((1600, 1600))
dev.save(dst)
