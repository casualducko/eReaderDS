#!/bin/bash
# Span the running eReaderDS across both screens of the Surface Duo emulator
# (microsoft's emulator, started with its run_SurfaceDuo.sh), and optionally
# save a screenshot of both screens.
#
#   tools/duo-span.sh [screenshot.png]
#
# The app's bottom handle is dragged to the hinge with touch events: a plain
# `adb shell input swipe` only moves the app to the other screen.
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
b=$($ADB shell am stack list | grep "com.casualducko.ereaderds" | head -1 | grep -o "bounds=\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]")
echo "before: $b"
if [[ "$b" != *"[2784,"* ]]; then
    if [[ "$b" == *"bounds=[0,"* ]]; then X0=700; XS="800 900 1000 1100 1200 1300 1380 1392"
    else X0=2100; XS="2000 1900 1800 1700 1600 1500 1420 1392"; fi
    $ADB shell input swipe $X0 1799 $X0 1700 200; sleep 1.5          # (shows the handle)
    $ADB shell "input motionevent DOWN $X0 1790; sleep 0.3; for x in $XS; do input motionevent MOVE \$x 1790; sleep 0.2; done; sleep 2; input motionevent UP 1392 1790"
    sleep 3
fi
[ -n "${1:-}" ] && $ADB exec-out screencap -p > "$1"
true
