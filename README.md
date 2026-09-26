# eReaderDS for the RG DS Plus

A two-page ebook reader for the **Anbernic RG DS Plus**. Hold the device
sideways like an open book: each screen shows one page.

Created by **casualducko**.

![Reading, held sideways](docs/screenshots/reading.png)

> **RG DS Plus on its stock firmware only** (not the original RG DS, and not
> custom firmware such as ROCKNIX or KNULLI). **This is a test release**:
> please [report problems](#reporting-problems).

## Install

1. Download `eReaderDS-vX.Y.Z.zip` from the
   [latest release](https://github.com/casualducko/eReaderDS-beta/releases/latest)
   and unzip it on your computer.
2. From the unzipped `Ports` folder, copy **`eReaderDS.sh`** and the
   **`eReaderDS`** folder into the `Ports` folder on the SD card.
3. Put `.epub` or `.txt` books in the card's `Ebook` folder.
4. On the device, open **Ports → eReaderDS**.

To update, copy the same two items from a newer zip over the old ones. Your
settings, reading positions, bookmarks and fonts are kept. (Copy the two
items, not the whole `Ports` folder: on a Mac, replacing `Ports` deletes your
other ports.)

## Controls

Hold the device turned counter-clockwise, buttons under your right hand.
Directions are as you hold it.

| Button | While reading | In lists and menus |
|---|---|---|
| D-pad or stick | Turn pages (right/down forward) | Up/down move; left/right change a value, page through a list, or change the library's sort order |
| A | Show the notes on these pages | Select |
| B | Settings, or go back after a jump | Back |
| Y | Look up a word | Delete (a book in the library, a bookmark in Bookmarks) |
| Select | Bookmark the page (again to remove) | Close; in the library: Get books |
| Start, X, ↩, or pressing the stick in | Settings | Open or close Settings (the stick selects) |
| Menu (Anbernic button) | Quit | Quit |

The L/R and L2/R2 shoulder buttons aren't used. Contents, Bookmarks, Jump to %
and the Library are at the top of **Settings**.

**Touch (bottom screen only):**
- Swipe left/right, or tap the right/left half, to turn pages. (To make a tap
  open Settings instead: **Settings → Page turns & device → Tap**.)
- Slide up/down to change brightness; keep going below 1% for Extra dim.
- Tap the top-right corner to bookmark the page.
- Tap the top edge (left of that corner) to show or hide all the status bars.
- Press and hold a word to look it up.
- Tap a note number, or the **Notes** button, to show footnotes.

## Features

- **Reading:** EPUB and plain text with italics, headings, images and covers;
  justified text with optional hyphenation (English); 10 built-in fonts plus
  your own; 11 themes (E-ink by default, plus Paper, Night, Amber and more); page-flip or fade
  animation.
- **Footnotes on the facing page:** press A and the note appears on the other
  page while the text stays put.
- **Dictionary on the facing page:** press Y and move a cursor over the words;
  English is built in, and you can add your own ([below](#dictionaries)).
- **Get books over Wi-Fi:** Project Gutenberg built in, plus Calibre or any
  OPDS catalog ([below](#getting-books-over-wi-fi)).
- **Library:** covers and progress, sorted by recent, title, author or
  progress; delete books from it.
- **Finding your place:** bookmarks, Contents, Jump to %, and "Back to …"
  after any jump. Your place in every book is saved.
- **Status bar:** book and chapter titles, pages left, time left (learned
  from your reading speed), percent read, a progress bar, battery and a clock.
  Choose what shows in **Settings → Status bar**.
- **Battery-friendly:** the screen only redraws when something changes, and
  closing the lid puts the device to sleep.

| Library | Contents |
|---|---|
| ![Library](docs/screenshots/library.png) | ![Contents](docs/screenshots/contents.png) |

| Settings | Night theme |
|---|---|
| ![Settings](docs/screenshots/settings.png) | ![Night theme](docs/screenshots/night.png) |

*Screenshots use public-domain books from Project Gutenberg.*

## Getting books over Wi-Fi

Turn on Wi-Fi in the device's settings, then in the library press **Select**
(or tap **Get books** on the touchscreen) and choose a catalog. Browse with
the D-pad or by tapping, and press A on a book to download it to the `Ebook`
folder. Books you already have are marked ✓. Without Wi-Fi the button is
greyed out. There's no search, since there's no keyboard.

**Project Gutenberg** (70,000+ free books) works with no setup. To add your
own catalog, such as a Calibre content server or Calibre-Web, edit
`Ebook/.ereaderds/opds.txt` on the SD card (it's created the first time
eReaderDS runs):

```
name = Calibre
url = http://192.168.1.20:8080/opds
user = me
password = secret
```

Leave out `user` and `password` if the server doesn't need them, and add a
block for each extra catalog. Add `verify = no` for a server with a
self-signed certificate, and `gutenberg = off` to hide Project Gutenberg.

## Dictionaries

While reading, press **Y**: a cursor appears on a word. Left/right move it
word by word and up/down line by line, across both pages, and the definition
shows on the facing page (A for more of a long entry, B to close).

English (WordNet) is built in. To add others, copy **StarDict** dictionaries
(the files KOReader uses: `.ifo`, `.idx`, `.dict` or `.dict.dz`, and `.syn`
if there is one) into `Ebook/Dictionaries`. By default every dictionary with
the word is shown, yours first; pick a single one in
**Settings → Page turns & device → Dictionary**.

## Fonts

**Built in:** Gentium Book Plus (default), Literata, Charis SIL, Source Serif
4, Crimson Text, Bitter, Atkinson Hyperlegible Next, Inter, Lexend and
OpenDyslexic.

**Your own:** copy `.ttf` or `.otf` files into `Ebook/Fonts`, then choose
them in **Settings → Font**. Regular, italic and bold files of a family are
grouped automatically. Use static fonts: a variable font (`[wght]` in the
name) only shows one weight.

## Troubleshooting

| Problem | Try this |
|---|---|
| Not in the Ports menu | `eReaderDS.sh` and the `eReaderDS` folder must be directly inside `Ports`. |
| Black screen, or it closes at once | Send `Ports/eReaderDS/log.txt` with a [report](#reporting-problems). |
| "No books found" | Put `.epub` or `.txt` files in the `Ebook` folder at the top of the card. |
| A book won't open or looks wrong | Unusual EPUBs may not display well; DRM-protected books, PDF and MOBI aren't supported. |
| Get books is greyed out | Turn on Wi-Fi in the device's settings and wait for it to connect. |
| Pages upside down | Turn the device the other way, with the buttons on your right. |
| Screen stays dim after quitting | Brightness is restored when the app quits; after a crash, set it in the system menu. |

## Reporting problems

Tell whoever sent you eReaderDS, or
[open a bug report](https://github.com/casualducko/eReaderDS-beta/issues/new?template=bug_report.yml).
Include the **version** (top of Settings), **what happened** (a photo of the
screens helps), and **`Ports/eReaderDS/log.txt`**, copied right after the
problem.

## Known limitations

- Touch works only on the bottom screen.
- "Pages left in chapter" can be too low when a chapter spans several files in
  the EPUB.
- No tables, fixed-layout EPUBs, PDF, MOBI or DRM-protected books.
- Hyphenation and the built-in dictionary are English only.

## For developers

See [docs/DEVELOPING.md](docs/DEVELOPING.md).

## Credits

eReaderDS is created by **casualducko** (also in **Settings → Page turns &
device → About**).

- **Fonts**, all under the SIL Open Font License 1.1 (license files in
  `app/fonts/` and the download's `LICENSES` folder):
  [Gentium Book Plus](https://software.sil.org/gentium/) and
  [Charis SIL](https://software.sil.org/charis/) (SIL International),
  [Literata](https://github.com/googlefonts/literata) (TypeTogether),
  [Source Serif 4](https://github.com/adobe-fonts/source-serif) (Adobe),
  [Crimson Text](https://github.com/googlefonts/Crimson) (Sebastian Kosch),
  [Bitter](https://github.com/solmatas/BitterPro) (Huerta Tipográfica),
  [Atkinson Hyperlegible Next](https://github.com/googlefonts/atkinson-hyperlegible-next)
  (Braille Institute), [Inter](https://github.com/rsms/inter) (Rasmus Andersson),
  [Lexend](https://github.com/googlefonts/lexend) (Lexend Project) and
  [OpenDyslexic](https://github.com/antijingoist/opendyslexic) (Abbie Gonzalez).
  Bitter and Atkinson Hyperlegible Next are static instances generated from
  their variable fonts.
- **Hyphenation:** US English patterns from TeX's
  [hyph-utf8](https://www.hyphenation.org/tex), © Gerard D.C. Kuiken (notice
  in `app/hyph/en-us.txt`).
- **Dictionary:** [WordNet](https://wordnet.princeton.edu) 3.1, © 2011
  Princeton University, under the WordNet license
  (`app/dict/WordNet-LICENSE.txt`); converted by `tools/build-wordnet.py`.
- **Engine:** [LÖVE](https://love2d.org) 11.5 (zlib license), from the
  PortMaster aarch64 runtime. See [runtime/NOTICES.md](runtime/NOTICES.md).
