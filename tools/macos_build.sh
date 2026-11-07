#!/bin/sh
# Native Apple Silicon build. Dependencies: brew install sdl3 curl opus webp
# freetype fontconfig openssl@3 pkgconf; Zig 0.17.0 must be on PATH or in ZIG.
set -eu
cd "$(dirname "$0")/.."
BREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/curl/lib/pkgconfig:$BREW_PREFIX/opt/openssl@3/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
exec "${ZIG:-zig}" build -Dtarget=aarch64-macos -Dcpu=baseline "-Dmacos-sdk=$SDKROOT" "$@"
