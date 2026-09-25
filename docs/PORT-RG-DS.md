# Notes: porting eReaderDS to the original Anbernic RG DS

Research notes from 2026-09-25, kept for later. Nothing here is implemented yet.

## Summary

It should work on the original RG DS **when it runs Linux**, with moderate
work. Under the RG DS's default Android it's a separate, much bigger project.

## RG DS vs RG DS Plus

| | RG DS Plus (current target) | Original RG DS |
|---|---|---|
| Chip | RK3568, 4× Cortex-A55 up to 2.0 GHz, Mali-G52 | **Same** |
| Screens | 2 × 4.3" IPS, **1024×768** each | 2 × 4.0" IPS, **640×480** each |
| Touch | Bottom screen (gt9xx) | Touch with capacitive stylus; possibly both screens (unconfirmed) |
| OS | Linux | **Android 14** by default. Linux boots from SD: Anbernic's official dual-screen Linux (v1.0-260513, May 2026), ROCKNIX, KNULLI (alpha, supporters only), or GammaOS Next (Android) |
| RAM | 1 GB | 3 GB |
| Controls | One analog stick | Two analog sticks; otherwise the same buttons |

The same chip means the bundled LÖVE 11.5 aarch64 runtime runs as-is. Anbernic
probably uses the same button controller name (`ANBERNIC-rk3568-keys`) and a
similar Wayland setup on both models. Both are unconfirmed.

## What would need to change

1. **Resolution independence (main job).** The app assumes 1024×768 screens
   everywhere (`SCREEN_W/H`, 768×1024 page canvases, pixel margins, menu
   geometry, UI font sizes). 640×480 is exactly 0.625× 1024×768, with the same
   aspect ratio. Plan: keep all layout in the current logical coordinates and
   render at a scale:
   - `love.graphics.newCanvas(768, 1024, { dpiscale = 0.625 })` for page
     canvases (pixel size 480×640), and
   - fonts created with a matching `dpiscale`, so text renders crisply at
     native resolution instead of being downsampled.

   Touch coordinates scale the same way. This also makes other screen sizes
   easier later.
2. **Screen detection.** The Plus composes both screens into one 2048×768
   Wayland surface (top = x 0–1023, bottom = x 1024–2047). The RG DS under
   Anbernic Linux is probably 1280×480, but it might be two separate displays
   or stacked vertically. Detect at startup (`love.window.getDisplayCount`,
   `getDesktopDimensions` per display) instead of hardcoding `conf.lua`'s
   2048×768.
3. **Touch.** The evdev device name may differ from `gt9xx-0`, and there may be
   two touchscreens. `touch.lua` already reads the axis ranges through
   `EVIOCGABS`. It would need device discovery by capability rather than
   name, and support for more than one screen.
4. **Paths and launcher.**
   - Anbernic Linux: `/mnt/mmc` and `Ports/` may carry over (check).
   - ROCKNIX / KNULLI: different paths (e.g. `/storage/roms/ports`), sway or
     other compositors, and ports installed through **PortMaster**
     (`control.txt` conventions). A PortMaster-style launcher would cover
     these and other devices.
5. **Brightness and touch mode.** Brightness uses standard
   `/sys/class/backlight` and should work. `/sys/class/anbernic_misc/tpctrl`
   may not exist; `launch.sh` already skips it when missing.
6. **Defaults.** Pages are physically smaller (4.0"), so default text size
   and margins likely need tuning.

## Android (the RG DS default)

LÖVE runs on Android but draws to one display only. A page on each screen
would need native Android code for the second display (Presentation API),
which amounts to a separate project. The first RG DS version should say:
"requires the RG DS's Linux mode (boots from SD; Android is untouched)."

## Plan when we pick this up

1. **Device-info mode first.** On startup, write to `log.txt`:
   - display count and each display's size and position
   - joystick names and GUIDs
   - `/proc/bus/input/devices`
   - `/sys/class/backlight/*` (with max values)
   - whether `tpctrl` exists
   - SD mount points and where the Ports folder is

   Ideally it also shows a text page on whatever screen it finds. Most of this
   is useful on the Plus too, so it could ship in a normal beta.
2. Send that build to one or two RG DS owners (ideally one on Anbernic Linux,
   one on ROCKNIX) and collect their `log.txt`.
3. Implement dpiscale rendering and screen detection in one pass, then test
   with them.

## Reference: RG DS Plus input devices (stock firmware)

From `/proc/bus/input/devices`, logged by `keyprobe.lua`, for comparison with
the RG DS:

| Device | Name | Notes |
|---|---|---|
| event0 | `rk805 pwrkey` | Power button |
| event1 | `gt9xx-0` | Bottom touchscreen (0–1024 × 0–768) |
| event2 | `headset-keys` | Headset button |
| event3 | `rockchip-rk817 Headset` | Headset jack |
| event4 | `adc-keys` | Curved-arrow button → `KEY_BACK` (158), SDL key `appback` |
| event5 | `ANBERNIC-rk3568-keys` | Gamepad. Stick click = button 9 (`BTN_TL2`, 313). Stick axes: raw 0 = left/right, raw 1 = up/down (+ = down) |
| event6 | `dierct-keys-polled` | Other polled keys |

## Sources

- [Anbernic: RG DS vs. RG DS Plus](https://anbernic.com/blogs/news/rg-ds-plus-vs-rg-ds)
- [Anbernic RG DS product page](https://anbernic.com/products/rgds)
- [Retro Handhelds: RG DS gets a new Linux firmware that embraces dual screens](https://retrohandhelds.gg/anbernic-rg-ds-gets-a-new-linux-firmware-that-finally-embraces-dual-screens/)
- [Retro Handhelds: installing GammaOS, Anbernic Linux, ROCKNIX and KNULLI on the RG DS](https://retrohandhelds.gg/anbernic-rg-ds-how-to-install-gammaos-anbernic-linux-rocknix-and-knulli/)
- [Retro Society: dual boot GammaOS and ROCKNIX or Linux on RG DS](https://retrosociety.co/dual-boot-gammaos-rocknix-rgds/)
- [HandheldRank: RG DS vs. RG DS Plus](https://www.handheldrank.com/anbernic-rg-ds-vs-rg-ds-plus/)
- [Retro Catalog: Anbernic RG DS specifications](https://retrocatalog.com/retro-handhelds/anbernic-rg-ds)
- [Max Glenister: Anbernic RG DS review](https://blog.omgmog.net/post/anbernic-rg-ds-review/)
