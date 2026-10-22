#!/bin/bash
# Builds "Anime Themes.app" into ~/Applications. Needs Apple's command line tools (xcode-select --install).
#
# The app is signed with a local certificate that this script creates once in your login keychain.
# Because every build has the same signature, macOS keeps the permissions you gave it
# (Accessibility, Automation) across rebuilds instead of asking again.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Anime Themes Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

make_identity() {
  echo "==> One-time setup: creating a local signing certificate"
  echo "    macOS will ask for your login password once, to trust it for code signing."
  local tmp
  tmp="$(mktemp -d)"
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
  # Apple's own openssl (LibreSSL) makes a .p12 the keychain can import.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/id.p12" -name "$IDENTITY" -passout pass:animethemes 2>/dev/null
  security import "$tmp/id.p12" -k "$KEYCHAIN" -P animethemes -T /usr/bin/codesign >/dev/null
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"
  rm -rf "$tmp"
}

echo "==> Building (first build takes a minute)"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/AnimeThemes"

APP="$HOME/Applications/Anime Themes.app"
pkill -x AnimeThemes 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AnimeThemes"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  make_identity || echo "   Couldn't create the certificate; using a temporary signature instead."
fi
if security find-identity -v -p codesigning | grep -q "$IDENTITY" \
   && codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1; then
  echo "==> Signed with \"$IDENTITY\" (permissions will stick across rebuilds)"
else
  codesign --force --sign - "$APP" >/dev/null
  echo "==> Signed with a temporary signature (macOS may ask for permissions again after each rebuild)"
fi
echo "==> Built $APP"
