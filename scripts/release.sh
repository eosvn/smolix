#!/bin/bash
# Publishes a new version on GitHub: a notarized DMG plus the Sparkle appcast that the in-app
# updater reads (SUFeedURL points at releases/latest/download/appcast.xml), then bumps the
# Homebrew cask in eosvn/homebrew-tap.
#
#   1. Bump CFBundleShortVersionString and CFBundleVersion (+1) in App/Info.plist
#   2. Write ReleaseNotes/<version>.md (shown in the update window and on the GitHub release)
#   3. Commit and push, then run: make release   (DRY_RUN=1 make release stops before publishing)
#
# The appcast is signed with the Sparkle EdDSA key in the login keychain (account "smolix").
# Back it up once:  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account smolix -x <file>
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="eosvn/smolix"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-smolix}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

fail() { echo "✗ $*"; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" App/Info.plist; }

VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
TAG="v$VERSION"
NOTES="ReleaseNotes/$VERSION.md"
DMG="build/Smolix-$VERSION.dmg"

echo "▸ Releasing Smolix $VERSION (build $BUILD)"

# --- Preconditions -----------------------------------------------------------------------------
[[ -f "$NOTES" ]] || fail "Write $NOTES first"
[[ -z "$(git status --porcelain)" ]] || fail "Commit your changes first"
git fetch -q origin
git merge-base --is-ancestor HEAD origin/main || fail "Push HEAD to origin/main first"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then fail "$TAG already exists"; fi

# Sparkle offers an update only when CFBundleVersion goes up.
LATEST_BUILD=$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" 2>/dev/null \
    | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1 || true)
if [[ -n "$LATEST_BUILD" ]] && (( BUILD <= LATEST_BUILD )); then
    fail "CFBundleVersion $BUILD must be greater than the latest release's build $LATEST_BUILD"
fi

[[ -x "$SPARKLE_BIN/generate_appcast" ]] || swift package resolve

# --- Build, notarize ---------------------------------------------------------------------------
./scripts/make-dmg.sh
spctl -a -t open --context context:primary-signature "$DMG" 2>/dev/null \
    || fail "$DMG is not notarized (needs a Developer ID certificate and notary credentials)"

# --- Appcast -----------------------------------------------------------------------------------
STAGE="build/release"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"
cp "$NOTES" "$STAGE/Smolix-$VERSION.md"   # same name as the DMG = its release notes

echo "▸ Generating signed appcast"
"$SPARKLE_BIN/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --full-release-notes-url "https://github.com/$REPO/releases" \
    --link "https://github.com/$REPO" \
    -o "$STAGE/appcast.xml" \
    "$STAGE"

grep -q "<sparkle:version>$BUILD</sparkle:version>" "$STAGE/appcast.xml" || fail "appcast.xml has no build $BUILD"
grep -q 'sparkle:edSignature=' "$STAGE/appcast.xml" || fail "appcast.xml is not signed"

# --- GitHub release ----------------------------------------------------------------------------
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
BODY="$STAGE/github-notes.md"
{
    cat "$NOTES"
    echo
    echo "---"
    echo
    echo "**Cài mới:** tải \`Smolix-$VERSION.dmg\` bên dưới, mở ra và kéo Smolix vào Applications ([hướng dẫn](https://github.com/$REPO#tải-về-và-cài-đặt))."
    echo "**Homebrew:** \`brew install --cask eosvn/tap/smolix\`"
    echo "**Đã có Smolix 1.1.0 trở lên:** menu Smolix › Kiểm tra cập nhật…"
    echo
    echo "macOS 14 trở lên · Apple Silicon và Intel · ký Developer ID, đã notarize"
    echo
    echo "SHA-256 \`Smolix-$VERSION.dmg\`: \`$SHA\`"
} > "$BODY"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "✓ Dry run: not published. Check $STAGE/appcast.xml and $BODY"
    exit 0
fi

echo "▸ Publishing $TAG"
gh release create "$TAG" "$DMG" "$STAGE/appcast.xml" \
    --repo "$REPO" \
    --target "$(git rev-parse HEAD)" \
    --title "Smolix $VERSION" \
    --notes-file "$BODY" \
    --latest

echo "✓ https://github.com/$REPO/releases/tag/$TAG"

# --- Homebrew cask -----------------------------------------------------------------------------
# brew install --cask eosvn/tap/smolix reads Casks/smolix.rb in eosvn/homebrew-tap.
bump_cask() {
    local sha cask="$STAGE/smolix.rb"
    sha=$(gh api "repos/$TAP_REPO/contents/$TAP_CASK" --jq .sha) || return 1
    gh api "repos/$TAP_REPO/contents/$TAP_CASK" --jq .content | base64 -D \
        | sed -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" > "$cask"
    grep -q "^  version \"$VERSION\"" "$cask" && grep -q "^  sha256 \"$SHA\"" "$cask" || return 1
    gh api -X PUT "repos/$TAP_REPO/contents/$TAP_CASK" -f message="smolix $VERSION" \
        -f content="$(base64 < "$cask")" -f sha="$sha" >/dev/null
}
TAP_REPO="eosvn/homebrew-tap"
TAP_CASK="Casks/smolix.rb"
echo "▸ Updating Homebrew cask ($TAP_REPO)"
if bump_cask; then
    echo "✓ brew install --cask eosvn/tap/smolix → $VERSION"
else
    echo "⚠ Couldn't update $TAP_REPO/$TAP_CASK — set version \"$VERSION\" and sha256 \"$SHA\" by hand"
fi
