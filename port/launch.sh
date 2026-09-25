#!/bin/bash
# eReaderDS for RG DS Plus: two-page ebook reader, hold the device sideways.
set -u
APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export SDL_VIDEODRIVER=wayland
export SDL_VIDEO_DOUBLE_BUFFER=1
export LOVE_GRAPHICS_USE_OPENGLES=1
export LD_LIBRARY_PATH="$APP_DIR/runtime/libs.aarch64:/usr/lib:/lib"
# Settings and reading progress live outside the app folder, so replacing
# Ports/eReaderDS with a newer version never loses them.
if [ -d /mnt/mmc ]; then
    export READER_DATA="${READER_DATA:-/mnt/mmc/Ebook/.ereaderds}"
else
    export READER_DATA="${READER_DATA:-$APP_DIR/data}"
fi
export READER_BOOKS="${READER_BOOKS:-/mnt/mmc/Ebook:/mnt/sdcard/Ebook}"
mkdir -p "$READER_DATA"
# Bring settings over from older versions (named "Book Reader") once. Copy
# rather than move, so the old files stay as a backup.
if [ ! -f "$READER_DATA/settings.txt" ]; then
    for old in /mnt/mmc/Ebook/.bookreader /mnt/mmc/Ports/BookReader/data "$APP_DIR/data"; do
        [ "$old" != "$READER_DATA" ] && [ -f "$old/settings.txt" ] || continue
        for f in settings.txt progress.txt last.txt; do
            [ -f "$old/$f" ] && cp "$old/$f" "$READER_DATA/$f"
        done
        MIGRATED="$old"
        break
    done
fi
# First run: make the folders people put books and fonts in.
[ -d /mnt/mmc ] && mkdir -p /mnt/mmc/Ebook/Fonts 2>/dev/null
exec > "$APP_DIR/log.txt" 2>&1
printf '[launch] %s\n' "$(date -Iseconds 2>/dev/null || date)"
printf '[launch] data=%s%s\n' "$READER_DATA" "${MIGRATED:+ (copied from $MIGRATED)}"
chmod +x "$APP_DIR/runtime/love.aarch64" 2>/dev/null || true
# Remember the system brightness so the reader's own level doesn't stick afterwards.
BL_SAVED=""
for d in /sys/class/backlight/*; do
    [ -r "$d/brightness" ] || continue
    BL_SAVED="$BL_SAVED $d=$(cat "$d/brightness")"
done
printf '[launch] backlight:%s\n' "${BL_SAVED:- none}"
# Route the bottom touchscreen to the app (the firmware's app mode), as other
# dual-screen ports do; the previous mode is restored on exit.
TP=/sys/class/anbernic_misc/tpctrl
TP_SAVED=""
if [ -r "$TP" ] && [ -w "$TP" ]; then
    TP_SAVED=$(cat "$TP")
    [ "$TP_SAVED" = 1 ] && printf '0\n' > "$TP"
    printf '[launch] tpctrl %s -> %s\n' "$TP_SAVED" "$(cat "$TP")"
fi
cd "$APP_DIR/app" || exit 1
"$APP_DIR/runtime/love.aarch64" "$APP_DIR/app"
rc=$?
[ -n "$TP_SAVED" ] && printf '%s\n' "$TP_SAVED" > "$TP" 2>/dev/null
for e in $BL_SAVED; do
    printf '%s\n' "${e##*=}" > "${e%=*}/brightness" 2>/dev/null
done
printf '[launch] exit=%s\n' "$rc"
sync
exit "$rc"
