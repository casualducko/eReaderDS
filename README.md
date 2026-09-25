# RG DS Plus Book Reader

A two-page ebook reader for the **Anbernic RG DS Plus**. Hold the device
sideways like an open book and each screen shows one portrait page.

![Reading, held sideways](docs/screenshots/reading.png)

## Features

- **Two-page spreads** across both screens, rotated for sideways reading, with
  a setting to flip for either hand
- **EPUB and plain text**: italics, bold, headings, images, covers and the
  book's table of contents
- **Book-style layout**: justified text, paragraph indents, and each chapter
  starts on a new page
- **Library** with cover previews and per-book progress
- **Remembers your place** in every book and reopens the last one on launch
- **Settings**: text size, line spacing, margins, justification, brightness,
  four themes (Paper, White, Sepia, Night), page info on/off, and go to %
- **Battery-friendly**: redraws only when you press a button

| Library | Contents |
|---|---|
| ![Library](docs/screenshots/library.png) | ![Contents](docs/screenshots/contents.png) |

| Settings | Night theme |
|---|---|
| ![Settings](docs/screenshots/settings.png) | ![Night theme](docs/screenshots/night.png) |

*Screenshots use public-domain books from Project Gutenberg.*

## Install

1. Put the SD card in your computer. It should mount as `ROMS`.
2. Run:
   ```sh
   ./install.sh                 # defaults to /Volumes/ROMS
   ./install.sh /path/to/card   # any other mount point
   ```
3. Copy `.epub` or `.txt` files into the `Ebook` folder on the card.
4. On the device, open **Ports → Book Reader**.

The installer copies the app to `Ports/BookReader/` and adds
`Ports/Book Reader.sh` to the Ports menu. Running it again updates the app
and keeps your settings and reading progress.

### LÖVE runtime

The reader runs on [LÖVE](https://love2d.org) 11.5 (aarch64). Those binaries
aren't stored in this repo. On a first install, `install.sh` copies them from
another port on the card that bundles them (for example a PortMaster LÖVE
port with `runtime/love.aarch64` and `runtime/libs.aarch64/`). To use a
different copy, point the installer at it:

```sh
LOVE_RUNTIME=/path/to/love_11.5 ./install.sh
```

## Controls

Hold the device turned counter-clockwise: the top screen is the left page and
the buttons are under your right hand. **Settings → Flip for other hand**
switches to the opposite grip.

| Button | Reading | Menus |
|---|---|---|
| R, or D-pad forward | Next two pages | Change setting / next page of list |
| L, or D-pad back | Previous two pages | Change setting / previous page of list |
| R2 / L2 | Next / previous chapter | |
| D-pad up/down (as held) | | Move selection |
| A | | Select |
| B | Settings | Back |
| Y | Contents | |
| Start / Select / X | Settings | Close |
| Menu (home) | Quit | Quit |

The D-pad follows the rotation: forward means right or down as you're holding
it, whichever way that is.

## Files on the card

```
Ebook/                      your books (.epub, .txt)
Ports/Book Reader.sh        Ports menu entry
Ports/BookReader/
  launch.sh                 sets up Wayland and starts LÖVE
  app/                      Lua sources and fonts
  runtime/                  LÖVE 11.5 aarch64 (copied by install.sh)
  data/
    settings.txt            your settings
    progress.txt            position in each book
    last.txt                the last book you opened
    log.txt                 output from the last run (check this if something fails)
```

## How it works

- **Screens.** The RG DS Plus firmware runs a Wayland compositor that joins
  the two 1024×768 screens into one 2048×768 surface: the top screen is
  x 0–1023 and the bottom screen is x 1024–2047. The reader opens one
  borderless 2048×768 window, draws each page onto a 768×1024 canvas, and
  rotates that canvas onto its screen.
- **Input.** Buttons arrive as the joystick `ANBERNIC-rk3568-keys`. The
  reader loads a gamepad mapping for it, and turns physical D-pad directions
  into on-page directions based on the current grip.
- **Brightness.** The reader sets every device under `/sys/class/backlight`
  to the same percentage. `launch.sh` saves the system brightness before
  starting and restores it afterwards, so the reader's level doesn't stick
  outside it.
- **Idle.** A custom `love.run` waits for input events instead of drawing
  60 frames a second.

### Source layout

| File | Purpose |
|---|---|
| `app/main.lua` | App states (library, reader, settings, contents), drawing, input, main loop |
| `app/book.lua` | EPUB/TXT loading: OPF, spine, NCX/nav TOC, basic CSS, HTML to blocks |
| `app/layout.lua` | Line breaking, justification and pagination |
| `app/zip.lua` | Minimal ZIP reader (stored and deflate) |
| `app/store.lua` | Settings and progress files |
| `app/backlight.lua` | Screen brightness through sysfs |
| `app/conf.lua` | LÖVE window configuration |
| `port/` | Device launch scripts |
| `tools/` | Desktop testing helpers |

## Developing on a computer

Install LÖVE 11.5 (on macOS, download `love-11.5-macos.zip` from the
[LÖVE releases](https://github.com/love2d/love/releases/tag/11.5)). Then run
the app in a half-size window:

```sh
cd app
READER_SCALE=0.5 READER_BOOKS=~/Books READER_DATA=/tmp/reader-data love .
```

On a computer the arrow keys are page directions. Space/PageDown turns
forward, Enter selects, Esc goes back, `m` opens settings, `t` opens
contents, and `q` quits.

Scripted screenshots:

```sh
LOVE=/path/to/love BOOKS=~/Books tools/shot.sh frame.png "confirm,toc,down,confirm"
tools/sideways.py frame.png view.png   # how it looks held sideways (needs Pillow)
```

| Environment variable | Meaning |
|---|---|
| `READER_BOOKS` | Colon-separated book folders (device default: `/mnt/mmc/Ebook:/mnt/sdcard/Ebook`) |
| `READER_DATA` | Where settings and progress are stored |
| `READER_SCALE` | Window scale for desktop testing (also makes the window bordered) |
| `READER_BACKLIGHT` | Backlight sysfs root, useful for testing with fake files |
| `READER_SCRIPT` / `READER_SHOT` | Run actions, save a PNG of the frame, then quit |
| `READER_DEBUG` | Print layout timings |

## Known limitations

- **No touch.** Touch input on this device needs raw evdev access, so pages
  can't be turned by tapping yet.
- **Page counts.** "Pages left in chapter" counts only to the end of the
  current file inside the EPUB, so it can undercount chapters that span files.
- **Styling.** Only a small CSS subset is used (italic, bold, centering,
  `display: none`). Tables, fixed-layout EPUBs, PDF, MOBI and DRM-protected
  books aren't supported.

## Credits

- Font: [Gentium Book Plus](https://software.sil.org/gentium/) by SIL
  International, SIL Open Font License 1.1 (`app/fonts/OFL.txt`)
- Engine: [LÖVE](https://love2d.org), zlib license
