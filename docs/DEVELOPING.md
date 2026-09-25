# Developing Book Reader

Notes for working on the code. For installing and using the reader, see the
[README](../README.md).

## Running on a computer

Install LÖVE 11.5 (on macOS, download `love-11.5-macos.zip` from the
[LÖVE releases](https://github.com/love2d/love/releases/tag/11.5)). Then run
the app in a half-size window:

```sh
cd app
READER_SCALE=0.5 READER_BOOKS=~/Books READER_DATA=/tmp/reader-data love .
```

On a computer the arrow keys are page directions, and dragging with the mouse
on the right half of the window stands in for the touchscreen. Space/PageDown turns
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
| `READER_FONTS` | Colon-separated user font folders (device default: `Ebook/Fonts` and the firmware font folder) |
| `READER_BACKLIGHT` | Backlight sysfs root, useful for testing with fake files |
| `READER_SCRIPT` / `READER_SHOT` | Run actions, save a PNG of the frame, then quit |
| `READER_TOUCH` | With `READER_SHOT`, simulate a touch drag `x0,y0,x1,y1` in bottom-screen coordinates |
| `READER_TOUCH_DEV` | Touchscreen evdev path (default: found by name `gt9xx-0`) |
| `READER_ANIM_T` | With `READER_SHOT`, freeze a page turn at this progress (0–1) |
| `READER_DEBUG` | Print layout timings |

## Installing from a clone

With the SD card mounted (macOS/Linux):

```sh
./install.sh                 # defaults to /Volumes/ROMS
./install.sh /path/to/card   # any other mount point
```

It replaces `Ports/BookReader/app`, updates the launchers and runtime, and
leaves settings and progress (`Ebook/.bookreader`) alone.

## Making a release

1. Bump the version in `app/version.lua` and add a `## vX.Y.Z` section to
   `CHANGELOG.md`.
2. Commit, then tag and push:
   ```sh
   git tag v0.2.0 && git push origin main v0.2.0
   ```
3. The **Release** workflow builds `BookReader-vX.Y.Z.zip` with
   `tools/build-release.sh`, and publishes it as a GitHub pre-release using
   that version's changelog section as the notes.

To build the zip locally: `tools/build-release.sh` (writes to `dist/`).

The zip contains only `Ports/…`, laid out like the SD card. It never includes
settings, progress, books or fonts, so replacing an old version with a new
one keeps everything the reader has saved.

## Files on the card

```
Ebook/                      your books (.epub, .txt)
Ebook/Fonts/                your own fonts (.ttf, .otf)
Ebook/.bookreader/          saved state (outside the app, so updates keep it)
  settings.txt              your settings
  progress.txt              position in each book
  last.txt                  the last book you opened
Ports/Book Reader.sh        Ports menu entry
Ports/BookReader/
  launch.sh                 sets up Wayland and starts LÖVE
  app/                      Lua sources and fonts
  runtime/                  LÖVE 11.5 aarch64
  README.txt                quick instructions
  log.txt                   output from the last run (check this if something fails)
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
- **Touch.** SDL doesn't deliver this touchscreen to apps, so `touch.lua`
  reads the `gt9xx-0` evdev device directly (non-blocking, through LuaJIT
  FFI). `launch.sh` switches `/sys/class/anbernic_misc/tpctrl` to app mode
  (0) while the reader runs and restores it afterwards. Because touch events
  can't wake the event wait, the loop polls about 40 times a second while a
  touchscreen is available.
- **Idle.** A custom `love.run` waits for input events instead of drawing
  60 frames a second. It only renders frames while a page-turn animation
  runs.
- **Page turns.** Both spreads are kept as canvases. The turning page is
  drawn as a strip mesh whose spine end shrinks as it lifts, which gives the
  3D tilt.

## Source layout

| File | Purpose |
|---|---|
| `app/main.lua` | App states (library, reader, settings, contents), drawing, input, main loop |
| `app/book.lua` | EPUB/TXT loading: OPF, spine, NCX/nav TOC, basic CSS, HTML to blocks |
| `app/layout.lua` | Line breaking, justification and pagination |
| `app/zip.lua` | Minimal ZIP reader (stored and deflate) |
| `app/store.lua` | Settings and progress files |
| `app/backlight.lua` | Screen brightness through sysfs |
| `app/touch.lua` | Raw evdev touchscreen reader (LuaJIT FFI) |
| `app/fonts.lua` | Font discovery, family/style grouping from the font name table, loading |
| `app/conf.lua` | LÖVE window configuration |
| `port/` | Device launch scripts |
| `tools/` | Desktop testing helpers |
| `app/version.lua` | Version string shown in the app and used for releases |
| `runtime/` | LÖVE 11.5 aarch64 engine and its libraries (see `runtime/NOTICES.md`) |
