#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it into a runnable .app bundle.
set -euo pipefail

CONFIG="${1:-debug}"
# A stable identity keeps privacy permissions (Accessibility) across rebuilds;
# ad-hoc signatures change every build and macOS forgets the grant.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Apple Development[^"]*)".*/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DynamicIsland.app"

swift build --package-path "$ROOT" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/DynamicIsland"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Now Playing adapter (built separately by `make adapter`). Without it the app
# falls back to Spotify/Music notifications.
ADAPTER="$ROOT/build/MediaRemoteAdapter.framework"
if [[ -d "$ADAPTER" ]]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$ADAPTER" "$APP/Contents/Frameworks/"
    cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter" >/dev/null
else
    echo "Note: MediaRemoteAdapter.framework not built; Now Playing uses the Spotify/Music fallback."
fi

codesign --force --sign "$IDENTITY" "$APP" >/dev/null

echo "Built $APP (signed: $IDENTITY)"
