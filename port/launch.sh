#!/bin/bash
# Book Reader for RG DS Plus: two-page ebook reader, hold the device sideways.
set -u
APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export SDL_VIDEODRIVER=wayland
export SDL_VIDEO_DOUBLE_BUFFER=1
export LOVE_GRAPHICS_USE_OPENGLES=1
export LD_LIBRARY_PATH="$APP_DIR/runtime/libs.aarch64:/usr/lib:/lib"
export READER_DATA="$APP_DIR/data"
export READER_BOOKS="${READER_BOOKS:-/mnt/mmc/Ebook:/mnt/sdcard/Ebook}"
mkdir -p "$READER_DATA"
exec > "$READER_DATA/log.txt" 2>&1
printf '[launch] %s\n' "$(date -Iseconds 2>/dev/null || date)"
chmod +x "$APP_DIR/runtime/love.aarch64" 2>/dev/null || true
# Remember the system brightness so the reader's own level doesn't stick afterwards.
BL_SAVED=""
for d in /sys/class/backlight/*; do
    [ -r "$d/brightness" ] || continue
    BL_SAVED="$BL_SAVED $d=$(cat "$d/brightness")"
done
printf '[launch] backlight:%s\n' "${BL_SAVED:- none}"
cd "$APP_DIR/app" || exit 1
"$APP_DIR/runtime/love.aarch64" "$APP_DIR/app"
rc=$?
for e in $BL_SAVED; do
    printf '%s\n' "${e##*=}" > "${e%=*}/brightness" 2>/dev/null
done
printf '[launch] exit=%s\n' "$rc"
sync
exit "$rc"
