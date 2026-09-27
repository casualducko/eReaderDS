#!/bin/bash
# eReaderDS for RG DS Plus: two-page ebook reader, hold the device sideways.
# Runs on the stock firmware (Ports/eReaderDS) and on ROCKNIX (roms/ports).
set -u
APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
ROCKNIX=""
grep -qs 'OS_NAME="ROCKNIX"' /etc/os-release && ROCKNIX=1

# ROCKNIX: put the menu icon in the Ports list. EmulationStation only shows an
# image listed in the folder's gamelist.xml, and it rewrites that file from
# memory when a game ends (play stats) and when it reloads. So this runs on
# its own after eReaderDS exits: wait until EmulationStation says no game is
# running, reload (it saves its stats), add the entry, and reload again.
if [ "${1:-}" = "--menu-icon" ]; then
    ES=http://127.0.0.1:1234
    PORTS=$(dirname "$APP_DIR")
    # EmulationStation says no game is running before its launcher script
    # (runemu.sh) has finished, and saves the play stats after that.
    for i in $(seq 1 120); do
        pgrep -f /usr/bin/runemu.sh >/dev/null || break
        sleep 1
    done
    for attempt in 1 2 3; do
        sleep 3
        curl -s -m 60 $ES/reloadgames >/dev/null
        python3 - "$PORTS" <<'EOF' | grep -q changed && curl -s -m 60 $ES/reloadgames >/dev/null
import sys, os, xml.etree.ElementTree as ET
g = os.path.join(sys.argv[1], 'gamelist.xml')
if os.path.exists(g):
    try: t = ET.parse(g)
    except ET.ParseError: sys.exit()
    root = t.getroot()
else:
    root = ET.Element('gameList'); t = ET.ElementTree(root)
e = next((x for x in root.findall('game') if x.findtext('path') == './eReaderDS.sh'), None)
if e is None:
    e = ET.SubElement(root, 'game')
    ET.SubElement(e, 'path').text = './eReaderDS.sh'
    ET.SubElement(e, 'name').text = 'eReaderDS'
i = e.find('image')
if i is None: i = ET.SubElement(e, 'image')
if i.text != './images/eReaderDS-image.png':
    i.text = './images/eReaderDS-image.png'
    ET.indent(t, '\t')
    t.write(g + '.tmp', encoding='utf-8', xml_declaration=True)
    os.replace(g + '.tmp', g)
    print('changed')
EOF
        sleep 5                                 # still there once it settles?
        grep -qs 'eReaderDS-image.png' "$PORTS/gamelist.xml" && break
    done
    exit 0
fi
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
    mkdir -p /storage/roms/ebook/Fonts 2>/dev/null
elif [ -d /mnt/mmc ]; then
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
cd "$APP_DIR/app" || exit 1
if [ -n "$ROCKNIX" ] && command -v swaymsg >/dev/null; then
    # sway puts windows on one screen and keeps the bottom one off in the
    # menu: turn it on and stretch the window over both, and afterwards turn
    # it off and give the menu back its focus.
    "$APP_DIR/runtime/love.aarch64" "$APP_DIR/app" &
    pid=$!
    swaymsg 'output DSI-1 power on' >/dev/null
    for i in $(seq 1 50); do
        swaymsg "[pid=$pid] fullscreen enable global, focus" >/dev/null 2>&1 && break
        sleep 0.2
    done
    wait "$pid"
    rc=$?
    swaymsg 'output DSI-1 power off' >/dev/null
    swaymsg '[app_id="emulationstation"] focus' >/dev/null
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
    "$APP_DIR/runtime/love.aarch64" "$APP_DIR/app"
    rc=$?
fi
[ -n "$TP_SAVED" ] && printf '%s\n' "$TP_SAVED" > "$TP" 2>/dev/null
for e in $BL_SAVED; do
    printf '%s\n' "${e##*=}" > "${e%=*}/brightness" 2>/dev/null
done
printf '[launch] exit=%s\n' "$rc"
sync
exit "$rc"
