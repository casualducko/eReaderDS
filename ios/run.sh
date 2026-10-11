#!/bin/bash
# Install the Simulator build and launch it on the iPhone Duo simulator.
#
#   ios/run.sh              -> boots "eReaderDS Duo" (made on first use), installs, launches
#   ios/run.sh shot out.png -> the same, then a screenshot after a few seconds
#
# DEVICE=<name> uses another simulator (an existing one, by name); BOOKS=<folder>
# puts that folder's books in the app first.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/cache/out/eReaderDS.app"
[ -d "$app" ] || { echo "build first: ios/build.sh"; exit 1; }
name="${DEVICE:-eReaderDS Duo}"

udid=$(xcrun simctl list devices available | sed -n "s/^ *$name (\([0-9A-F-]\{36\}\)).*/\1/p" | head -1)
if [ -z "$udid" ]; then
    runtime=$(xcrun simctl list runtimes | sed -n 's/.*\(com.apple.CoreSimulator.SimRuntime.iOS-27-[0-9]*\)$/\1/p' | sort | tail -1)
    udid=$(xcrun simctl create "$name" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$runtime")
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" >/dev/null
open "$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || true     # (so it can be watched)
xcrun simctl terminate "$udid" com.casualducko.ereaderds 2>/dev/null || true
xcrun simctl install "$udid" "$app"
# BOOKS=<folder>: its books are copied into the app's Documents/Ebook first
# (what Files shows), for trying the library without going through Files.
if [ -n "${BOOKS:-}" ]; then
    data=$(xcrun simctl get_app_container "$udid" com.casualducko.ereaderds data)
    mkdir -p "$data/Documents/Ebook"
    cp "$BOOKS"/*.epub "$BOOKS"/*.cbz "$BOOKS"/*.txt "$data/Documents/Ebook/" 2>/dev/null || true
fi
xcrun simctl launch "$udid" com.casualducko.ereaderds
if [ "${1:-}" = shot ]; then
    sleep "${SHOT_WAIT:-8}"
    xcrun simctl io "$udid" screenshot "${2:-/tmp/ereaderds-shot.png}"
fi
