#!/usr/bin/env bash
# Build signed Android App Bundle (.aab) for Google Play.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties — run: ./scripts/generate_upload_keystore.sh"
  exit 1
fi
if [[ ! -f android/app/upload-keystore.jks ]]; then
  echo "Missing android/app/upload-keystore.jks"
  exit 1
fi

if ! grep -q '^appSigningSecret=.\{32,\}' android/key.properties && [[ -z "${WASHA_APP_SIGNING_SECRET:-}" ]]; then
  echo "Missing appSigningSecret in android/key.properties (same value as APP_SIGNING_SECRET on the API)."
  exit 1
fi

echo "Building release app bundle (com.washatv)..."
flutter pub get
# Obfuscated Dart symbols; keep build/symbols private (needed to read crash stack traces).
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols

OUT="build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "Upload to Play Console:"
echo "  $OUT"
