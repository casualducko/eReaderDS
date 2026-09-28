#!/bin/bash
# Install or update eReaderDS on an RG DS Plus SD card from a clone of this
# repo (macOS/Linux). Most people should use the release zip instead: see README.
# Settings and reading progress (Ebook/.ereaderds) are kept.
#
#   ./install.sh [/Volumes/ROMS]      from the SD card in the computer
#   ./install.sh --ssh [device-ip]    over Wi-Fi to the device (SSH as root)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)

# Over Wi-Fi: ./install.sh --ssh [host]   (host defaults to the one in .device)
if [ "${1:-}" = "--ssh" ]; then
    HOST="${2:-$(cat "$HERE/.device" 2>/dev/null)}"
    [ -n "$HOST" ] || { echo "Usage: ./install.sh --ssh <device-ip>  (or put the IP in .device)"; exit 1; }
    [ -n "${2:-}" ] && echo "$HOST" > "$HERE/.device"
    SSH="ssh -o BatchMode=yes -o ConnectTimeout=8 root@$HOST"
    VERSION=$(sed -n 's/^return "\(.*\)"$/\1/p' "$HERE/app/version.lua")
    STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
    P="$STAGE/Ports/eReaderDS"
    mkdir -p "$P/app/fonts" "$P/app/hyph" "$P/app/dict"
    cp "$HERE"/app/*.lua "$HERE/app/whatsnew.txt" "$P/app/"
    cp "$HERE"/app/hyph/* "$P/app/hyph/"
    cp "$HERE"/app/dict/* "$P/app/dict/"
    cp "$HERE"/app/fonts/* "$P/app/fonts/"
    cp "$HERE/port/launch.sh" "$P/"
    cp "$HERE/port/eReaderDS.sh" "$STAGE/Ports/"
    mkdir -p "$STAGE/Ports/Imgs"
    cp "$HERE/port/art/eReaderDS.png" "$STAGE/Ports/Imgs/eReaderDS.png"
    cp "$HERE/port/art/eReaderDS.png" "$P/icon.png"
    sed "s/@VERSION@/$VERSION/g" "$HERE/port/README.txt" > "$P/README.txt"
    # The engine only goes over the first time.
    if ! $SSH test -f /mnt/mmc/Ports/eReaderDS/runtime/love.aarch64; then
        mkdir -p "$P/runtime"
        cp -R "$HERE/runtime/love.aarch64" "$HERE/runtime/libs.aarch64" "$P/runtime/"
    fi
    COPYFILE_DISABLE=1 tar -C "$STAGE" -czf - Ports | $SSH '
        set -e
        cd /mnt/mmc
        rm -rf Ports/eReaderDS/app
        tar -xzf -
        chmod +x Ports/eReaderDS.sh Ports/eReaderDS/launch.sh
        [ -f Ports/eReaderDS/runtime/love.aarch64 ] && chmod +x Ports/eReaderDS/runtime/love.aarch64
        mkdir -p Ebook/Fonts Ebook/Dictionaries
        sync'
    echo "Installed eReaderDS v$VERSION on $HOST over SSH."
    echo "If eReaderDS is open on the device, quit and reopen it to load the new version."
    exit 0
fi

SD="${1:-/Volumes/ROMS}"
[ -d "$SD/Ports" ] || { echo "SD card not found at $SD (expected a Ports folder)"; exit 1; }
D="$SD/Ports/eReaderDS"

# Replace the app folder wholesale; settings and progress live in Ebook/.ereaderds.
rm -rf "$D/app"
mkdir -p "$D/app/fonts" "$D/app/hyph" "$D/app/dict" "$D/runtime/libs.aarch64" "$SD/Ebook/Fonts" "$SD/Ebook/Dictionaries"
cp "$HERE"/app/*.lua "$HERE/app/whatsnew.txt" "$D/app/"
cp "$HERE"/app/hyph/* "$D/app/hyph/"
cp "$HERE"/app/dict/* "$D/app/dict/"
cp "$HERE"/app/fonts/* "$D/app/fonts/"
cp "$HERE/port/launch.sh" "$D/"
cp "$HERE/port/eReaderDS.sh" "$SD/Ports/"
mkdir -p "$SD/Ports/Imgs"
cp "$HERE/port/art/eReaderDS.png" "$SD/Ports/Imgs/eReaderDS.png"
cp "$HERE/port/art/eReaderDS.png" "$D/icon.png"
VERSION=$(sed -n 's/^return "\(.*\)"$/\1/p' "$HERE/app/version.lua")
sed "s/@VERSION@/$VERSION/g" "$HERE/port/README.txt" > "$D/README.txt"

# Upgrading from "Book Reader" (v0.1.x): bring settings over, then remove the
# old menu entry and folder so the Ports menu doesn't show both.
NEWDATA="$SD/Ebook/.ereaderds"
if [ ! -f "$NEWDATA/settings.txt" ]; then
    for old in "$SD/Ebook/.bookreader" "$SD/Ports/BookReader/data"; do
        if [ -f "$old/settings.txt" ]; then
            mkdir -p "$NEWDATA"
            for f in settings.txt progress.txt last.txt; do
                [ -f "$old/$f" ] && cp "$old/$f" "$NEWDATA/$f"
            done
            echo "Copied settings from $old"
            break
        fi
    done
fi
if [ -d "$SD/Ports/BookReader" ] || [ -f "$SD/Ports/Book Reader.sh" ]; then
    [ -d "$SD/Ports/BookReader/runtime" ] && [ ! -f "$D/runtime/love.aarch64" ] && \
        cp -R "$SD/Ports/BookReader/runtime/." "$D/runtime/"
    rm -rf "$SD/Ports/BookReader" "$SD/Ports/Book Reader.sh"
    echo "Removed the old Book Reader install"
fi

# LÖVE 11.5 aarch64 runtime: from this repo, or another port on the card.
SRC="${LOVE_RUNTIME:-}"
[ -z "$SRC" ] && [ -f "$HERE/runtime/love.aarch64" ] && SRC="$HERE/runtime"
if [ -z "$SRC" ] && [ ! -f "$D/runtime/love.aarch64" ]; then
    for c in "$SD"/Ports/*/runtime "$SD"/PortMaster/runtimes/love_11.5; do
        if [ "$c" != "$D/runtime" ] && [ -f "$c/love.aarch64" ] && [ -d "$c/libs.aarch64" ]; then SRC="$c"; break; fi
    done
fi
if [ -n "$SRC" ]; then
    cp "$SRC/love.aarch64" "$D/runtime/"
    cp "$SRC"/libs.aarch64/* "$D/runtime/libs.aarch64/"
elif [ ! -f "$D/runtime/love.aarch64" ]; then
    echo "No LÖVE 11.5 runtime found. Set LOVE_RUNTIME to a folder containing"
    echo "love.aarch64 and libs.aarch64/."
    exit 1
fi

dot_clean -m "$SD/Ports" 2>/dev/null || true
sync
echo "Installed eReaderDS v$VERSION to $D"
echo "Eject the card before removing it (Finder, or: diskutil eject \"$SD\")."
echo "macOS can hold writes to FAT cards until eject; pulling it early can leave"
echo "the device reading a half-updated folder."
