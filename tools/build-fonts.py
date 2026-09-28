#!/usr/bin/env python3
"""Download extra bundled fonts from Google Fonts (all SIL OFL 1.1) into
app/fonts as regular / italic / bold / bold-italic files.

Fonts published only as variable fonts are cut into static instances at
weight 400 and 700 (eReaderDS picks faces by family and style name), like
Bitter and Atkinson Hyperlegible Next.

    tools/build-fonts.py        (needs fontTools: pip install fonttools)
"""
import io
import os
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "app", "fonts")
BASE = "https://github.com/google/fonts/raw/main/ofl/"

STYLES = [("Regular", False, 400), ("Italic", True, 400), ("Bold", False, 700), ("BoldItalic", True, 700)]

# family: (Google Fonts folder, file stem, {style: file} for static fonts or
# (upright, italic) variable files, extra axis values)
FAMILIES = {
    "EB Garamond": ("ebgaramond", "EBGaramond", ("EBGaramond[wght].ttf", "EBGaramond-Italic[wght].ttf"), {}),
    "Lora": ("lora", "Lora", ("Lora[wght].ttf", "Lora-Italic[wght].ttf"), {}),
    "Merriweather": ("merriweather", "Merriweather",
                     ("Merriweather[opsz,wdth,wght].ttf", "Merriweather-Italic[opsz,wdth,wght].ttf"),
                     {"opsz": 18, "wdth": 100}),
    "Vollkorn": ("vollkorn", "Vollkorn", ("Vollkorn[wght].ttf", "Vollkorn-Italic[wght].ttf"), {}),
    "Spectral": ("spectral", "Spectral", {s: "Spectral-%s.ttf" % s for s, _, _ in STYLES}, {}),
    "PT Serif": ("ptserif", "PTSerif", {s: "PT_Serif-Web-%s.ttf" % s for s, _, _ in STYLES}, {}),
    "Andika": ("andika", "Andika", {s: "Andika-%s.ttf" % s for s, _, _ in STYLES}, {}),
}


def fetch(url):
    with urllib.request.urlopen(url) as r:
        return r.read()


def set_names(font, family, style, italic, weight):
    """Family / style names, weight and style bits for one static face."""
    label = {"Regular": "Regular", "Italic": "Italic", "Bold": "Bold", "BoldItalic": "Bold Italic"}[style]
    name = font["name"]
    for nid in (16, 17, 21, 22, 25):
        name.removeNames(nameID=nid)
    ps = (family.replace(" ", "") + "-" + style)
    for nid, value in ((1, family), (2, label), (3, ps), (4, family + " " + label if label != "Regular" else family),
                       (6, ps)):
        name.setName(value, nid, 3, 1, 0x409)
        name.setName(value, nid, 1, 0, 0)
    os2 = font["OS/2"]
    os2.usWeightClass = weight
    sel = os2.fsSelection & ~0b1100001      # clear italic, bold, regular
    if italic:
        sel |= 1
    if weight >= 700:
        sel |= 1 << 5
    if not italic and weight < 700:
        sel |= 1 << 6
    os2.fsSelection = sel
    font["head"].macStyle = (1 if weight >= 700 else 0) | (2 if italic else 0)


def main():
    for family, (folder, stem, files, axes) in FAMILIES.items():
        print(family)
        if isinstance(files, dict):
            for style, italic, weight in STYLES:
                font = TTFont(io.BytesIO(fetch(BASE + folder + "/" + files[style])))
                set_names(font, family, style, italic, weight)
                font.save(os.path.join(OUT, "%s-%s.ttf" % (stem, style)))
        else:
            varfonts = [fetch(BASE + folder + "/" + f.replace("[", "%5B").replace("]", "%5D")) for f in files]
            for style, italic, weight in STYLES:
                font = TTFont(io.BytesIO(varfonts[1 if italic else 0]))
                location = dict(axes, wght=weight)
                location = {k: v for k, v in location.items() if k in [a.axisTag for a in font["fvar"].axes]}
                font = instantiateVariableFont(font, location, updateFontNames=False)
                set_names(font, family, style, italic, weight)
                font.save(os.path.join(OUT, "%s-%s.ttf" % (stem, style)))
        with open(os.path.join(OUT, stem + "-OFL.txt"), "wb") as f:
            f.write(fetch(BASE + folder + "/OFL.txt"))


if __name__ == "__main__":
    main()
