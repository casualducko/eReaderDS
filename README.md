# eReaderDS for the RG DS Plus

A two-page ebook reader for the **Anbernic RG DS Plus**. Turn the device
sideways, like an open book, and each screen shows one page.

![Reading, held sideways](docs/screenshots/reading.png)

> **Made for the RG DS Plus on its stock firmware**, the Linux system it
> ships with. It isn't for the original RG DS (640×480 screens), and it isn't
> for custom firmware such as ROCKNIX or KNULLI.

> **This is a test release.** If something goes wrong, please
> [report it](#reporting-problems). It only takes a minute.

## Install

You need an RG DS Plus on its stock firmware, its SD card, and any computer
(Windows, Mac or Linux).

1. **Download** `eReaderDS-vX.Y.Z.zip` from the
   [latest release](https://github.com/casualducko/eReaderDS-beta/releases/latest)
   and unzip it on your computer.
2. **Copy two items onto the card.** Open the unzipped `Ports` folder. It
   contains `eReaderDS.sh` and a `eReaderDS` folder. Copy both into the
   `Ports` folder on the SD card, next to your other ports.
3. **Add books**: copy `.epub` or `.txt` files into the card's `Ebook` folder.
4. Put the card back, then open **Ports → eReaderDS** on the device.

To **update**, copy the two items from a newer release the same way and
replace the old ones when asked. Your settings, reading positions and fonts
are kept: they live in the `Ebook` folder (`Ebook/.ereaderds` and
`Ebook/Fonts`), which the download never touches.

> **Used "Book Reader" (v0.1.x)?** It's now called eReaderDS. Install it as
> above, then delete `Ports/Book Reader.sh` and `Ports/BookReader` from the
> card. Your settings and reading positions carry over automatically.

> Don't drag the whole `Ports` folder onto the card: on a Mac, choosing
> **Replace** would remove your other ports.

## Using it

**Hold it** turned counter-clockwise: the top screen is the left page and the
buttons are under your right hand.

| Button | Reading | In menus |
|---|---|---|
| **R** or D-pad forward | Next two pages | Change a setting |
| **L** or D-pad back | Previous two pages | Change a setting |
| **R2 / L2** | Next / previous chapter | |
| **Y** | Contents | |
| **Start**, **Select**, **X** or **B** | Settings | Back |
| **A** | | Select |
| **Menu** (home) | Quit | Quit |

The D-pad follows the way you're holding it: forward means right or down, as
you see it.

**Touch** (the bottom screen):

- **Swipe** left or right to turn pages.
- **Slide** up or down to change brightness.
- **Tap** the right half of the page to go forward, the left half to go back.
  Prefer taps to open Settings? Set **Settings → Tap** to **Open menu**.

## Features

- Two-page spreads with a 3D page-flip animation (or fade, or off)
- EPUB and plain text, with italics, bold, headings, images, covers and the
  book's contents
- Book-style layout: justified text, indents, and chapters that start on a
  new page
- Library with covers and progress. Your place in every book is saved, and
  the last book reopens on launch
- Settings: text size, font, line spacing, side and top/bottom margins,
  justification, brightness, what a tap does, page info, and jump to %
- Eleven themes: Paper, White, Sepia, Solarized, E-ink (grayscale, 16 gray
  levels and a speckled paper grain), Stone, Sage, Dusk, Night, Amber, Black
- Three built-in fonts, plus your own
- Battery-friendly: it sleeps between button presses

| Library | Contents |
|---|---|
| ![Library](docs/screenshots/library.png) | ![Contents](docs/screenshots/contents.png) |

| Settings | Night theme |
|---|---|
| ![Settings](docs/screenshots/settings.png) | ![Night theme](docs/screenshots/night.png) |

*Screenshots use public-domain books from Project Gutenberg.*

## Your own fonts

Copy `.ttf` or `.otf` files into `Ebook/Fonts` on the SD card (the reader
creates this folder the first time it runs), then pick them in
**Settings → Font**. A family's regular, italic and bold files are grouped
together automatically. Use static fonts: a variable font (with `[wght]` in
its file name) only shows its default weight.

Built in: Gentium Book Plus, Crimson Text and Atkinson Hyperlegible.

## Troubleshooting

| Problem | Try this |
|---|---|
| **eReaderDS isn't in the Ports menu** | Check that `Ports/eReaderDS.sh` and the `Ports/eReaderDS` folder are at the top level of the card, not inside another folder. |
| **Black screen, or it closes right away** | Look at `Ports/eReaderDS/log.txt` on the card and include it in a [bug report](#reporting-problems). |
| **"No books found"** | Books go in the `Ebook` folder at the top level of the card, as `.epub` or `.txt`. |
| **A book won't open or looks wrong** | Some EPUBs use unusual formatting. DRM-protected books, PDF and MOBI aren't supported. |
| **Pages are upside down** | Turn the device the other way: counter-clockwise, with the buttons on the right. |
| **Screen too dim after leaving** | The reader restores your normal brightness when it quits normally. If it crashed, change brightness in the system menu. |

## Reporting problems

[Open a bug report](https://github.com/casualducko/eReaderDS-beta/issues/new?template=bug_report.yml).
It asks for:

- The **version**, shown at the top of Settings and at the bottom of the
  Library (for example `v0.1.0`).
- **What happened**. Photos of the screens help a lot.
- The contents of **`Ports/eReaderDS/log.txt`** from the SD card,
  copied right after the problem.

## Known limitations

- **Touch** is on the bottom screen only, so it works on whichever page that
  screen shows.
- **"Pages left in chapter"** can undercount when a chapter spans several
  files inside the EPUB.
- **Formatting** support is basic: tables, fixed-layout EPUBs, PDF, MOBI and
  DRM-protected books aren't supported.
- **RG DS Plus, stock firmware only.** The original RG DS and custom
  firmware (ROCKNIX, KNULLI and others) aren't supported: they use different
  screens, folders or display setups.

## For developers

See [docs/DEVELOPING.md](docs/DEVELOPING.md) for how it works, running it on a
computer, installing from a clone, and making releases.

## Credits

- Fonts (SIL Open Font License 1.1):
  [Gentium Book Plus](https://software.sil.org/gentium/) by SIL International,
  [Crimson Text](https://github.com/googlefonts/Crimson) by Sebastian Kosch,
  [Atkinson Hyperlegible](https://www.brailleinstitute.org/freefont/) by the
  Braille Institute
- Engine: [LÖVE](https://love2d.org) 11.5 (zlib license), from the PortMaster
  aarch64 runtime. See [runtime/NOTICES.md](runtime/NOTICES.md).
