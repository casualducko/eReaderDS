#!/bin/bash
# Sign a published release, so the in-app updater will install it.
#
#   tools/sign-release.sh v1.23.3
#
# Run it on your own computer after the release is published (and again after
# adding the Android APK, if that came later). It downloads the release's zip
# and APK, signs each one's name, version and SHA-256 with the update-signing
# key, and uploads the signatures as eReaderDS-v1.23.3.zip.sig and
# eReaderDS-v1.23.3-android.apk.sig. The app (app/updater.lua, PUBLIC_KEYS)
# refuses a release without a signature from this key, so one published
# through a hijacked GitHub account or Actions run can't be installed.
#
# The key is a file that stays on this computer (and in your key backup):
#   EREADERDS_SIGNING_KEY, default ~/.android/ereaderds-update-signing.pem
# Make a new one with:  openssl genpkey -algorithm ed25519 -out KEY.pem
# and put its public half in PUBLIC_KEYS (print it with:
#   openssl pkey -in KEY.pem -pubout -outform DER | tail -c 32 | xxd -p -c 64).
# Lose the key and installed copies can't update to anything new until they're
# replaced by hand, so back it up.
set -euo pipefail
tag="${1:?usage: tools/sign-release.sh vX.Y.Z}"
version="${tag#v}"
repo=casualducko/eReaderDS
key="${EREADERDS_SIGNING_KEY:-$HOME/.android/ereaderds-update-signing.pem}"
[ -f "$key" ] || { echo "no signing key at $key"; exit 1; }
command -v gh >/dev/null || { echo "needs the GitHub CLI (gh)"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh release download "$tag" -R "$repo" -D "$tmp" -p "eReaderDS-v*.zip" -p "eReaderDS-v*-android.apk"

pub="$tmp/pub.der"
openssl pkey -in "$key" -pubout -outform DER > "$pub"

signed=0
for file in "$tmp"/eReaderDS-v*; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    case "$name" in "eReaderDS-$tag.zip"|"eReaderDS-$tag-android.apk") ;; *) echo "skipping $name"; continue;; esac
    sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
    printf 'eReaderDS-release-v1\n%s\n%s\n%s\n' "$version" "$name" "$sha" > "$tmp/message"
    openssl pkeyutl -sign -rawin -inkey "$key" -in "$tmp/message" -out "$tmp/sig.bin"
    # (Checked straight away with the public half.)
    openssl pkeyutl -verify -rawin -pubin -keyform DER -inkey "$pub" -in "$tmp/message" -sigfile "$tmp/sig.bin" >/dev/null
    xxd -p -c 128 "$tmp/sig.bin" > "$tmp/$name.sig"
    echo "signed $name  sha256 $sha"
    signed=$((signed + 1))
done
[ "$signed" -gt 0 ] || { echo "nothing to sign: no eReaderDS-$tag.zip in that release"; exit 1; }

gh release upload "$tag" -R "$repo" --clobber "$tmp"/*.sig
echo "uploaded $signed signature(s) to $tag"
[ -f "$tmp/eReaderDS-$tag-android.apk" ] || echo "note: no Android APK in the release yet; run this again after uploading it"
