#!/bin/bash
# Build the SDL2 that BananaOS runs eReaderDS with: SDL 2.32.10 + BananaLinux's panel patch (0001) + zero-copy
# panels (0002), for aarch64 Linux with glibc 2.41 like BananaOS's (a Debian 13 "trixie" container, so it needs
# Docker on an Apple-silicon or arm64 machine). Writes runtime/libs.banana/libSDL2-2.0.so.0.
#   runtime/banana-sdl/build.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$HERE/../libs.banana"
docker run --rm --platform linux/arm64 -v "$HERE:/patches:ro" -v "$WORK:/work" -v "$HERE/../libs.banana:/out" debian:trixie bash -c '
set -e
apt-get update -qq
apt-get install -y -qq build-essential curl ca-certificates patch pkg-config libdrm-dev libgbm-dev libegl-dev libgles-dev libasound2-dev libudev-dev binutils >/dev/null
cd /work
curl -sL https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz | tar xz
cd SDL2-2.32.10
patch -p1 -s < /patches/0001-banana-panels.patch
patch -p1 -s < /patches/0002-banana-zero-copy-panels.patch
./configure --disable-static --enable-video-dummy --enable-video-offscreen --enable-video-kmsdrm \
  --disable-video-x11 --disable-video-wayland --disable-video-vulkan --disable-pulseaudio --disable-esd \
  --disable-sndio --disable-jack --disable-pipewire --disable-oss >/dev/null
make -j8 >/dev/null
cp build/.libs/libSDL2-2.0.so.0.* /out/libSDL2-2.0.so.0
strip --strip-unneeded /out/libSDL2-2.0.so.0
'
ls -la "$HERE/../libs.banana/libSDL2-2.0.so.0"
