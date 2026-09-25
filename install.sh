#!/bin/bash
# Install or update Book Reader on the RG DS Plus SD card.
# Settings and reading progress in Ports/BookReader/data are kept.
#
#   ./install.sh [/Volumes/ROMS]
set -e
SD="${1:-/Volumes/ROMS}"
[ -d "$SD/Ports" ] || { echo "SD card not found at $SD (expected a Ports folder)"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
D="$SD/Ports/BookReader"

mkdir -p "$D/app/fonts" "$D/data" "$D/runtime/libs.aarch64"
cp "$HERE"/app/*.lua "$D/app/"
cp "$HERE"/app/fonts/* "$D/app/fonts/"
cp "$HERE/port/launch.sh" "$D/"
cp "$HERE/port/Book Reader.sh" "$SD/Ports/"

# LÖVE 11.5 aarch64 runtime (not stored in this repo).
if [ ! -f "$D/runtime/love.aarch64" ]; then
    SRC="${LOVE_RUNTIME:-}"
    if [ -z "$SRC" ]; then
        for c in "$SD"/Ports/*/runtime "$SD"/PortMaster/runtimes/love_11.5; do
            if [ -f "$c/love.aarch64" ] && [ -d "$c/libs.aarch64" ]; then SRC="$c"; break; fi
        done
    fi
    if [ -z "$SRC" ]; then
        echo "No LÖVE 11.5 runtime found. Set LOVE_RUNTIME to a folder containing"
        echo "love.aarch64 and libs.aarch64/ (e.g. from a PortMaster love_11.5 runtime)."
        exit 1
    fi
    echo "Copying LÖVE runtime from $SRC"
    cp "$SRC/love.aarch64" "$D/runtime/"
    cp "$SRC"/libs.aarch64/* "$D/runtime/libs.aarch64/"
    [ -f "$SRC/LICENSE-love.txt" ] && cp "$SRC/LICENSE-love.txt" "$D/runtime/"
fi

dot_clean -m "$SD/Ports" 2>/dev/null || true
sync
echo "Installed to $D"
