#!/bin/bash
# Build eReaderDS for iOS (the iPhone Duo and other iPhones/iPads): LÖVE 11.5's
# iOS app with eReaderDS inside as game.love, its own name, icon and version.
#
#   ios/build.sh              -> ios/cache/out/eReaderDS.app (for the Simulator)
#   ios/build.sh device       -> ios/cache/out-device/eReaderDS.app (for a device;
#                                unsigned unless IOS_SIGN is set: see "Signing" below)
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
# (A changed patch: the SDL2 built from the old one is thrown away.)
patch_sum=$(shasum "$here/patches/sdl2-uiscene.patch" | cut -d' ' -f1)
if [ "$(cat "$cache/sdl2.patch-sum" 2>/dev/null)" != "$patch_sum" ]; then
    rm -rf "$cache/sdl2" "$cache"/sdl-*.done
    echo "$patch_sum" > "$cache/sdl2.patch-sum"
fi
if [ ! -d "$cache/sdl2" ]; then
    git init -q "$cache/sdl2"
    git -C "$cache/sdl2" fetch -q --depth 1 https://github.com/libsdl-org/SDL.git "$SDL_COMMIT"
    git -C "$cache/sdl2" checkout -q FETCH_HEAD
    git -C "$cache/sdl2" apply "$here/patches/sdl2-uiscene.patch" || { rm -rf "$cache/sdl2"; echo "the SDL2 patch didn't apply"; exit 1; }
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
    extra=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="")
    xcodebuild -project "$xc/love.xcodeproj" -scheme love-ios -configuration Release -sdk $sdk -arch arm64 \
        IPHONEOS_DEPLOYMENT_TARGET=$TARGET "${extra[@]}" -derivedDataPath "$cache/love-build-$sdk" build \
        > "$cache/love-$sdk.log" 2>&1 || { grep -E "error:" "$cache/love-$sdk.log" | head; exit 1; }
    touch "$cache/love-$sdk.done"
fi
built="$(ls -d "$cache"/love-build-$sdk/Build/Products/Release-*/love.app)"

# --- OpenSSL, as two dylibs that go in the app (net.lua loads them)
ossl="$cache/openssl-$sdk"
if [ ! -f "$ossl/libssl.3.dylib" ]; then
    # (Pinned: this is OpenSSL's own published SHA-256 for 3.0.22; change both together.)
    want=67ebca7e50d17383028045486653492195b83db95f8558709701bb47b5c1ef81
    tgz="$cache/openssl-$OPENSSL.tar.gz"
    if [ -f "$tgz" ] && [ "$(shasum -a 256 "$tgz" | cut -d' ' -f1)" != "$want" ]; then rm -f "$tgz"; fi
    if [ ! -f "$tgz" ]; then
        curl -fsSL -o "$tgz.part" "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL/openssl-$OPENSSL.tar.gz"
        [ "$(shasum -a 256 "$tgz.part" | cut -d' ' -f1)" = "$want" ] || { rm -f "$tgz.part"; echo "OpenSSL $OPENSSL isn't the file expected"; exit 1; }
        mv "$tgz.part" "$tgz"
    fi
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

# The icon (the Android one, 512 px, enlarged: put a 1024 px ios/icon-1024.png here for the App Store)
# and the opening navy as the launch screen, in place of LÖVE's.
icons="$cache/AppIcon.xcassets"
rm -rf "$icons" && mkdir -p "$icons/AppIcon.appiconset"
if [ -f "$here/icon-1024.png" ]; then cp "$here/icon-1024.png" "$icons/AppIcon.appiconset/icon.png"
else sips -z 1024 1024 "$repo/android/icon.png" --out "$icons/AppIcon.appiconset/icon.png" >/dev/null; fi
cat > "$icons/AppIcon.appiconset/Contents.json" <<'JSON'
{ "images": [ { "filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" } ],
  "info": { "author": "xcode", "version": 1 } }
JSON
rm -f "$app"/Assets.car "$app"/iOS\ AppIcon* "$app/Launch Screen.nib"
xcrun actool --output-format human-readable-text --notices --warnings --platform $sdk \
    --minimum-deployment-target $TARGET --app-icon AppIcon --output-partial-info-plist "$cache/icon-partial.plist" \
    --target-device iphone --target-device ipad --compile "$app" "$icons" >/dev/null
