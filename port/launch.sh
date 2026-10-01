#!/bin/bash
# eReaderDS for RG DS Plus: two-page ebook reader, hold the device sideways.
# Runs on the stock firmware (Ports/eReaderDS) and on ROCKNIX (roms/ports).
set -u
T0=$(cut -d" " -f1 /proc/uptime 2>/dev/null)     # for the log: how long starting takes
APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
ROCKNIX=""
grep -qs 'OS_NAME="ROCKNIX"' /etc/os-release && ROCKNIX=1

# ROCKNIX: put the menu icon in the Ports list. EmulationStation only shows an
# image listed for the game, and it keeps its game list in memory: editing
# gamelist.xml gets overwritten by its play stats, and a reload redraws the
# menu. Its /addgames call instead updates the game in memory and saves the
# file, with no reload. It only takes effect once the game has ended, so this
# runs on its own after eReaderDS exits.
if [ "${1:-}" = "--menu-icon" ]; then
    ES=http://127.0.0.1:1234
    PORTS=$(dirname "$APP_DIR")
    for i in $(seq 1 60); do
        [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' $ES/runningGame)" = 201 ] && break
        sleep 1
    done
    for attempt in 1 2 3; do
        sleep 2
        curl -s -m 10 -X POST $ES/addgames/ports -d "<?xml version=\"1.0\"?><gameList><game>\
<path>$PORTS/eReaderDS.sh</path><image>$PORTS/images/eReaderDS-image.png</image>\
</game></gameList>" >/dev/null
        sleep 1
        grep -qs 'eReaderDS-image.png' "$PORTS/gamelist.xml" && break
    done
    exit 0
fi
# Updates: eReaderDS unpacks the files of a newer version that changed into
# .delta (READY is written last, once it's complete), and lists files the new
# version dropped in .delta/DELETE. Move each one over the installed file
# before starting: a rename on the same card, so it's instant. A moved file
# leaves .delta, so if this is cut short (power off) the next start carries
# on where it stopped; READY goes last. This launcher is moved last too (the
# shell running it keeps the old copy open, so it isn't disturbed).
# Settings, progress and books live elsewhere.
apply_delta() {
    local U="$APP_DIR/.delta" PORTS rel
    PORTS=$(dirname "$APP_DIR")
    [ -f "$U/READY" ] || return 1
    if [ -d "$U/eReaderDS" ]; then
        # The list first, then the moves (not moving files out of the folder
        # find is still reading).
        local files
        mapfile -t files < <(cd "$U/eReaderDS" && find . -type f)
        for rel in "${files[@]}"; do
            rel=${rel#./}
            [ "$rel" = launch.sh ] && continue
            mkdir -p "$APP_DIR/$(dirname "$rel")" && mv -f "$U/eReaderDS/$rel" "$APP_DIR/$rel" || return 1
        done
    fi
    if [ -f "$U/DELETE" ]; then
        while IFS= read -r rel; do
            case "$rel" in *..*) ;; app/?*) rm -f "$APP_DIR/$rel" ;; esac
        done < "$U/DELETE"
    fi
    if [ -f "$U/eReaderDS.sh" ]; then mv -f "$U/eReaderDS.sh" "$PORTS/eReaderDS.sh" || return 1; fi
    if [ -f "$U/Imgs/eReaderDS.png" ] && [ -d "$PORTS/Imgs" ]; then
        mv -f "$U/Imgs/eReaderDS.png" "$PORTS/Imgs/eReaderDS.png" || return 1
    fi
    chmod +x "$PORTS/eReaderDS.sh" "$APP_DIR/runtime/love.aarch64" 2>/dev/null
    if [ -f "$U/eReaderDS/launch.sh" ]; then
        chmod +x "$U/eReaderDS/launch.sh" 2>/dev/null
        mv -f "$U/eReaderDS/launch.sh" "$APP_DIR/launch.sh" || return 1
    fi
    sync
    rm -rf "$U"
    sync
    return 0
}
# Versions before v0.3.24 unpacked the whole new version into .update and
# swapped it in (kept for one left waiting when this launcher arrived).
apply_update() {
    local U="$APP_DIR/.update" PORTS
    PORTS=$(dirname "$APP_DIR")
    [ -f "$U/READY" ] && [ -f "$U/eReaderDS/app/main.lua" ] && [ -f "$U/eReaderDS/launch.sh" ] || return 1
    rm -rf "$APP_DIR/app.old"
    mv "$APP_DIR/app" "$APP_DIR/app.old" || return 1
    if ! mv "$U/eReaderDS/app" "$APP_DIR/app"; then mv "$APP_DIR/app.old" "$APP_DIR/app"; return 1; fi
    rm -rf "$APP_DIR/app.old"
    mv "$U/eReaderDS/launch.sh" "$APP_DIR/launch.sh.new"
    cp -R "$U/eReaderDS/." "$APP_DIR/" 2>/dev/null            # runtime, icon, notes, licences
    [ -f "$U/eReaderDS.sh" ] && cp "$U/eReaderDS.sh" "$PORTS/eReaderDS.sh.new" && mv -f "$PORTS/eReaderDS.sh.new" "$PORTS/eReaderDS.sh"
    [ -d "$PORTS/Imgs" ] && [ -f "$U/Imgs/eReaderDS.png" ] && cp "$U/Imgs/eReaderDS.png" "$PORTS/Imgs/eReaderDS.png"
    chmod +x "$APP_DIR/launch.sh.new" "$PORTS/eReaderDS.sh" "$APP_DIR/runtime/love.aarch64" 2>/dev/null
    mv -f "$APP_DIR/launch.sh.new" "$APP_DIR/launch.sh"
    rm -rf "$U"
    sync
    return 0
}
if apply_delta || apply_update; then exec /bin/bash "$APP_DIR/launch.sh" "$@"; fi
# Left over from an update that was cut short (quit while downloading or
# unpacking: no READY marker): free the space; the app offers it again. A
# .delta with READY that couldn't be finished stays, to finish next time
# (half of it may already be in place).
[ -d "$APP_DIR/.delta" ] && [ ! -f "$APP_DIR/.delta/READY" ] && rm -rf "$APP_DIR/.delta"
rm -rf "$APP_DIR/.update"
rm -f "$APP_DIR/.update.zip" "$APP_DIR/.update.zip.part"

