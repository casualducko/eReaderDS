#!/bin/bash
# Install or update Book Reader on an RG DS Plus SD card from a clone of this
# repo (macOS/Linux). Most people should use the release zip instead: see README.
# Settings and reading progress (Ebook/.bookreader) are kept.
#
#   ./install.sh [/Volumes/ROMS]
set -e
SD="${1:-/Volumes/ROMS}"
[ -d "$SD/Ports" ] || { echo "SD card not found at $SD (expected a Ports folder)"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
D="$SD/Ports/BookReader"

# Replace the app folder wholesale; settings and progress live in Ebook/.bookreader.
rm -rf "$D/app"
mkdir -p "$D/app/fonts" "$D/runtime/libs.aarch64" "$SD/Ebook/Fonts"
cp "$HERE"/app/*.lua "$D/app/"
cp "$HERE"/app/fonts/* "$D/app/fonts/"
cp "$HERE/port/launch.sh" "$D/"
cp "$HERE/port/Book Reader.sh" "$SD/Ports/"
VERSION=$(sed -n 's/^return "\(.*\)"$/\1/p' "$HERE/app/version.lua")
sed "s/@VERSION@/$VERSION/g" "$HERE/port/README.txt" > "$D/README.txt"

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
echo "Installed Book Reader v$VERSION to $D"
echo "Eject the card before removing it (Finder, or: diskutil eject \"$SD\")."
echo "macOS can hold writes to FAT cards until eject; pulling it early can leave"
echo "the device reading a half-updated folder."
