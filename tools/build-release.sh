#!/bin/bash
# Build the tester download: a zip laid out like the SD card.
#
#   tools/build-release.sh            -> dist/eReaderDS-v<version>.zip
#
# Unzipping it at the root of the SD card adds:
#   Ports/eReaderDS.sh
#   Ports/Imgs/eReaderDS.png  (the menu icon)
#   Ports/eReaderDS/{launch.sh, icon.png, app/, runtime/, README.txt, LICENSES/}
# It never contains settings, progress (Ebook/.ereaderds), books or fonts, so
# replacing an older install with it keeps everything the reader has saved.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n 's/^return "\(.*\)"$/\1/p' "$ROOT/app/version.lua")
[ -n "$VERSION" ] || { echo "could not read app/version.lua"; exit 1; }
[ -f "$ROOT/runtime/love.aarch64" ] || { echo "runtime/love.aarch64 missing"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
P="$STAGE/Ports/eReaderDS"
mkdir -p "$P/app/fonts" "$P/app/hyph" "$P/app/dict" "$P/runtime/libs.aarch64" "$P/runtime/libs.rocknix" "$P/LICENSES"

cp "$ROOT"/app/*.lua "$P/app/"
cp "$ROOT"/app/hyph/*.txt "$P/app/hyph/"
cp "$ROOT"/app/dict/* "$P/app/dict/"
cp "$ROOT"/app/dict/WordNet-LICENSE.txt "$P/LICENSES/"
cp "$ROOT"/app/fonts/*.ttf "$ROOT"/app/fonts/*.otf "$P/app/fonts/"
cp "$ROOT"/app/fonts/*-OFL.txt "$P/LICENSES/"
cp "$ROOT/runtime/love.aarch64" "$P/runtime/"
cp "$ROOT"/runtime/libs.aarch64/* "$P/runtime/libs.aarch64/"
cp "$ROOT"/runtime/libs.rocknix/* "$P/runtime/libs.rocknix/"
cp "$ROOT"/runtime/LICENSE-*.txt "$ROOT/runtime/NOTICES.md" "$P/LICENSES/" 2>/dev/null || true
[ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$P/LICENSES/eReaderDS-LICENSE.txt"
cp "$ROOT/port/launch.sh" "$P/"
cp "$ROOT/port/eReaderDS.sh" "$STAGE/Ports/"
# Menu icon: Ports/Imgs on the stock firmware; ROCKNIX's launcher uses icon.png.
mkdir -p "$STAGE/Ports/Imgs"
cp "$ROOT/port/art/eReaderDS.png" "$STAGE/Ports/Imgs/eReaderDS.png"
cp "$ROOT/port/art/eReaderDS.png" "$P/icon.png"
sed "s/@VERSION@/$VERSION/g" "$ROOT/port/README.txt" > "$P/README.txt"
chmod +x "$P/launch.sh" "$STAGE/Ports/eReaderDS.sh" "$P/runtime/love.aarch64"

# Scripts must keep Unix line endings to run on the device.
if grep -l $'\r' "$P/launch.sh" "$STAGE/Ports/eReaderDS.sh" >/dev/null; then
    echo "launch scripts contain CRLF line endings"; exit 1
fi

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/eReaderDS-v$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" Ports)
echo "$OUT"
unzip -l "$OUT" | tail -1
