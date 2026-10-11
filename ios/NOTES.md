# iOS port notes (the iPhone Duo)

Everything learned while porting eReaderDS to iOS (started 2026-10-10). `README.md` here is the
short how-to; this file is the why and the gotchas. Status: built and tested **only in the Xcode
simulator**. No real device has run it.

## Goal and decisions

- The user wanted eReaderDS on the iPhone Duo, which has the same form factor as the Microsoft
  Surface Duo that the Android port already runs on. Same repo, `ios/` beside `android/`, the same
  Lua in `app/` (not a fork).
- **The app is a dual-screen reader and only shows the reader open.** Wide window (Duo open) = two
  portrait pages side by side. Tall window (Duo closed, phone upright) = only the note "Open your
  iPhone Duo to read". No one-above-the-other column layout (removed on request). A phone held
  sideways gets the two pages small.
- No quit row/action on iOS (LÖVE restarts the game when it quits), no update checker (TestFlight /
  App Store updates), no lid/grip/screens-off settings, no hardware-button hints needing buttons.
- The user has an Apple account but no device. The Duo hasn't shipped (pre-order ~Oct 16, ships
  ~Oct 23 2026), so all testing is in the simulator.
- Commit and push only when asked; the shared Lua changes were not re-run on the RG DS Plus
  (stock/ROCKNIX) or GammaOS handhelds before the first push (it was pushed anyway on request).
  Test them there before the next release. No version bump or release was made for iOS.

## Tooling

- Xcode **27.1** (Release Candidate) at `/Applications/Xcode-27.1-RC.app`; the older Xcode 27.0 stays
  the active one, so build with
  `DEVELOPER_DIR=/Applications/Xcode-27.1-RC.app/Contents/Developer`. 27.0 can't target the Duo.