if [ -n "$ROCKNIX" ]; then
    # Its Wayland display, sway socket and controller database (the buttons
    # are "retrogame_joypad" there); set -u off for its profile scripts.
    set +u; . /etc/profile; set -u
    # SDL drops controller input unless it thinks its window has keyboard
    # focus, which it never gets under ROCKNIX's sway (there's no keyboard).
    export SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export SDL_VIDEODRIVER=wayland
export SDL_VIDEO_DOUBLE_BUFFER=1
export LOVE_GRAPHICS_USE_OPENGLES=1
export LD_LIBRARY_PATH="$APP_DIR/runtime/libs.aarch64:/usr/lib:/lib"
# ROCKNIX lacks a library LÖVE links to (libtheoradec); only used there.
[ -n "$ROCKNIX" ] && LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$APP_DIR/runtime/libs.rocknix"
# Settings and reading progress live outside the app folder, so replacing
# Ports/eReaderDS with a newer version never loses them.
if [ -n "$ROCKNIX" ]; then
    export READER_DATA="${READER_DATA:-/storage/roms/ebook/.ereaderds}"
    export READER_BOOKS="${READER_BOOKS:-/storage/roms/ebook}"
    export READER_FONTS="${READER_FONTS:-/storage/roms/ebook/Fonts}"
    export READER_DEFAULT_BRIGHTNESS=40     # 20% (the stock default) is too dim here
    mkdir -p /storage/roms/ebook/Fonts /storage/roms/ebook/Dictionaries 2>/dev/null
elif [ -d /mnt/mmc ]; then
    export READER_DATA="${READER_DATA:-/mnt/mmc/Ebook/.ereaderds}"
else
    export READER_DATA="${READER_DATA:-$APP_DIR/data}"
fi
export READER_BOOKS="${READER_BOOKS:-/mnt/mmc/Ebook:/mnt/sdcard/Ebook}"
# Bring settings over from older versions (named "Book Reader") once: only
# on the very first start, when there's no data folder yet (after Settings →
# Reset there is one, emptied, and old settings mustn't come back). Copy
# rather than move, so the old files stay as a backup.
FIRST_START=""
[ -d "$READER_DATA" ] || FIRST_START=1
mkdir -p "$READER_DATA"
if [ -n "$FIRST_START" ] && [ ! -f "$READER_DATA/settings.txt" ]; then
    for old in /mnt/mmc/Ebook/.bookreader /mnt/mmc/Ports/BookReader/data "$APP_DIR/data"; do
        [ "$old" != "$READER_DATA" ] && [ -f "$old/settings.txt" ] || continue
        for f in settings.txt progress.txt last.txt; do
            [ -f "$old/$f" ] && cp "$old/$f" "$READER_DATA/$f"
        done
        MIGRATED="$old"
        break
    done
fi
# Stock firmware, first run: make the folders people put books and fonts in.
[ -z "$ROCKNIX" ] && [ -d /mnt/mmc ] && mkdir -p /mnt/mmc/Ebook/Fonts 2>/dev/null
# Stock firmware: the menu shows Ports/Imgs/<name>.png next to a port. Put the
# icon there if it's missing (e.g. only eReaderDS.sh and the folder were
# copied). The menu restarts when a port exits, so it shows on the way out.
if [ -z "$ROCKNIX" ] && [ -d /mnt/mmc ] && [ -f "$APP_DIR/icon.png" ]; then
    IMGS="$(dirname "$APP_DIR")/Imgs"
    [ -f "$IMGS/eReaderDS.png" ] || { mkdir -p "$IMGS" && cp "$APP_DIR/icon.png" "$IMGS/eReaderDS.png"; } 2>/dev/null
