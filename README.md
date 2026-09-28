# eReaderDS for the RG DS Plus

Hey guys, I'm casualducko. I've been coding since the late 90's and I absolutely
love it. I like to think that I know my stuff, but I don't know everything. With
that being said, I have gladly been using Claude Code to help me bring this idea
to its full potential.

eReaderDS is a two-page ebook reader for the **Anbernic RG DS Plus**. Hold the
device sideways like an open book: each screen shows one page.

![Reading, held sideways](docs/screenshots/reading.png)

> **RG DS Plus on its stock firmware or ROCKNIX** (not the original RG DS,
> and not other custom firmware such as KNULLI). **This is a test release**:
> please [report problems](#reporting-problems).

## Install

1. Download `eReaderDS-vX.Y.Z.zip` from the
   [releases page](https://github.com/casualducko/eReaderDS-beta/releases) (the newest is at the top)
   and unzip it on your computer.
2. From the unzipped `Ports` folder, copy **`eReaderDS.sh`** and the
   **`eReaderDS`** folder into the `Ports` folder on the SD card, and
   `Imgs/eReaderDS.png` (the menu icon) into `Ports/Imgs`.
3. Put `.epub` or `.txt` books in the card's `Ebook` folder.
4. On the device, open **Ports → eReaderDS**.

**On ROCKNIX:** copy `eReaderDS.sh` and the `eReaderDS` folder into
`roms/ports` instead (over the network, `/storage/roms/ports`), put books in
`roms/ebook` (fonts in `roms/ebook/Fonts`), and open **Ports → eReaderDS**.
The bottom screen turns on while it runs; closing the lid is handled by
ROCKNIX.

**Updates:** when it's online, eReaderDS checks for a newer version each time
it starts and says so (with the version you have). Tap that note to update, or
use **Settings → About eReaderDS** (or **Start** in the library with no book
open). The update screen lists what's new in plain words; **Update now**
downloads it, saves only the files that changed, and restarts. Your books,
settings and progress are kept. After an update, a note offers to show
**What's new** (also in Settings → About eReaderDS).

To stop the automatic check and its notes, set **Update notices** to Off (same
page); **Check for updates** still works. To pass on just one version, choose
**Skip this version** on the update screen; you'll still hear about the next.

To update by hand, copy the same two items from a newer zip over the old ones. Your
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
| Y | Look up (or highlight) a word | Delete (a book in the library, a bookmark or highlight in the list) |
| Select | Bookmark the page (again to remove) | Close; in the library: Get books |
| Start, X, ↩, or pressing the stick in | Settings | Open or close Settings (the stick selects) |
| Menu (Anbernic button) | Quit | Quit |

The L/R and L2/R2 shoulder buttons aren't used. **Help** in Settings is a
one-page summary of the buttons and touchscreen.

**Touch (bottom screen only):**
- Swipe left/right, or tap the right/left half, to turn pages. (To make a tap
  open Settings instead: **Settings → Reading & device → Tap**.)
- Slide up/down to change brightness; keep going below 1% for Extra dim.
- Pinch with two fingers to make the text bigger or smaller.
- Tap the top-right corner to bookmark the page.
- Tap the top edge (left of that corner) to show or hide all the status bars.
- Press and hold a word to look it up.
- While highlighting (**Y**, then **Select**), tap a word to extend the
  highlight to it.
- In the library and Get books, tap an entry to see it on the other screen,
  and tap it again to open (or download) it. In Contents, Bookmarks and Find
  in book, tap an entry to go there.
- Swipe (or tap) to turn the pages of What's new.
- Tap a note number, or the **Notes** button, to show footnotes.

## Settings

Press **B** (or Start, X, ↩) while reading. One page, top to bottom:

- **Contents, Bookmarks and highlights, Find in book, Jump to %, Library**
- **Text:** Font (its own page, [below](#fonts)), text size, line spacing,
  justify, hyphenation
- **Page:** margins, theme, **Night theme** ([below](#night-theme)), brightness
- **Status bar ›** what the top and bottom lines show, and the clock style
- **Reading & device ›** page-turn animation, what a tap does, dictionary,
  closing the lid, time zone
- **About eReaderDS ›** What's new, Check for updates, Update notices, Report
  a problem, About & credits (and **Update to v…** when one is waiting; the row says **Update**)
- **Help**, **Quit**

## Features

- **Reading:** EPUB and plain text with italics, headings, images and covers;
  justified text with optional hyphenation (English); 17 built-in fonts plus
  your own; 11 themes (Sepia by default, plus E-ink, Paper, Midnight, Amber
  and more) that the whole app follows, and a night theme that switches on by
  itself in the evening; page-flip or fade animation.
- **Footnotes on the facing page:** press A and the note appears on the other
  page while the text stays put.
- **Dictionary on the facing page:** press Y and move a cursor over the words;
  English is built in, and you can add your own ([below](#dictionaries)).
- **Highlights:** mark passages and find them again in the list of bookmarks
  and highlights ([below](#highlights)).
- **Get books over Wi-Fi:** Project Gutenberg built in, plus Calibre or any
  OPDS catalog ([below](#getting-books-over-wi-fi)).
- **Library:** covers and progress, sorted by recent, title, author or
  progress; delete books from it.
- **Finding your place:** bookmarks and highlights, Contents, Jump to %, **Find in book**
  (type a word or phrase on the touchscreen keyboard; every match is listed,
  and the words are marked on the page you open), and "Back to …" after any
  jump. Your place in every book is saved.
- **Status bar:** book and chapter titles, pages left, time left in the chapter
  (learned from your reading speed), percent read, a progress bar, battery and a clock.
  Choose what shows in **Settings → Status bar**. The clock follows the
  device's time; if it's off, pick your zone in **Settings → Reading &
  device → Time zone**.
- **Battery-friendly:** the screen only redraws when something changes, and
  closing the lid puts the device to sleep.

| Library | Contents |
|---|---|
| ![Library](docs/screenshots/library.png) | ![Contents](docs/screenshots/contents.png) |

| Settings | Midnight theme |
|---|---|
| ![Settings](docs/screenshots/settings.png) | ![Midnight theme](docs/screenshots/night.png) |

*Screenshots use public-domain books from Project Gutenberg.*

## Night theme

**Settings → Night theme** picks a second theme (Midnight, Amber and Dusk
are the darker ones) and the hours to use it, 9 PM to 7 AM to start. It
switches on the hour by the device's clock, and the whole app changes with
it. While picking, the touchscreen previews each theme. At night, the
**Theme** row changes the night theme (it says "(night)"), so your daytime
theme is left alone.

## Getting books over Wi-Fi

Turn on Wi-Fi in the device's settings, then in the library press **Select**
(or tap **Get books** on the touchscreen) and choose a catalog. Browse with
the D-pad or by tapping, and press A on a book to download it to the `Ebook`
folder. Books you already have are marked ✓. Without Wi-Fi the button is
greyed out. **Search** (at the top of a catalog, when it supports searching,
as Gutenberg and Calibre do) opens an on-screen keyboard on the touchscreen:
tap the keys, or use the D-pad and A.

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

## Highlights

Press **Y** for the word cursor, move to the first word, press **Select**, move
to the last word (the highlight grows as you go, across both pages), and press
**Select** again. **B** cancels. To remove one, put the cursor on it and press
**Select**. Highlights show as a band behind the words in every theme, stay
put when you change the font or text size, and are listed with your bookmarks
in **Settings → Bookmarks and highlights** (A goes there, Y deletes).

## Dictionaries

While reading, press **Y**: a cursor appears on a word. Left/right move it
word by word and up/down line by line, across both pages, and the definition
shows on the facing page (A for more of a long entry, B to close).

English (WordNet) is built in. To add others, copy **StarDict** dictionaries
(the files KOReader uses: `.ifo`, `.idx`, `.dict` or `.dict.dz`, and `.syn`
if there is one) into `Ebook/Dictionaries`. By default every dictionary with
the word is shown, yours first; pick a single one in
**Settings → Reading & device → Dictionary**.

## Fonts

**Settings → Font** opens a two-page view: the fonts on the touchscreen, each
named in its own typeface, and a sample page in the highlighted one on the
other screen. The list is alphabetical; left/right (or tapping **All · Serif ·
Sans** at the top) narrow it. Up/down pick a font, A uses it.

**Built in:** Gentium Book Plus (default), Literata, Charis SIL, Source Serif
4, Crimson Text, EB Garamond, Lora, Merriweather, PT Serif, Spectral,
Vollkorn, Bitter, Atkinson Hyperlegible Next, Inter, Lexend, Andika and
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
| The clock is wrong | Set **Settings → Reading & device → Time zone** (**Device clock** uses the system's own setting). |
| An update fails | Check Wi-Fi and choose **Try again**. Nothing is changed until an update is complete; you can also [update by hand](#install). |

## Reporting problems

If eReaderDS runs into a problem it says so, keeps your place in the book, and
quits when you press a button. The next time you open it, a note offers to
report it: tap it for a QR code that opens a bug report on your phone with the
version and what went wrong filled in (no book titles). Nothing is sent from
the device; you read the report and send it yourself. **Settings → About
eReaderDS → Report a problem** shows the same code any time.

Or tell whoever sent you eReaderDS, or
[open a bug report](https://github.com/casualducko/eReaderDS-beta/issues/new?template=bug_report.yml).
Include the **version** (top of Settings), **what happened** (a photo of the
screens helps), and **`Ports/eReaderDS/log.txt`**, copied right after the
problem.

## Known limitations

- Touch works only on the bottom screen.
- When a chapter runs over several files in the EPUB, its pages in files not
  opened yet are estimated (usually within a few pages) until you reach them.
- No tables, fixed-layout EPUBs, PDF, MOBI or DRM-protected books.
- Hyphenation and the built-in dictionary are English only.

## For developers

See [docs/DEVELOPING.md](docs/DEVELOPING.md).

## Credits

eReaderDS is created by **casualducko** (also in **Settings → About eReaderDS →
About & credits**).

- **Fonts**, all under the SIL Open Font License 1.1 (license files in
  `app/fonts/` and the download's `LICENSES` folder):
  [Gentium Book Plus](https://software.sil.org/gentium/),
  [Charis SIL](https://software.sil.org/charis/) and
  [Andika](https://software.sil.org/andika/) (SIL International),
  [Literata](https://github.com/googlefonts/literata) (TypeTogether),
  [Source Serif 4](https://github.com/adobe-fonts/source-serif) (Adobe),
  [Crimson Text](https://github.com/googlefonts/Crimson) (Sebastian Kosch),
  [EB Garamond](https://github.com/octaviopardo/EBGaramond12) (Georg Duffner,
  Octavio Pardo), [Lora](https://github.com/cyrealtype/Lora-Cyrillic) (Cyreal),
  [Merriweather](https://github.com/SorkinType/Merriweather) (Sorkin Type),
  [PT Serif](https://fonts.google.com/specimen/PT+Serif) (ParaType),
  [Spectral](https://github.com/productiontype/Spectral) (Production Type),
  [Vollkorn](http://vollkorn-typeface.com) (Friedrich Althausen),
  [Bitter](https://github.com/solmatas/BitterPro) (Huerta Tipográfica),
  [Atkinson Hyperlegible Next](https://github.com/googlefonts/atkinson-hyperlegible-next)
  (Braille Institute), [Inter](https://github.com/rsms/inter) (Rasmus Andersson),
  [Lexend](https://github.com/googlefonts/lexend) (Lexend Project) and
  [OpenDyslexic](https://github.com/antijingoist/opendyslexic) (Abbie Gonzalez).
  Bitter, Atkinson Hyperlegible Next, EB Garamond, Lora, Merriweather and
  Vollkorn are static instances generated from their variable fonts
  (`tools/build-fonts.py` for the last four).
- **Hyphenation:** US English patterns from TeX's
  [hyph-utf8](https://www.hyphenation.org/tex), © Gerard D.C. Kuiken (notice
  in `app/hyph/en-us.txt`).
- **Dictionary:** [WordNet](https://wordnet.princeton.edu) 3.1, © 2011
  Princeton University, under the WordNet license
  (`app/dict/WordNet-LICENSE.txt`); converted by `tools/build-wordnet.py`.
- **QR codes:** [qrencode.lua](https://github.com/speedata/luaqrcode) by
  Patrick Gundlach and contributors (BSD license, in `app/qrencode.lua`).
- **Engine:** [LÖVE](https://love2d.org) 11.5 (zlib license), from the
  PortMaster aarch64 runtime. See [runtime/NOTICES.md](runtime/NOTICES.md).
