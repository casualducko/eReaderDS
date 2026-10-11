#!/bin/bash
# Build eReaderDS for iOS (the iPhone Duo and other iPhones/iPads): LÖVE 11.5's
# iOS app with eReaderDS inside as game.love, its own name, icon and version.
#
#   ios/build.sh              -> ios/cache/out/eReaderDS.app (for the Simulator)
#   ios/build.sh device       -> ios/cache/out-device/eReaderDS.app (for a device;
#                                signed with your team: IOS_TEAM=ABCDE12345)
#
# Needs: Xcode 27.1 or later (the iOS 27.1 SDK; the iPhone Duo simulator comes
# with it), the Metal toolchain (xcodebuild -downloadComponent MetalToolchain),
# git, python3, zip. Set DEVELOPER_DIR to pick an Xcode other than the active one.
#
# Why SDL2 is patched: apps built with the iOS 27 SDK must use the UIScene life
# cycle ("UIScene life cycle is required"), and so must anything that follows a
# folding display. SDL2 (what LÖVE 11 uses) has no scene support, so
# ios/patches/sdl2-uiscene.patch adds it (the window is made in the scene).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
cache="$here/cache"
mode="${1:-sim}"
mkdir -p "$cache"

SDL_COMMIT=74be4c2836da0940f0144d0d97852606f9ab11e9     # libsdl-org/SDL, branch SDL2 (2.33 pre-release)
LOVE_TAG=11.5
DEPS_BRANCH=11.x
TARGET=15.0                                             # the oldest iOS it runs on
OPENSSL=3.0.22                                          # for HTTPS (net.lua loads libssl through FFI; iOS has none)

version=$(sed -n 's/^return "\(.*\)"$/\1/p' "$repo/app/version.lua")
[ -n "$version" ] || { echo "no version in app/version.lua"; exit 1; }
IFS=. read -r v1 v2 v3 <<<"$version"
code=$(( v1 * 1000000 + v2 * 1000 + ${v3:-0} ))

if [ "$mode" = device ]; then sdk=iphoneos; out="$cache/out-device"; else sdk=iphonesimulator; out="$cache/out"; fi
echo "== eReaderDS v$version for iOS ($mode)"

# --- sources
[ -d "$cache/love" ] || git clone -q --depth 1 --branch "$LOVE_TAG" https://github.com/love2d/love.git "$cache/love"
[ -d "$cache/deps" ] || git clone -q --depth 1 --branch "$DEPS_BRANCH" https://github.com/love2d/love-apple-dependencies.git "$cache/deps"
if [ ! -d "$cache/sdl2" ]; then
    git init -q "$cache/sdl2"
    git -C "$cache/sdl2" fetch -q --depth 1 https://github.com/libsdl-org/SDL.git "$SDL_COMMIT"
    git -C "$cache/sdl2" checkout -q FETCH_HEAD
    git -C "$cache/sdl2" apply "$here/patches/sdl2-uiscene.patch"
fi
xc="$cache/love/platform/xcode"
[ -d "$xc/ios/libraries" ] || cp -R "$cache/deps/iOS/libraries" "$xc/ios/libraries"

# --- SDL2 with scene support, put into LÖVE's own SDL2 framework
sdlx="$xc/ios/libraries/SDL2.xcframework"
if [ ! -f "$cache/sdl-$sdk.done" ]; then
    xcodebuild -project "$cache/sdl2/Xcode/SDL/SDL.xcodeproj" -target "Static Library-iOS" \
        -configuration Release -sdk $sdk -arch arm64 IPHONEOS_DEPLOYMENT_TARGET=$TARGET \
        CODE_SIGNING_ALLOWED=NO SYMROOT="$cache/sdlbuild" OBJROOT="$cache/sdlobj" build \
        > "$cache/sdl-$sdk.log" 2>&1 || { tail -20 "$cache/sdl-$sdk.log"; exit 1; }
    if [ $sdk = iphonesimulator ]; then lib="$sdlx/ios-arm64_x86_64-simulator"; else lib="$sdlx/ios-arm64"; fi
    cp "$cache/sdlbuild/Release-$sdk/libSDL2.a" "$lib/libSDL2.a"
    cp "$cache/sdl2"/include/*.h "$lib/Headers/"
    touch "$cache/sdl-$sdk.done"
fi

# --- LÖVE
if [ ! -f "$cache/love-$sdk.done" ] || [ "$cache/sdl-$sdk.done" -nt "$cache/love-$sdk.done" ]; then
    extra=()
    if [ $mode = device ]; then extra=(DEVELOPMENT_TEAM="${IOS_TEAM:?set IOS_TEAM to your Apple team id}" -allowProvisioningUpdates)
    else extra=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""); fi
    xcodebuild -project "$xc/love.xcodeproj" -scheme love-ios -configuration Release -sdk $sdk -arch arm64 \
        IPHONEOS_DEPLOYMENT_TARGET=$TARGET "${extra[@]}" -derivedDataPath "$cache/love-build-$sdk" build \
        > "$cache/love-$sdk.log" 2>&1 || { grep -E "error:" "$cache/love-$sdk.log" | head; exit 1; }
    touch "$cache/love-$sdk.done"
fi
built="$(ls -d "$cache"/love-build-$sdk/Build/Products/Release-*/love.app)"