xcrun ibtool --compile "$app/LaunchScreen.storyboardc" "$here/LaunchScreen.storyboard" \
    --minimum-deployment-target $TARGET --target-device iphone --target-device ipad >/dev/null

mkdir -p "$app/Frameworks"
cp "$ossl"/libssl.3.dylib "$ossl"/libcrypto.3.dylib "$app/Frameworks/"
# The certificates HTTPS trusts (Mozilla's list, from curl.se): iOS gives apps no PEM file.
# (Fetched aside and checked as a certificate list before it's kept; a partial download isn't cached.
# Not pinned: Mozilla's list changes, and a stale one stops HTTPS working.)
if [ ! -f "$cache/cacert.pem" ] || [ -n "$(find "$cache/cacert.pem" -mtime +60 2>/dev/null)" ]; then
    curl -fsSL -o "$cache/cacert.pem.part" https://curl.se/ca/cacert.pem &&
        grep -q "BEGIN CERTIFICATE" "$cache/cacert.pem.part" && mv "$cache/cacert.pem.part" "$cache/cacert.pem" ||
        { rm -f "$cache/cacert.pem.part"; [ -f "$cache/cacert.pem" ] || { echo "couldn't fetch the certificate list"; exit 1; }; }
fi
cp "$cache/cacert.pem" "$app/cacert.pem"

plist="$app/Info.plist"
set_key() { plutil -replace "$1" -"$2" "$3" "$plist"; }
set_key CFBundleIdentifier string com.casualducko.ereaderds
set_key CFBundleName string eReaderDS
set_key CFBundleDisplayName string eReaderDS
set_key CFBundleShortVersionString string "$version"
set_key CFBundleVersion string "$code"
plutil -replace CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60"],"CFBundleIconName":"AppIcon"}}' "$plist"
plutil -replace CFBundleIcons~ipad -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60","AppIcon76x76"],"CFBundleIconName":"AppIcon"}}' "$plist"
plutil -replace UILaunchStoryboardName -string LaunchScreen "$plist"
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
plutil -replace UIApplicationSupportsIndirectInputEvents -bool true "$plist"     # (a mouse or trackpad on an iPad)
# Books can be opened in the app (Files, Mail, Share): epub, cbz, txt.
plutil -replace UTExportedTypeDeclarations -json '[{"UTTypeIdentifier":"com.casualducko.ereaderds.cbz","UTTypeDescription":"Comic Book Archive","UTTypeConformsTo":["com.pkware.zip-archive"],"UTTypeTagSpecification":{"public.filename-extension":["cbz"],"public.mime-type":["application/vnd.comicbook+zip"]}}]' "$plist"
plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"E-book","CFBundleTypeRole":"Viewer","LSHandlerRank":"Alternate","LSItemContentTypes":["org.idpf.epub-container","com.casualducko.ereaderds.cbz","public.plain-text"]}]' "$plist"
# What the system tells the reader when it asks: Get Books' "Send from your
# phone" and Calibre's connection are on the local network.
plutil -replace NSLocalNetworkUsageDescription -string "eReaderDS connects to Calibre or a web browser on your network to receive books." "$plist"
plutil -replace ITSAppUsesNonExemptEncryption -bool false "$plist"     # (HTTPS only, through the system's standard)

# Signing. The Simulator takes it unsigned. A device needs the app signed with
# your team's certificate and a provisioning profile that lists the device:
#   IOS_SIGN="Apple Development: Your Name (TEAMID)" IOS_PROFILE=path/to.mobileprovision ios/build.sh device
# (or open Xcode's Devices window and drag the unsigned app in once it has a
# profile; see ios/README.md). Nothing is signed when IOS_SIGN isn't set.
if [ $mode = device ] && [ -n "${IOS_SIGN:-}" ]; then
    [ -n "${IOS_PROFILE:-}" ] && cp "$IOS_PROFILE" "$app/embedded.mobileprovision"
    ents="$cache/entitlements.plist"
    if [ -n "${IOS_PROFILE:-}" ]; then
        security cms -D -i "$IOS_PROFILE" > "$cache/profile.plist"
        /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$cache/profile.plist" > "$ents"
    else printf '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$ents"; fi
    for f in "$app"/Frameworks/*.dylib; do codesign --force --sign "$IOS_SIGN" "$f"; done
    codesign --force --sign "$IOS_SIGN" --entitlements "$ents" "$app"
fi
echo "== $app ($(du -sh "$app" | cut -f1))"
