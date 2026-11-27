#!/bin/bash
# Builds a universal, signed Smolix.app and packs it into build/Smolix-<version>.dmg
# (drag Smolix onto the Applications shortcut to install).
#
# With a Developer ID certificate, the DMG is also signed, notarized by Apple and stapled, so it
# opens on any Mac without Gatekeeper warnings. One-time setup for notarization:
#   xcrun notarytool store-credentials smolix-notary --apple-id <apple-id> --team-id <TEAM_ID>
# (asks for an app-specific password from account.apple.com). Override with NOTARY_PROFILE=...
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-smolix-notary}"

UNIVERSAL=1 ./scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" App/Info.plist)
DMG="build/Smolix-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

ditto build/Smolix.app "$STAGING/Smolix.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ Creating $DMG"
rm -f "$DMG"
hdiutil create -quiet -volname "Smolix $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"

SIGNER=$(codesign -dv --verbose=2 build/Smolix.app 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)

if [[ -z "$SIGNER" ]]; then
    echo "⚠ Self-signed build: other Macs will block it until the user clicks \"Open Anyway\"."
    echo "  Install a Developer ID Application certificate to produce a notarized DMG."
elif ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✗ Signed with Developer ID but no notarization credentials ('$NOTARY_PROFILE')."
    echo "  Run once: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <TEAM_ID>"
    exit 1
else
    echo "▸ Signing DMG"
    codesign --force --timestamp --sign "$SIGNER" "$DMG"

    echo "▸ Notarizing (usually 1–5 minutes)…"
    RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
    STATUS=$(/usr/bin/plutil -extract status raw - <<<"$RESULT" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" != "Accepted" ]]; then
        echo "✗ Notarization status: $STATUS"
        ID=$(/usr/bin/plutil -extract id raw - <<<"$RESULT" 2>/dev/null || true)
        [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE"
        exit 1
    fi

    echo "▸ Stapling ticket"
    xcrun stapler staple -q "$DMG"
    spctl -a -t open --context context:primary-signature "$DMG"
    echo "  Gatekeeper: accepted (notarized)"
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
