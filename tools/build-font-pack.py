#!/usr/bin/env python3
"""Build the downloadable font pack: extra reading fonts for "Get more fonts".

Each family becomes a zip of regular / italic / bold / bold-italic TrueType
files plus its licence (all SIL Open Font License 1.1, from Google Fonts),
and a preview image of its name set in the font. catalog.json lists them.
Commit the fontpack folder; the app downloads from it on GitHub:

    tools/build-font-pack.py
    git add fontpack && git commit -m "Font pack" && git push

Variable-only families are cut into static instances like the bundled fonts
(see build-fonts.py). Needs fontTools and Pillow.
"""
import io
import json
import os
import sys
import zipfile

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
build_fonts = __import__("build-fonts")
fetch, set_names, STYLES = build_fonts.fetch, build_fonts.set_names, build_fonts.STYLES

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "fontpack")
# A fixed snapshot of github.com/google/fonts, so the pack can be rebuilt exactly.
COMMIT = "23e54b51ddffbc7713c583748e3bd86f62b1fa4a"
BASE = "https://github.com/google/fonts/raw/%s/ofl/" % COMMIT


def static(prefix, styles=("Regular", "Italic", "Bold", "BoldItalic")):
    return {s: "%s-%s.ttf" % (prefix, s) for s in styles}


# name: (folder, file stem, files, extra axes, kind, about)
FAMILIES = [
    ("Alegreya", "alegreya", "Alegreya", ("Alegreya[wght].ttf", "Alegreya-Italic[wght].ttf"), {}, "serif",
     "Lively and calligraphic, made for long literary reading."),
    ("Cardo", "cardo", "Cardo", static("Cardo", ("Regular", "Italic", "Bold")), {}, "serif",
     "An old-style book face in the spirit of Renaissance printing."),
    ("Crimson Pro", "crimsonpro", "CrimsonPro", ("CrimsonPro[wght].ttf", "CrimsonPro-Italic[wght].ttf"), {}, "serif",
     "A classic Garamond-like text face, crisp and even."),
    ("Gelasio", "gelasio", "Gelasio", ("Gelasio[wght].ttf", "Gelasio-Italic[wght].ttf"), {}, "serif",
     "Sturdy and friendly, in the manner of Georgia."),
    ("IBM Plex Serif", "ibmplexserif", "IBMPlexSerif", static("IBMPlexSerif"), {}, "serif",
     "Clean and modern, with a slightly technical character."),
    ("Libre Baskerville", "librebaskerville", "LibreBaskerville",
     ("LibreBaskerville[wght].ttf", "LibreBaskerville-Italic[wght].ttf"), {}, "serif",
     "A Baskerville cut for screens: open, tall and elegant."),
    ("Newsreader", "newsreader", "Newsreader", ("Newsreader[opsz,wght].ttf", "Newsreader-Italic[opsz,wght].ttf"),
     {"opsz": 16}, "serif", "Designed for reading long stretches of text on screens."),
    ("Noticia Text", "noticiatext", "NoticiaText", static("NoticiaText"), {}, "serif",
     "A warm text face with strong, clear letters."),
    ("Zilla Slab", "zillaslab", "ZillaSlab", static("ZillaSlab"), {}, "serif",
     "A slab serif: friendly, bold and very readable."),
    ("Alegreya Sans", "alegreyasans", "AlegreyaSans", static("AlegreyaSans"), {}, "sans",
     "The sans companion to Alegreya, with a humanist hand."),
    ("Fira Sans", "firasans", "FiraSans", static("FiraSans"), {}, "sans",
     "Open and legible, made for small screens."),
    ("IBM Plex Sans", "ibmplexsans", "IBMPlexSans", ("IBMPlexSans[wdth,wght].ttf", "IBMPlexSans-Italic[wdth,wght].ttf"),
     {"wdth": 100}, "sans", "Neutral and precise, with a gentle warmth."),
    ("Lato", "lato", "Lato", static("Lato"), {}, "sans",
     "Smooth and balanced; one of the most popular sans-serifs."),
    ("Source Sans 3", "sourcesans3", "SourceSans3", ("SourceSans3[wght].ttf", "SourceSans3-Italic[wght].ttf"), {},
     "sans", "Adobe's first open source typeface, clear and quiet."),
]


def faces(folder, stem, files, axes, family):
    """[(file name, TTFont)] for each style the family has."""
    out = []
    if isinstance(files, dict):
        for style, italic, weight in STYLES:
            if style in files:
                font = TTFont(io.BytesIO(fetch(BASE + folder + "/" + files[style])))
                set_names(font, family, style, italic, weight)
                out.append(("%s-%s.ttf" % (stem, style), font))
    else:
        var = [fetch(BASE + folder + "/" + f.replace("[", "%5B").replace("]", "%5D")) for f in files]
        for style, italic, weight in STYLES:
            font = TTFont(io.BytesIO(var[1 if italic else 0]))
            tags = [a.axisTag for a in font["fvar"].axes]
            location = {k: v for k, v in dict(axes, wght=weight).items() if k in tags}
            font = instantiateVariableFont(font, location, updateFontNames=False)
            set_names(font, family, style, italic, weight)
            out.append(("%s-%s.ttf" % (stem, style), font))
    return out


def preview(ttf_bytes, text, path):
    """The family's name set in its regular face: white on transparent (the app tints it
    to the theme's text colour)."""
    font = ImageFont.truetype(io.BytesIO(ttf_bytes), 64)
    box = font.getbbox(text)
    im = Image.new("LA", (box[2] - box[0] + 8, box[3] - box[1] + 8), (0, 0))
    ImageDraw.Draw(im).text((4 - box[0], 4 - box[1]), text, font=font, fill=(255, 255))
    im.save(path, optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    catalog = []
    for name, folder, stem, files, axes, kind, about in FAMILIES:
        print(name)
        zname = stem + ".zip"
        styles = []
        regular = None
        with zipfile.ZipFile(os.path.join(OUT, zname), "w", zipfile.ZIP_DEFLATED) as z:
            for fname, font in faces(folder, stem, files, axes, name):
                buf = io.BytesIO()
                font.save(buf)
                z.writestr(fname, buf.getvalue())
                styles.append(fname.rsplit("-", 1)[1][:-4])
                if fname.endswith("-Regular.ttf"):
                    regular = buf.getvalue()
            z.writestr(stem + "-OFL.txt", fetch(BASE + folder + "/OFL.txt"))
        preview(regular, name, os.path.join(OUT, stem + ".png"))
        catalog.append({"name": name, "kind": kind, "about": about, "zip": zname, "preview": stem + ".png",
                        "size": os.path.getsize(os.path.join(OUT, zname)), "styles": styles,
                        "license": "SIL Open Font License 1.1"})
    with open(os.path.join(OUT, "catalog.json"), "w") as f:
        json.dump({"version": 1, "fonts": catalog}, f, indent=1, ensure_ascii=False)
    print(len(catalog), "families ->", OUT)


if __name__ == "__main__":
    main()
