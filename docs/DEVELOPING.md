# Developing eReaderDS

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

## Installing over Wi-Fi (SSH)

The stock firmware runs an SSH server (user `root`, password `root`). Once
your computer's key is installed on the device (`ssh-copy-id root@<ip>`, run
in a real terminal), you can update the device while it stays on:

```sh
./install.sh --ssh 192.168.1.140   # remembers the address in .device
./install.sh --ssh                 # later installs
tools/device.sh log                # read Ports/eReaderDS/log.txt
tools/device.sh data               # settings, progress, bookmarks
```

It replaces the app files only, and sends the engine only if the device doesn't
have it yet. Quit and reopen eReaderDS on the device to load a new version.

## Installing from a clone

With the SD card mounted (macOS/Linux):

```sh
./install.sh                 # defaults to /Volumes/ROMS
./install.sh /path/to/card   # any other mount point
```

It replaces `Ports/eReaderDS/app`, updates the launchers and runtime, and
leaves settings and progress (`Ebook/.ereaderds`) alone.

## Making a release

1. Bump the version in `app/version.lua` and add a `## vX.Y.Z` section to
   `CHANGELOG.md`.
2. Commit, then tag and push:
   ```sh
   git tag v0.2.0 && git push origin main v0.2.0
   ```
3. The **Release** workflow builds `eReaderDS-vX.Y.Z.zip` with
   `tools/build-release.sh`, and publishes it as a GitHub release using
   that version's changelog section as the notes. (A tag with a suffix, such
   as `v1.3.0-beta`, becomes a pre-release, which the in-app updater never
   offers.)

4. Once the release is up, build the Android APK here (it needs the signing
   key, which stays off GitHub) and add it:
   ```sh
   android/build.sh && gh release upload v0.2.0 dist/eReaderDS-v0.2.0-android.apk
   ```

To build the zip locally: `tools/build-release.sh` (writes to `dist/`).

The zip contains only `Ports/…`, laid out like the SD card. It never includes
settings, progress, books or fonts, so replacing an old version with a new
one keeps everything the reader has saved.

## Files on the card

```
Ebook/                      your books (.epub, .txt)
Ebook/Fonts/                your own fonts (.ttf, .otf)
Ebook/.ereaderds/          saved state (outside the app, so updates keep it)
  settings.txt              your settings
  progress.txt              position in each book
  last.txt                  the last book you opened
Ports/eReaderDS.sh        Ports menu entry
Ports/eReaderDS/
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
  into on-page directions for the sideways grip. (The code still supports a
  flipped grip via `S.orient`, but it is no longer offered: the buttons
  would sit under the wrong hand.)
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
| `app/zip.lua` | Minimal ZIP reader (stored and deflate); reads entries on demand |
| `app/store.lua` | Settings and progress files |
| `app/backlight.lua` | Screen brightness through sysfs |
| `app/touch.lua` | Raw evdev touchscreen reader (LuaJIT FFI) |
| `app/fonts.lua` | Font discovery, family/style grouping from the font name table, loading |
| `app/battery.lua` | Battery level for the status bar (sysfs, cached) |
| `app/keyprobe.lua` | Input diagnostics: logs input devices and the first raw key presses |
| `app/conf.lua` | LÖVE window configuration |
| `port/` | Device launch scripts |
| `tools/` | Desktop testing helpers |
| `app/version.lua` | Version string shown in the app and used for releases |
| `runtime/` | LÖVE 11.5 aarch64 engine and its libraries (see `runtime/NOTICES.md`) |

## Android (GammaOS)

`android/build.sh` makes `dist/eReaderDS-vX.Y.Z-android.apk`: LÖVE 11.5's
Android app (downloaded once to `android/cache/`) with `app/` unzipped in the
APK's `assets/` (LÖVE copies an `assets/game.love` to its cache on every
launch, ~3 s for ours; unzipped it reads the files in place), LÖVE's
embedded-game switch on, the
package renamed `com.casualducko.ereaderds`, our icon (`android/icon.png`), and
Google's OpenSSL 1.1.1 build for Android (for HTTPS). It needs Java 17,
apktool, the Android SDK build-tools (zipalign, apksigner) and python3.

**Signing:** Android only installs an update signed with the same key as the
installed app. The script uses `~/.android/ereaderds-release.keystore` (made on
the first build, password in the `.pass` file beside it). Back both up; a lost
key means everyone has to uninstall before the next version. Releases: build
locally and upload the APK to the release (`gh release upload vX.Y.Z
dist/eReaderDS-vX.Y.Z-android.apk`); the in-app updater looks for
`eReaderDS-v*-android.apk` on Android.

How it fits GammaOS (`app/android.lua`):
- **Both screens:** GammaOS's DualStack gives an app on
  `persist.gammaos.dualstack.pkgs` one 1024x1536 window, top screen above
  bottom. The app draws its usual 2048x768 frame (screens side by side) to a
  canvas and shows its halves stacked. It only gets both screens when it opens;
  another app's window makes DualStack let go.
- **Front end:** GammaOS's front end (`gammaos-nano`) draws over Android.
  Launch the app from it (Android apps); `am start` over ADB runs it underneath.
- **Touch:** LÖVE's own touch events (the top screen has none); the evdev
  reader is Linux-only.
- **No root:** GammaOS runs SELinux permissive, so any app may set
  `persist.gammaos.*` and restart GammaOS services (`ctl.restart`). First run
  adds the package to `dualstack.pkgs` (or `pkgs_1`, `pkgs_2`... when the 91
  characters are used up) and a gamepad profile (`gamepad.paN_*`, then
  `ctl.restart gammapad`) through `__system_property_set`. Magisk's question
  would open on display 0 under GammaOS's Control Center and time out, so
  root is used only to install updates. The backlight needs root, so the
  brightness is GammaOS's.
- **Installer's Open:** it starts the app outside the front end, which covers
  it; tap Done and launch from the front end.
- **Files:** books and data in `/sdcard/Ebook`; the built-in dictionary is
  copied out of the APK to `.ereaderds/bundled/`; Android's CA certificates are
  gathered into `.ereaderds/cacerts.pem` for OpenSSL.

Testing over ADB (files in `/sdcard/Ebook/.ereaderds/`):
- `.shot`: the app saves its next frame as `shot.png` (both screens side by
  side). Android's own screenshots don't show DualStack's window as the
  screens do.
- `.crash`: a test crash, for the crash screen and report.
- `.update-test` containing a URL: the updater reads that release list
  instead of GitHub's, so an update can be tried without publishing (serve a
  JSON list and a higher-version APK from a computer).

GammaOS stops apps outright when you go home (no chance to save on the way
out), so the app saves its place 0.4 s after a page turn and when it loses
focus. When it comes back (after sleep or the menu), DualStack reshapes the
window: the window is resizable on Android, or SDL waits for a rotation that
never comes and the app freezes. GammaOS's buttons
come from a virtual "Xbox Wireless Controller" (`getevent -pl`); `sendevent`
to it presses them, including in the front end.