fi
exec > "$APP_DIR/log.txt" 2>&1
printf '[launch] %s (uptime %s)\n' "$(date -Iseconds 2>/dev/null || date)" "${T0:-?}"
printf '[launch] data=%s%s\n' "$READER_DATA" "${MIGRATED:+ (copied from $MIGRATED)}"
chmod +x "$APP_DIR/runtime/love.aarch64" 2>/dev/null || true
# Remember the system brightness so the reader's own level doesn't stick
# afterwards, and each backlight's power (the reader turns it off when the
# screens sleep; if it's stopped then, they'd stay dark).
BL_SAVED=""
BLP_SAVED=""
for d in /sys/class/backlight/*; do
    [ -r "$d/brightness" ] || continue
    BL_SAVED="$BL_SAVED $d=$(cat "$d/brightness")"
    [ -r "$d/bl_power" ] && BLP_SAVED="$BLP_SAVED $d=$(cat "$d/bl_power")"
done
printf '[launch] backlight:%s\n' "${BL_SAVED:- none}"
printf '[launch] power state: %s; mem_sleep: %s\n' "$(cat /sys/power/state 2>/dev/null)" "$(cat /sys/power/mem_sleep 2>/dev/null)"
# Route the bottom touchscreen to the app (the firmware's app mode), as other
# dual-screen ports do; the previous mode is restored on exit.
TP=/sys/class/anbernic_misc/tpctrl
TP_SAVED=""
if [ -r "$TP" ] && [ -w "$TP" ]; then
    TP_SAVED=$(cat "$TP")
    [ "$TP_SAVED" = 1 ] && printf '0\n' > "$TP"
    printf '[launch] tpctrl %s -> %s\n' "$TP_SAVED" "$(cat "$TP")"
fi
# Put the device back as it was: the touchscreen mode and the brightness, and
# on ROCKNIX the bottom screen (off in its menu) and the menu's focus. Also run
# if the launcher is told to stop (e.g. by a system exit hotkey).
pid=""
restore() {
    if [ -n "$ROCKNIX" ] && command -v swaymsg >/dev/null; then
        swaymsg 'output DSI-1 power off' >/dev/null 2>&1
        swaymsg '[app_id="emulationstation"] focus' >/dev/null 2>&1
    fi
    [ -n "$TP_SAVED" ] && printf '%s\n' "$TP_SAVED" > "$TP" 2>/dev/null
    for e in $BLP_SAVED; do
        printf '%s\n' "${e##*=}" > "${e%=*}/bl_power" 2>/dev/null
    done
    for e in $BL_SAVED; do
        printf '%s\n' "${e##*=}" > "${e%=*}/brightness" 2>/dev/null
    done
}
# (On a stop signal: the app is asked to quit, and given a few seconds to save
# before the screens are put back.)
stopped() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        for i in 1 2 3 4 5 6; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    fi
    restore
    printf "[launch] stopped by a signal\n"
    sync
    exit 143
}
trap stopped TERM INT HUP

cd "$APP_DIR/app" || exit 1
if [ -n "$ROCKNIX" ] && command -v swaymsg >/dev/null; then
    # sway puts windows on one screen and keeps the bottom one off in the
    # menu: turn it on and stretch the window over both (restore() turns it
    # off again and gives the menu back its focus).
    "$APP_DIR/runtime/love.aarch64" "$APP_DIR/app" &
    pid=$!
    swaymsg 'output DSI-1 power on' >/dev/null
    # Wait for its window (the first run can be slow), for as long as it runs.
    for i in $(seq 1 300); do
        swaymsg "[pid=$pid] fullscreen enable global, focus" >/dev/null 2>&1 && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    wait "$pid"
    rc=$?
    pid=""
    restore
    # The menu icon (see --menu-icon above), once EmulationStation is back.
    PORTS=$(dirname "$APP_DIR")
    if [ -f "$APP_DIR/icon.png" ]; then
        mkdir -p "$PORTS/images"
        cmp -s "$APP_DIR/icon.png" "$PORTS/images/eReaderDS-image.png" ||
            cp "$APP_DIR/icon.png" "$PORTS/images/eReaderDS-image.png"
        grep -qs 'eReaderDS-image.png' "$PORTS/gamelist.xml" ||
            setsid /bin/bash "$APP_DIR/launch.sh" --menu-icon </dev/null >/dev/null 2>&1 &
    fi
else
    # In the background and waited for, so a stop signal is handled at once.
    printf '[launch] starting the app (uptime %s)\n' "$(cut -d" " -f1 /proc/uptime 2>/dev/null)"
    "$APP_DIR/runtime/love.aarch64" "$APP_DIR/app" &
    pid=$!
    wait "$pid"
    rc=$?
    pid=""
    restore
fi
printf '[launch] exit=%s\n' "$rc"
sync
# The app asked to restart into a downloaded update.
if [ "$rc" = 42 ] && { apply_delta || apply_update; }; then exec /bin/bash "$APP_DIR/launch.sh" "$@"; fi
exit "$rc"
