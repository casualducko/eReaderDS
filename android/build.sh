#!/bin/bash
# Build eReaderDS for Android (GammaOS on the RG DS Plus) as an APK:
# LÖVE 11.5's Android app with eReaderDS inside, its own name, icon and
# version, and OpenSSL (Google's Android build) for HTTPS.
#
#   android/build.sh            -> dist/eReaderDS-vX.Y.Z-android.apk
#
# Needs: Java 17, apktool, the Android SDK's build-tools (zipalign,
# apksigner; ANDROID_HOME or ~/Library/Android/sdk), python3, zip, sips
# (macOS) or ImageMagick's convert.
#
# Signing: an APK can only be updated by one signed with the same key, so
# every build uses one key: EREADERDS_KEYSTORE (default
# ~/.android/ereaderds-release.keystore), made on the first build if it's
# missing, with its password in EREADERDS_KEYSTORE_PASS (default: the
# keystore's path + ".pass", a file). Keep both safe and out of the repo.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
cache="$here/cache"
work="$cache/work"
mkdir -p "$cache" "$repo/dist"

version=$(sed -n 's/^return "\(.*\)"$/\1/p' "$repo/app/version.lua")
[ -n "$version" ] || { echo "no version in app/version.lua"; exit 1; }
# 1.16.1 -> 1016001: always rises with the version, as Android requires.
IFS=. read -r v1 v2 v3 <<<"$version"
code=$(( v1 * 1000000 + v2 * 1000 + ${v3:-0} ))

sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
bt=$(ls -d "$sdk"/build-tools/* 2>/dev/null | sort -V | tail -1)
[ -x "$bt/apksigner" ] || { echo "no Android build-tools in $sdk"; exit 1; }
if [ -z "${JAVA_HOME:-}" ] && [ -d /opt/homebrew/opt/openjdk@17 ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@17
    export PATH="$JAVA_HOME/bin:$PATH"
fi

love_apk="$cache/love-11.5-android.apk"
[ -f "$love_apk" ] || curl -fL -o "$love_apk" \
    https://github.com/love2d/love/releases/download/11.5/love-11.5-android.apk
openssl_aar="$cache/openssl-1.1.1q-beta-1.aar"
[ -f "$openssl_aar" ] || curl -fL -o "$openssl_aar" \
    https://dl.google.com/android/maven2/com/android/ndk/thirdparty/openssl/1.1.1q-beta-1/openssl-1.1.1q-beta-1.aar

echo "== eReaderDS v$version for Android"
rm -rf "$work"
apktool d -q -f -s -o "$work" "$love_apk"          # (-s: LÖVE's code stays as it is)
python3 "$here/patch_manifest.py" "$work" "$version" "$code"

# Icon, at each density LÖVE's own has.
for f in "$work"/res/drawable-*/love.png; do
    size=$(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(struct.unpack('>I',d[16:20])[0])" "$f")
    if command -v sips >/dev/null; then sips -s format png -z "$size" "$size" "$here/icon.png" --out "$f" >/dev/null
    else convert "$here/icon.png" -resize "${size}x${size}" "$f"; fi
done

# The app itself, unzipped in the APK's assets: LÖVE reads it there in place.
# (Packed as assets/game.love instead, LÖVE copies all of it to its cache on
# every launch: about three seconds of black screen for our 22 MB.)
mkdir -p "$work/assets"
(cd "$repo/app" && find . -type f ! -name '.*' ! -path './data/*' ! -path '*/.*' | while read -r f; do
    mkdir -p "$work/assets/$(dirname "$f")"; cp "$f" "$work/assets/$f"; done)

# Our own bit of Java (smali), as a second dex beside LÖVE's: see android/smali.
cp -R "$here/smali" "$work/smali_classes2"

# 64-bit ARM only (the RG DS Plus and its kin), plus OpenSSL.
find "$work/lib" -mindepth 1 -maxdepth 1 ! -name arm64-v8a -exec rm -rf {} +
unzip -q -o -j "$openssl_aar" \
    prefab/modules/ssl/libs/android.arm64-v8a/libssl.so \
    prefab/modules/crypto/libs/android.arm64-v8a/libcrypto.so \
    -d "$work/lib/arm64-v8a"

unsigned="$cache/unsigned.apk"
aligned="$cache/aligned.apk"
out="$repo/dist/eReaderDS-v$version-android.apk"
rm -f "$unsigned" "$aligned"
apktool b -q -o "$unsigned" "$work"
"$bt/zipalign" -p -f 4 "$unsigned" "$aligned"

ks="${EREADERDS_KEYSTORE:-$HOME/.android/ereaderds-release.keystore}"
passfile="$ks.pass"
if [ -z "${EREADERDS_KEYSTORE_PASS:-}" ]; then
    if [ ! -f "$ks" ]; then
        mkdir -p "$(dirname "$ks")"
        openssl rand -base64 24 > "$passfile"
        chmod 600 "$passfile"
        keytool -genkeypair -keystore "$ks" -storepass "$(cat "$passfile")" -keypass "$(cat "$passfile")" \
            -alias ereaderds -keyalg RSA -keysize 4096 -validity 36500 \
            -dname "CN=eReaderDS, O=casualducko" >/dev/null 2>&1
        chmod 600 "$ks"
        echo "made a signing key: $ks (password in $passfile) - back both up"
    fi
    EREADERDS_KEYSTORE_PASS="$(cat "$passfile")"
fi
"$bt/apksigner" sign --ks "$ks" --ks-key-alias ereaderds --ks-pass "pass:$EREADERDS_KEYSTORE_PASS" \
    --out "$out" "$aligned"
rm -f "$out.idsig"
echo "== $out ($(du -h "$out" | cut -f1))"
