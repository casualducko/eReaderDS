# eReaderDS for iOS (the iPhone Duo)

The same app as on the handhelds (the Lua in `app/`), in LÖVE 11.5's iOS app. It's
made for the iPhone Duo, and runs on any iPhone or iPad (iOS 15 or later).

Status: built and tested in the iPhone Duo **simulator** (Xcode 27.1). It hasn't
been on a real device yet (the Duo isn't out).

## Build and run (simulator)

Needs Xcode 27.1 or later (it has the iOS 27.1 SDK and the iPhone Duo simulator),
the Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`), and the iOS
27.1 simulator runtime (Xcode → Settings → Components).

```
ios/build.sh                 # -> ios/cache/out/eReaderDS.app   (the first build takes ~10 minutes:
                             #    SDL2, LÖVE and OpenSSL are built from source, then kept in ios/cache)
ios/run.sh                   # boots an "eReaderDS Duo" simulator, installs, launches
BOOKS=~/some/books ios/run.sh   # the same, with those books put in the app first
```

`DEVELOPER_DIR=/Applications/Xcode-27.1-RC.app/Contents/Developer` picks another Xcode
than the active one. Xcode 27 replaced Simulator.app with **Device Hub** (the window with
the Duo's poses and the rotate button).

## How it differs from the handhelds

- **Screens.** The app draws its usual 2048x768 frame (two screens, each with a
  portrait page turned on its side, as the handheld is held like a book). Here each
  screen is turned back upright and shown as two portrait pages: **side by side**
  when the window is wide (the Duo open), **one above the other** when it's tall
  (a phone, the Duo closed). Whichever is larger wins, inside the safe area; the
  margins are the page's colour. The window follows folding and rotation
  (`app/android.lua`, "iOS").
- **Touch only.** The left page shows the book; the right page is the touchscreen
  (taps, swipes, pinch for text size, swipe up from the bottom for Settings). The
  button hints (A, B, Y) are also what you tap.
- **Books.** Files → On My iPhone → eReaderDS → `Ebook` (or "Open in eReaderDS"
  from Files, Mail or Share). Settings, progress and fonts are in `Ebook/.ereaderds`.
- **No updater** (TestFlight / the App Store do that), no quit, no lid, no
  screens-off timer (iOS's auto-lock applies). Brightness is the system's.
- **HTTPS** through OpenSSL's two libraries in the app (`Frameworks/`) and Mozilla's
  certificate list (`cacert.pem`); iOS has neither for apps to use.

## SDL2 is patched

Apps built with the iOS 27 SDK must use the UIScene life cycle (the app closes at
launch otherwise: "UIScene life cycle is required"), and a window that follows a
folding display has to live in a scene. SDL2 (what LÖVE 11 uses) has no scene
support yet, so `patches/sdl2-uiscene.patch` adds it to a pinned SDL2 commit:
the window is made in the scene and follows its size, and files opened in place
(from Files) can be read. When LÖVE moves to SDL3 this goes away.

## On a device, TestFlight, the App Store

You need a paid Apple Developer account. Build for a device:

```
ios/build.sh device          # unsigned build in ios/cache/out-device/eReaderDS.app
IOS_SIGN="Apple Development: Your Name (TEAMID)" IOS_PROFILE=path/to.mobileprovision ios/build.sh device
```

For TestFlight the simplest route is Xcode: make an iOS app project, or sign the
built app with a distribution certificate and an App Store profile and upload it
with `xcrun altool` / Transporter. The bundle id is `com.casualducko.ereaderds`.
(The signing path is written but untried: there's been no device.) An App Store
icon wants 1024 px: put it at `ios/icon-1024.png` (the Android icon, enlarged, is
used until then).

## Testing notes

- Device Hub turns a click into a touch only after the pointer has moved there
  (`cliclick m:x,y w:300 dd:x,y w:150 du:x,y`); the first one after a launch is
  often dropped.
- `xcrun simctl io <device> screenshot` is black in the Duo's open pose: take the
  screenshot of the Device Hub window instead (`screencapture`).
- `SIMCTL_CHILD_READER_DEBUG=1 xcrun simctl launch --console <device> com.casualducko.ereaderds`
  prints the app's log with touches.
- The poses take a few seconds to settle; the app gets a `resize` event with the
  new size.

## Not done yet

- A real device (only the simulator has been tried): signing, performance, battery.
- Notches and the Duo's hinge: the safe area is used, but nothing keeps text off
  the hinge crease (the book layout puts it between the two pages, which is where
  a spine is anyway).
- The first screen after install says "Copy files into the Ebook folder on the
  handheld's storage": the wording is from the handhelds.
