#!/bin/bash
# Build eReaderDS for macOS: LÖVE 11.5's own app with eReaderDS inside as a .love,
# its own name, icon and version, and OpenSSL beside its frameworks (net.lua loads it
# through FFI: macOS's own libssl aborts the process when loaded).
#
#   mac/build.sh    -> dist/eReaderDS.app and dist/eReaderDS-v<version>-mac.zip
#
# Needs: macOS with Homebrew's openssl@3 (brew install openssl@3), Xcode's command
# line tools (codesign, iconutil), curl, zip. Apple silicon or Intel: LÖVE's app is
# universal, but the OpenSSL copied in is Homebrew's for this Mac's chip.
#
# The app is signed ad hoc, which is enough to open it on the Mac that built it.
# Anywhere else Gatekeeper asks for a right-click > Open the first time (a
# Developer ID signature and notarization would avoid that).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
cache="$here/cache"
mkdir -p "$cache" "$repo/dist"

LOVE_URL=https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip
SSL="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"

version=$(sed -n 's/^return "\(.*\)"$/\1/p' "$repo/app/version.lua")
[ -n "$version" ] || { echo "no version in app/version.lua"; exit 1; }
echo "== eReaderDS v$version for macOS"

# A syntax error would only show when the app runs, so stop here.
for f in "$repo"/app/*.lua; do luajit -bl "$f" >/dev/null || { echo "syntax error in $f"; exit 1; }; done
[ -f "$SSL/lib/libssl.3.dylib" ] || { echo "OpenSSL 3 not found at $SSL (brew install openssl@3)"; exit 1; }

# --- LÖVE
if [ ! -d "$cache/love/love.app" ]; then
    rm -rf "$cache/love"; mkdir -p "$cache/love"
    curl -sL -o "$cache/love.zip" "$LOVE_URL"
    unzip -q "$cache/love.zip" -d "$cache/love"
fi

out="$repo/dist/eReaderDS.app"
rm -rf "$out"
ditto "$cache/love/love.app" "$out"
res="$out/Contents/Resources"

# --- the game: LÖVE finds the .love in Resources
(cd "$repo/app" && zip -qr -9 -X "$res/eReaderDS.love" . -x '*.DS_Store' 'data/*')

# --- the name, identity and version (and not a .love's file type)
plist="$out/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist" 2>/dev/null || true; }
pb "Set :CFBundleName eReaderDS"
pb "Add :CFBundleDisplayName string eReaderDS"
pb "Set :CFBundleIdentifier com.casualducko.ereaderds"
pb "Set :CFBundleShortVersionString $version"
pb "Set :CFBundleVersion $version"
pb "Set :CFBundleIconFile eReaderDS"
pb "Delete :CFBundleDocumentTypes"
pb "Delete :UTExportedTypeDeclarations"
pb "Set :LSApplicationCategoryType public.app-category.reference"      # (not a game: macOS turns Game Mode on for those)
pb "Set :NSHumanReadableCopyright eReaderDS"
pb "Add :NSDocumentsFolderUsageDescription string eReaderDS keeps your books and reading places in the Ebook folder in Documents."
rm -f "$res/OS X AppIcon.icns" "$res/Assets.car" "$res/GameIcon.icns" 2>/dev/null || true

# --- the icon
iconset="$cache/eReaderDS.iconset"
rm -rf "$iconset"; mkdir -p "$iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$repo/android/icon.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$repo/android/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$res/eReaderDS.icns"

# --- OpenSSL, loaded by net.lua from Contents/Frameworks (next to LÖVE's own)
fw="$out/Contents/Frameworks"
for lib in libssl.3.dylib libcrypto.3.dylib; do
    cp -L "$SSL/lib/$lib" "$fw/$lib"
    chmod u+w "$fw/$lib"
    install_name_tool -id "@loader_path/$lib" "$fw/$lib" 2>/dev/null
done
# (libssl points at libcrypto by its Homebrew path: point it at the copy beside it.)
crypto_ref=$(otool -L "$fw/libssl.3.dylib" | awk '/libcrypto\.3\.dylib/ {print $1; exit}')
[ -n "$crypto_ref" ] && install_name_tool -change "$crypto_ref" "@loader_path/libcrypto.3.dylib" "$fw/libssl.3.dylib"
cp "$SSL/LICENSE.txt" "$res/OpenSSL-LICENSE.txt" 2>/dev/null || true
cp "$repo/LICENSE" "$res/eReaderDS-LICENSE.txt" 2>/dev/null || true

# --- sign (ad hoc), and zip
codesign --force --deep --sign - "$out" 2>&1 | tail -1
zip_out="$repo/dist/eReaderDS-v$version-mac.zip"
rm -f "$zip_out"
ditto -c -k --keepParent "$out" "$zip_out"
echo "$out"
du -sh "$out" "$zip_out" | sed 's|/Users/[^/]*/||'
