#!/bin/bash
# Creates a local, self-signed code-signing identity for Smolix in its own keychain
# (.signing/smolix.keychain-db). Does not touch your login keychain.
#
# Why: macOS ties the Accessibility permission to the app's signature. Ad-hoc signed
# builds get a new identity on every rebuild, so the permission silently stops working.
# A stable self-signed certificate keeps the permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=".signing"
KEYCHAIN="$PWD/$DIR/smolix.keychain-db"
KEYCHAIN_PASS="smolix-local"
CN="Smolix Local Signing"
OPENSSL=/usr/bin/openssl   # system LibreSSL: produces a PKCS#12 that `security` can import

if [[ -f "$KEYCHAIN" ]] && security find-certificate -c "$CN" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing identity already set up: $CN"
    exit 0
fi

mkdir -p "$DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CN
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CN" -out "$TMP/id.p12" -passout pass:smolix

# Remember the user's keychain search list: create-keychain appends to it.
ORIGINAL_LIST=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [[ -n "$line" ]] && ORIGINAL_LIST+=("$line")
done < <(security list-keychains -d user)

rm -f "$KEYCHAIN"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"            # no auto-lock
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P smolix -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

# Restore the original search list (keep our keychain out of it).
security list-keychains -d user -s "${ORIGINAL_LIST[@]}"

echo "Created signing identity '$CN' in $KEYCHAIN"
