#!/bin/bash
# Builds build/Smolix.app (release, signed).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Smolix.app"
KEYCHAIN="$PWD/.signing/smolix.keychain-db"
IDENTITY="Smolix Local Signing"

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Smolix"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Smolix"
cp App/Info.plist "$APP/Contents/Info.plist"
[[ -f App/AppIcon.icns ]] && cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ ! -f "$KEYCHAIN" ]]; then
    ./scripts/setup-signing.sh
fi

echo "▸ Signing with '$IDENTITY'"
security unlock-keychain -p smolix-local "$KEYCHAIN"
codesign --force --options runtime --timestamp=none \
    --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "✓ Built $APP"
