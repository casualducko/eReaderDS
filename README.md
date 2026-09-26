# eReaderDS for the RG DS Plus

A two-page ebook reader for the **Anbernic RG DS Plus**. Hold the device
sideways like an open book, and each screen shows one page.

Created by **casualducko**.

![Reading, held sideways](docs/screenshots/reading.png)

> **For the RG DS Plus on its stock firmware only.** It isn't for the original
> RG DS or for custom firmware such as ROCKNIX or KNULLI.
>
> **This is a test release.** If something goes wrong, please
> [report it](#reporting-problems).

## Install

1. Download `eReaderDS-vX.Y.Z.zip` from the
   [latest release](https://github.com/casualducko/eReaderDS-beta/releases/latest)
   (or use the zip you were sent) and unzip it on your computer.
2. Open the unzipped `Ports` folder and copy **`eReaderDS.sh`** and the
   **`eReaderDS`** folder into the `Ports` folder on the SD card.
3. Copy `.epub` or `.txt` books into the card's `Ebook` folder.
4. On the device, open **Ports → eReaderDS**.

**Updating:** copy the two items from a newer zip the same way, replacing the
old ones. Your settings, reading positions and fonts are kept.

> Copy the two items, not the whole `Ports` folder: on a Mac, replacing
> `Ports` would delete your other ports.

## Controls

Hold it turned counter-clockwise: the top screen is the left page, and the
buttons are under your right hand. Directions below are as you hold it.

| Button | Reading | Menus |
|---|---|---|
| D-pad | Turn pages (right/down forward, left/up back) | Up/down move; left/right change a value (or move, on rows without one) |
| R / L | Next / previous pages | Change a value |
| R2 / L2 | Next / previous chapter | |
| A, or press the stick in | | Select |
| B | Settings | Back |
| Start, Select, X, or the ↩ button | Settings | Close |
| Y | Contents | |
| Menu (Anbernic button) | Quit | Quit |

The **analog stick** works like the D-pad.

**Touch** (bottom screen): swipe left/right to turn pages, and slide up/down
for brightness. Tapping the right or left half turns pages forward or back.
To make a tap open Settings instead, use **Settings → Tap**.

## Features

- Two-page spreads with a page-flip animation (or fade, or none)
- EPUB and plain text, with italics, headings, images, covers and contents
- Justified text, indents, and each chapter starting on a new page
- Library with covers and progress; your place in every book is saved
- Text size, line spacing, margins and brightness settings
- Customizable status bar: titles, chapter pages ("12 pages left" or "Page 3
  of 15"), percent of the book read, a progress bar across both pages, and battery
- 11 themes, including E-ink (grayscale, with paper grain), Night and Amber
- 10 built-in fonts, plus your own
- Only redraws when something changes, to save battery

| Library | Contents |
|---|---|
| ![Library](docs/screenshots/library.png) | ![Contents](docs/screenshots/contents.png) |

| Settings | Night theme |
|---|---|
| ![Settings](docs/screenshots/settings.png) | ![Night theme](docs/screenshots/night.png) |

*Screenshots use public-domain books from Project Gutenberg.*

## Fonts

**Built in:** Gentium Book Plus (default), Literata, Charis SIL, Source Serif
4, Crimson Text and Bitter (serif); Atkinson Hyperlegible Next, Inter and
Lexend (sans-serif); and OpenDyslexic.

**Your own:** copy `.ttf` or `.otf` files into `Ebook/Fonts` on the SD card,
then choose them in **Settings → Font**. Regular, italic and bold files of a
family are grouped automatically. Use static fonts: variable fonts (with
`[wght]` in the name) only show one weight.

## Troubleshooting

| Problem | Try this |
|---|---|
| Not in the Ports menu | `eReaderDS.sh` and the `eReaderDS` folder must be directly inside `Ports`. |
| Black screen, or it closes at once | Send `Ports/eReaderDS/log.txt` with a [report](#reporting-problems). |
| "No books found" | Put `.epub` or `.txt` files in the `Ebook` folder at the top of the card. |
| A book won't open or looks wrong | Unusual EPUBs may not display well. DRM-protected books, PDF and MOBI aren't supported. |
| Pages upside down | Turn the device the other way, with the buttons on your right. |
| Screen stays dim after quitting | Normal brightness comes back when the app quits. After a crash, set it in the system menu. |

## Reporting problems

Tell whoever sent you eReaderDS, or
[open a bug report](https://github.com/casualducko/eReaderDS-beta/issues/new?template=bug_report.yml)
if you have access to this repository. Include:

- The **version**, shown at the top of Settings (for example `v0.2.4`)
- **What happened**, with a photo of the screens if you can
- **`Ports/eReaderDS/log.txt`** from the SD card, copied right after the
  problem

## Known limitations

- Touch works only on the bottom screen.
- "Pages left in chapter" can be too low when a chapter spans several files
  in the EPUB.
- No tables, fixed-layout EPUBs, PDF, MOBI or DRM-protected books.
- RG DS Plus on stock firmware only.

## For developers

See [docs/DEVELOPING.md](docs/DEVELOPING.md).

## Credits

eReaderDS is created by **casualducko**. It also appears in **Settings → About**.

- Fonts, all under the SIL Open Font License 1.1 (license files are in
  `app/fonts/` and in the download's `LICENSES` folder):
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
- Engine: [LÖVE](https://love2d.org) 11.5 (zlib license), from the PortMaster
  aarch64 runtime. See [runtime/NOTICES.md](runtime/NOTICES.md).
