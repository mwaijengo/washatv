#!/usr/bin/env bash
# Create Play Store upload keystore + android/key.properties (local only).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID="$ROOT/android"
KEYSTORE="$ANDROID/app/upload-keystore.jks"
PROPS="$ANDROID/key.properties"
CREDS="$ANDROID/keystore-credentials.local.txt"

if [[ -f "$KEYSTORE" ]]; then
  echo "Keystore already exists: $KEYSTORE"
  echo "Delete it first if you really need a new one (you cannot reuse the old Play upload key)."
  exit 1
fi

read -r -p "Store password (min 6 chars): " STORE_PASS
read -r -p "Key password [same as store]: " KEY_PASS
KEY_PASS="${KEY_PASS:-$STORE_PASS}"

keytool -genkey -v \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=Washa TV, OU=Mobile, O=Washa TV, L=Dar es Salaam, ST=Dar es Salaam, C=TZ"

cat > "$PROPS" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=upload
storeFile=upload-keystore.jks
EOF

cat > "$CREDS" <<EOF
Washa TV — Play Store upload keystore (KEEP PRIVATE)
Keystore: android/app/upload-keystore.jks
Alias: upload
Store password: $STORE_PASS
Key password: $KEY_PASS
EOF

chmod 600 "$PROPS" "$CREDS"
echo "Created $KEYSTORE and $PROPS"
echo "Credentials copy: $CREDS"
