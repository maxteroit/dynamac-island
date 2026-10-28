#!/usr/bin/env bash
# Builds Vendor/mediaremote-adapter into a minimal framework with clang
# (mirrors its CMakeLists.txt, so cmake is not required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="$ROOT/build/MediaRemoteAdapter.framework"

SOURCES=(
    src/adapter/env.m src/adapter/get.m src/adapter/globals.m src/adapter/keys.m
    src/adapter/now_playing.m src/adapter/repeat.m src/adapter/seek.m src/adapter/send.m
    src/adapter/shuffle.m src/adapter/speed.m src/adapter/stream.m src/adapter/test.m
    src/private/MediaRemote.m src/utility/Debounce.m src/utility/helpers.m
)

rm -rf "$OUT"
mkdir -p "$OUT"
(
    cd "$SRC"
    clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
        -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
        -Iinclude -Isrc \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
        -o "$OUT/MediaRemoteAdapter" "${SOURCES[@]}"
)
codesign --force --sign - "$OUT/MediaRemoteAdapter" >/dev/null
echo "Built $OUT"
