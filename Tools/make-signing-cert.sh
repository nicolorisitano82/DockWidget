#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain.
#
# Why: TCC ties a permission to the app's designated requirement. An ad-hoc
# signature changes with every build, so every rebuild silently invalidates the
# Accessibility consent the bar needs. A stable identity keeps it.
#
# macOS will ask for the keychain password when the certificate is marked as
# trusted for code signing — that prompt is the system's, and the password goes
# to it, not here.
set -euo pipefail

NAME="${1:-Dock Widgets Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identità «$NAME» già presente."
  exit 0
fi

echo "→ genero chiave e certificato"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# The keychain cannot read a PKCS#12 written with OpenSSL 3's defaults, so the
# bundle is written with the legacy algorithms it does understand.
PASSPHRASE="$(openssl rand -hex 16)"
openssl pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$PASSPHRASE" 2>/dev/null

echo "→ importo nel portachiavi login"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSPHRASE" -T /usr/bin/codesign -A

echo "→ marco il certificato come affidabile per la firma del codice"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | sed -n '1,5p'
echo
echo "Usa:  SIGN_IDENTITY=\"$NAME\" ./build.sh"