# --- OpenSSL, as two dylibs that go in the app (net.lua loads them)
ossl="$cache/openssl-$sdk"
if [ ! -f "$ossl/libssl.3.dylib" ]; then
    [ -f "$cache/openssl-$OPENSSL.tar.gz" ] || curl -fsSL -o "$cache/openssl-$OPENSSL.tar.gz" \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL/openssl-$OPENSSL.tar.gz"
    rm -rf "$cache/ossl-build-$sdk" && mkdir -p "$cache/ossl-build-$sdk" "$ossl"
    tar xzf "$cache/openssl-$OPENSSL.tar.gz" -C "$cache/ossl-build-$sdk" --strip-components 1
    if [ $sdk = iphonesimulator ]; then cfg=iossimulator-xcrun; flags="-arch arm64 -mios-simulator-version-min=$TARGET"
    else cfg=ios64-xcrun; flags="-mios-version-min=$TARGET"; fi
    ( cd "$cache/ossl-build-$sdk" &&
      CFLAGS="$flags" ./Configure $cfg shared no-tests no-ui-console no-engine no-dso no-comp >/dev/null &&
      make -j8 build_libs >/dev/null 2>&1 ) || { echo "OpenSSL didn't build ($cache/ossl-build-$sdk)"; exit 1; }
    cp "$cache/ossl-build-$sdk"/libssl.3.dylib "$cache/ossl-build-$sdk"/libcrypto.3.dylib "$ossl/"
    # (Loaded by path from the app's Frameworks folder: each finds the other beside it.)
    install_name_tool -id @loader_path/libcrypto.3.dylib "$ossl/libcrypto.3.dylib"
    install_name_tool -id @loader_path/libssl.3.dylib "$ossl/libssl.3.dylib"
    old=$(otool -L "$ossl/libssl.3.dylib" | sed -n 's/^[[:space:]]*\(.*libcrypto.3.dylib\) .*/\1/p' | head -1)
    [ -z "$old" ] || install_name_tool -change "$old" @loader_path/libcrypto.3.dylib "$ossl/libssl.3.dylib"
fi

# --- the app
rm -rf "$out" && mkdir -p "$out"
app="$out/eReaderDS.app"
cp -R "$built" "$app"
rm -f "$app/game.love"
(cd "$repo/app" && find . -type f ! -name '.*' ! -path './data/*' ! -path '*/.*' | zip -q -X -@ "$app/game.love")

mkdir -p "$app/Frameworks"
cp "$ossl"/libssl.3.dylib "$ossl"/libcrypto.3.dylib "$app/Frameworks/"
# The certificates HTTPS trusts (Mozilla's list, from curl.se): iOS gives apps no PEM file.
[ -f "$cache/cacert.pem" ] || curl -fsSL -o "$cache/cacert.pem" https://curl.se/ca/cacert.pem
cp "$cache/cacert.pem" "$app/cacert.pem"

plist="$app/Info.plist"
set_key() { plutil -replace "$1" -"$2" "$3" "$plist"; }
set_key CFBundleIdentifier string com.casualducko.ereaderds
set_key CFBundleName string eReaderDS
set_key CFBundleDisplayName string eReaderDS
set_key CFBundleShortVersionString string "$version"
set_key CFBundleVersion string "$code"
plutil -remove CFBundleDocumentTypes "$plist" 2>/dev/null || true
plutil -remove UTExportedTypeDeclarations "$plist" 2>/dev/null || true
# UIScene (see the top), the Files app showing the Documents folder (books go
# there), and every orientation (the window follows the display).
plutil -replace UIApplicationSceneManifest -json '{"UIApplicationSupportsMultipleScenes":false,"UISceneConfigurations":{"UIWindowSceneSessionRoleApplication":[{"UISceneConfigurationName":"Default","UISceneDelegateClassName":"SDLUIKitSceneDelegate"}]}}' "$plist"
plutil -replace UIFileSharingEnabled -bool true "$plist"
plutil -replace LSSupportsOpeningDocumentsInPlace -bool true "$plist"
plutil -replace UISupportedInterfaceOrientations -json '["UIInterfaceOrientationPortrait","UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight","UIInterfaceOrientationPortraitUpsideDown"]' "$plist"
plutil -replace UISupportedInterfaceOrientations~ipad -json '["UIInterfaceOrientationPortrait","UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight","UIInterfaceOrientationPortraitUpsideDown"]' "$plist"
plutil -replace UIStatusBarHidden -bool true "$plist"
# Books can be opened in the app (Files, Mail, Share): epub, cbz, txt.
plutil -replace UTExportedTypeDeclarations -json '[{"UTTypeIdentifier":"com.casualducko.ereaderds.cbz","UTTypeDescription":"Comic Book Archive","UTTypeConformsTo":["com.pkware.zip-archive"],"UTTypeTagSpecification":{"public.filename-extension":["cbz"],"public.mime-type":["application/vnd.comicbook+zip"]}}]' "$plist"
plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"E-book","CFBundleTypeRole":"Viewer","LSHandlerRank":"Alternate","LSItemContentTypes":["org.idpf.epub-container","com.casualducko.ereaderds.cbz","public.plain-text"]}]' "$plist"
# What the system tells the reader when it asks: Get Books' "Send from your
# phone" and Calibre's connection are on the local network.
plutil -replace NSLocalNetworkUsageDescription -string "eReaderDS connects to Calibre or a web browser on your network to receive books." "$plist"
plutil -replace ITSAppUsesNonExemptEncryption -bool false "$plist"     # (HTTPS only, through the system's standard)

if [ $mode = device ]; then
    codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1 || true
fi
echo "== $app ($(du -sh "$app" | cut -f1))"