- Xcode 27 replaced Simulator.app with **Device Hub** (`Contents/Applications/DeviceHub.app`).
- Needs the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`) and the iOS 27.1
  simulator runtime. `xcodes` was installed with brew but not used.
- Simulators: "eReaderDS Duo" (made by `run.sh`, the one used for testing), "Duo" and "iPhone Duo"
  (auto-created), "Phone270" (iPhone 18 Pro, iOS 27.0 runtime). The 27.1 runtime only offers the Duo;
  older 27.0 devices fail with "Data Migration Failed" (recreate them instead).
- Build: `ios/build.sh` (first build ~10 min, later ~20 s when only Lua changes), run: `ios/run.sh`
  (`BOOKS=<dir>` copies books in, `DEVICE=<name>`, `shot <file>`).

## The Duo (as the simulator shows it)

- A book-style foldable, one continuous display, vertical hinge.
- Closed pose: outer display 466x678 pt (1398x2034 px, 3x), about 84 pt of it reserved by the system on
  the right and a 34 pt bottom inset (safe area 382x644).
- Open-book pose: 951x669 pt, landscape, hinge in the middle.
- Apple: apps built with the iOS 27.1 SDK go edge to edge and must follow resizing. Real-device
  behaviour (poses, hinge, performance, battery) is unknown.

## How the build works (`ios/build.sh`)

LÖVE 11.5's iOS app is built from source into the gitignored `ios/cache/`:

1. Clones LÖVE 11.5, `love-apple-dependencies` (11.x) and **SDL2 pinned at commit 74be4c28...**,
   applies `ios/patches/sdl2-uiscene.patch`. The patch's checksum is stored; a changed patch deletes
   the SDL checkout and rebuilds. A failed patch removes the checkout.
2. Builds SDL2 static library and LÖVE (deployment target iOS 15.0, arm64; simulator build is
   arm64-only, so Apple silicon Macs).
3. Builds **OpenSSL 3.0.22** as two dylibs, embedded in `Frameworks/` with `@loader_path` install
   names. iOS gives apps no libssl, and `app/net.lua` loads it through FFI.
4. Bundles Mozilla's `cacert.pem` (from curl.se) next to the app; iOS has no PEM file for apps.
5. Zips `app/` as `game.love` (no dotfiles, no `data/`).
6. Icon: `android/icon.png` enlarged to 1024 (override with `ios/icon-1024.png`), compiled with
   `actool`. Launch screen: `ios/LaunchScreen.storyboard` (navy 40,52,78).
7. Edits Info.plist: bundle id `com.casualducko.ereaderds`, version from `app/version.lua`
   (build number = major*1e6 + minor*1e3 + patch), UIScene manifest (`SDLUIKitSceneDelegate`),
   `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` (Files shows the Documents folder),
   all orientations, status bar hidden, `UIApplicationSupportsIndirectInputEvents`, document types
   for epub/cbz/txt (+ an exported cbz UTI), `NSLocalNetworkUsageDescription`,
   `ITSAppUsesNonExemptEncryption=false`.
8. `build.sh device` builds an unsigned device app (verified to compile: arm64, platform IOS,
   minos 15.0). Signing with `IOS_SIGN` / `IOS_PROFILE` is written but **never tried**.

## The SDL2 patch (why it exists)

- iOS 27 SDK apps must use the **UIScene life cycle**; without it the app exits at launch with
  "UIScene life cycle is required for apps built with this SDK". SDL2 (what LÖVE 11 uses) has no scene
  support. The patch adds `SDLUIKitSceneDelegate`, makes the window in the scene (so it follows
  folding/resizing), skips SDL's own launch-screen window under scenes, and removes the orientation
  flip in `UIKit_ComputeViewFrame`.
- Files opened in place (Files app) need `startAccessingSecurityScopedResource` (done).
- **Files handed over while the app starts are queued** and sent once the window exists, because
  SDL's event queue isn't active yet at that point (before this fix a book opened with "Open in
  eReaderDS" on a closed app was lost).
- Borderless windows hide the home indicator when idle. LÖVE makes the iOS window fullscreen, and SDL
  then defers system gestures on all edges, so a swipe up from the very bottom edge needs a second
  swipe to go home. (Not verified on a device.)
- When LÖVE moves to SDL3 the patch goes away.
- SDL's own repo has a CLAUDE.md asking that generative AI not be used for contributions to SDL. The
  patch is a private build patch, not submitted upstream; don't send it upstream.

## Lua side

- `app/android.lua` is the shared "no shell" platform module: `M.android`, `M.ios`, `M.active`
  (true for both). On iOS: ROOT = app Documents (derived from the save dir), BOOKS = `Documents/Ebook`,
  DATA = `Documents/Ebook/.ereaderds` (settings, progress, fonts), CACHE = `Library/Caches` (the
  bundled dictionary is copied there). Darwin `dirent` layout. UIKit is called through the
  Objective-C runtime via FFI (safe-area insets, `UIScreen` brightness), each call inside its own
  autorelease pool. `love.window.getSafeArea` is wrong under scenes, hence the FFI call; insets are
  cached 0.5 s.
- Layout (`ios_layout`, `present`, `bottom_xy`): the 2048x768 frame canvas holds two 1024x768 screens,
  each drawn rotated back (-π/2) as a 768x1024 upright page. Book mode scales both pages into the
  safe area; margins are the theme background colour (navy during the splash). Closed mode draws the
  note and ignores touches. `bottom_xy` inverts the mapping for touch.
- Canvases are forced to dpiscale 1 (the screen is 3x; the app sizes everything in its own units).
  `conf.lua`: highdpi + resizable on iOS.
- `app/sysfs.lua` (thread-safe, FFI): `ls`, `find`, `free_bytes` (statfs) without a shell, because
  iOS has no `io.popen`/`os.execute` (the simulator's `os.execute` returns -1; real devices likely
  lack popen). Used by dict scan, receiver, calibre, backup, main. Linux/Android still use the old
  commands where behaviour must not change.
- Other iOS branches: touch.lua (shared with Android), net.lua (bundle OpenSSL + cacert), battery.lua
  (`love.system.getPowerInfo`), backlight.lua (UIScreen brightness), store.lua (idle default 0,
  books-folder wording), zip.lua/backup.lua (libz name, Darwin dirent).
- main.lua: `app.device_rows()`, `app.help_quit_rows()`, `love.filedropped` (imports epub/cbz/txt into
  Ebook, copies in 1 MB pieces, never overwrites, says "already in My Books" for an identical file,
  deletes only copies under `/Documents/Inbox/`), display sleep enabled (iOS auto-lock applies),
  system text input off, `app.system_name()` = "iOS", progress and settings saved on focus loss.
- Checked with `luajit -bl` for stray globals (see the "Lua global checks" habit).

## What was tested in the simulator (both poses)

Launch, library with covers, opening books, two-page spreads, page turns by tap, dictionary (WordNet,
long-press), Get Books over HTTPS (Standard Ebooks), Wi-Fi receiver (QR + address; curl upload landed
in Ebook), file import via `simctl openurl` (also with the app closed), Settings via swipe-up and
swipe-left (brightness row present, Quit gone), Back Up (settings and Everything zips), in-process
restart on quit, pose changes (settle after a few seconds), icon, an iPhone 18 Pro (note shown when
upright), touch hit-mapping.

## Testing quirks

- Device Hub only turns a click into a touch after the pointer has moved there:
  `cliclick m:x,y w:300 dd:x,y w:150 du:x,y`; the first touch after a launch is often dropped.
  cliclick uses points (screenshot pixels / 2 on this Mac). **Bring Device Hub to the front first**
  (`osascript -e 'tell application "Device Hub" to activate'`), or the clicks land in another window.
- `simctl io screenshot` is black in the open pose: use `screencapture` of the Hub window.
- `SIMCTL_CHILD_READER_DEBUG=1 xcrun simctl launch --console <udid> com.casualducko.ereaderds` prints the
  log (touches too).
- `simctl install` gives a fresh data container, hence `BOOKS=` in run.sh.
- `simctl openurl file://...` can take 20+ s to return and the copy arrives late; check afterwards.
  `simctl terminate` can hang on a stuck simulator: shut it down and boot again.

## Not done / open

- A real device: signing, TestFlight, performance, memory, battery, real Duo poses and hinge behaviour.
- Apple Developer account (paid) needed for a device or TestFlight; App Store review rules for a
  bundled-Lua reader are unchecked; a 1024 px icon is wanted (`ios/icon-1024.png`).
- Shared Lua changes untested on the RG DS Plus and GammaOS handhelds.
- No CHANGELOG / whatsnew entries (only needed for a real iOS release; then add them, tag, check).
- Button hint letters (A, B, Y) remain, since they double as tap targets. The first-run text still says
  "handheld's storage" in one place. Nothing keeps text off the hinge crease beyond the book layout
  putting it between the pages.
- Minor: `startAccessingSecurityScopedResource` is never balanced (bounded by the files opened).
