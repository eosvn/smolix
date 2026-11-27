#!/bin/bash
# Builds build/Smolix.app (release, signed). UNIVERSAL=1 for Apple Silicon + Intel.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Smolix.app"
KEYCHAIN="$PWD/.signing/smolix.keychain-db"
IDENTITY="Smolix Local Signing"

# UNIVERSAL=1 builds for Apple Silicon + Intel (used for releases); default is this Mac only.
SWIFT_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    SWIFT_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "▸ Compiling (release${UNIVERSAL:+, universal})…"
BUILD_LOG=$(mktemp)
if ! swift build "${SWIFT_ARGS[@]}" >"$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG"; rm -f "$BUILD_LOG"
    echo "✗ Build failed"; exit 1
fi
# Show warnings/errors, minus Xcode's generic "x86_64 is deprecated" notice for universal builds.
grep -E "warning:|error:" "$BUILD_LOG" | grep -v "x86_64 architecture is deprecated" || true
rm -f "$BUILD_LOG"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/Smolix"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Smolix"
cp App/Info.plist "$APP/Contents/Info.plist"
[[ -f App/AppIcon.icns ]] && cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Prefer an Apple "Developer ID Application" certificate (with notarization the app opens on any
# Mac without warnings). Otherwise fall back to the local self-signed identity, which only keeps
# the Accessibility permission stable across rebuilds on this Mac.
# Override with SIGN_IDENTITY="..." if you have several certificates.
DEVELOPER_ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "▸ Signing with '$DEVELOPER_ID'"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
    [[ -f "$KEYCHAIN" ]] || ./scripts/setup-signing.sh
    echo "▸ Signing with '$IDENTITY' (self-signed, this Mac only)"
    security unlock-keychain -p smolix-local "$KEYCHAIN"
    codesign --force --options runtime --timestamp=none \
        --keychain "$KEYCHAIN" --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ Built $APP"
