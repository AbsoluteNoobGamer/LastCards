#!/usr/bin/env bash
# Export upload_certificate.pem for Google Play upload-key reset requests.
# Run from android/: ./export_upload_certificate.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROPS="$ROOT/key.properties"
KEYSTORE="$ROOT/upload-keystore.p12"
OUT="$ROOT/upload_certificate.pem"

if [[ ! -f "$PROPS" ]]; then
  echo "Missing key.properties" >&2
  exit 1
fi
if [[ ! -f "$KEYSTORE" ]]; then
  echo "Missing upload-keystore.p12" >&2
  exit 1
fi

storePassword="$(grep '^storePassword=' "$PROPS" | cut -d= -f2- | tr -d '\r\n')"
keyAlias="$(grep '^keyAlias=' "$PROPS" | cut -d= -f2- | tr -d '\r\n ')"
keyAlias="${keyAlias:-upload}"

KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [[ ! -x "$KEYTOOL" ]]; then
  KEYTOOL="$(command -v keytool || true)"
fi
if [[ -z "$KEYTOOL" ]]; then
  echo "keytool not found (install Android Studio JDK or set KEYTOOL)" >&2
  exit 1
fi

"$KEYTOOL" -export -rfc \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -alias "$keyAlias" \
  -storepass "$storePassword" \
  -file "$OUT"

echo "Wrote $OUT"
"$KEYTOOL" -list -v \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -alias "$keyAlias" \
  -storepass "$storePassword" 2>/dev/null | grep -E 'SHA1:|SHA256:'
